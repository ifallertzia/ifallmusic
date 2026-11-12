import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'movie_http_client.dart';

/// The second way to a poster, for when the normal image cache cannot get it.
///
/// Catalog pages are fetched by [DioMovieHttpTransport], which falls back to
/// DNS-over-HTTPS when a mobile network poisons the catalog's hosts and sends
/// a browser User-Agent and a `Referer`. Posters, however, were loaded by the
/// plain image cache: system DNS, a `Dart/x.y` User-Agent, no `Referer`. On
/// those networks the list of titles arrived and every thumbnail on it stayed
/// a grey placeholder.
///
/// [load] fetches the poster the way the page was fetched, keeps the bytes in
/// memory (and on disk, so a relaunch does not download them again), and
/// remembers which hosts needed it so later posters from the same host skip
/// the doomed first attempt.
class MovieImageLoader {
  MovieImageLoader._();

  static final MovieImageLoader instance = MovieImageLoader._();

  static const int _maxMemoryEntries = 160;
  static const int _maxMemoryBytes = 48 * 1024 * 1024;
  static const int _maxConcurrent = 6;

  DioMovieHttpTransport? _transport;
  Future<Directory?>? _directory;

  final LinkedHashMap<String, Uint8List> _memory =
      LinkedHashMap<String, Uint8List>();
  int _memoryBytes = 0;

  final Map<String, Future<Uint8List?>> _inflight =
      <String, Future<Uint8List?>>{};
  final Set<String> _hostsNeedingLoader = <String>{};
  final Map<String, DateTime> _failedAt = <String, DateTime>{};

  int _running = 0;
  final Queue<Completer<void>> _waiting = Queue<Completer<void>>();

  /// Widget tests have no network and must not be left with pending timers.
  static bool get _runningTests {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  /// Whether this build can fetch posters this way at all.
  bool get isAvailable => !kIsWeb && !_runningTests;

  /// True when an earlier poster from [url]'s host only arrived through this
  /// loader — the image cache is skipped for that host from then on.
  bool prefersLoader(String url) {
    final String host = Uri.tryParse(url)?.host ?? '';
    return host.isNotEmpty && _hostsNeedingLoader.contains(host);
  }

  /// Bytes already in memory for [url], if any.
  Uint8List? peek(String url) {
    final Uint8List? bytes = _memory.remove(url);
    if (bytes != null) _memory[url] = bytes; // most recently used last
    return bytes;
  }

  /// The poster at [url], or null when it cannot be fetched.
  ///
  /// [referer] is the catalog page the poster belongs to; hosts that refuse
  /// hot-linking only answer when it is sent.
  Future<Uint8List?> load(String url, {String referer = ''}) {
    final String key = url.trim();
    if (key.isEmpty || !isAvailable) {
      return Future<Uint8List?>.value();
    }
    final Uint8List? cached = peek(key);
    if (cached != null) return Future<Uint8List?>.value(cached);

    final DateTime? failed = _failedAt[key];
    if (failed != null &&
        DateTime.now().difference(failed) < const Duration(minutes: 2)) {
      return Future<Uint8List?>.value();
    }

    final Future<Uint8List?>? running = _inflight[key];
    if (running != null) return running;

    final Future<Uint8List?> future = _load(key, referer).whenComplete(() {
      _inflight.remove(key);
    });
    _inflight[key] = future;
    return future;
  }

  Future<Uint8List?> _load(String url, String referer) async {
    try {
      final File? file = await _fileFor(url);
      if (file != null && file.existsSync()) {
        final Uint8List bytes = await file.readAsBytes();
        if (DioMovieHttpTransport.looksLikeImage(bytes)) {
          _remember(url, bytes);
          return bytes;
        }
      }

      await _acquire();
      Uint8List? bytes;
      try {
        bytes = await _fetch(url, referer);
      } finally {
        _release();
      }
      if (bytes == null) {
        _failedAt[url] = DateTime.now();
        return null;
      }
      _failedAt.remove(url);
      _remember(url, bytes);
      final String host = Uri.tryParse(url)?.host ?? '';
      if (host.isNotEmpty) _hostsNeedingLoader.add(host);
      if (file != null) {
        unawaited(_writeQuietly(file, bytes));
      }
      return bytes;
    } catch (_) {
      _failedAt[url] = DateTime.now();
      return null;
    }
  }

  Future<Uint8List?> _fetch(String url, String referer) async {
    final DioMovieHttpTransport transport =
        _transport ??= DioMovieHttpTransport();
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return null;

    const Map<String, String> base = <String, String>{
      'Accept': 'image/avif,image/webp,image/apng,image/*,*/*;q=0.8',
    };
    final String pageOrigin = _origin(referer);
    final String ownOrigin = _origin(url);

    // The page the poster sits on first; then the poster's own host; then no
    // Referer at all — hot-link rules differ from host to host.
    final List<String> referers = <String>[
      if (pageOrigin.isNotEmpty) '$pageOrigin/',
      if (ownOrigin.isNotEmpty && ownOrigin != pageOrigin) '$ownOrigin/',
      '',
    ];
    for (final String value in referers) {
      final Uint8List? bytes = await transport.getBytes(
        url,
        headers: <String, String>{
          ...base,
          if (value.isNotEmpty) 'Referer': value,
        },
      );
      if (bytes != null) return bytes;
    }
    return null;
  }

  static String _origin(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || uri.host.isEmpty) return '';
    if (uri.scheme != 'http' && uri.scheme != 'https') return '';
    return '${uri.scheme}://${uri.host}${uri.hasPort ? ':${uri.port}' : ''}';
  }

  void _remember(String url, Uint8List bytes) {
    final Uint8List? previous = _memory.remove(url);
    if (previous != null) _memoryBytes -= previous.length;
    _memory[url] = bytes;
    _memoryBytes += bytes.length;
    while (_memory.isNotEmpty &&
        (_memory.length > _maxMemoryEntries || _memoryBytes > _maxMemoryBytes)) {
      final String oldest = _memory.keys.first;
      _memoryBytes -= _memory.remove(oldest)?.length ?? 0;
    }
  }

  Future<void> _acquire() async {
    if (_running < _maxConcurrent) {
      _running++;
      return;
    }
    final Completer<void> turn = Completer<void>();
    _waiting.add(turn);
    await turn.future;
  }

  void _release() {
    if (_waiting.isNotEmpty) {
      // Hand the slot straight to the next poster in line.
      _waiting.removeFirst().complete();
    } else if (_running > 0) {
      _running--;
    }
  }

  Future<File?> _fileFor(String url) async {
    final Directory? dir = await (_directory ??= _openDirectory());
    if (dir == null) return null;
    return File('${dir.path}/${_hash(url)}.img');
  }

  Future<Directory?> _openDirectory() async {
    try {
      final Directory base = await getTemporaryDirectory();
      final Directory dir = Directory('${base.path}/movie_posters');
      if (!dir.existsSync()) await dir.create(recursive: true);
      return dir;
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeQuietly(File file, Uint8List bytes) async {
    try {
      await file.writeAsBytes(bytes, flush: false);
    } catch (_) {
      // A poster that cannot be cached is simply fetched again next time.
    }
  }

  /// FNV-1a over the URL, long enough to keep two posters apart.
  static String _hash(String value) {
    int a = 0x811c9dc5;
    int b = 0x01000193;
    for (final int code in value.codeUnits) {
      a ^= code;
      a = (a * 0x01000193) & 0xFFFFFFFF;
      b = ((b << 5) + b + code) & 0xFFFFFFFF;
    }
    return '${a.toRadixString(16).padLeft(8, '0')}'
        '${b.toRadixString(16).padLeft(8, '0')}_${value.length}';
  }
}
