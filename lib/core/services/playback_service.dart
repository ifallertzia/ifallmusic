import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../config/branding.dart';
import '../models/song.dart';
import '../utils/playback_errors.dart';
import 'playback_error_reporter.dart';
import 'radio_queue.dart';
import 'innertube_resolver.dart';
import 'library_service.dart';
import 'notification_bootstrap.dart';
import 'settings_service.dart';
import 'youtube_service.dart';

/// The playback engine.
///
/// The stream-resolution algorithm below is **exactly** the one that shipped in
/// `main.dart` (HEAD-probe + androidSdkless → ios → androidVr fallback, the
/// youtube_explode_dart #332 workaround). It was moved here unchanged; what is
/// new around it is the queue, auto-next, related-track refill and error
/// recovery so a song never silently kills playback.
class PlaybackService extends ChangeNotifier {
  PlaybackService({
    required YoutubeService youtube,
    required SettingsService settings,
    required LibraryService library,
    AudioPlayer? player,
  }) : _youtube = youtube,
       _settings = settings,
       _library = library,
       _player = player ?? AudioPlayer() {
    _eventSub = _player.playbackEventStream.listen(
      (_) {},
      onError: (Object error, StackTrace stack) {
        final song = _current;
        // setAudioSource failures are handled by its awaited load/retry path.
        if (song != null && !_isLoading && !_stopped) {
          unawaited(
            _handleFailure(song, _epoch.value, error, stack, 'playback event'),
          );
        }
      },
    );
    _playerStateSub = _player.playerStateStream.listen(_onPlayerState);
    _positionSub = _player.positionStream.listen(_onPosition);
    _durationSub = _player.durationStream.listen((Duration? d) {
      _duration = d ?? Duration.zero;
      notifyListeners();
    });
  }

  final YoutubeService _youtube;
  final SettingsService _settings;
  final LibraryService _library;
  final AudioPlayer _player;
  final InnertubeResolver _innertube = InnertubeResolver();
  final Random _random = Random();

  StreamSubscription<PlaybackEvent>? _eventSub;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;

  // ------------------------------------------------------------------- state
  final List<Song> _queue = <Song>[];
  int _index = -1;
  final PlaybackEpoch _epoch = PlaybackEpoch();
  int _session = 0;
  bool _radioMode = false;
  Future<void>? _advanceOperation, _fillOperation;
  int _fillSession = -1;
  final Set<String> _runtimeRetriedIds = {};
  final Set<String> _warming = {};
  PlaybackErrorReport? _lastError;
  PlaybackErrorReport? get lastError => _lastError;
  bool _stopped = false;
  bool _playRequested = true;
  Song? _current;
  bool _isPlaying = false;
  bool _isLoading = false;
  bool _shuffle = false;
  bool _restoredQueuePendingSource = false;
  LoopMode _loopMode = LoopMode.off;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  String? _notice;
  Timer? _sleepTimer;
  Duration? _sleepRemaining;
  Timer? _sleepTicker;
  Timer? _queuePersistDebounce;
  int _consecutiveFailures = 0;
  int _lastSavedSecond = -1;

  /// Fired after a track really starts. Recommendations listen; playback does not wait.
  void Function(Song song)? onTrackStarted;

  /// Fired when the listener skips a track that barely started.
  void Function(Song song)? onTrackSkipped;

  /// Stream URLs resolved ahead of time for the next track (gapless).
  final Map<String, ({String url, DateTime at})> _prewarmed = {};

  /// Resolved googlevideo URLs are short-lived; keep them well below expiry and
  /// coalesce simultaneous playback/download/prewarm requests per video.
  final Map<String, ({String url, DateTime at})> _resolveCache = {};
  final Map<String, Future<String>> _resolveInflight = <String, Future<String>>{};
  final Map<int, int> _legacyProbeFailuresByItag = <int, int>{};
  final Set<int> _legacyBlacklistedItags = <int>{};

  /// Device-local file URIs registered from Your Downloads.
  final Map<String, String> _offlineSources = <String, String>{};

  /// Tracks that already failed once — never retry them in the same session.
  final Set<String> _failedIds = <String>{};

  // ------------------------------------------------------------------ getters
  AudioPlayer get player => _player;
  List<Song> get queue => List<Song>.unmodifiable(_queue);
  int get currentIndex => _index;
  Song? get current => _current;
  bool get isPlaying => _isPlaying;
  bool get isLoading => _isLoading;
  bool get shuffleEnabled => _shuffle;
  LoopMode get loopMode => _loopMode;
  Duration get position => _position;
  Duration get duration => _duration;
  String? get notice => _notice;
  bool get hasTrack => _current != null;
  Duration? get sleepRemaining => _sleepRemaining;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;

  double get progress {
    if (_duration.inMilliseconds <= 0) return 0;
    return (_position.inMilliseconds / _duration.inMilliseconds).clamp(
      0.0,
      1.0,
    );
  }

  Song? get nextUp {
    if (_queue.isEmpty) return null;
    final int i = _index + 1;
    if (i < _queue.length) return _queue[i];
    if (_loopMode == LoopMode.all) return _queue.first;
    return null;
  }

  Song? get previousUp {
    if (_queue.isEmpty) return null;
    final int i = _index - 1;
    if (i >= 0) return _queue[i];
    if (_loopMode == LoopMode.all) return _queue.last;
    return null;
  }

  // -------------------------------------------------------------- public API
  /// Replace the whole queue and start at [startIndex].
  Future<void> playQueue(List<Song> songs, {int startIndex = 0}) async {
    if (songs.isEmpty) return;
    _newSession();
    _queue
      ..clear()
      ..addAll(songs);
    _failedIds.clear();
    _consecutiveFailures = 0;
    _notice = null;
    await _startSong(startIndex.clamp(0, _queue.length - 1));
    persistQueueSoon();
  }

  void _newSession({bool radio = false}) {
    _session++;
    _epoch.begin();
    _stopped = false;
    _radioMode = radio;
    _playRequested = true;
    _advanceOperation = null;
    _fillOperation = null;
    _prewarmed.clear();
    _runtimeRetriedIds.clear();
    _failedIds.clear();
    _consecutiveFailures = 0;
    _notice = null;
  }

  /// A search selection is a radio seed, never a queue of its search variants.
  Future<void> playRadio(Song seed) async {
    _newSession(radio: true);
    _queue
      ..clear()
      ..add(seed);
    unawaited(_fillRadio(seed, _session));
    await _startSong(0);
  }

  /// Play a single track right now, keeping the rest of the queue as "up next".
  Future<void> playSong(Song song) async {
    _newSession();
    final int existing = _queue.indexWhere((Song s) => s.id == song.id);
    if (existing >= 0) {
      await _startSong(existing);
      return;
    }
    _queue.insert(0, song);
    _failedIds.clear();
    _consecutiveFailures = 0;
    _notice = null;
    await _startSong(0);
  }

  Future<void> playNext(Song song) async {
    _queue.insert(_index + 1, song);
    notifyListeners();
    persistQueueSoon();
  }

  Future<void> addToQueue(Song song) async {
    _queue.add(song);
    notifyListeners();
    persistQueueSoon();
  }

  void removeFromQueue(int index) {
    if (index < 0 || index >= _queue.length) return;
    if (index == _index) return; // never pull the track that is playing
    _queue.removeAt(index);
    if (index < _index) _index--;
    notifyListeners();
    persistQueueSoon();
  }

  void clearQueue() {
    final Song? keep = _current;
    _queue.clear();
    if (keep != null) _queue.add(keep);
    _index = 0;
    notifyListeners();
    persistQueueSoon();
  }

  Future<void> togglePlayPause() async {
    if (_isLoading) {
      _playRequested = !_playRequested;
      if (!_playRequested) await _player.pause();
      notifyListeners();
    } else if (_player.playing) {
      await pause();
    } else {
      await resume();
    }
  }

  Future<void> pause() {
    _playRequested = false;
    return _player.pause();
  }

  Future<void> stop() async {
    _playRequested = false;
    _stopped = true;
    _session++;
    _epoch.begin();
    _advanceOperation = null;
    _fillOperation = null;
    _prewarmed.clear();
    cancelSleepTimer();
    _isLoading = false;
    _isPlaying = false;
    await _player.stop();
    notifyListeners();
  }

  Future<void> resume() async {
    _stopped = false;
    _playRequested = true;
    if (_isLoading) return;
    if (_player.processingState == ProcessingState.completed) {
      await _advance(manual: true);
      return;
    }
    final Song? song = _current;
    if (song != null) {
      if (_restoredQueuePendingSource) {
        final Duration resumeAt = _position;
        _restoredQueuePendingSource = false;
        await _startSong(_index, retryPosition: resumeAt);
      } else if (_failedIds.remove(song.id)) {
        _consecutiveFailures = 0;
        await _startSong(_index);
      } else {
        _epoch.ready(_epoch.value);
        _startPlayerPlayback(song);
      }
    }
  }

  /// Play saved music without resolving a network URL. A local source is
  /// preferred for that song until its download is removed.
  Future<void> playOfflineSong(Song song, String pathOrUri) =>
      playOfflineQueue(<Song>[song], <String, String>{song.id: pathOrUri});

  Future<void> playOfflineQueue(
    List<Song> songs,
    Map<String, String> sources, {
    int startIndex = 0,
  }) async {
    for (final MapEntry<String, String> entry in sources.entries) {
      _offlineSources[entry.key] = _asLocalUri(entry.value);
    }
    await playQueue(songs, startIndex: startIndex);
  }

  void forgetOfflineSong(String songId) {
    _offlineSources.remove(songId);
  }

  String _asLocalUri(String pathOrUri) {
    final Uri? parsed = Uri.tryParse(pathOrUri);
    if (parsed != null && parsed.hasScheme) return parsed.toString();
    return Uri.file(pathOrUri).toString();
  }

  Future<void> seekTo(Duration position) => _player.seek(position);

  Future<void> seekFraction(double fraction) {
    if (_duration <= Duration.zero) return Future<void>.value();
    final double clamped = fraction.clamp(0.0, 1.0);
    return _player.seek(
      Duration(milliseconds: (_duration.inMilliseconds * clamped).round()),
    );
  }

  Future<void> setVolume(double v) => _player.setVolume(v.clamp(0.0, 1.0));
  double get volume => _player.volume;

  Future<void> setSpeed(double v) async {
    await _settings.setPlaybackSpeed(v);
    await _player.setSpeed(v);
  }

  Future<void> setSkipSilence(bool enabled) async {
    await _settings.setSkipSilence(enabled);
    try {
      await _player.setSkipSilenceEnabled(enabled);
    } catch (e) {
      debugPrint('skip silence unavailable: $e');
    }
  }

  double get speed => _player.speed;

  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    // App-level queue owns shuffle; native player has a single source.
    notifyListeners();
  }

  Future<void> cycleLoopMode() async {
    _loopMode = switch (_loopMode) {
      LoopMode.off => LoopMode.all,
      LoopMode.all => LoopMode.one,
      LoopMode.one => LoopMode.off,
    };
    // Keep native loop off; completion selects the next app-queue item.
    notifyListeners();
  }

  Future<void> next() {
    _stopped = false;
    _playRequested = true;
    final Song? song = _current;
    if (song != null && _position < const Duration(seconds: 20)) {
      try {
        onTrackSkipped?.call(song);
      } catch (e) {
        debugPrint('onTrackSkipped failed: $e');
      }
    }
    return _advance(manual: true);
  }

  Future<void> previous() async {
    _stopped = false;
    _playRequested = true;
    // Like every other player: rewind first, jump back only when we're near
    // the start.
    if (_position > const Duration(seconds: 4)) {
      await _player.seek(Duration.zero);
      return;
    }
    if (_queue.isEmpty) return;
    if (_shuffle && _queue.length > 1) {
      await _startSong(_randomIndex(excluding: _index));
      return;
    }
    final int target = _index - 1;
    if (target >= 0) {
      await _startSong(target);
    } else if (_loopMode == LoopMode.all) {
      await _startSong(_queue.length - 1);
    } else {
      await _player.seek(Duration.zero);
    }
  }

  Future<void> skipToIndex(int index) async {
    _stopped = false;
    _playRequested = true;
    if (index < 0 || index >= _queue.length) return;
    await _startSong(index);
  }

  /// Sleep timer: pauses playback when it runs out.
  void startSleepTimer(Duration duration) {
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    _sleepRemaining = duration;
    _sleepTimer = Timer(duration, () async {
      await pause();
      _sleepRemaining = null;
      _sleepTicker?.cancel();
      notifyListeners();
    });
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_sleepRemaining == null) return;
      _sleepRemaining = _sleepRemaining! - const Duration(seconds: 1);
      notifyListeners();
    });
    notifyListeners();
  }

  void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    _sleepRemaining = null;
    notifyListeners();
  }

  void dismissNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }

  Future<void> clearPlaybackCache() async {
    _resolveCache.clear();
    _prewarmed.clear();
    for (final File file in await _playbackCacheFiles()) {
      try {
        await file.delete();
      } catch (_) {}
    }
  }

  Future<int> playbackCacheBytes() async {
    int total = 0;
    for (final File file in await _playbackCacheFiles()) {
      try {
        total += await file.length();
      } catch (_) {}
    }
    return total;
  }

  Future<void> prunePlaybackCache() async {
    final int? maxBytes = _settings.offlineCacheSizeBytes;
    if (maxBytes == null) return;
    final List<File> files = await _playbackCacheFiles();
    final List<({File file, int size, DateTime touched})> entries = [];
    int total = 0;
    for (final File file in files) {
      try {
        final int size = await file.length();
        total += size;
        entries.add((file: file, size: size, touched: await file.lastModified()));
      } catch (_) {}
    }
    if (total <= maxBytes) return;
    entries.sort((a, b) => a.touched.compareTo(b.touched));
    for (final entry in entries) {
      if (total <= maxBytes) break;
      try {
        await entry.file.delete();
        total -= entry.size;
      } catch (_) {}
    }
  }

  Future<List<File>> _playbackCacheFiles() async {
    final List<Directory> roots = <Directory>[];
    try {
      roots.add(await getTemporaryDirectory());
    } catch (_) {}
    try {
      roots.add(await getApplicationSupportDirectory());
    } catch (_) {}
    final List<File> files = <File>[];
    for (final Directory root in roots) {
      if (!await root.exists()) continue;
      await for (final FileSystemEntity entity in root.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        final String path = entity.path.toLowerCase();
        if (path.contains('just_audio') ||
            path.contains('lockcaching') ||
            path.contains('audio_cache')) {
          files.add(entity);
        }
      }
    }
    return files;
  }

  Future<void> restorePersistedQueue() async {
    final Map<String, dynamic>? saved = _settings.persistentQueue;
    if (saved == null || _queue.isNotEmpty) return;
    final Object? rawSongs = saved['queue'];
    if (rawSongs is! List || rawSongs.isEmpty) return;
    final List<Song> songs = rawSongs
        .whereType<Map>()
        .map((Map item) => Song.fromJson(item.cast<String, dynamic>()))
        .where((Song song) => song.id.isNotEmpty)
        .toList();
    if (songs.isEmpty) return;
    _queue
      ..clear()
      ..addAll(songs);
    _index = (saved['index'] is int ? saved['index'] as int : 0)
        .clamp(0, _queue.length - 1)
        .toInt();
    _current = _queue[_index];
    _position = Duration(
      milliseconds: saved['positionMs'] is int ? saved['positionMs'] as int : 0,
    );
    _duration = _current?.duration ?? Duration.zero;
    _isPlaying = false;
    _isLoading = false;
    _playRequested = false;
    _restoredQueuePendingSource = true;
    notifyListeners();
  }

  Future<void> persistQueueNow() => _persistQueueNow();

  void persistQueueSoon() {
    _queuePersistDebounce?.cancel();
    _queuePersistDebounce = Timer(const Duration(seconds: 2), () {
      unawaited(_persistQueueNow());
    });
  }

  Future<void> _persistQueueNow() async {
    if (_queue.isEmpty || _index < 0) {
      await _settings.clearPersistentQueue();
      return;
    }
    await _settings.savePersistentQueue(<String, dynamic>{
      'queue': _queue.map((Song song) => song.toJson()).toList(),
      'index': _index,
      'positionMs': _position.inMilliseconds,
      'savedAt': DateTime.now().millisecondsSinceEpoch,
    });
  }

  // ============================================================ the engine
  //
  // Stream resolution with playback pre-validation.
  //
  // Under YouTube's 2026 anti-bot rules, getManifest() still succeeds but some
  // of the returned stream URLs (usually the highest-bitrate ones) return
  // HTTP 403 the moment the player fetches them — the player then fails with
  // "(0) source error" (youtube_explode_dart issue #332).
  //
  // Strategy:
  //  1. Ask each client (highest success rate first) for a manifest.
  //  2. Sort audio-only streams by bitrate (desc) and HEAD-probe each URL;
  //     use the first one that actually responds 200/206.
  //  3. If no audio-only stream is playable, try muxed (A/V) streams — they
  //     still play fine as audio.
  //  4. If a whole client yields nothing usable, fall through to the next.
  // ============================================================
  static final List<(String, YoutubeApiClient)> _streamClients =
      <(String, YoutubeApiClient)>[
    ('androidSdkless', YoutubeApiClient.androidSdkless), // v3 default, no PO-token
    ('ios', YoutubeApiClient.ios), // no PO-token, no deciphering
    ('androidVr', YoutubeApiClient.androidVr), // no PO-token
  ];

  Future<String> resolvePlayableStreamUrl(VideoId videoId) =>
      _resolvePlayableStreamUrl(videoId, preferDownload: false);

  /// Download path keeps the historic public contract above intact, but asks
  /// the unified resolver for an M4A/content-length-friendly URL when possible
  /// so Dio can keep showing determinate progress.
  Future<String> resolveDownloadStreamUrl(VideoId videoId) =>
      _resolvePlayableStreamUrl(videoId, preferDownload: true);

  Future<String> _resolvePlayableStreamUrl(
    VideoId videoId, {
    required bool preferDownload,
  }) {
    final String key = '${videoId.value}:${preferDownload ? 'download' : 'play'}';
    final cached = _resolveCache[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(hours: 4)) {
      return Future<String>.value(cached.url);
    }
    final Future<String>? inflight = _resolveInflight[key];
    if (inflight != null) return inflight;

    final Future<String> operation = _resolveFresh(
      videoId,
      preferDownload: preferDownload,
    ).then((String url) {
      _resolveCache[key] = (url: url, at: DateTime.now());
      return url;
    });
    _resolveInflight[key] = operation;
    return operation.whenComplete(() {
      if (identical(_resolveInflight[key], operation)) _resolveInflight.remove(key);
    });
  }

  void _evictResolved(String videoId) {
    _resolveCache.remove('$videoId:play');
    _resolveCache.remove('$videoId:download');
    _prewarmed.remove(videoId);
  }

  Future<String> _resolveFresh(
    VideoId videoId, {
    required bool preferDownload,
  }) async {
    final StreamResolverMode mode = _settings.streamResolverMode;
    Object? primaryError;

    if (mode != StreamResolverMode.legacyOnly) {
      try {
        return (await _innertube
                .resolve(videoId, preferDownload: preferDownload)
                .timeout(const Duration(seconds: 34)))
            .url
            .toString();
      } catch (error) {
        primaryError = error;
        debugPrint('[resolver] Innertube failed: $error');
        if (mode == StreamResolverMode.innertubeOnly) rethrow;
      }
    }

    if (mode != StreamResolverMode.innertubeOnly) {
      try {
        return await _resolveWithExplode(videoId).timeout(
          const Duration(seconds: 34),
        );
      } catch (error) {
        throw Exception(
          'No playable stream found. Smart resolver failed.'
          '${primaryError != null ? ' Innertube: $primaryError.' : ''}'
          ' Legacy: $error',
        );
      }
    }

    throw Exception('No playable stream found: $primaryError');
  }

  Future<String> _resolveWithExplode(VideoId videoId) async {
    Object? lastError;
    bool sawNetworkError = false;

    for (int pass = 0; pass < 2; pass++) {
      for (final (String name, YoutubeApiClient client) in _streamClients) {
        try {
          final StreamManifest manifest = await _youtube.client.videos.streams
              .getManifest(videoId, ytClients: [client])
              .timeout(const Duration(seconds: 10));

          final StreamInfo? playable =
              await _firstPlayable(_sortByBitrateDesc(manifest.audioOnly)) ??
                  await _firstPlayable(_sortByBitrateDesc(manifest.muxed));

          if (playable != null) {
            debugPrint('[$name] using itag ${playable.tag} '
                '(${playable.container}, ${playable.bitrate})');
            return playable.url.toString();
          }
          debugPrint('[$name] manifest OK but no playable stream, '
              'falling back to next client...');
        } on SocketException catch (e) {
          lastError = e;
          sawNetworkError = true;
          debugPrint('[$name] network failed: $e');
        } on YoutubeExplodeException catch (e) {
          lastError = e;
          debugPrint('[$name] youtube_explode failed: $e');
        } on TimeoutException catch (e) {
          lastError = e;
          sawNetworkError = true;
          debugPrint('[$name] timed out: $e');
        } catch (e) {
          lastError = e;
          if (_looksLikeNetwork(e)) sawNetworkError = true;
          debugPrint('[$name] getManifest failed: $e');
        }
      }
      if (!sawNetworkError) break;
      sawNetworkError = false;
      debugPrint('[legacy] retrying once after network failure...');
    }

    throw Exception('Legacy resolver found no playable stream'
        '${lastError != null ? ' | last error: $lastError' : ''}');
  }

  bool _looksLikeNetwork(Object error) =>
      error is SocketException ||
      error is TimeoutException ||
      error.toString().contains('SocketException') ||
      error.toString().contains('Connection closed') ||
      error.toString().contains('Failed host lookup');

  List<T> _sortByBitrateDesc<T extends StreamInfo>(Iterable<T> streams) =>
      streams.toList()..sort((StreamInfo a, StreamInfo b) => b.bitrate.compareTo(a.bitrate));

  /// Returns the first stream whose URL is actually fetchable right now.
  ///
  /// We probe with a HEAD request — the exact same validity check
  /// youtube_explode_dart itself uses internally — because under YouTube's
  /// anti-bot rules some URLs return 403 and ExoPlayer would fail later.
  Future<StreamInfo?> _firstPlayable(List<StreamInfo> candidates) async {
    if (candidates.isEmpty) return null;

    final HttpClient httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      for (final StreamInfo candidate in candidates) {
        final int itag = int.tryParse(candidate.tag.toString()) ?? candidate.tag.hashCode;
        if (_legacyBlacklistedItags.contains(itag)) continue;
        try {
          final HttpClientRequest request =
              await httpClient.headUrl(candidate.url);
          final HttpClientResponse response =
              await request.close().timeout(const Duration(seconds: 8));
          await response.drain<void>().timeout(const Duration(seconds: 8));

          if (response.statusCode == HttpStatus.ok ||
              response.statusCode == HttpStatus.partialContent) {
            return candidate;
          }
          _noteLegacyProbeFailure(itag);
          debugPrint('itag ${candidate.tag} -> HTTP ${response.statusCode}, '
              'trying next stream');
        } catch (e) {
          _noteLegacyProbeFailure(itag);
          debugPrint('itag ${candidate.tag} probe failed: $e');
        }
      }
    } finally {
      httpClient.close(force: true);
    }
    return null;
  }

  void _noteLegacyProbeFailure(int itag) {
    final int failures = (_legacyProbeFailuresByItag[itag] ?? 0) + 1;
    _legacyProbeFailuresByItag[itag] = failures;
    if (failures >= 2) _legacyBlacklistedItags.add(itag);
  }

  // ----------------------------------------------------------- queue control
  Future<void> _startSong(int index, {Duration? retryPosition}) async {
    if (_stopped || index < 0 || index >= _queue.length) return;
    final generation = _epoch.begin();
    final song = _queue[index];
    _isLoading = true;
    await _flushPosition();
    if (!_epoch.current(generation) || _stopped) return;
    _index = index;
    _current = song;
    _restoredQueuePendingSource = false;
    _position = Duration.zero;
    _duration = song.duration ?? Duration.zero;
    _lastSavedSecond = -1;
    _notice = null;
    notifyListeners();
    persistQueueSoon();

    Object? failure;
    StackTrace failureStack = StackTrace.empty;
    final local = _offlineSources[song.id] ??
        (song.source == TrackSource.localDevice ? song.localUri : null);
    final warmed = _prewarmed.remove(song.id);
    // Signed URLs are short-lived. Also retry with a fresh URL if a previously
    // validated stream fails at ExoPlayer load time (403/expiry/network hiccup).
    for (int attempt = 0; attempt < (local == null ? 2 : 1); attempt++) {
      try {
        if (!_epoch.current(generation) || _stopped) return;
        await _player.pause();
        final cached =
            attempt == 0 &&
                warmed != null &&
                DateTime.now().difference(warmed.at) <
                    const Duration(seconds: 90)
            ? warmed.url
            : null;
        final url =
            local ??
            cached ??
            await resolvePlayableStreamUrl(
              VideoId(song.id),
            ).timeout(const Duration(seconds: 35));
        if (!_epoch.current(generation) || _stopped) return;
        final art = Uri.tryParse(song.thumbnailUrl);
        final MediaItem tag = MediaItem(
          id: song.id,
          title: song.title,
          artist: song.artist,
          album: song.album ?? song.subtitle ?? IfallBranding.appName,
          artUri: art != null && art.hasScheme ? art : null,
          duration: song.duration,
        );
        final Uri sourceUri = Uri.parse(url);
        final AudioSource source = local == null && sourceUri.scheme.startsWith('http')
            ? LockCachingAudioSource(sourceUri, tag: tag)
            : AudioSource.uri(sourceUri, tag: tag);
        await _player
            .setAudioSource(source)
            .timeout(const Duration(seconds: 25));
        if (!_epoch.current(generation) || _stopped) return;
        await _player.setLoopMode(LoopMode.off);
        await _player.setSpeed(_settings.playbackSpeed);
        try {
          await _player.setSkipSilenceEnabled(_settings.skipSilence);
        } catch (_) {}
        final resume = retryPosition ?? _settings.resumePositionFor(song.id);
        final duration = _player.duration ?? Duration.zero;
        if (resume != null &&
            resume > Duration.zero &&
            resume < duration - const Duration(seconds: 10)) {
          await _player.seek(resume);
        }
        if (!_epoch.current(generation) || _stopped) return;
        _isLoading = false;
        _epoch.ready(generation);
        notifyListeners();
        _startPlayerPlayback(song);
        unawaited(prunePlaybackCache());
        // Don't reset the failure budget until real progress/completion: a
        // source can load successfully but then fail immediately while playing.
        if (_radioMode && _queue.length - _index <= 3)
          unawaited(_fillRadio(song, _session));
        unawaited(_recordStarted(song, generation));
        unawaited(NotificationBootstrap.requestOnFirstPlay());
        return;
      } catch (error, stack) {
        if (!_epoch.current(generation) || _stopped) return;
        failure = error;
        failureStack = stack;
        _evictResolved(song.id);
        if (isUnavailableTrack(error)) break;
      }
    }
    await _handleFailure(
      song,
      generation,
      failure ?? StateError('Source unavailable'),
      failureStack,
      'load source',
    );
  }

  Future<void> _recordStarted(Song song, int generation) async {
    try {
      await _library.recordPlay(song);
    } catch (_) {}
    if (!_epoch.current(generation) || _stopped) return;
    try {
      onTrackStarted?.call(song);
    } catch (_) {}
  }

  void _startPlayerPlayback(Song song) {
    if (_stopped || !_playRequested) return;
    final generation = _epoch.value;
    try {
      unawaited(
        _player.play().catchError((Object error, StackTrace stack) {
          unawaited(
            _handleFailure(
              song,
              generation,
              error,
              stack,
              'start / stream playback',
            ),
          );
        }),
      );
    } catch (error, stack) {
      unawaited(
        _handleFailure(song, generation, error, stack, 'start playback'),
      );
    }
  }

  Future<void> _handleFailure(
    Song failed,
    int generation,
    Object error,
    StackTrace stack,
    String stage,
  ) async {
    if (_stopped || !_epoch.fail(generation)) return;
    _isLoading = true;
    _isPlaying = false;
    _evictResolved(failed.id);
    // One fresh-source recovery for a mid-stream interruption, preserving
    // position. Duplicate play-future/event errors claim the same epoch once.
    if (stage != 'load source' &&
        !isUnavailableTrack(error) &&
        _runtimeRetriedIds.add(failed.id)) {
      final position = _player.position;
      await _startSong(_index, retryPosition: position);
      return;
    }
    _consecutiveFailures++;
    _failedIds.add(failed.id);
    _lastError = PlaybackErrorReport(
      song: failed,
      error: error,
      stack: stack,
      stage: stage,
      queueIndex: _index,
      queueLength: _queue.length,
    );
    unawaited(PlaybackErrorReporter.remember(_lastError!));
    _notice = 'Failed, proceeding to next.';
    notifyListeners();
    try {
      await _player.pause();
    } catch (_) {}
    if (!_epoch.current(generation) || _stopped) return;
    if (_consecutiveFailures >= 6) {
      _isLoading = false;
      _notice = 'Failed. Check your connection and tap play to retry.';
      notifyListeners();
      return;
    }
    int nextIndex = _nextEligible();
    if (nextIndex < 0) {
      await _fillRadio(failed, _session);
      if (!_epoch.current(generation) || _stopped) return;
      nextIndex = _nextEligible();
    }
    if (nextIndex >= 0) {
      await _startSong(nextIndex);
    } else {
      _isLoading = false;
      _notice = 'Failed. No playable next song — tap play to retry.';
      notifyListeners();
    }
  }

  void _onPlayerState(PlayerState state) {
    if (_stopped) return;
    final playing =
        state.playing && state.processingState != ProcessingState.completed;
    if (playing != _isPlaying) {
      _isPlaying = playing;
      notifyListeners();
    }
    if (state.processingState == ProcessingState.completed &&
        !_isLoading &&
        _epoch.complete()) {
      _consecutiveFailures = 0;
      unawaited(_onTrackCompleted());
    }
  }

  void _onPosition(Duration p) {
    _position = p;
    if (_isPlaying && !_isLoading && p.inSeconds >= 10)
      _consecutiveFailures = 0;
    final left = _duration - p;
    if (!_isLoading &&
        left > Duration.zero &&
        left <= const Duration(seconds: 45))
      _prewarmNext();
    // Persist a resume point every ~10 s instead of on every tick.
    final int second = p.inSeconds;
    if (second > 0 && second % 10 == 0 && second != _lastSavedSecond) {
      _lastSavedSecond = second;
      final Song? song = _current;
      if (song != null) _settings.saveResumePosition(song.id, p);
      persistQueueSoon();
    }
  }

  Future<void> _flushPosition() async {
    final Song? song = _current;
    if (song == null) return;
    if (_position.inSeconds < 5) return;
    try {
      await _settings.saveResumePosition(song.id, _position);
    } catch (_) {}
  }

  Future<void> _onTrackCompleted() async {
    if (_stopped || !_playRequested) return;
    if (_loopMode == LoopMode.one) {
      await _startSong(_index, retryPosition: Duration.zero);
      return;
    }
    await _advance(manual: false);
  }

  Future<void> _advance({required bool manual}) {
    if (_advanceOperation != null) return _advanceOperation!;
    final operation = _performAdvance(manual: manual);
    _advanceOperation = operation;
    return operation.whenComplete(() {
      if (identical(_advanceOperation, operation)) _advanceOperation = null;
    });
  }

  Future<void> _performAdvance({required bool manual}) async {
    if (_queue.isEmpty || _stopped) return;
    final generation = _epoch.value;
    int nextIndex = _shuffle
        ? _randomIndex(excluding: _index)
        : _nextEligible();
    if (nextIndex < 0 && _loopMode == LoopMode.all) {
      nextIndex = _queue.indexWhere((s) => !_failedIds.contains(s.id));
    }
    if (nextIndex >= 0) {
      await _startSong(nextIndex);
      return;
    }
    if (!manual && !_settings.autoplay && !_radioMode) {
      await _player.pause();
      return;
    }
    final anchor = _current;
    if (anchor == null) return;
    if (anchor.source == TrackSource.localDevice) {
      _isLoading = false;
      _notice = 'No next song available.';
      await _player.pause();
      notifyListeners();
      return;
    }
    _isLoading = true;
    notifyListeners();
    await _fillRadio(anchor, _session);
    if (!_epoch.current(generation) || _stopped) return;
    nextIndex = _nextEligible();
    if (nextIndex >= 0) {
      await _startSong(nextIndex);
    } else {
      _isLoading = false;
      _notice = 'No next song available. Check your connection and try again.';
      await _player.pause();
      notifyListeners();
    }
  }

  int _nextEligible() {
    for (int i = _index + 1; i < _queue.length; i++) {
      if (!_failedIds.contains(_queue[i].id)) return i;
    }
    return -1;
  }

  int _randomIndex({int excluding = -1}) {
    final candidates = [
      for (int i = 0; i < _queue.length; i++)
        if (i != excluding && !_failedIds.contains(_queue[i].id)) i,
    ];
    return candidates.isEmpty
        ? -1
        : candidates[_random.nextInt(candidates.length)];
  }

  Future<void> _fillRadio(Song anchor, int session) {
    if (_fillOperation != null && _fillSession == session)
      return _fillOperation!;
    _fillSession = session;
    final operation = () async {
      List<Song> candidates;
      try {
        candidates = await _youtube
            .radioSongs(
              anchor,
              history: _queue.toList(),
              exclude: _failedIds.toSet(),
            )
            .timeout(const Duration(seconds: 26));
      } catch (_) {
        candidates = [];
      }
      if (session != _session || _stopped) return;
      final fresh = radioCandidates(
        anchor,
        candidates,
        history: _queue,
        excludedIds: _failedIds,
      );
      _queue.addAll(fresh);
      notifyListeners();
    }();
    _fillOperation = operation;
    return operation.whenComplete(() {
      if (identical(_fillOperation, operation)) _fillOperation = null;
    });
  }

  void _prewarmNext() {
    if (!_settings.gapless || _stopped) return;
    final index = _nextEligible();
    if (index < 0) return;
    final song = _queue[index];
    if (_prewarmed.containsKey(song.id) ||
        _offlineSources.containsKey(song.id) ||
        !_warming.add(song.id))
      return;
    final session = _session;
    () async {
      try {
        final url = await resolvePlayableStreamUrl(
          VideoId(song.id),
        ).timeout(const Duration(seconds: 35));
        if (session == _session && !_stopped) {
          _prewarmed[song.id] = (url: url, at: DateTime.now());
          if (_prewarmed.length > 3) _prewarmed.remove(_prewarmed.keys.first);
        }
      } catch (_) {
        /* A fresh foreground resolution still gets a chance. */
      } finally {
        _warming.remove(song.id);
      }
    }();
  }

  @override
  void dispose() {
    _stopped = true;
    _session++;
    _epoch.begin();
    _sleepTimer?.cancel();
    _sleepTicker?.cancel();
    _queuePersistDebounce?.cancel();
    unawaited(_persistQueueNow());
    _eventSub?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _innertube.close();
    _player.dispose();
    super.dispose();
  }
}
