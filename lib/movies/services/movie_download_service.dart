import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/services/native_bridge.dart';
import '../models/movie_models.dart';
import 'eon_movies_service.dart';

class OpenedByteStream {
  const OpenedByteStream({
    required this.statusCode,
    required this.contentType,
    required this.contentLength,
    required this.stream,
  });

  final int statusCode;
  final String contentType;
  final int contentLength;
  final Stream<List<int>> stream;
}

typedef ByteStreamOpener = Future<OpenedByteStream> Function({
  required String url,
  required Map<String, String> headers,
  required CancelToken cancelToken,
});

/// Resumable multi-mirror downloader for Movies & Series.
///
/// Completely separate from [MusicDownloadService] so existing song offline
/// storage and UI remain untouched.
class MovieDownloadService extends ChangeNotifier {
  MovieDownloadService._({
    required SharedPreferences prefs,
    required EonMoviesService moviesService,
    Directory? customDirectory,
    ByteStreamOpener? streamOpener,
  })  : _prefs = prefs,
        _moviesService = moviesService,
        _customDirectory = customDirectory,
        _streamOpener = streamOpener;

  static const String _storageKey = 'saxify.movie_downloads.v1';
  static const int maxConcurrentDownloads = 2;

  final SharedPreferences _prefs;
  final EonMoviesService _moviesService;
  final Directory? _customDirectory;
  final ByteStreamOpener? _streamOpener;

  final List<MovieDownloadItem> _items = <MovieDownloadItem>[];
  final Map<String, CancelToken> _cancelTokens = <String, CancelToken>{};
  final Set<String> _runningIds = <String>{};
  final Set<String> _pausedExplicitly = <String>{};
  final Set<String> _canceledExplicitly = <String>{};

  Timer? _persistDebounce;
  bool _disposed = false;

  static Future<MovieDownloadService> create(
    SharedPreferences prefs, {
    required EonMoviesService moviesService,
    Directory? customDirectory,
    ByteStreamOpener? streamOpener,
  }) async {
    final MovieDownloadService svc = MovieDownloadService._(
      prefs: prefs,
      moviesService: moviesService,
      customDirectory: customDirectory,
      streamOpener: streamOpener,
    );
    svc._loadFromPrefs();
    return svc;
  }

  List<MovieDownloadItem> get items => List<MovieDownloadItem>.unmodifiable(_items);

  List<MovieDownloadItem> get activeItems => _items
      .where(
        (MovieDownloadItem e) =>
            e.isActive || e.status == MovieDownloadStatus.paused,
      )
      .toList(growable: false);

  List<MovieDownloadItem> get completedItems => _items
      .where((MovieDownloadItem e) => e.status == MovieDownloadStatus.completed)
      .toList(growable: false);

  int get activeCount =>
      _items.where((MovieDownloadItem e) => e.isActive).length;

  int get totalCount => _items.length;

  MovieDownloadItem? itemById(String id) {
    for (final MovieDownloadItem item in _items) {
      if (item.id == id) return item;
    }
    return null;
  }

  void _loadFromPrefs() {
    final String? raw = _prefs.getString(_storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is List) {
        _items
          ..clear()
          ..addAll(
            decoded
                .whereType<Map<String, dynamic>>()
                .map(MovieDownloadItem.fromJson),
          );
      }
    } catch (e) {
      debugPrint('[MoviesDownload] Failed reading persisted items: $e');
    }
  }

  void _schedulePersist({bool immediate = false}) {
    if (_disposed) return;
    if (immediate) {
      _persistDebounce?.cancel();
      unawaited(_writePrefsNow());
      return;
    }
    if (_persistDebounce?.isActive ?? false) return;
    _persistDebounce = Timer(const Duration(seconds: 2), _writePrefsNow);
  }

  Future<void> _writePrefsNow() async {
    try {
      final String payload = jsonEncode(
        _items.map((MovieDownloadItem e) => e.toJson()).toList(),
      );
      await _prefs.setString(_storageKey, payload);
    } catch (e) {
      debugPrint('[MoviesDownload] Persist error: $e');
    }
  }

  void _notifySafe() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _upsertItem(MovieDownloadItem updated, {bool persistImmediate = false}) {
    final int idx = _items.indexWhere((MovieDownloadItem e) => e.id == updated.id);
    if (idx >= 0) {
      _items[idx] = updated;
    } else {
      _items.insert(0, updated);
    }
    _schedulePersist(immediate: persistImmediate);
    _notifySafe();
  }

  Future<Directory> _resolveMoviesDir() async {
    if (_customDirectory != null) {
      if (!_customDirectory.existsSync()) {
        await _customDirectory.create(recursive: true);
      }
      return _customDirectory;
    }
    Directory base;
    if (!kIsWeb && Platform.isAndroid) {
      base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
    } else {
      base = await getApplicationDocumentsDirectory();
    }
    final Directory target = Directory('${base.path}/Movies');
    if (!target.existsSync()) {
      await target.create(recursive: true);
    }
    return target;
  }

  static String _sanitizeFileName(String raw) {
    final String cleaned = raw
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (cleaned.isEmpty) return 'movie_download.mkv';
    return cleaned.length > 180
        ? cleaned.substring(cleaned.length - 180)
        : cleaned;
  }

  Future<OpenedByteStream> _openStream({
    required String url,
    required Map<String, String> headers,
    required CancelToken cancelToken,
  }) async {
    if (_streamOpener != null) {
      return _streamOpener(
        url: url,
        headers: headers,
        cancelToken: cancelToken,
      );
    }

    final Response<ResponseBody> response =
        await _moviesService.transport.streamDio.get<ResponseBody>(
      url,
      cancelToken: cancelToken,
      options: Options(
        headers: headers,
        responseType: ResponseType.stream,
        followRedirects: true,
        receiveTimeout: const Duration(minutes: 30),
        validateStatus: (int? s) => s != null && s < 500,
      ),
    );

    final ResponseBody? body = response.data;
    if (body == null) {
      throw StateError('Empty stream body from server');
    }
    final String contentType =
        response.headers.value(Headers.contentTypeHeader) ?? '';
    final int contentLength = int.tryParse(
          response.headers.value(Headers.contentLengthHeader) ?? '',
        ) ??
        -1;

    return OpenedByteStream(
      statusCode: response.statusCode ?? 0,
      contentType: contentType,
      contentLength: contentLength,
      stream: body.stream,
    );
  }

  /// Enqueues or resumes a movie / series quality download.
  Future<MovieDownloadItem> enqueueDownload({
    required MovieDetail detail,
    required MovieQualityLink quality,
  }) async {
    final String itemId = 'mdl_${quality.id}';
    final MovieDownloadItem? existing = itemById(itemId);
    if (existing != null) {
      if (existing.isActive) return existing;
      if (existing.status == MovieDownloadStatus.completed &&
          existing.savedPath.isNotEmpty &&
          File(existing.savedPath).existsSync()) {
        return existing;
      }
      await resume(itemId);
      return itemById(itemId)!;
    }

    final MovieDownloadItem created = MovieDownloadItem(
      id: itemId,
      movieTitle: detail.cleanTitle.isNotEmpty ? detail.cleanTitle : detail.title,
      posterUrl: detail.posterUrl.isNotEmpty ? detail.posterUrl : detail.backdropUrl,
      isSeries: detail.isSeries,
      seasonLabel: quality.seasonLabel.isNotEmpty
          ? quality.seasonLabel
          : detail.defaultSeasonLabel,
      episodeLabel: quality.episodeLabel,
      qualityLabel: quality.displayQuality,
      languages:
          quality.languages.isNotEmpty ? quality.languages : detail.languages,
      sizeLabel: quality.sizeLabel,
      sourceDlUrl: quality.dlUrl,
      mimeType: quality.isZipPack ? 'application/zip' : 'video/x-matroska',
      status: MovieDownloadStatus.queued,
      createdAtMs: DateTime.now().millisecondsSinceEpoch,
    );

    _upsertItem(created, persistImmediate: true);
    _pumpQueue();
    return created;
  }

  Future<void> pause(String id) async {
    final MovieDownloadItem? current = itemById(id);
    if (current == null || !current.isActive) return;
    _pausedExplicitly.add(id);
    _cancelTokens.remove(id)?.cancel('Paused by user');
    _runningIds.remove(id);
    _upsertItem(
      current.copyWith(
        status: MovieDownloadStatus.paused,
        speedBytesPerSec: 0,
      ),
      persistImmediate: true,
    );
    _pumpQueue();
  }

  Future<void> resume(String id) async {
    final MovieDownloadItem? current = itemById(id);
    if (current == null) return;
    _pausedExplicitly.remove(id);
    _canceledExplicitly.remove(id);
    _upsertItem(
      current.copyWith(
        status: MovieDownloadStatus.queued,
        errorMessage: '',
        speedBytesPerSec: 0,
      ),
      persistImmediate: true,
    );
    _pumpQueue();
  }

  Future<void> cancel(String id) async {
    final MovieDownloadItem? current = itemById(id);
    if (current == null) return;
    _canceledExplicitly.add(id);
    _cancelTokens.remove(id)?.cancel('Canceled by user');
    _runningIds.remove(id);

    if (current.savedPath.isNotEmpty) {
      try {
        final File part = File('${current.savedPath}.part');
        if (part.existsSync()) await part.delete();
      } catch (_) {}
    }

    _upsertItem(
      current.copyWith(
        status: MovieDownloadStatus.canceled,
        downloadedBytes: 0,
        speedBytesPerSec: 0,
      ),
      persistImmediate: true,
    );
    _pumpQueue();
  }

  Future<void> remove(String id, {bool deleteFile = true}) async {
    final MovieDownloadItem? current = itemById(id);
    _canceledExplicitly.add(id);
    _cancelTokens.remove(id)?.cancel('Removed');
    _runningIds.remove(id);

    if (deleteFile && current != null && current.savedPath.isNotEmpty) {
      try {
        final File f = File(current.savedPath);
        if (f.existsSync()) await f.delete();
        final File part = File('${current.savedPath}.part');
        if (part.existsSync()) await part.delete();
      } catch (_) {}
    }

    _items.removeWhere((MovieDownloadItem e) => e.id == id);
    _schedulePersist(immediate: true);
    _notifySafe();
    _pumpQueue();
  }

  Future<OpenResult> openFile(MovieDownloadItem item) async {
    if (item.savedPath.isEmpty || !File(item.savedPath).existsSync()) {
      return OpenResult(
        type: ResultType.fileNotFound,
        message: 'Downloaded file was moved or deleted.',
      );
    }
    return OpenFilex.open(item.savedPath, type: item.mimeType);
  }

  /// Copies the finished file into Android's public `Download/IfallMusic` folder.
  Future<SavedFile?> saveToDeviceDownloads(MovieDownloadItem item) async {
    if (item.savedPath.isEmpty || !File(item.savedPath).existsSync()) {
      return null;
    }
    final SavedFile? saved = await NativeBridge.saveToDownloads(
      sourcePath: item.savedPath,
      displayName: item.fileName.isNotEmpty
          ? item.fileName
          : '${item.movieTitle}.mkv',
      mime: item.mimeType,
    );
    if (saved != null) {
      _upsertItem(
        item.copyWith(publicUri: saved.uri ?? ''),
        persistImmediate: true,
      );
    }
    return saved;
  }

  Future<bool> openSharePageExternal(MovieDownloadItem item) async {
    final String url =
        item.sharePageUrl.isNotEmpty ? item.sharePageUrl : item.sourceDlUrl;
    if (url.isEmpty) return false;
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return false;
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _pumpQueue() {
    if (_disposed) return;
    while (_runningIds.length < maxConcurrentDownloads) {
      MovieDownloadItem? next;
      for (final MovieDownloadItem item in _items) {
        if (item.status == MovieDownloadStatus.queued &&
            !_runningIds.contains(item.id)) {
          next = item;
          break;
        }
      }
      if (next == null) break;
      _runningIds.add(next.id);
      unawaited(_executeDownload(next.id));
    }
  }

  Future<void> _executeDownload(String id) async {
    MovieDownloadItem? current = itemById(id);
    if (current == null) {
      _runningIds.remove(id);
      return;
    }

    _pausedExplicitly.remove(id);
    _canceledExplicitly.remove(id);

    _upsertItem(
      current.copyWith(
        status: MovieDownloadStatus.resolving,
        errorMessage: '',
        speedBytesPerSec: 0,
      ),
    );

    try {
      final MovieQualityLink linkSpec = MovieQualityLink(
        id: id.replaceFirst('mdl_', ''),
        rawLabel: current.qualityLabel,
        resolution: current.qualityLabel,
        sizeLabel: current.sizeLabel,
        dlUrl: current.sourceDlUrl,
        languages: current.languages,
        isZipPack: current.isZip,
        seasonLabel: current.seasonLabel,
        episodeLabel: current.episodeLabel,
      );

      final ResolvedMovieStream resolved =
          await _moviesService.resolveDownloadStream(
        linkSpec,
        fallbackTitle: current.movieTitle,
      );

      if (_pausedExplicitly.contains(id) || _canceledExplicitly.contains(id)) {
        _runningIds.remove(id);
        return;
      }

      if (resolved.candidates.isEmpty) {
        throw StateError(
          resolved.sharePageUrl.isNotEmpty
              ? 'Direct mirror busy — tap Browser icon to download externally'
              : 'Could not extract direct download link right now',
        );
      }

      final Directory dir = await _resolveMoviesDir();
      current = itemById(id)!;
      final String finalName = _sanitizeFileName(
        current.fileName.isNotEmpty ? current.fileName : resolved.filename,
      );
      final String targetPath = '${dir.path}/$finalName';
      final File partFile = File('$targetPath.part');

      current = current.copyWith(
        fileName: finalName,
        savedPath: targetPath,
        mimeType: resolved.mimeType,
        sizeLabel:
            current.sizeLabel.isNotEmpty ? current.sizeLabel : resolved.sizeLabel,
        sharePageUrl: resolved.sharePageUrl,
      );
      _upsertItem(current, persistImmediate: true);

      Object? lastServerError;
      bool finished = false;

      for (final MovieStreamCandidate candidate in resolved.candidates) {
        if (_pausedExplicitly.contains(id) || _canceledExplicitly.contains(id)) {
          break;
        }
        try {
          await _streamSingleCandidate(
            id: id,
            candidate: candidate,
            partFile: partFile,
            finalPath: targetPath,
          );
          finished = true;
          break;
        } catch (err) {
          if (_pausedExplicitly.contains(id) ||
              _canceledExplicitly.contains(id)) {
            break;
          }
          lastServerError = err;
        }
      }

      if (!finished &&
          !_pausedExplicitly.contains(id) &&
          !_canceledExplicitly.contains(id)) {
        throw lastServerError ??
            StateError('All download mirrors returned an error');
      }
    } catch (err) {
      if (!_pausedExplicitly.contains(id) && !_canceledExplicitly.contains(id)) {
        final MovieDownloadItem? latest = itemById(id);
        if (latest != null) {
          _upsertItem(
            latest.copyWith(
              status: MovieDownloadStatus.failed,
              speedBytesPerSec: 0,
              errorMessage: err.toString().replaceFirst('Bad state: ', ''),
            ),
            persistImmediate: true,
          );
        }
      }
    } finally {
      _cancelTokens.remove(id);
      _runningIds.remove(id);
      _pumpQueue();
    }
  }

  Future<void> _streamSingleCandidate({
    required String id,
    required MovieStreamCandidate candidate,
    required File partFile,
    required String finalPath,
  }) async {
    int existingBytes = partFile.existsSync() ? partFile.lengthSync() : 0;
    final CancelToken cancelToken = CancelToken();
    _cancelTokens[id] = cancelToken;

    final Map<String, String> reqHeaders = <String, String>{
      ...candidate.headers,
      if (existingBytes > 0) 'Range': 'bytes=$existingBytes-',
    };

    final OpenedByteStream opened = await _openStream(
      url: candidate.url,
      headers: reqHeaders,
      cancelToken: cancelToken,
    );

    if (opened.statusCode != 200 && opened.statusCode != 206) {
      throw StateError('${candidate.server} HTTP ${opened.statusCode}');
    }
    if (opened.contentType.toLowerCase().contains('text/html')) {
      throw StateError('${candidate.server} returned an HTML page instead of media');
    }

    final bool appending = opened.statusCode == 206 && existingBytes > 0;
    if (!appending) {
      existingBytes = 0;
    }

    final int totalBytes = opened.contentLength > 0
        ? existingBytes + opened.contentLength
        : (itemById(id)?.totalBytes ?? 0);

    int received = existingBytes;
    int lastTickBytes = received;
    DateTime lastTickTime = DateTime.now();
    double smoothedSpeed = 0;

    final MovieDownloadItem? startSnap = itemById(id);
    if (startSnap != null) {
      _upsertItem(
        startSnap.copyWith(
          status: MovieDownloadStatus.downloading,
          activeServer: candidate.server,
          downloadedBytes: received,
          totalBytes: totalBytes,
          errorMessage: '',
        ),
      );
    }

    final IOSink sink = partFile.openWrite(
      mode: appending ? FileMode.append : FileMode.write,
    );
    try {
      await for (final List<int> chunk in opened.stream) {
        if (_pausedExplicitly.contains(id) || _canceledExplicitly.contains(id)) {
          break;
        }
        sink.add(chunk);
        received += chunk.length;

        final DateTime now = DateTime.now();
        final int elapsedMs = now.difference(lastTickTime).inMilliseconds;
        if (elapsedMs >= 250) {
          final double instant =
              ((received - lastTickBytes) * 1000.0) / elapsedMs;
          smoothedSpeed = smoothedSpeed <= 0
              ? instant
              : (smoothedSpeed * 0.65 + instant * 0.35);
          lastTickBytes = received;
          lastTickTime = now;

          final MovieDownloadItem? snap = itemById(id);
          if (snap != null) {
            _upsertItem(
              snap.copyWith(
                status: MovieDownloadStatus.downloading,
                activeServer: candidate.server,
                downloadedBytes: received,
                totalBytes: totalBytes,
                speedBytesPerSec: smoothedSpeed,
              ),
            );
          }
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }

    if (_pausedExplicitly.contains(id) || _canceledExplicitly.contains(id)) {
      return;
    }

    if (received < 1024 && totalBytes <= 0) {
      throw StateError('Downloaded file from ${candidate.server} was empty');
    }

    final File finalFile = File(finalPath);
    if (finalFile.existsSync()) {
      await finalFile.delete();
    }
    await partFile.rename(finalPath);

    final MovieDownloadItem? doneSnap = itemById(id);
    if (doneSnap != null) {
      _upsertItem(
        doneSnap.copyWith(
          status: MovieDownloadStatus.completed,
          activeServer: candidate.server,
          downloadedBytes: received,
          totalBytes: received,
          speedBytesPerSec: 0,
          completedAtMs: DateTime.now().millisecondsSinceEpoch,
          errorMessage: '',
        ),
        persistImmediate: true,
      );
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _persistDebounce?.cancel();
    for (final CancelToken token in _cancelTokens.values) {
      token.cancel('Service disposed');
    }
    _cancelTokens.clear();
    super.dispose();
  }
}
