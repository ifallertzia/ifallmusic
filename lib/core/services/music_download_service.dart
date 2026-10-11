import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../config/backend_config.dart';
import '../../config/branding.dart';
import '../models/song.dart';
import '../utils/audio_container.dart';
import '../utils/filenames.dart';
import '../utils/playback_errors.dart';
import 'app_feedback.dart';
import 'native_bridge.dart';
import 'playback_service.dart';

enum MusicDownloadPhase { idle, running, done, failed, cancelled }

class MusicDownloadJob {
  MusicDownloadJob({required this.song, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();

  final Song song;
  final DateTime createdAt;
  MusicDownloadPhase phase = MusicDownloadPhase.idle;
  double fraction = 0;
  int received = 0;
  int size = 0;
  String? error;
  String? savedPath;
  String? savedUri;

  /// Private app copy used for offline playback, independent of Android's
  /// public Downloads/MediaStore permission and URI behavior.
  String? offlinePath;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'song': song.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'phase': phase.name,
    'fraction': fraction,
    'received': received,
    'size': size,
    if (error != null) 'error': error,
    if (savedPath != null) 'savedPath': savedPath,
    if (savedUri != null) 'savedUri': savedUri,
    if (offlinePath != null) 'offlinePath': offlinePath,
  };

  static MusicDownloadJob? fromJson(Map<String, dynamic> json) {
    final Object? rawSong = json['song'];
    if (rawSong is! Map) return null;
    final MusicDownloadJob job =
        MusicDownloadJob(
            song: Song.fromJson(rawSong.cast<String, dynamic>()),
            createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
          )
          ..phase = MusicDownloadPhase.values.firstWhere(
            (MusicDownloadPhase value) => value.name == json['phase'],
            orElse: () => MusicDownloadPhase.done,
          )
          ..fraction = (json['fraction'] as num?)?.toDouble() ?? 1
          ..received = json['received'] is int ? json['received'] as int : 0
          ..size = json['size'] is int ? json['size'] as int : 0
          ..error = json['error'] as String?
          ..savedPath = json['savedPath'] as String?
          ..savedUri = json['savedUri'] as String?
          ..offlinePath = json['offlinePath'] as String?;
    return job;
  }
}

/// Downloads a song using the same stream resolver as the player, then keeps
/// an app-private copy for offline playback and a public Download/IfallMusic copy
/// where the platform supports it. Downloading never touches play/pause/seek.
///
/// Throughput: the CDN serves byte ranges, so a file is fetched over several
/// connections at once (4× on a normal track) and stitched together on disk.
/// If the server refuses ranges — or a part fails — the job silently falls back
/// to one straight stream, so a download always finishes.
///
/// Failures are **announced, never listed**: a failed job leaves a notification
/// and is dropped, so the Downloads section only ever shows real, playable
/// files.
class MusicDownloadService extends ChangeNotifier {
  MusicDownloadService({Dio? dio, SharedPreferences? prefs})
    : _dio = dio ?? Dio(),
      _prefs = prefs {
    jobs.addAll(_readJobs());
  }

  static const String _historyKey = 'saxify.music_downloads.v1';

  /// Ranged downloads: parts are never smaller than this, and never more than
  /// [_maxParts] connections are opened for one file.
  static const int _minPartBytes = 2 * 1024 * 1024;
  static const int _maxParts = 4;

  /// A browser-ish User-Agent — the CDN throttles unknown clients.
  static const String _mediaUserAgent =
      'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/124.0 Mobile Safari/537.36';

  final Dio _dio;
  final SharedPreferences? _prefs;
  final List<MusicDownloadJob> jobs = <MusicDownloadJob>[];
  CancelToken? _token;
  MusicDownloadJob? _activeJob;
  bool _busy = false;

  MusicDownloadJob? get active => _activeJob;

  List<MusicDownloadJob> get downloaded => List<MusicDownloadJob>.unmodifiable(
    jobs.where(
      (MusicDownloadJob job) =>
          job.phase == MusicDownloadPhase.done &&
          job.offlinePath != null &&
          File(job.offlinePath!).existsSync(),
    ),
  );

  MusicDownloadJob? jobFor(String songId) {
    for (final MusicDownloadJob job in jobs) {
      if (job.song.id == songId) return job;
    }
    return null;
  }

  bool isDownloaded(String songId) =>
      downloaded.any((MusicDownloadJob job) => job.song.id == songId);

  /// Older builds saved the offline copy under `…/Saxify/Music`. The folder is
  /// now `…/IfallMusic/Music`, so an existing download is re-pointed instead of
  /// vanishing from the list.
  static String _migratePath(String path) {
    final String legacy =
        '/${String.fromCharCodes(const <int>[83, 97, 120, 105, 102, 121])}/';
    if (!path.contains(legacy)) return path;
    return path.replaceAll(legacy, '/${IfallBranding.downloadFolderName}/');
  }

  List<MusicDownloadJob> _readJobs() {
    final String? raw = _prefs?.getString(_historyKey);
    if (raw == null || raw.isEmpty) return <MusicDownloadJob>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <MusicDownloadJob>[];
      return decoded
          .whereType<Map>()
          .map(
            (Map item) =>
                MusicDownloadJob.fromJson(item.cast<String, dynamic>()),
          )
          .whereType<MusicDownloadJob>()
          .map((MusicDownloadJob job) {
            final String? path = job.offlinePath;
            if (path == null) return job;
            final String migrated = _migratePath(path);
            if (migrated != path) job.offlinePath = migrated;
            return job;
          })
          .where(
            (MusicDownloadJob job) =>
                job.phase == MusicDownloadPhase.done &&
                job.offlinePath != null &&
                File(job.offlinePath!).existsSync(),
          )
          .toList();
    } catch (e) {
      debugPrint('[IfallMusic][MusicDownloads] history read failed: $e');
      return <MusicDownloadJob>[];
    }
  }

  Future<void> _persist() async {
    final SharedPreferences? prefs = _prefs;
    if (prefs == null) return;
    // Only finished files are history. A failure is a notification, not a row.
    final List<MusicDownloadJob> saved = jobs
        .where(
          (MusicDownloadJob job) =>
              job.phase == MusicDownloadPhase.done && job.offlinePath != null,
        )
        .take(120)
        .toList();
    await prefs.setString(
      _historyKey,
      jsonEncode(saved.map((MusicDownloadJob job) => job.toJson()).toList()),
    );
  }

  Future<MusicDownloadJob> enqueue(Song song, PlaybackService playback) async {
    final MusicDownloadJob? existing = jobFor(song.id);
    if (existing != null &&
        (existing.phase == MusicDownloadPhase.running ||
            existing.phase == MusicDownloadPhase.idle ||
            (existing.phase == MusicDownloadPhase.done &&
                existing.offlinePath != null &&
                File(existing.offlinePath!).existsSync()))) {
      return existing;
    }
    // A previous attempt failed: forget it before starting over.
    if (existing != null && existing.phase == MusicDownloadPhase.failed) {
      jobs.remove(existing);
    }

    final MusicDownloadJob job = MusicDownloadJob(song: song);
    jobs.insert(0, job);
    if (jobs.length > 120) jobs.removeLast();
    notifyListeners();
    await _pump(playback);
    return job;
  }

  Future<void> _pump(PlaybackService playback) async {
    if (_busy) return;
    _busy = true;
    try {
      while (true) {
        MusicDownloadJob? next;
        for (final MusicDownloadJob job in jobs.reversed) {
          if (job.phase == MusicDownloadPhase.idle) {
            next = job;
            break;
          }
        }
        if (next == null) break;
        _activeJob = next;
        next.phase = MusicDownloadPhase.running;
        notifyListeners();
        await _run(next, playback);
      }
    } finally {
      _activeJob = null;
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> _run(MusicDownloadJob job, PlaybackService playback) async {
    _token = CancelToken();
    File? temp;
    try {
      final String streamUrl = await playback
          .resolveDownloadStreamUrl(VideoId(job.song.id))
          .timeout(const Duration(seconds: 35));
      final Directory cache = await getTemporaryDirectory();
      String filename = Filenames.saxify(
        '${job.song.title}_${job.song.id}',
        'audio',
      );
      temp = File('${cache.path}/$filename.part');
      if (temp.existsSync()) await temp.delete();

      await _download(streamUrl, temp, job);

      final int size = await temp.length();
      final RandomAccessFile raf = await temp.open();
      final List<int> head = await raf.read(32);
      await raf.close();
      if (Filenames.looksCorrupt(head, size)) {
        throw Exception('Downloaded file looks empty or is not audio');
      }

      final container = audioContainer(head);
      filename = Filenames.saxify(
        '${job.song.title}_${job.song.id}',
        container.extension,
      );
      final Directory documents = await getApplicationDocumentsDirectory();
      final Directory privateFolder = Directory(
        '${documents.path}/${IfallBranding.downloadFolderName}/Music',
      );
      if (!privateFolder.existsSync())
        privateFolder.createSync(recursive: true);
      final File offlineFile = File('${privateFolder.path}/$filename');
      if (offlineFile.existsSync()) await offlineFile.delete();
      await temp.copy(offlineFile.path);
      job.offlinePath = offlineFile.path;
      job.size = size;

      SavedFile? publicFile;
      try {
        publicFile = await NativeBridge.saveToDownloads(
          sourcePath: temp.path,
          displayName: filename,
          mime: container.mime,
        );
      } catch (e) {
        debugPrint('[IfallMusic][MusicDownloads] public copy failed: $e');
      }
      job.savedPath = publicFile?.path;
      job.savedUri = publicFile?.uri;
      job.phase = MusicDownloadPhase.done;
      job.fraction = 1;
      job.error = null;
      await _persist();
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        job.phase = MusicDownloadPhase.cancelled;
        job.error = 'Download cancelled';
        _deleteTemp(temp);
      } else {
        _fail(job, e.message ?? 'Network error');
        _deleteTemp(temp);
      }
    } catch (e) {
      _fail(job, trackFailureMessage(e));
      _deleteTemp(temp);
    } finally {
      try {
        await _persist();
      } catch (e) {
        debugPrint('Download history save: $e');
      }
      _token = null;
      notifyListeners();
    }

    if (job.phase == MusicDownloadPhase.done) _deleteTemp(temp);
  }

  /// A failed download is a *notification*, not a row in the Downloads tab:
  /// the reason is announced once and the job is dropped shortly after, so
  /// Downloads only ever lists music that really plays offline.
  void _fail(MusicDownloadJob job, String reason) {
    job.phase = MusicDownloadPhase.failed;
    job.error = reason;
    notifyListeners();
    showAppNotice(
      'Download failed · ${job.song.title} — $reason',
      duration: const Duration(seconds: 6),
    );
    Timer(const Duration(seconds: 8), () {
      if (jobs.remove(job)) notifyListeners();
    });
  }

  // ------------------------------------------------------------------ bytes
  /// Ranged (parallel) download first — a big speed-up — with a single-stream
  /// fallback whenever the server refuses ranges or a part dies.
  Future<void> _download(
    String url,
    File target,
    MusicDownloadJob job,
  ) async {
    // Some CDN URLs carry a baked-in `range=` chunk; sending our own byte
    // ranges on top of that is asking for trouble, so those go straight down
    // one connection.
    final bool mayRange = !RegExp(r'[?&]range=').hasMatch(url);
    final int? total = mayRange ? await _probeSize(url) : null;
    if (total != null && total >= _minPartBytes * 2) {
      final int parts = (total ~/ _minPartBytes).clamp(2, _maxParts);
      final bool ok = await _downloadRanged(url, target, job, total, parts);
      if (ok) return;
      debugPrint(
        '[IfallMusic][MusicDownloads] ranged download fell back to one stream',
      );
      _deleteTemp(target);
      job.received = 0;
      job.fraction = 0;
      job.size = 0;
      notifyListeners();
    }
    await _downloadSingle(url, target, job);
  }

  /// One-byte range request: the reply's `content-range` carries the real size
  /// and proves the CDN honours ranges (otherwise we go single-stream).
  Future<int?> _probeSize(String url) async {
    Response<ResponseBody>? response;
    try {
      response = await _dio.get<ResponseBody>(
        url,
        cancelToken: _token,
        options: Options(
          responseType: ResponseType.stream,
          headers: <String, dynamic>{
            ...BackendConfig.downloadHeaders(userAgent: _mediaUserAgent),
            'Range': 'bytes=0-0',
          },
          validateStatus: (int? code) => code == 200 || code == 206,
          receiveTimeout: const Duration(seconds: 25),
          sendTimeout: const Duration(seconds: 15),
        ),
      );
      final String? range = response.headers.value('content-range');
      if (range != null && range.contains('/')) {
        final int? total = int.tryParse(range.split('/').last.trim());
        if (total != null && total > 1) {
          _drain(response.data);
          return total;
        }
      }
      // 200 means ranges are ignored — the body is the whole file, so stop it.
      if (response.statusCode == 200) {
        final int? length =
            int.tryParse(response.headers.value('content-length') ?? '');
        _drain(response.data);
        if (length != null && length > 1) return length;
      }
      _drain(response.data);
      return null;
    } catch (e) {
      debugPrint('[IfallMusic][MusicDownloads] size probe failed: $e');
      _drain(response?.data);
      return null;
    }
  }

  /// Releases a streamed response without keeping its bytes.
  void _drain(ResponseBody? body) {
    if (body == null) return;
    final StreamSubscription<List<int>>? sub = body.stream.listen((_) {});
    unawaited(sub?.cancel());
  }

  Future<bool> _downloadRanged(
    String url,
    File target,
    MusicDownloadJob job,
    int total,
    int parts,
  ) async {
    final RandomAccessFile out = await target.open(mode: FileMode.write);
    final List<int> received = List<int>.filled(parts, 0);
    try {
      out.truncateSync(total);
      final int chunk = (total / parts).ceil();
      final List<Future<void>> workers = <Future<void>>[];

      void publish() {
        final int done = received.fold<int>(0, (int a, int b) => a + b);
        job.received = done;
        job.size = total;
        job.fraction = total <= 0 ? 0 : (done / total).clamp(0.0, 1.0);
      }

      for (int i = 0; i < parts; i++) {
        final int start = i * chunk;
        if (start >= total) break;
        final int end = (start + chunk - 1) < total ? start + chunk - 1 : total - 1;
        workers.add(_part(url, out, i, start, end, received, publish));
      }
      await Future.wait(workers);
      publish();
      job.fraction = 1;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[IfallMusic][MusicDownloads] ranged part failed: $e');
      return false;
    } finally {
      try {
        await out.close();
      } catch (_) {}
    }
  }

  Future<void> _part(
    String url,
    RandomAccessFile out,
    int index,
    int start,
    int end,
    List<int> received,
    void Function() publish,
  ) async {
    final Response<ResponseBody> response = await _dio.get<ResponseBody>(
      url,
      cancelToken: _token,
      options: Options(
        responseType: ResponseType.stream,
        headers: <String, dynamic>{
          ...BackendConfig.downloadHeaders(userAgent: _mediaUserAgent),
          'Range': 'bytes=$start-$end',
        },
        validateStatus: (int? code) => code == 200 || code == 206,
        receiveTimeout: const Duration(minutes: 12),
        sendTimeout: const Duration(seconds: 20),
      ),
    );
    if (response.statusCode == 200 && index > 0) {
      // The server ignored the range and re-sent the whole file.
      _drain(response.data);
      throw StateError('Server ignored byte range');
    }

    int written = 0;
    DateTime lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
    await for (final List<int> block in response.data!.stream) {
      final int position = start + written;
      // Position + write stay synchronous so the four parts can never tear.
      out.setPositionSync(position);
      out.writeFromSync(block);
      written += block.length;
      received[index] = written;
      final DateTime now = DateTime.now();
      if (now.difference(lastNotify).inMilliseconds >= 180 ||
          written >= end - start + 1) {
        lastNotify = now;
        publish();
        notifyListeners();
      }
    }
    received[index] = written;
    publish();
    if (written < end - start + 1) {
      throw StateError('Range part $index ended short ($written bytes)');
    }
  }

  Future<void> _downloadSingle(
    String url,
    File target,
    MusicDownloadJob job,
  ) async {
    DateTime lastNotify = DateTime.fromMillisecondsSinceEpoch(0);
    await _dio.download(
      url,
      target.path,
      cancelToken: _token,
      options: Options(
        headers: BackendConfig.downloadHeaders(userAgent: _mediaUserAgent),
        receiveTimeout: const Duration(minutes: 12),
        sendTimeout: const Duration(seconds: 20),
      ),
      onReceiveProgress: (int received, int total) {
        job.received = received;
        job.size = total;
        job.fraction = total <= 0 ? 0 : (received / total).clamp(0.0, 1.0);
        final DateTime now = DateTime.now();
        if (now.difference(lastNotify).inMilliseconds >= 180 ||
            (total > 0 && received >= total)) {
          lastNotify = now;
          notifyListeners();
        }
      },
    );
  }

  void _deleteTemp(File? file) {
    try {
      if (file?.existsSync() == true) file!.deleteSync();
    } catch (_) {}
  }

  void cancel([MusicDownloadJob? job]) {
    if (job != null && job != _activeJob) {
      if (job.phase == MusicDownloadPhase.idle) {
        job.phase = MusicDownloadPhase.cancelled;
        notifyListeners();
      }
      return;
    }
    _token?.cancel('user');
  }

  Future<void> delete(MusicDownloadJob job, {PlaybackService? playback}) async {
    if (job == _activeJob) _token?.cancel('user');
    if (job.offlinePath != null) {
      try {
        final File offline = File(job.offlinePath!);
        if (offline.existsSync()) await offline.delete();
      } catch (e) {
        debugPrint('[IfallMusic][MusicDownloads] private delete failed: $e');
      }
    }
    try {
      if (job.savedUri != null || job.savedPath != null) {
        await NativeBridge.deleteDownload(
          uri: job.savedUri,
          path: job.savedPath,
        );
      }
    } catch (e) {
      debugPrint('[IfallMusic][MusicDownloads] public delete failed: $e');
    }
    playback?.forgetOfflineSong(job.song.id);
    jobs.remove(job);
    await _persist();
    notifyListeners();
  }
}
