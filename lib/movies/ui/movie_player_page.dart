import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import 'package:url_launcher/url_launcher.dart';

import '../../config/branding.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/native_bridge.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../../core/utils/track_labels.dart';
import '../models/movie_models.dart';
import '../services/movies_repository.dart';
import '../services/movie_download_service.dart';
import '../services/movie_library_service.dart';
import '../services/movie_quality_order.dart';
import '../services/movie_resume_store.dart';
import '../services/movie_seek_runner.dart';
import '../services/movie_text_scrub.dart';
import 'movie_detail_page.dart';
import 'player/movie_player_controls.dart';
import 'player/movie_player_info.dart';
import 'player/movie_player_sheets.dart';
import 'player/movie_seek_bar.dart';

/// Opens the in-app streaming player for a movie or per-episode quality.
///
/// The same resolver used for downloads supplies the ordered direct mirrors;
/// playback does not enqueue or save a download.
Future<void> openOnlineMoviePlayer(
  BuildContext context, {
  required MovieDetail detail,
  required MovieQualityLink quality,
  required List<MovieQualityLink> allQualities,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => MoviePlayerPage.online(
        detail: detail,
        initialQuality: quality,
        qualities: allQualities,
      ),
      fullscreenDialog: true,
      settings: const RouteSettings(name: 'sidify/movie-player-online'),
    ),
  );
}

/// Opens a completed local movie/episode download in the in-app player.
Future<void> openLocalMoviePlayer(
  BuildContext context, {
  required MovieDownloadItem item,
}) {
  return Navigator.of(context, rootNavigator: true).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => MoviePlayerPage.local(item: item),
      fullscreenDialog: true,
      settings: const RouteSettings(name: 'sidify/movie-player-local'),
    ),
  );
}

class MoviePlayerPage extends StatefulWidget {
  const MoviePlayerPage.online({
    super.key,
    required this.detail,
    required this.initialQuality,
    required this.qualities,
  }) : localItem = null;

  const MoviePlayerPage.local({
    super.key,
    required MovieDownloadItem item,
  })  : detail = null,
        initialQuality = null,
        qualities = const <MovieQualityLink>[],
        localItem = item;

  final MovieDetail? detail;
  final MovieQualityLink? initialQuality;
  final List<MovieQualityLink> qualities;
  final MovieDownloadItem? localItem;

  bool get isLocal => localItem != null;

  @override
  State<MoviePlayerPage> createState() => _MoviePlayerPageState();
}

/// The player page.
///
/// One [Player] and one [Video] live for as long as the page does. Portrait
/// (video on top, the title's details below) and landscape (video edge to
/// edge) are two arrangements of the same widgets, so turning the phone or
/// pressing Fullscreen never reopens the stream: position, speed, quality,
/// audio and subtitle choices all carry over untouched.
class _MoviePlayerPageState extends State<MoviePlayerPage>
    with WidgetsBindingObserver {
  static const List<double> _speeds = <double>[
    0.25,
    0.5,
    0.75,
    1.0,
    1.25,
    1.5,
    1.75,
    2.0,
  ];

  late final Player _player;
  late final VideoController _controller;

  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  final ValueNotifier<String> _statusText =
      ValueNotifier<String>('Preparing player…');
  final ValueNotifier<bool> _buffering = ValueNotifier<bool>(false);

  /// Controls locked: owned here so the system back button respects it too.
  final ValueNotifier<bool> _locked = ValueNotifier<bool>(false);

  /// Bumped when back is pressed while locked — the lock chip shows again.
  final ValueNotifier<int> _lockPoke = ValueNotifier<int>(0);

  /// A short message over the picture ("Fill"), cleared by [_toastTimer].
  final ValueNotifier<String?> _toast = ValueNotifier<String?>(null);
  Timer? _toastTimer;

  /// Tells an open sheet that tracks / quality may have changed.
  final ValueNotifier<int> _sheetRefresh = ValueNotifier<int>(0);

  /// The aspect modes the aspect button walks through:
  /// label, how the picture is fitted, and a forced shape (null = its own).
  static const List<(String, BoxFit, double?)> _aspectModes =
      <(String, BoxFit, double?)>[
    ('Fit', BoxFit.contain, null),
    ('Fill', BoxFit.cover, null),
    ('Stretch', BoxFit.fill, null),
    ('16:9', BoxFit.contain, 16 / 9),
    ('4:3', BoxFit.contain, 4 / 3),
  ];
  int _aspectIndex = 0;

  bool _pipSupported = false;

  /// Which system-bar arrangement is applied (null until the first build).
  bool? _chromeLandscape;

  /// Playback was running when the person left for Android's Cast screen: it
  /// picks up again when they come back.
  bool _resumeAfterLeaving = false;

  /// Where this title's "continue watching" position is kept.
  String _resumeKey = '';
  DateTime _lastResumeSave = DateTime.fromMillisecondsSinceEpoch(0);
  Duration? _resumeNotice;

  /// The audio track the person picked, remembered by what it *is* (track ids
  /// change between mirrors and qualities) so a quality switch keeps it.
  String _preferredAudioLanguage = '';
  String _preferredAudioTitle = '';
  bool _subtitlesOff = false;

  /// The timestamp a seek was asked for and has not been confirmed yet. The
  /// seek bar holds the thumb there instead of letting the position events
  /// that are still arriving from the *old* place drag it back — that snap
  /// back is what made a long drag look like it had failed while the mirror
  /// was in fact still being asked.
  final ValueNotifier<Duration?> _pendingSeek = ValueNotifier<Duration?>(null);

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  MoviesRepository? _movieRepository;
  MovieDownloadService? _downloadService;
  PlaybackService? _musicPlayback;

  /// Every streamable quality for this title/episode, best first. The player
  /// starts on [first] and walks down the list when a quality's mirrors die.
  List<MovieQualityLink> _availableQualities = const <MovieQualityLink>[];
  MovieQualityLink? _currentQuality;

  /// Qualities already attempted and given up on (mirrors exhausted).
  final Set<String> _failedQualities = <String>{};

  List<MovieStreamCandidate> _candidates = const <MovieStreamCandidate>[];
  final Set<int> _failedCandidates = <int>{};
  int _candidateIndex = -1;

  Timer? _startupTimer;

  /// The "still finding a stream" ticker: while nothing is playing, the line
  /// under the spinner walks through [_waitingLines] instead of sitting on one
  /// message, and stops the moment the picture arrives.
  Timer? _waitingRotator;
  int _waitingLine = 0;

  /// mpv options that make a network stream seekable are applied once, after
  /// the first media has been opened.
  bool _tunedForSeeking = false;

  /// Watches a healthy stream after mpv reports an error (a far seek on a
  /// network mirror often does): only a real stall — no position movement at
  /// all — is a failure. Without this, a perfectly playing video used to be
  /// torn down and replaced by "Couldn't start playback".
  Timer? _stallTimer;
  Duration _lastPositionValue = Duration.zero;
  DateTime _lastPositionAt = DateTime.now();

  /// Seek bookkeeping: the target still being waited on, which step of the
  /// recovery ladder is next, which mirrors have already refused to seek, and
  /// whether the "this stream cannot seek" note has been shown.
  Timer? _seekWatchdog;
  Duration? _pendingSeekTarget;
  int _seekRecoveryStep = 0;
  final Set<int> _seekFailedCandidates = <int>{};
  bool _seekLimitNoticed = false;
  int _generation = 0;
  bool _providersReady = false;
  bool _disposed = false;
  bool _isResolving = false;
  bool _loading = true;
  bool _ready = false;
  bool _candidateHealthy = false;
  bool _desiredPlaying = true;
  String? _errorMessage;

  Duration _lastKnownPosition = Duration.zero;
  Duration _candidateStartPosition = Duration.zero;
  Duration _healthPosition = Duration.zero;
  Duration _healthDuration = Duration.zero;
  Duration _healthBuffer = Duration.zero;
  int? _healthWidth;
  int? _healthHeight;
  DateTime? _candidateStartedAt;

  double _rate = 1.0;
  Tracks _tracks = const Tracks();
  String _audioSelectionId = 'auto';
  String _subtitleSelectionId = 'auto';

  String get _displayTitle {
    final MovieDownloadItem? item = widget.localItem;
    final MovieDetail? detail = widget.detail;
    final String raw = item != null
        ? item.movieTitle
        : detail == null
            ? ''
            : (detail.cleanTitle.isNotEmpty ? detail.cleanTitle : detail.title);
    final String clean = scrubSourceNames(raw).trim();
    return clean.isNotEmpty ? clean : 'Video Player';
  }

  String get _displaySubtitle {
    final MovieDownloadItem? item = widget.localItem;
    if (item != null) return item.subtitleSummary;

    final MovieDetail? detail = widget.detail;
    final MovieQualityLink? quality = _currentQuality;
    if (detail == null || quality == null) return '';

    final String season = quality.seasonLabel.isNotEmpty
        ? quality.seasonLabel
        : detail.defaultSeasonLabel;
    final List<String> parts = <String>[
      if (season.isNotEmpty) season,
      if (quality.episodeLabel.isNotEmpty) quality.episodeLabel,
      quality.displayQuality,
      if (quality.languages.isNotEmpty)
        quality.languages
      else if (detail.languages.isNotEmpty)
        detail.languages,
    ];
    return parts.where((String e) => e.trim().isNotEmpty).join(' • ');
  }

  /// Season/episode only — never the resolution while the player is still
  /// hunting for a stream that works.
  String get _loadingSubtitle {
    if (widget.isLocal) return _displaySubtitle;
    final MovieDetail? detail = widget.detail;
    final MovieQualityLink? quality = _currentQuality;
    if (detail == null || quality == null) return '';
    final String season = quality.seasonLabel.isNotEmpty
        ? quality.seasonLabel
        : detail.defaultSeasonLabel;
    return <String>[
      if (season.isNotEmpty) season,
      if (quality.episodeLabel.isNotEmpty) quality.episodeLabel,
    ].join(' • ');
  }

  @override
  void initState() {
    super.initState();
    _availableQualities = _buildAvailableQualities();
    // Playback always starts on the *lightest* stream on offer — not on
    // whatever row was tapped. 480p opens fast; if that stream is dead or
    // unplayable the pick climbs one resolution at a time instead of dropping.
    _currentQuality = _availableQualities.isNotEmpty
        ? _availableQualities.first
        : widget.initialQuality;
    _player = Player();
    _controller = VideoController(_player);
    _listenToPlayer();
    _resumeKey = MovieResumeStore.keyFor(
      detail: widget.detail,
      quality: _currentQuality ?? widget.initialQuality,
      localItem: widget.localItem,
    );
    WidgetsBinding.instance.addObserver(this);
    NativeBridge.pipMode.addListener(_onPipChanged);
    // The rest of the app is portrait-only; the player follows the phone.
    unawaited(_setOrientations(_anyOrientation));
    unawaited(
      NativeBridge.pictureInPictureSupported().then((bool supported) {
        if (mounted && supported) setState(() => _pipSupported = true);
      }),
    );
    if (widget.isLocal) {
      _setStatus('Opening video…');
    } else {
      _startWaitingStatus();
    }
  }

  /// What the player says while it is still finding a stream. Deliberately
  /// quiet about resolutions and mirrors — the fallback is meant to be
  /// invisible — but never a flat "please wait": the line moves on its own, so
  /// a slow start still reads as the app working rather than as a stuck screen.
  /// The rotation stops the instant a picture arrives.
  static const List<String> _waitingLines = <String>[
    'Trying modi ji…',
    'Asking Rahul g..',
    'Waiting for achhe din…',
    'Connecting to ifallertzia…',
    'Asking for Siddharth…',
    'Collecting from Ritu…',
    'Picking the fastest mirror…',
    'Threading the reel…',
  ];

  static const Duration _waitingLineEvery = Duration(milliseconds: 2200);

  void _startWaitingStatus() {
    if (_disposed) return;
    _waitingLine = 0;
    _setStatus(_waitingLines.first);
    _waitingRotator?.cancel();
    _waitingRotator = Timer.periodic(_waitingLineEvery, (Timer timer) {
      if (_disposed) {
        timer.cancel();
        return;
      }
      // Only a page that is still hunting for a stream keeps talking: an error
      // or a playing picture owns the status line from here on.
      if (!_loading || _errorMessage != null) {
        timer.cancel();
        return;
      }
      _waitingLine = (_waitingLine + 1) % _waitingLines.length;
      _setStatus(_waitingLines[_waitingLine]);
    });
  }

  void _stopWaitingStatus() {
    _waitingRotator?.cancel();
    _waitingRotator = null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_providersReady) return;
    _providersReady = true;

    _movieRepository = moviesRepositoryOf(context);
    _downloadService = context.read<MovieDownloadService>();
    _musicPlayback = context.read<PlaybackService>();
    unawaited(_pauseMusicPlayback());

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) {
        unawaited(_startInitialPlayback());
      }
    });
  }

  @override
  void dispose() {
    _saveResumePoint();
    _disposed = true;
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    NativeBridge.pipMode.removeListener(_onPipChanged);
    _toastTimer?.cancel();
    _startupTimer?.cancel();
    _stallTimer?.cancel();
    _seekWatchdog?.cancel();
    _stopWaitingStatus();
    for (final StreamSubscription<dynamic> sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _statusText.dispose();
    _buffering.dispose();
    _pendingSeek.dispose();
    _locked.dispose();
    _lockPoke.dispose();
    _toast.dispose();
    _sheetRefresh.dispose();
    unawaited(_player.dispose());
    unawaited(_restorePortraitChrome());
    super.dispose();
  }

  List<MovieQualityLink> _buildAvailableQualities() {
    if (widget.isLocal) return const <MovieQualityLink>[];
    final MovieQualityLink? initial = widget.initialQuality;
    final List<MovieQualityLink> source = <MovieQualityLink>[
      ...widget.qualities,
      if (initial != null) initial,
    ];
    return playableQualitiesLowestFirst(source);
  }

  void _listenToPlayer() {
    _subscriptions.addAll(<StreamSubscription<dynamic>>[
      _player.stream.position.listen(_handlePosition),
      _player.stream.duration.listen((Duration duration) {
        _healthDuration = duration;
        _checkCandidateHealth();
      }),
      _player.stream.buffer.listen((Duration buffer) {
        _healthBuffer = buffer;
        _checkCandidateHealth();
      }),
      _player.stream.width.listen((int? width) {
        _healthWidth = width;
        _checkCandidateHealth();
      }),
      _player.stream.height.listen((int? height) {
        _healthHeight = height;
        _checkCandidateHealth();
      }),
      _player.stream.playing.listen((bool playing) {
        _desiredPlaying = playing;
        _checkCandidateHealth();
        // Pausing is the usual last thing done before leaving.
        if (!playing) _saveResumePoint();
      }),
      _player.stream.rate.listen((double rate) {
        if (rate > 0) _rate = rate;
      }),
      _player.stream.tracks.listen((Tracks tracks) {
        _tracks = tracks;
        if (_disposed) return;
        if (_candidateHealthy) _reapplyTrackChoices();
        _sheetRefresh.value++;
      }),
      _player.stream.completed.listen((bool completed) {
        if (!completed || _disposed) return;
        _desiredPlaying = false;
        _startupTimer?.cancel();
        _setStatus('Playback finished');
        // A finished title starts from the beginning next time.
        unawaited(MovieResumeStore.clear(_resumeKey));
        if (mounted) {
          setState(() {
            _loading = false;
            _ready = true;
          });
        }
      }),
      _player.stream.buffering.listen((bool buffering) {
        if (_disposed) return;
        if (_buffering.value != buffering) _buffering.value = buffering;
        if (_ready && !_loading && _errorMessage == null) {
          _setStatus(buffering ? 'Buffering…' : _healthyStatusText());
        }
      }),
      _player.stream.error.listen(_handlePlayerError),
    ]);
  }

  Future<void> _pauseMusicPlayback() async {
    try {
      final PlaybackService? playback = _musicPlayback;
      if (playback != null && playback.isPlaying) {
        await playback.pause();
      }
    } catch (_) {
      // Video playback should still start if pausing music fails.
    }
  }

  Future<void> _startInitialPlayback() async {
    // Pick up where this title was left, if it was left part-way through.
    final MovieResumePoint? point = await MovieResumeStore.load(_resumeKey);
    if (_disposed) return;
    final Duration start = point?.position ?? Duration.zero;
    if (start > Duration.zero) _resumeNotice = start;

    if (widget.isLocal) {
      await _openLocalFile(start: start);
      return;
    }

    final MovieQualityLink? quality = _currentQuality;
    if (quality == null) {
      _showFatalError('No playable quality was provided.');
      return;
    }
    await _resolveAndOpenQuality(quality, start: start);
  }

  Future<void> _openLocalFile({required Duration start}) async {
    final MovieDownloadItem? item = widget.localItem;
    if (item == null) {
      _showFatalError('Downloaded video information is missing.');
      return;
    }
    if (item.isZip) {
      _showFatalError('ZIP files must be extracted before playback.');
      return;
    }
    if (item.savedPath.isEmpty || !File(item.savedPath).existsSync()) {
      _showFatalError('The downloaded file was moved or deleted.');
      return;
    }

    final int generation = ++_generation;
    _startupTimer?.cancel();
    _isResolving = false;
    _candidates = const <MovieStreamCandidate>[];
    _candidateIndex = -1;
    _failedCandidates.clear();
    _seekFailedCandidates.clear();
    _desiredPlaying = true;
    _prepareForOpen(start);
    _setStatus('Opening downloaded video…');
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      await _player.open(
        Media(
          Uri.file(item.savedPath).toString(),
          start: start > Duration.zero ? start : null,
        ),
        play: true,
      );
      if (!_isCurrentGeneration(generation)) return;
      unawaited(_safeSetRate(_rate));
      _tuneForSeekingOnce();
      _armStartupTimer(generation);
    } catch (error) {
      if (_isCurrentGeneration(generation)) {
        _showFatalError('Could not play this downloaded file.');
      }
    }
  }

  /// Resolves [quality] and opens its first mirror.
  ///
  /// [autoFallback] marks a step in the automatic walk down the quality list,
  /// where a failure is expected to continue further down instead of showing
  /// a message. The user never sees which resolution is being attempted.
  Future<void> _resolveAndOpenQuality(
    MovieQualityLink quality, {
    Duration? start,
    bool autoFallback = false,
  }) async {
    final MoviesRepository? repository = _movieRepository;
    final MovieDetail? detail = widget.detail;
    if (repository == null || detail == null) {
      _showFatalError('Streaming service is unavailable right now.');
      return;
    }

    final int generation = ++_generation;
    final bool shouldPlay = !_ready || _desiredPlaying;
    _startupTimer?.cancel();
    _stallTimer?.cancel();
    _clearPendingSeek();
    _isResolving = true;
    _currentQuality = quality;
    _startWaitingStatus();
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    try {
      final ResolvedMovieStream resolved =
          await repository.resolvePlaybackStream(
        quality,
        fallbackTitle:
            detail.cleanTitle.isNotEmpty ? detail.cleanTitle : detail.title,
      );
      if (!_isCurrentGeneration(generation)) return;

      _isResolving = false;
      _candidates = resolved.candidates;
      _failedCandidates.clear();
      _seekFailedCandidates.clear();
      _candidateIndex = -1;

      if (_candidates.isEmpty) {
        throw StateError(
          'No streamable mirror is available for this quality right now.',
        );
      }

      await _openNextCandidate(
        generation: generation,
        start: start ?? _lastKnownPosition,
        play: shouldPlay,
      );
    } catch (error) {
      if (!_isCurrentGeneration(generation)) return;
      _isResolving = false;
      if (autoFallback || !_ready) {
        // This quality's link is dead (or the page never started): climb to
        // the next one instead of bothering the person with it.
        await _advanceToNextQuality(generation: generation);
        return;
      }
      if (mounted) {
        setState(() => _loading = false);
      }
      _candidateHealthy = true;
      _setStatus(_healthyStatusText());
      showAppNotice(
        'Could not switch quality. Please try again.',
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// True when there is a higher, untried quality to climb to.
  MovieQualityLink? _nextQualityAfter(MovieQualityLink? current) {
    if (_availableQualities.isEmpty) return null;
    final int from = current == null
        ? -1
        : _availableQualities.indexWhere(
            (MovieQualityLink q) => q.id == current.id,
          );
    // Deliberately only *up* the list: 360p -> 480p -> 720p -> 1080p. Once
    // the top is reached the title is treated as not streamable.
    for (int i = from + 1; i < _availableQualities.length; i++) {
      if (!_failedQualities.contains(_availableQualities[i].id)) {
        return _availableQualities[i];
      }
    }
    return null;
  }

  /// Marks the current quality dead and tries the next-higher one. When every
  /// quality (and every mirror inside it) has failed, the player shows the
  /// honest "download it and watch offline" message instead.
  Future<void> _advanceToNextQuality({required int generation}) async {
    if (!_isCurrentGeneration(generation)) return;
    final MovieQualityLink? current = _currentQuality;
    if (current != null) _failedQualities.add(current.id);
    final MovieQualityLink? next = _nextQualityAfter(current);
    if (next == null) {
      _showPlaybackUnavailable();
      return;
    }
    _startWaitingStatus();
    await _resolveAndOpenQuality(
      next,
      start: _lastKnownPosition,
      autoFallback: true,
    );
  }

  Future<void> _openNextCandidate({
    required int generation,
    required Duration start,
    required bool play,
  }) async {
    final int? next = _findNextCandidateIndex();
    if (next == null) {
      // Every mirror of this quality is dead — climb to the next-higher
      // quality rather than giving up on the title.
      await _advanceToNextQuality(generation: generation);
      return;
    }
    await _openCandidate(
      next,
      generation: generation,
      start: start,
      play: play,
    );
  }

  int? _findNextCandidateIndex() {
    if (_candidates.isEmpty) return null;
    for (int i = _candidateIndex + 1; i < _candidates.length; i++) {
      if (!_failedCandidates.contains(i)) return i;
    }
    for (int i = 0; i < _candidateIndex && i < _candidates.length; i++) {
      if (!_failedCandidates.contains(i)) return i;
    }
    return null;
  }

  /// Opens mirror [index].
  ///
  /// [overlay] decides whether the whole screen goes behind the "still finding
  /// a stream" card. A seek recovery keeps it off: the picture stays up, only
  /// the status line says it is jumping, because the stream itself is fine —
  /// it just refused to move.
  Future<void> _openCandidate(
    int index, {
    required int generation,
    required Duration start,
    required bool play,
    bool overlay = true,
    String? status,
  }) async {
    if (!_isCurrentGeneration(generation)) return;
    if (index < 0 || index >= _candidates.length) {
      _showFatalError('No stream is available right now. Please try again.');
      return;
    }

    final MovieStreamCandidate candidate = _candidates[index];
    _candidateIndex = index;
    _failedCandidates.remove(index);
    _desiredPlaying = play;
    _prepareForOpen(start);
    if (overlay) {
      _startWaitingStatus();
    } else {
      _stopWaitingStatus();
      _setStatus(status ?? _healthyStatusText());
    }
    if (mounted) {
      setState(() {
        if (overlay) _loading = true;
        _errorMessage = null;
      });
    }

    try {
      await _player.open(
        Media(
          candidate.url.trim(),
          httpHeaders:
              candidate.headers.isEmpty ? null : candidate.headers,
          start: start > Duration.zero ? start : null,
        ),
        play: play,
      );
      if (!_isCurrentGeneration(generation)) return;
      unawaited(_safeSetRate(_rate));
      _tuneForSeekingOnce();
      _armStartupTimer(generation);
    } catch (error) {
      if (_isCurrentGeneration(generation)) {
        await _handleCandidateFailure(
          generation: generation,
          reason: _friendlyError(error),
        );
      }
    }
  }

  void _prepareForOpen(Duration start) {
    _candidateHealthy = false;
    _candidateStartPosition = start;
    if (start > Duration.zero || !_ready) {
      _lastKnownPosition = start;
    }
    _healthPosition = start;
    _healthDuration = Duration.zero;
    _healthBuffer = Duration.zero;
    _healthWidth = null;
    _healthHeight = null;
    _candidateStartedAt = DateTime.now();
    _tracks = const Tracks();
    _audioSelectionId = 'auto';
    _subtitleSelectionId = 'auto';
    _lastPositionValue = start;
    _lastPositionAt = DateTime.now();
    _stallTimer?.cancel();
  }

  void _handlePosition(Duration position) {
    // The stream reached the timestamp that was asked for: the bar can go
    // back to following the picture.
    final Duration? pending = _pendingSeekTarget;
    if (pending != null &&
        (position - pending).abs() <= const Duration(seconds: 3)) {
      _clearPendingSeek();
    }
    if (position != _lastPositionValue) {
      _lastPositionValue = position;
      _lastPositionAt = DateTime.now();
    }
    _healthPosition = position;
    if (_candidateHealthy ||
        _candidateStartPosition == Duration.zero ||
        position >= _candidateStartPosition) {
      _lastKnownPosition = position;
    }
    if (_candidateHealthy) {
      final DateTime now = DateTime.now();
      if (now.difference(_lastResumeSave) >= const Duration(seconds: 5)) {
        _lastResumeSave = now;
        _saveResumePoint();
      }
    }
    _checkCandidateHealth();
  }

  void _checkCandidateHealth() {
    if (_disposed || _candidateHealthy || _errorMessage != null) return;
    final DateTime? startedAt = _candidateStartedAt;
    if (startedAt != null &&
        DateTime.now().difference(startedAt) <
            const Duration(milliseconds: 250)) {
      return;
    }

    final bool hasDuration = _healthDuration > Duration.zero;
    final bool hasDimensions =
        (_healthWidth ?? 0) > 0 && (_healthHeight ?? 0) > 0;
    final bool progressed = _healthPosition >
        _candidateStartPosition + const Duration(seconds: 1);
    final bool bufferedAhead =
        _healthBuffer > _healthPosition + const Duration(seconds: 2) ||
            _healthBuffer >
                _candidateStartPosition + const Duration(seconds: 2);

    if (hasDuration && (hasDimensions || progressed || bufferedAhead)) {
      _markCandidateHealthy();
    }
  }

  void _markCandidateHealthy() {
    if (_disposed || _candidateHealthy) return;
    _candidateHealthy = true;
    _startupTimer?.cancel();
    _stopWaitingStatus();
    _tracks = _player.state.tracks;
    _setStatus(_healthyStatusText());
    if (mounted) {
      setState(() {
        _loading = false;
        _ready = true;
        _errorMessage = null;
      });
    }
    unawaited(_safeSetRate(_rate));

    _reapplyTrackChoices();
    _sheetRefresh.value++;

    final Duration? resumed = _resumeNotice;
    if (resumed != null) {
      _resumeNotice = null;
      _showToast(
        'Resuming from ${movieClock(resumed)}',
        duration: const Duration(seconds: 2),
      );
    }
  }

  String _healthyStatusText() {
    if (widget.isLocal) {
      return _displaySubtitle.isNotEmpty
          ? 'Local playback • $_displaySubtitle'
          : 'Local playback';
    }
    // Under the title once a picture is up: what is playing, not "Playing".
    final String playing = _displaySubtitle;
    return playing.isNotEmpty ? playing : 'Playing';
  }

  void _armStartupTimer(int generation) {
    _startupTimer?.cancel();
    // A dead mirror must not hold the player hostage: if nothing has been
    // decoded in 18 s the next stream is tried, quietly.
    _startupTimer = Timer(
      Duration(seconds: widget.isLocal ? 20 : 18),
      () {
        if (!_isCurrentGeneration(generation) || _candidateHealthy) return;
        if (widget.isLocal) {
          _showFatalError(
            'This downloaded file is taking too long to open or may be corrupted.',
          );
        } else {
          unawaited(
            _handleCandidateFailure(
              generation: generation,
              reason: 'Mirror did not start playback in time.',
            ),
          );
        }
      },
    );
  }

  void _handlePlayerError(String error) {
    if (_disposed || _isResolving || error.trim().isEmpty) return;

    // A stream that is already playing can still make mpv report an error —
    // seeking far ahead on an HTTP mirror routinely does, and mpv recovers on
    // its own. Tearing the candidate down here is what produced the false
    // "Couldn't start playback" over a video that never stopped. Watch the
    // position instead, and only fail when it really stops moving.
    if (_ready && _candidateHealthy) {
      _scheduleStallCheck();
      return;
    }

    if (widget.isLocal) {
      _showFatalError('Could not play this downloaded file.');
      return;
    }
    if (_candidateIndex < 0) return;
    unawaited(
      _handleCandidateFailure(
        generation: _generation,
        reason: error,
      ),
    );
  }

  /// Gives a playing stream a few seconds to prove it is still alive after an
  /// error. A paused video is never treated as stalled.
  void _scheduleStallCheck() {
    if (_disposed) return;
    if (_stallTimer?.isActive ?? false) return;
    final int generation = _generation;
    final Duration probe = _player.state.position;
    _stallTimer = Timer(const Duration(seconds: 10), () {
      if (!_isCurrentGeneration(generation) || _disposed) return;
      if (!_player.state.playing) return;
      if (_player.state.buffering) {
        // Still waiting on data after the seek: not a dead stream, just a
        // slow one. Look again later instead of swapping underneath it.
        _stallTimer = null;
        _scheduleStallCheck();
        return;
      }
      final Duration now = _player.state.position;
      final bool moved = now > probe + const Duration(milliseconds: 750);
      final bool recent = DateTime.now().difference(_lastPositionAt) <
          const Duration(seconds: 3);
      if (moved || recent) return;
      unawaited(
        _handleCandidateFailure(
          generation: generation,
          reason: 'The stream stopped responding.',
        ),
      );
    });
  }

  Future<void> _handleCandidateFailure({
    required int generation,
    required String reason,
  }) async {
    if (!_isCurrentGeneration(generation) ||
        widget.isLocal ||
        _candidateIndex < 0 ||
        _candidateIndex >= _candidates.length) {
      return;
    }
    final int failedIndex = _candidateIndex;
    if (_failedCandidates.contains(failedIndex)) return;

    _startupTimer?.cancel();
    _stallTimer?.cancel();
    _failedCandidates.add(failedIndex);
    _candidateHealthy = false;
    final Duration resumePosition = _lastKnownPosition;
    final bool shouldPlay = _desiredPlaying || !_ready;

    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    // No "mirror failed", no resolution names: the swap happens quietly in
    // the same player.
    _startWaitingStatus();

    await _openNextCandidate(
      generation: generation,
      start: resumePosition,
      play: shouldPlay,
    );
  }

  Future<void> _retryPlayback() async {
    _desiredPlaying = true;
    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }

    if (widget.isLocal) {
      await _openLocalFile(start: _lastKnownPosition);
      return;
    }

    // Retry means retry *everything* again, from the lightest stream up: the
    // list of qualities and mirrors that failed a moment ago is cleared.
    _failedQualities.clear();
    _failedCandidates.clear();
    final MovieQualityLink? quality = _availableQualities.isNotEmpty
        ? _availableQualities.first
        : _currentQuality;
    if (quality == null) {
      _showPlaybackUnavailable();
      return;
    }
    _ready = false;
    _startWaitingStatus();
    await _resolveAndOpenQuality(quality, start: _lastKnownPosition);
  }

  Future<void> _switchToCandidate(int index) async {
    if (widget.isLocal || index < 0 || index >= _candidates.length) return;
    if (index == _candidateIndex && _candidateHealthy) return;

    final int generation = ++_generation;
    _startupTimer?.cancel();
    _stallTimer?.cancel();
    _clearPendingSeek();
    _isResolving = false;
    _failedCandidates.remove(index);
    await _openCandidate(
      index,
      generation: generation,
      start: _lastKnownPosition,
      play: !_ready || _desiredPlaying,
    );
  }

  Future<void> _switchQuality(MovieQualityLink quality) async {
    if (widget.isLocal || quality.id == _currentQuality?.id) return;
    await _resolveAndOpenQuality(quality, start: null);
  }

  void _showFatalError(String message) {
    if (_disposed) return;
    _startupTimer?.cancel();
    _stallTimer?.cancel();
    _stopWaitingStatus();
    _clearPendingSeek();
    _isResolving = false;
    _setStatus('Playback failed');
    if (mounted) {
      setState(() {
        _loading = false;
        _ready = false;
        _errorMessage = message;
      });
    }
    // An error screen must always be reachable: never leave it locked.
    if (_locked.value) _locked.value = false;
  }

  /// The sentence shown when nothing at all could be streamed.
  String get _offlineLine =>
      'Cannot play $_displayTitle online but you can still download it '
      'and play offline.';

  /// Every quality and every mirror has been tried and failed. The player
  /// stays open on purpose: the download button beside the message is the
  /// way to still watch this title offline.
  void _showPlaybackUnavailable() {
    if (_disposed) return;
    _startupTimer?.cancel();
    _stallTimer?.cancel();
    _stopWaitingStatus();
    _clearPendingSeek();
    _isResolving = false;
    _candidateHealthy = false;
    _setStatus('Playback failed');
    if (mounted) {
      setState(() {
        _loading = false;
        _ready = false;
        _errorMessage = _offlineLine;
      });
    }
    // An error screen must always be reachable: never leave it locked.
    if (_locked.value) _locked.value = false;
  }

  /// The quality the download button should save: the one on screen when
  /// something is playing, otherwise a playable one for this title.
  MovieQualityLink? get _downloadQuality {
    if (widget.isLocal) return null;
    return _currentQuality ??
        (_availableQualities.isNotEmpty
            ? _availableQualities.first
            : widget.initialQuality);
  }

  /// When streaming failed at every quality, the offline copy should still be
  /// the best one available (the player starts at the bottom, so the list's
  /// first entry is no longer the biggest).
  MovieQualityLink? get _bestDownloadQuality {
    if (widget.isLocal) return null;
    if (_availableQualities.isNotEmpty) {
      return highestPlayableQuality(_availableQualities) ??
          _availableQualities.last;
    }
    return _currentQuality ?? widget.initialQuality;
  }

  bool _isCurrentGeneration(int generation) {
    return !_disposed && generation == _generation;
  }

  void _setStatus(String value) {
    if (!_disposed && _statusText.value != value) {
      _statusText.value = value;
    }
  }

  String _friendlyError(Object error) {
    final String raw = error.toString().toLowerCase();
    final bool network = raw.contains('socket') ||
        raw.contains('timeout') ||
        raw.contains('timed out') ||
        raw.contains('network') ||
        raw.contains('connection') ||
        raw.contains('host lookup') ||
        raw.contains('unreachable') ||
        raw.contains('mirror');
    return network
        ? 'Connection problem — check your internet and try again.'
        : 'This video could not be played right now. Please try again.';
  }

  Future<void> _safeSetRate(double rate) async {
    try {
      await _player.setRate(rate);
    } catch (_) {}
  }

  Future<void> _seekRelative(Duration offset) async {
    // Taps stack: a second +10 s lands 20 s on, even while the first one is
    // still on its way.
    await _seekTo((_pendingSeekTarget ?? _player.state.position) + offset);
  }

  /// mpv defaults that make an HTTP stream behave like a file: keep the
  /// demuxer cache (and make it searchable backwards), read further ahead, and
  /// always seek exactly. Applied once, after the first media is open, and
  /// never fatal — a property this mpv build does not know must not stop a
  /// video that is already playing.
  void _tuneForSeekingOnce() {
    if (_tunedForSeeking || _disposed) return;
    _tunedForSeeking = true;
    final PlatformPlayer? platform = _player.platform;
    if (platform is! NativePlayer) return;
    unawaited(() async {
      const Map<String, String> options = <String, String>{
        'cache': 'yes',
        'demuxer-seekable-cache': 'yes',
        'demuxer-readahead-secs': '120',
        'hr-seek': 'yes',
        'hr-seek-framedrop': 'no',
        'network-timeout': '30',
      };
      for (final MapEntry<String, String> option in options.entries) {
        if (_disposed) return;
        try {
          await platform.setProperty(option.key, option.value);
        } catch (_) {}
      }
    }());
  }

  /// One way into a seek, whichever control asked for it. The target is
  /// clamped to the media and handed to mpv under an already-running watchdog:
  /// a mirror that silently refuses to move (or never answers the native seek)
  /// is re-opened at that timestamp, then replaced by another one — instead of
  /// leaving the bar stuck where it was.
  ///
  /// The bar itself is told about the target right away ([_pendingSeek]), so
  /// the thumb stays where the finger put it while the stream catches up.
  Future<void> _seekTo(Duration target) async {
    final Duration duration = _player.state.duration;
    Duration wanted = target < Duration.zero ? Duration.zero : target;
    if (duration > Duration.zero && wanted > duration) wanted = duration;

    _seekWatchdog?.cancel();
    _seekRecoveryStep = 0;
    _pendingSeekTarget = wanted;
    _pendingSeek.value = wanted;
    await runMovieSeekWithWatchdog(
      target: wanted,
      seek: _player.seek,
      armWatchdog: _armSeekWatchdog,
      onError: (Duration failedTarget) {
        // A late error from an older request must not clear a newer seek.
        if (!_disposed && _pendingSeekTarget == failedTarget) {
          _clearPendingSeek();
        }
      },
    );
  }

  /// How long each look at a pending seek waits before deciding it failed.
  /// Short on purpose: a mirror that cannot seek says so immediately, and
  /// nine seconds of a bar sitting in the wrong place reads as a broken app.
  static const List<Duration> _seekCheckDelays = <Duration>[
    Duration(milliseconds: 1400),
    Duration(seconds: 2),
    Duration(seconds: 3),
    Duration(seconds: 4),
  ];

  void _armSeekWatchdog(Duration wanted, {int attempt = 0}) {
    _seekWatchdog?.cancel();
    final Duration delay = attempt < _seekCheckDelays.length
        ? _seekCheckDelays[attempt]
        : _seekCheckDelays.last;
    _seekWatchdog = Timer(delay, () {
      if (_disposed || _pendingSeekTarget != wanted) return;
      final Duration position = _player.state.position;
      if ((position - wanted).abs() <= const Duration(seconds: 3)) {
        _clearPendingSeek();
        return;
      }
      // Only buffering is evidence that the seek still needs time. Ordinary
      // playback also moves the position, so movement from the old timestamp
      // must not delay recovery while the movie continues at the wrong place.
      if (_player.state.buffering && attempt < _seekCheckDelays.length) {
        _armSeekWatchdog(wanted, attempt: attempt + 1);
        return;
      }
      unawaited(_recoverStuckSeek(wanted));
    });
  }

  void _clearPendingSeek() {
    _pendingSeekTarget = null;
    _seekWatchdog?.cancel();
    if (!_disposed && _pendingSeek.value != null) _pendingSeek.value = null;
  }

  /// `Jumping to 42:10…` — the status line while a seek is being recovered.
  String _jumpingStatus(Duration target) => 'Jumping to ${movieClock(target)}…';

  /// The stream did not move to [wanted]. Walk the ladder: the same mirror
  /// re-opened at that timestamp, then the other mirrors of this quality, then
  /// the next quality down. If nothing else is available, say so once and keep
  /// the picture that is playing — a stream that cannot seek is still worth
  /// watching.
  Future<void> _recoverStuckSeek(Duration wanted) async {
    if (_disposed || _errorMessage != null) return;
    final bool playAfter = _player.state.playing || _desiredPlaying;

    if (widget.isLocal) {
      _clearPendingSeek();
      await _openLocalFile(start: wanted);
      return;
    }

    final int step = _seekRecoveryStep++;

    // Step one is the one that actually fixes a long drag: the mirror is asked
    // for the timestamp in the request itself instead of being told to move a
    // stream it has already declared unseekable.
    if (step == 0 && _candidateIndex >= 0 && _candidateIndex < _candidates.length) {
      final int generation = ++_generation;
      _startupTimer?.cancel();
      _stallTimer?.cancel();
      _isResolving = false;
      _failedCandidates.remove(_candidateIndex);
      await _openCandidate(
        _candidateIndex,
        generation: generation,
        start: wanted,
        play: playAfter,
        overlay: false,
        status: _jumpingStatus(wanted),
      );
      if (!_isCurrentGeneration(generation)) return;
      _armSeekWatchdog(wanted, attempt: 2);
      return;
    }

    for (int i = 0; i < _candidates.length; i++) {
      if (i == _candidateIndex) continue;
      if (_failedCandidates.contains(i) || _seekFailedCandidates.contains(i)) {
        continue;
      }
      _seekFailedCandidates.add(_candidateIndex);
      final int generation = ++_generation;
      _startupTimer?.cancel();
      _stallTimer?.cancel();
      _isResolving = false;
      _failedCandidates.remove(i);
      await _openCandidate(
        i,
        generation: generation,
        start: wanted,
        play: playAfter,
        overlay: false,
        status: _jumpingStatus(wanted),
      );
      if (!_isCurrentGeneration(generation)) return;
      _armSeekWatchdog(wanted, attempt: 2);
      return;
    }

    // No mirror of this quality can reach it: try the next one down, from the
    // timestamp the person asked for.
    final MovieQualityLink? next = _nextQualityAfter(_currentQuality);
    if (next != null && !_failedQualities.contains(next.id)) {
      _seekFailedCandidates.add(_candidateIndex);
      await _resolveAndOpenQuality(next, start: wanted, autoFallback: true);
      return;
    }

    // Nothing left to try: keep playing, explain the limit once.
    _clearPendingSeek();
    if (!_seekLimitNoticed) {
      _seekLimitNoticed = true;
      showAppNotice(
        'This stream cannot jump around. Download it to watch offline with '
        'full seeking.',
        duration: const Duration(seconds: 4),
      );
    }
    if (playAfter && !_player.state.playing) {
      unawaited(_player.play());
    }
  }

  void _handleSeekBarStart() {
    _seekWatchdog?.cancel();
    _clearPendingSeek();
  }

  void _handleSeekBarSeek(Duration target) {
    unawaited(_seekTo(target));
  }

  // ------------------------------------------------------ resume position

  /// Remembers where this title is, so leaving and coming back continues from
  /// here. A failed player keeps the position it had; nothing is written
  /// until a real duration is known.
  void _saveResumePoint() {
    if (_resumeKey.isEmpty || !_ready) return;
    final Duration duration = _player.state.duration;
    if (duration <= Duration.zero) return;
    unawaited(
      MovieResumeStore.save(
        _resumeKey,
        position: _lastKnownPosition,
        duration: duration,
      ),
    );
  }

  // ---------------------------------------------------- layout and chrome

  static const List<DeviceOrientation> _anyOrientation = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];
  static const List<DeviceOrientation> _portraitOnly = <DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ];
  static const List<DeviceOrientation> _landscapeOnly = <DeviceOrientation>[
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ];

  Future<void> _setOrientations(List<DeviceOrientation> orientations) async {
    try {
      await SystemChrome.setPreferredOrientations(orientations);
    } catch (_) {}
  }

  bool get _isLandscape =>
      mounted && MediaQuery.orientationOf(context) == Orientation.landscape;

  /// The Fullscreen button. It only turns the screen: the layout follows the
  /// new orientation by itself and the video underneath is never touched.
  void _toggleFullscreen() {
    unawaited(_setOrientations(_isLandscape ? _portraitOnly : _landscapeOnly));
  }

  /// Landscape hides the status and navigation bars; portrait brings them
  /// back. Called from build, so it only acts when the layout really changed.
  void _syncSystemChrome(bool landscape) {
    if (_chromeLandscape == landscape) return;
    _chromeLandscape = landscape;
    unawaited(() async {
      try {
        await SystemChrome.setEnabledSystemUIMode(
          landscape ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
        );
      } catch (_) {}
    }());
  }

  /// Back — the on-screen arrow and the system button alike. Locked: nothing
  /// happens except the lock chip coming back. Landscape: back to portrait.
  /// Portrait: the player closes.
  void _handleBack() {
    if (_locked.value) {
      _lockPoke.value++;
      return;
    }
    if (_isLandscape && !NativeBridge.pipMode.value) {
      unawaited(_setOrientations(_portraitOnly));
      return;
    }
    _closePlayer();
  }

  void _closePlayer() {
    _saveResumePoint();
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _restorePortraitChrome() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
      SystemChrome.setSystemUIOverlayStyle(
        const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: Colors.black,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(NativeBridge.refreshPictureInPictureState());
      if (_resumeAfterLeaving) {
        _resumeAfterLeaving = false;
        unawaited(_player.play());
      }
    } else if (state == AppLifecycleState.paused) {
      _saveResumePoint();
    }
  }

  void _showToast(
    String message, {
    Duration duration = const Duration(seconds: 1),
  }) {
    if (_disposed) return;
    _toastTimer?.cancel();
    _toast.value = message;
    _toastTimer = Timer(duration, () {
      if (!_disposed) _toast.value = null;
    });
  }

  /// Fit → Fill → Stretch → 16:9 → 4:3 → Fit. The picture changes at once and
  /// the new mode's name is shown for a second.
  void _cycleAspect() {
    final int next = (_aspectIndex + 1) % _aspectModes.length;
    setState(() => _aspectIndex = next);
    _showToast(_aspectModes[next].$1);
  }

  // ------------------------------------------- picture-in-picture and TV

  void _onPipChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _enterPip() async {
    final int width = _player.state.width ?? 0;
    final int height = _player.state.height ?? 0;
    final bool entered = await NativeBridge.enterPictureInPicture(
      width: width > 0 ? width : 16,
      height: height > 0 ? height : 9,
    );
    if (!entered && !_disposed) {
      showAppNotice(
        'Picture-in-picture could not start. Check that it is allowed for '
        '${SidifyBranding.appName} in Android settings.',
        duration: const Duration(seconds: 4),
      );
    }
  }

  /// "Play on TV": opens Android's own Cast screen, where the phone is
  /// mirrored to a TV on the same Wi-Fi. Playback continues on return.
  Future<void> _openCast() async {
    final bool wasPlaying = _player.state.playing;
    _resumeAfterLeaving = wasPlaying;
    final bool opened = await NativeBridge.openCastSettings();
    if (opened || _disposed) return;
    _resumeAfterLeaving = false;
    showAppNotice(
      'This device has no screen-cast setting to open.',
      duration: const Duration(seconds: 3),
    );
  }

  // ------------------------------------------------------ share / report

  String get _shareLine {
    final String year = (widget.detail?.year ?? '').trim();
    final String title = year.isNotEmpty && !_displayTitle.contains(year)
        ? '$_displayTitle ($year)'
        : _displayTitle;
    return 'Watching "$title" on ${SidifyBranding.appName}.';
  }

  Future<void> _share() async {
    final String text = _shareLine;
    final bool shared = await NativeBridge.shareText(text: text);
    if (shared || _disposed) return;
    await Clipboard.setData(ClipboardData(text: text));
    showAppNotice('Copied to clipboard');
  }

  static const List<MovieSheetOption> _reportReasons = <MovieSheetOption>[
    MovieSheetOption(
      id: 'Video does not play or keeps buffering',
      title: 'Video does not play or keeps buffering',
      icon: Icons.play_disabled_rounded,
    ),
    MovieSheetOption(
      id: 'Wrong movie or episode',
      title: 'Wrong movie or episode',
      icon: Icons.movie_filter_outlined,
    ),
    MovieSheetOption(
      id: 'Audio is missing, wrong or out of sync',
      title: 'Audio is missing, wrong or out of sync',
      icon: Icons.volume_off_outlined,
    ),
    MovieSheetOption(
      id: 'Subtitles are missing or wrong',
      title: 'Subtitles are missing or wrong',
      icon: Icons.closed_caption_disabled_outlined,
    ),
    MovieSheetOption(
      id: 'Poor picture quality',
      title: 'Poor picture quality',
      icon: Icons.blur_on_rounded,
    ),
    MovieSheetOption(
      id: 'Something else',
      title: 'Something else',
      icon: Icons.more_horiz_rounded,
    ),
  ];

  /// Report: pick what is wrong, and a ready-written mail opens in the
  /// phone's mail app. Nothing is sent until the person presses Send, and no
  /// stream address is included.
  Future<void> _report() async {
    final String? reason = await showMovieGlassSheet<String>(
      context,
      builder: (_) => MovieOptionsSheet(
        title: 'Report a problem',
        closeOnSelect: true,
        showSelection: false,
        read: () => _reportReasons,
        note: () => 'Opens your mail app with the details filled in.',
        onSelected: (_) async {},
      ),
    );
    if (reason == null || _disposed) return;

    final MovieDetail? detail = widget.detail;
    final String body = <String>[
      'Problem: $reason',
      '',
      'Title: $_displayTitle',
      if (_displaySubtitle.isNotEmpty) 'Playing: $_displaySubtitle',
      if (detail != null) 'Catalog: ${detail.provider.label}',
      if (widget.isLocal)
        'Source: downloaded file'
      else if (_candidates.isNotEmpty)
        'Server: ${_candidateIndex + 1} of ${_candidates.length}',
      'Position: ${movieClock(_lastKnownPosition)}',
      'App: ${SidifyBranding.appName} ${SidifyBranding.versionLabel}',
      'Device: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
      '',
      'Anything else we should know:',
      '',
    ].join('\n');
    final String subject = Uri.encodeComponent(
      'Video problem: $_displayTitle',
    );
    final String encodedBody = Uri.encodeComponent(body);
    final Uri mail = Uri(
      scheme: 'mailto',
      path: SidifyBranding.contactEmail,
      query: 'subject=$subject&body=$encodedBody',
    );
    bool opened = false;
    try {
      opened = await launchUrl(mail, mode: LaunchMode.externalApplication);
    } catch (_) {}
    if (!opened && !_disposed) {
      showAppNotice(
        'No mail app found. Write to ${SidifyBranding.contactEmail}',
        duration: const Duration(seconds: 5),
      );
    }
  }

  // ---------------------------------------------------- list and related

  /// This title as the library knows it (keyed by its page, exactly like the
  /// bookmark on the details page), or null for a downloaded file.
  MoviePost? get _libraryPost {
    final MovieDetail? detail = widget.detail;
    if (detail == null || detail.webUrl.trim().isEmpty) return null;
    return MoviePost(
      title: detail.title,
      link: detail.webUrl,
      imageUrl: detail.posterUrl,
      fallbackImageUrl: detail.fallbackPosterUrl,
      badge: detail.isSeries ? 'Series' : 'Movie',
      subtitle: detail.year,
      provider: detail.provider,
    );
  }

  void _toggleMyList(MovieLibraryService library, MoviePost post) {
    final bool wasSaved = library.contains(post);
    unawaited(library.toggleWatchlist(post));
    showAppNotice(wasSaved ? 'Removed from My List' : 'Added to My List');
  }

  /// A related title replaces the player with that title's page.
  void _openRelated(MoviePost post) {
    _saveResumePoint();
    unawaited(_player.pause());
    Navigator.of(context, rootNavigator: true).pushReplacement<void, void>(
      MaterialPageRoute<void>(
        builder: (_) => MovieDetailPage(initialPost: post),
        settings: const RouteSettings(name: 'sidify/movie-detail'),
      ),
    );
  }

  List<AudioTrack> get _realAudioTracks {
    return _tracks.audio
        .where((AudioTrack track) => track.id != 'auto' && track.id != 'no')
        .toList();
  }

  List<SubtitleTrack> get _realSubtitleTracks {
    return _tracks.subtitle
        .where(
          (SubtitleTrack track) => track.id != 'auto' && track.id != 'no',
        )
        .toList();
  }

  /// The name shown for one audio track.
  ///
  /// Muxers name their tracks after whoever uploaded the file, so the raw title
  /// arrives as something like `-eonmovies.com.hin.aac.2ch`. [describeAudioTrack]
  /// swaps that domain for ours and makes the rest readable — the language,
  /// codec and speaker layout all still say exactly what the file said.
  String _audioTrackLabel(AudioTrack track, int index) {
    return describeAudioTrack(
      title: scrubSourceNames(track.title ?? ''),
      language: track.language,
      codec: track.codec,
      channels: track.channelscount ?? 0,
      index: index,
    );
  }

  /// The same treatment for subtitle tracks.
  String _subtitleTrackLabel(SubtitleTrack track, int index) {
    return describeSubtitleTrack(
      title: scrubSourceNames(track.title ?? ''),
      language: track.language,
      codec: track.codec,
      index: index,
    );
  }

  Future<void> _setAudioTrack(
    AudioTrack track,
    String selectionId, {
    bool remember = true,
  }) async {
    try {
      _audioSelectionId = selectionId;
      if (remember) {
        final bool auto = selectionId == 'auto';
        _preferredAudioLanguage = auto ? '' : (track.language ?? '');
        _preferredAudioTitle = auto ? '' : (track.title ?? '');
      }
      await _player.setAudioTrack(track);
    } catch (_) {
      showAppNotice('Could not switch audio track.');
    }
  }

  Future<void> _setSubtitleTrack(
    SubtitleTrack track,
    String selectionId, {
    bool remember = true,
  }) async {
    try {
      _subtitleSelectionId = selectionId;
      if (remember) _subtitlesOff = selectionId == 'no';
      await _player.setSubtitleTrack(track);
    } catch (_) {
      showAppNotice('Could not switch subtitles.');
    }
  }

  /// A new stream (another quality, another mirror, a seek recovery) starts
  /// on its default tracks. Put back what the person had chosen: the same
  /// audio language, and subtitles off if they had turned them off.
  void _reapplyTrackChoices() {
    if (_disposed) return;
    final String language = _preferredAudioLanguage;
    final String title = _preferredAudioTitle;
    if (_audioSelectionId == 'auto' &&
        (language.isNotEmpty || title.isNotEmpty)) {
      AudioTrack? match;
      for (final AudioTrack track in _realAudioTracks) {
        final bool sameLanguage =
            language.isNotEmpty && (track.language ?? '') == language;
        final bool sameTitle = title.isNotEmpty && (track.title ?? '') == title;
        if (sameLanguage && sameTitle) {
          match = track;
          break;
        }
        if (match == null && (sameLanguage || sameTitle)) match = track;
      }
      if (match != null) {
        unawaited(_setAudioTrack(match, match.id, remember: false));
      }
    }
    if (_subtitlesOff && _subtitleSelectionId != 'no') {
      unawaited(_setSubtitleTrack(SubtitleTrack.no(), 'no', remember: false));
    }
  }

  Future<void> _setPlaybackRate(double rate) async {
    _rate = rate;
    await _safeSetRate(rate);
  }

  Future<void> _downloadCurrentQuality({MovieQualityLink? quality}) async {
    final MovieDownloadService? service = _downloadService;
    final MovieDetail? detail = widget.detail;
    final MovieQualityLink? target = quality ?? _downloadQuality;
    if (service == null || detail == null || target == null) return;

    try {
      final MovieDownloadItem item = await service.enqueueDownload(
        detail: detail,
        quality: target,
      );
      showAppNotice(
        item.status == MovieDownloadStatus.completed
            ? 'Already downloaded: $_displayTitle (${target.displayQuality})'
            : 'Download started: $_displayTitle (${target.displayQuality})',
      );
    } catch (error) {
      showAppNotice(
        'Could not start download. Please try again.',
        duration: const Duration(seconds: 2),
      );
    }
  }

  /// What the Playback Settings sheet shows right now — read from the player
  /// and from this title's real links, never invented.
  MoviePlaybackSettings _readPlaybackSettings() {
    _tracks = _player.state.tracks;
    final List<AudioTrack> audio = _realAudioTracks;
    final MovieDownloadItem? item = widget.localItem;

    final List<MovieSheetOption> qualities = <MovieSheetOption>[
      if (item != null && item.qualityLabel.trim().isNotEmpty)
        MovieSheetOption(
          id: 'local',
          title: item.qualityLabel,
          subtitle: item.sizeLabel,
          selected: true,
        ),
      if (!widget.isLocal)
        for (final MovieQualityLink quality
            in playableQualitiesBestFirst(_availableQualities))
          MovieSheetOption(
            id: quality.id,
            title: quality.displayQuality,
            subtitle: <String>[
              if (quality.sizeLabel.isNotEmpty) quality.sizeLabel,
              if (quality.languages.isNotEmpty) quality.languages,
            ].join(' • '),
            selected: quality.id == _currentQuality?.id,
          ),
    ];

    return MoviePlaybackSettings(
      speed: _rate,
      speeds: _speeds,
      qualities: qualities,
      qualityNote: widget.isLocal
          ? 'A downloaded file has the one quality it was saved in.'
          : (qualities.length <= 1
              ? 'This title is offered in a single quality.'
              : 'Changing quality continues from the same moment.'),
      audioTracks: <MovieSheetOption>[
        MovieSheetOption(
          id: 'auto',
          title: 'Auto',
          subtitle: "The video's default audio",
          selected: _audioSelectionId == 'auto',
        ),
        for (int i = 0; i < audio.length; i++)
          MovieSheetOption(
            id: audio[i].id,
            title: _audioTrackLabel(audio[i], i),
            selected: _audioSelectionId == audio[i].id,
          ),
      ],
      audioNote: audio.isEmpty
          ? 'Audio tracks appear once the video has loaded.'
          : (audio.length == 1 ? 'This video has one audio track.' : ''),
    );
  }

  void _showSettingsSheet() {
    unawaited(
      showMovieGlassSheet<void>(
        context,
        builder: (_) => MoviePlaybackSettingsSheet(
          read: _readPlaybackSettings,
          refresh: _sheetRefresh,
          onSpeed: _setPlaybackRate,
          onQuality: (String id) {
            for (final MovieQualityLink quality in _availableQualities) {
              if (quality.id == id) {
                unawaited(_switchQuality(quality));
                return;
              }
            }
          },
          onAudio: (String id) async {
            if (id == 'auto') {
              await _setAudioTrack(AudioTrack.auto(), 'auto');
              return;
            }
            for (final AudioTrack track in _realAudioTracks) {
              if (track.id == id) {
                await _setAudioTrack(track, id);
                return;
              }
            }
          },
        ),
      ),
    );
  }

  List<MovieSheetOption> _readSubtitleOptions() {
    _tracks = _player.state.tracks;
    final List<SubtitleTrack> subtitles = _realSubtitleTracks;
    return <MovieSheetOption>[
      MovieSheetOption(
        id: 'no',
        title: 'Off',
        selected: _subtitleSelectionId == 'no',
      ),
      MovieSheetOption(
        id: 'auto',
        title: 'Auto',
        subtitle: "The video's default subtitles, if it has any",
        selected: _subtitleSelectionId == 'auto',
      ),
      for (int i = 0; i < subtitles.length; i++)
        MovieSheetOption(
          id: subtitles[i].id,
          title: _subtitleTrackLabel(subtitles[i], i),
          selected: _subtitleSelectionId == subtitles[i].id,
        ),
    ];
  }

  void _showSubtitleSheet() {
    unawaited(
      showMovieGlassSheet<void>(
        context,
        builder: (_) => MovieOptionsSheet(
          title: 'Subtitles',
          refresh: _sheetRefresh,
          read: _readSubtitleOptions,
          note: () => _realSubtitleTracks.isEmpty
              ? 'No subtitles were found inside this video.'
              : '',
          onSelected: (MovieSheetOption option) async {
            if (option.id == 'no') {
              await _setSubtitleTrack(SubtitleTrack.no(), 'no');
              return;
            }
            if (option.id == 'auto') {
              await _setSubtitleTrack(SubtitleTrack.auto(), 'auto');
              return;
            }
            for (final SubtitleTrack track in _realSubtitleTracks) {
              if (track.id == option.id) {
                await _setSubtitleTrack(track, track.id);
                return;
              }
            }
          },
        ),
      ),
    );
  }

  /// The "finding a stream" card over the picture. It scales down to fit the
  /// small portrait player instead of overflowing it.
  Widget _buildLoadingOverlay(SidifyTokens t) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.38),
          alignment: Alignment.center,
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 14),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(color: t.brand),
                const SizedBox(height: 16),
                if (_loadingSubtitle.isNotEmpty) ...<Widget>[
                  Text(
                    _loadingSubtitle,
                    textAlign: TextAlign.center,
                    style: SidifyText.caption(Colors.white70),
                  ),
                  const SizedBox(height: 6),
                ],
                ValueListenableBuilder<String>(
                  valueListenable: _statusText,
                  builder: (_, String status, __) {
                    return Text(
                      status,
                      textAlign: TextAlign.center,
                      style: SidifyText.bodyS(Colors.white70),
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildErrorOverlay(SidifyTokens t, String message) {
    final bool offline = !widget.isLocal && message == _offlineLine;
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.82),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                offline
                    ? Icons.download_for_offline_rounded
                    : Icons.error_outline_rounded,
                size: 46,
                color: offline ? t.brand : t.danger,
              ),
              const SizedBox(height: 16),
              Text(
                offline ? 'Not streamable right now' : "Couldn't start playback",
                textAlign: TextAlign.center,
                style: SidifyText.titleM(Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: SidifyText.bodyS(Colors.white70),
              ),
              if (offline) ...<Widget>[
                const SizedBox(height: 6),
                Text(
                  'Downloading keeps the highest quality available and plays '
                  'without a connection.',
                  textAlign: TextAlign.center,
                  style: SidifyText.caption(Colors.white54),
                ),
              ],
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  // Right beside the message, as asked: the way to still
                  // watch this title is to download it once.
                  if (offline)
                    FilledButton.icon(
                      onPressed: () => unawaited(
                        _downloadCurrentQuality(quality: _bestDownloadQuality),
                      ),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Download'),
                      style: FilledButton.styleFrom(
                        backgroundColor: t.brand,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: () => unawaited(_retryPlayback()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                    style: FilledButton.styleFrom(
                      backgroundColor:
                          offline ? Colors.white24 : t.brand,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _closePlayer,
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Back'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white38),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The portrait layout's lower half.
  Widget _buildInfoPanel(MovieLibraryService? library) {
    final MovieDetail? detail = widget.detail;
    final MovieDownloadItem? item = widget.localItem;
    final MovieQualityLink? quality = _currentQuality;
    final MoviePost? post = _libraryPost;
    final bool saved =
        library != null && post != null && library.contains(post);

    final List<String> meta = <String>[];
    if (item != null) {
      meta.add(item.subtitleSummary);
    } else if (detail != null) {
      meta.add(detail.year);
      if (quality != null) {
        final String season = quality.seasonLabel.isNotEmpty
            ? quality.seasonLabel
            : detail.defaultSeasonLabel;
        if (detail.isSeries || quality.episodeLabel.isNotEmpty) {
          meta.add(season);
          meta.add(quality.episodeLabel);
        }
        // The resolution is only named once it is really on screen.
        if (_ready) meta.add(quality.displayQuality);
        meta.add(
          quality.languages.isNotEmpty ? quality.languages : detail.languages,
        );
      }
    }

    return MoviePlayerInfoPanel(
      title: _displayTitle,
      meta: meta,
      rating: detail?.rating ?? '',
      genres: detail?.genres ?? const <String>[],
      synopsis: detail?.synopsis ?? '',
      actions: <MoviePlayerAction>[
        if (library != null && post != null)
          MoviePlayerAction(
            icon: saved ? Icons.check_rounded : Icons.add_rounded,
            label: 'My List',
            active: saved,
            onTap: () => _toggleMyList(library, post),
          ),
        if (!widget.isLocal)
          MoviePlayerAction(
            icon: Icons.download_rounded,
            label: 'Download',
            onTap: () => unawaited(_downloadCurrentQuality()),
          ),
        MoviePlayerAction(
          icon: Icons.share_outlined,
          label: 'Share',
          onTap: () => unawaited(_share()),
        ),
        MoviePlayerAction(
          icon: Icons.flag_outlined,
          label: 'Report',
          onTap: () => unawaited(_report()),
        ),
        if (Platform.isAndroid)
          MoviePlayerAction(
            icon: Icons.cast_rounded,
            label: 'Play on TV',
            onTap: () => unawaited(_openCast()),
          ),
      ],
      serverCount: widget.isLocal ? 0 : _candidates.length,
      currentServer: _candidateIndex,
      failedServers: _failedCandidates,
      onServer: (int index) => unawaited(_switchToCandidate(index)),
      related: detail?.relatedPosts ?? const <MoviePost>[],
      onRelated: _openRelated,
      footnote: widget.isLocal
          ? 'Playing from this device — no mobile data is used.'
          : '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final String? error = _errorMessage;
    final MovieLibraryService? library = context.watch<MovieLibraryService?>();

    // Picture-in-picture is the whole app shrunk into a small window: show
    // nothing in it but the video.
    final bool pip = NativeBridge.pipMode.value;
    final Size size = MediaQuery.sizeOf(context);
    final bool landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final bool immersive = landscape || pip;
    if (!pip) _syncSystemChrome(landscape);

    final (String aspectLabel, BoxFit fit, double? aspectRatio) =
        _aspectModes[_aspectIndex];

    // The one Video. Its GlobalKey moves it between the two layouts below
    // without rebuilding it, so the stream is never reopened on rotation.
    final Widget stage = ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Video(
            key: _videoKey,
            controller: _controller,
            // The controls are ours (MoviePlayerControls), drawn above.
            controls: null,
            fit: fit,
            aspectRatio: aspectRatio,
            fill: Colors.black,
            wakelock: true,
            pauseUponEnteringBackgroundMode: true,
            resumeUponEnteringForegroundMode: false,
          ),
          if (_loading && !pip) _buildLoadingOverlay(t),
          if (!pip && error == null)
            Positioned.fill(
              child: MoviePlayerControls(
                player: _player,
                title: _displayTitle,
                status: _statusText,
                pendingSeek: _pendingSeek,
                locked: _locked,
                lockPoke: _lockPoke,
                toast: _toast,
                immersive: immersive,
                interactive: _ready && !_loading,
                showCast: Platform.isAndroid,
                showPip: _pipSupported,
                aspectLabel: aspectLabel,
                onBack: _handleBack,
                onSubtitles: _showSubtitleSheet,
                onSettings: _showSettingsSheet,
                onCast: () => unawaited(_openCast()),
                onPip: () => unawaited(_enterPip()),
                onToggleFullscreen: _toggleFullscreen,
                onCycleAspect: _cycleAspect,
                onSeekRelative: (Duration offset) =>
                    unawaited(_seekRelative(offset)),
                onSeekStart: _handleSeekBarStart,
                onSeekTo: _handleSeekBarSeek,
                onDownload: widget.isLocal
                    ? null
                    : () => unawaited(_downloadCurrentQuality()),
              ),
            ),
        ],
      ),
    );

    final Widget body;
    if (immersive) {
      // Landscape: the video is the screen.
      body = stage;
    } else {
      // Portrait: a 16:9 player on top (never more than half the screen, for
      // tablets and unfolded phones), the title's details scrolling below.
      final double wanted = size.width * 9 / 16;
      final double limit = size.height * 0.5;
      body = SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            SizedBox(
              width: double.infinity,
              height: wanted < limit ? wanted : limit,
              child: stage,
            ),
            Expanded(child: _buildInfoPanel(library)),
          ],
        ),
      );
    }

    return PopScope(
      // Back is decided by the player: locked → nothing, landscape → portrait,
      // portrait → close.
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop) _handleBack();
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              body,
              if (error != null && !pip) _buildErrorOverlay(t, error),
            ],
          ),
        ),
      ),
    );
  }
}
