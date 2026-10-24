import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:provider/provider.dart';

import '../../core/services/app_feedback.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../../core/utils/track_labels.dart';
import '../models/movie_models.dart';
import '../services/eon_movies_service.dart';
import '../services/movie_download_service.dart';
import '../services/movie_quality_order.dart';
import '../services/movie_seek_runner.dart';

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

class _MoviePlayerPageState extends State<MoviePlayerPage> {
  static const List<double> _speeds = <double>[
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
  late final MaterialVideoControlsThemeData _controlsTheme;

  final GlobalKey<VideoState> _videoKey = GlobalKey<VideoState>();
  final ValueNotifier<String> _statusText =
      ValueNotifier<String>('Preparing player…');
  final ValueNotifier<bool> _buffering = ValueNotifier<bool>(false);

  /// The timestamp a seek was asked for and has not been confirmed yet. The
  /// seek bar holds the thumb there instead of letting the position events
  /// that are still arriving from the *old* place drag it back — that snap
  /// back is what made a long drag look like it had failed while the mirror
  /// was in fact still being asked.
  final ValueNotifier<Duration?> _pendingSeek = ValueNotifier<Duration?>(null);

  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  EonMoviesService? _moviesService;
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
  bool _hasAutoEnteredFullscreen = false;
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
  BoxFit _fit = BoxFit.contain;
  Tracks _tracks = const Tracks();
  String _audioSelectionId = 'auto';
  String _subtitleSelectionId = 'auto';

  String get _displayTitle {
    final MovieDownloadItem? item = widget.localItem;
    if (item != null) return item.movieTitle;
    final MovieDetail? detail = widget.detail;
    if (detail == null) return 'Video Player';
    return detail.cleanTitle.isNotEmpty ? detail.cleanTitle : detail.title;
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
    // Playback always starts on the best stream on offer — not on whatever
    // row was tapped. The pick drops one step at a time if it is dead.
    _currentQuality = _availableQualities.isNotEmpty
        ? _availableQualities.first
        : widget.initialQuality;
    _player = Player();
    _controller = VideoController(_player);
    _controlsTheme = _buildControlsTheme();
    _listenToPlayer();
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

    _moviesService = context.read<EonMoviesService>();
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
    _disposed = true;
    _generation++;
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
    return playableQualitiesBestFirst(source);
  }

  MaterialVideoControlsThemeData _buildControlsTheme() {
    // media_kit compares normal/fullscreen theme data by identity when
    // deciding whether dependents should update. Build one instance once and
    // reuse that exact object for both slots; dynamic text goes through the
    // ValueNotifier below instead of rebuilding theme data.
    return MaterialVideoControlsThemeData(
      automaticallyImplySkipNextButton: false,
      automaticallyImplySkipPreviousButton: false,
      volumeGesture: true,
      brightnessGesture: true,
      seekGesture: true,
      seekOnDoubleTap: true,
      seekOnDoubleTapBackwardDuration: const Duration(seconds: 10),
      seekOnDoubleTapForwardDuration: const Duration(seconds: 10),
      visibleOnMount: true,
      backdropColor: Colors.black.withValues(alpha: 0.45),
      primaryButtonBar: <Widget>[
        const Spacer(flex: 2),
        MaterialCustomButton(
          icon: const Icon(Icons.replay_10_rounded),
          onPressed: () =>
              unawaited(_seekRelative(const Duration(seconds: -10))),
        ),
        const Spacer(),
        const MaterialPlayOrPauseButton(iconSize: 56),
        const Spacer(),
        MaterialCustomButton(
          icon: const Icon(Icons.forward_10_rounded),
          onPressed: () =>
              unawaited(_seekRelative(const Duration(seconds: 10))),
        ),
        const Spacer(flex: 2),
      ],
      topButtonBar: <Widget>[
        MaterialCustomButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => unawaited(_closePlayer()),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: _statusText,
            builder: (_, String status, __) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        if (!widget.isLocal)
          MaterialCustomButton(
            icon: const Icon(Icons.download_rounded),
            onPressed: () => unawaited(_downloadCurrentQuality()),
          ),
      ],
      // The seek bar is ours, not media_kit's: it is mounted above the button
      // row (clear of Android's bottom gesture strip), it seeks on a plain tap
      // to where the finger landed, and a drag follows the finger live. The
      // built-in bar only moved on a completed drag — a tap jumped at a stale
      // value — which is why tapping or dragging it never landed on the frame
      // people aimed at.
      bottomButtonBar: <Widget>[
        Expanded(
          child: SizedBox(
            height: 80,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  height: 32,
                  child: _MovieSeekBar(
                    player: _player,
                    pendingSeek: _pendingSeek,
                    onSeekStart: _handleSeekBarStart,
                    onSeek: _handleSeekBarSeek,
                    onSeekEnd: _handleSeekBarEnd,
                  ),
                ),
                SizedBox(
                  height: 48,
                  child: Row(
                    children: <Widget>[
                      const MaterialPositionIndicator(
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      MaterialCustomButton(
                        icon: const Icon(Icons.tune_rounded),
                        onPressed: _showSettingsSheet,
                      ),
                      const MaterialFullscreenButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
      buttonBarButtonColor: Colors.white,
      displaySeekBar: false,
      buttonBarHeight: 80,
      bottomButtonBarMargin:
          const EdgeInsets.only(left: 12, right: 4, bottom: 16),
      topButtonBarMargin: const EdgeInsets.only(left: 8, right: 8, top: 4),
      controlsHoverDuration: const Duration(seconds: 5),
      // The transient double-tap seek indicator keeps the same red as the
      // player's own bar.
      seekBarHeight: 3,
      seekBarContainerHeight: 30,
      seekBarThumbSize: 12,
      seekBarColor: Colors.white24,
      seekBarPositionColor: const Color(0xFFFA2D48),
      seekBarBufferColor: Colors.white38,
      seekBarThumbColor: const Color(0xFFFA2D48),
      shiftSubtitlesOnControlsVisibilityChange: true,
    );
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
      }),
      _player.stream.rate.listen((double rate) {
        if (rate > 0) _rate = rate;
      }),
      _player.stream.tracks.listen((Tracks tracks) {
        _tracks = tracks;
      }),
      _player.stream.completed.listen((bool completed) {
        if (!completed || _disposed) return;
        _desiredPlaying = false;
        _startupTimer?.cancel();
        _setStatus('Playback finished');
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
    if (widget.isLocal) {
      await _openLocalFile(start: Duration.zero);
      return;
    }

    final MovieQualityLink? quality = _currentQuality;
    if (quality == null) {
      _showFatalError('No playable quality was provided.');
      return;
    }
    await _resolveAndOpenQuality(quality, start: Duration.zero);
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
    final EonMoviesService? service = _moviesService;
    final MovieDetail? detail = widget.detail;
    if (service == null || detail == null) {
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
      final ResolvedMovieStream resolved = await service.resolvePlaybackStream(
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
        // This quality's link is dead (or the page never started): step down
        // to the next one instead of bothering the person with it.
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

  /// True when there is a lower, untried quality to fall back to.
  MovieQualityLink? _nextQualityAfter(MovieQualityLink? current) {
    if (_availableQualities.isEmpty) return null;
    final int from = current == null
        ? -1
        : _availableQualities.indexWhere(
            (MovieQualityLink q) => q.id == current.id,
          );
    // Deliberately only *down* the list: 1080p -> 720p -> 480p. Once the
    // bottom is reached the title is treated as not streamable.
    for (int i = from + 1; i < _availableQualities.length; i++) {
      if (!_failedQualities.contains(_availableQualities[i].id)) {
        return _availableQualities[i];
      }
    }
    return null;
  }

  /// Marks the current quality dead and tries the next-lower one. When every
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
      // Every mirror of this quality is dead — step down to the next-lower
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

    if (!_hasAutoEnteredFullscreen) {
      _hasAutoEnteredFullscreen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed) {
          unawaited(_enterFullscreenSafely());
        }
      });
    }
  }

  String _healthyStatusText() {
    if (widget.isLocal) {
      return _displaySubtitle.isNotEmpty
          ? 'Local playback • $_displaySubtitle'
          : 'Local playback';
    }
    return 'Playing';
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

    // Retry means retry *everything* again, best quality first: the list of
    // qualities and mirrors that failed a moment ago is cleared.
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
    unawaited(_exitFullscreenSafely());
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
    unawaited(_exitFullscreenSafely());
  }

  /// The quality the download button should save: the one on screen when
  /// something is playing, otherwise the best one this title has.
  MovieQualityLink? get _downloadQuality {
    if (widget.isLocal) return null;
    return _currentQuality ??
        (_availableQualities.isNotEmpty
            ? _availableQualities.first
            : widget.initialQuality);
  }

  /// When streaming failed at every quality, the offline copy should still be
  /// the best one available.
  MovieQualityLink? get _bestDownloadQuality {
    if (widget.isLocal) return null;
    if (_availableQualities.isNotEmpty) return _availableQualities.first;
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
    await _seekTo(_player.state.position + offset);
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
  String _jumpingStatus(Duration target) => 'Jumping to ${_movieClock(target)}…';

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

  void _handleSeekBarEnd() {}

  Future<void> _enterFullscreenSafely() async {
    try {
      final VideoState? state = _videoKey.currentState;
      if (state != null && !state.isFullscreen()) {
        await state.enterFullscreen();
      }
    } catch (_) {}
  }

  Future<void> _exitFullscreenSafely() async {
    try {
      final VideoState? state = _videoKey.currentState;
      if (state != null && state.isFullscreen()) {
        await state.exitFullscreen();
      }
    } catch (_) {}
  }

  Future<void> _closePlayer() async {
    try {
      final VideoState? state = _videoKey.currentState;
      if (state != null && state.isFullscreen()) {
        await state.exitFullscreen();
        return;
      }
    } catch (_) {}
    if (mounted) {
      await Navigator.of(context, rootNavigator: true).maybePop();
    }
  }

  Future<void> _enterFullscreenChrome() async {
    try {
      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
      await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    } catch (_) {}
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
      title: track.title,
      language: track.language,
      codec: track.codec,
      channels: track.channelscount ?? 0,
      index: index,
    );
  }

  /// The same treatment for subtitle tracks.
  String _subtitleTrackLabel(SubtitleTrack track, int index) {
    return describeSubtitleTrack(
      title: track.title,
      language: track.language,
      codec: track.codec,
      index: index,
    );
  }

  Future<void> _setAudioTrack(AudioTrack track, String selectionId) async {
    try {
      _audioSelectionId = selectionId;
      await _player.setAudioTrack(track);
    } catch (_) {
      showAppNotice('Could not switch audio track.');
    }
  }

  Future<void> _setSubtitleTrack(
    SubtitleTrack track,
    String selectionId,
  ) async {
    try {
      _subtitleSelectionId = selectionId;
      await _player.setSubtitleTrack(track);
    } catch (_) {
      showAppNotice('Could not switch subtitles.');
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

  void _showSettingsSheet() {
    // Refresh from the synchronous player state in case a track event has
    // arrived since the last stream callback was processed.
    _tracks = _player.state.tracks;

    showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setSheetState) {
            final SidifyTokens t = context.sidify;
            final List<AudioTrack> audioTracks = _realAudioTracks;
            final List<SubtitleTrack> subtitleTracks = _realSubtitleTracks;

            return SafeArea(
              child: Container(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.84,
                ),
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
                decoration: BoxDecoration(
                  color: t.bg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: t.edge),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Center(
                        child: Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                            color: t.fill3,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: <Widget>[
                          Icon(Icons.tune_rounded, color: t.brand, size: 21),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  'Playback settings',
                                  style: SidifyText.titleM(t.text),
                                ),
                                if (_displaySubtitle.isNotEmpty)
                                  Text(
                                    _displaySubtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: SidifyText.caption(t.text2),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Close settings',
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(),
                            icon: Icon(Icons.close_rounded, color: t.text2),
                          ),
                        ],
                      ),
                      if (!widget.isLocal && _candidates.isNotEmpty) ...<Widget>[
                        _settingsSectionHeader(
                          t,
                          icon: Icons.dns_rounded,
                          title: 'Server / Mirror',
                        ),
                        for (int i = 0; i < _candidates.length; i++)
                          _settingsOptionTile(
                            t,
                            title: 'Ifallertzia ${i + 1}',
                            subtitle: i == _candidateIndex
                                ? 'Current mirror'
                                : _failedCandidates.contains(i)
                                    ? 'Failed earlier — tap to retry'
                                    : 'Tap to switch mirror',
                            selected: i == _candidateIndex,
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              unawaited(_switchToCandidate(i));
                            },
                          ),
                      ],
                      if (!widget.isLocal &&
                          _availableQualities.isNotEmpty) ...<Widget>[
                        _settingsSectionHeader(
                          t,
                          icon: Icons.high_quality_rounded,
                          title: 'Quality',
                        ),
                        for (final MovieQualityLink quality
                            in _availableQualities)
                          _settingsOptionTile(
                            t,
                            title: quality.displayQuality,
                            subtitle: <String>[
                              if (quality.sizeLabel.isNotEmpty)
                                quality.sizeLabel,
                              if (quality.languages.isNotEmpty)
                                quality.languages,
                            ].join(' • '),
                            selected: quality.id == _currentQuality?.id,
                            onTap: () {
                              Navigator.of(sheetContext).pop();
                              unawaited(_switchQuality(quality));
                            },
                          ),
                      ],
                      _settingsSectionHeader(
                        t,
                        icon: Icons.audiotrack_rounded,
                        title: 'Audio Language',
                      ),
                      _settingsOptionTile(
                        t,
                        title: 'Auto',
                        subtitle: 'Use the default audio track',
                        selected: _audioSelectionId == 'auto',
                        onTap: () async {
                          await _setAudioTrack(AudioTrack.auto(), 'auto');
                          if (context.mounted) setSheetState(() {});
                        },
                      ),
                      for (int i = 0; i < audioTracks.length; i++)
                        _settingsOptionTile(
                          t,
                          title: _audioTrackLabel(audioTracks[i], i),
                          selected: _audioSelectionId == audioTracks[i].id,
                          onTap: () async {
                            await _setAudioTrack(
                              audioTracks[i],
                              audioTracks[i].id,
                            );
                            if (context.mounted) setSheetState(() {});
                          },
                        ),
                      if (audioTracks.isEmpty)
                        _settingsInfoText(
                          t,
                          'Alternate audio tracks will appear after the video loads.',
                        ),
                      _settingsSectionHeader(
                        t,
                        icon: Icons.subtitles_rounded,
                        title: 'Subtitles',
                      ),
                      _settingsOptionTile(
                        t,
                        title: 'Off',
                        selected: _subtitleSelectionId == 'no',
                        onTap: () async {
                          await _setSubtitleTrack(SubtitleTrack.no(), 'no');
                          if (context.mounted) setSheetState(() {});
                        },
                      ),
                      _settingsOptionTile(
                        t,
                        title: 'Auto',
                        subtitle: 'Use the default subtitle track, if any',
                        selected: _subtitleSelectionId == 'auto',
                        onTap: () async {
                          await _setSubtitleTrack(
                            SubtitleTrack.auto(),
                            'auto',
                          );
                          if (context.mounted) setSheetState(() {});
                        },
                      ),
                      for (int i = 0; i < subtitleTracks.length; i++)
                        _settingsOptionTile(
                          t,
                          title: _subtitleTrackLabel(subtitleTracks[i], i),
                          selected:
                              _subtitleSelectionId == subtitleTracks[i].id,
                          onTap: () async {
                            await _setSubtitleTrack(
                              subtitleTracks[i],
                              subtitleTracks[i].id,
                            );
                            if (context.mounted) setSheetState(() {});
                          },
                        ),
                      if (subtitleTracks.isEmpty)
                        _settingsInfoText(
                          t,
                          'No embedded subtitle tracks were found in this file.',
                        ),
                      _settingsSectionHeader(
                        t,
                        icon: Icons.speed_rounded,
                        title: 'Playback Speed',
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final double speed in _speeds)
                            ChoiceChip(
                              label: Text(_formatSpeed(speed)),
                              selected: (speed - _rate).abs() < 0.001,
                              onSelected: (bool selected) async {
                                if (!selected) return;
                                await _setPlaybackRate(speed);
                                if (context.mounted) setSheetState(() {});
                              },
                            ),
                        ],
                      ),
                      _settingsSectionHeader(
                        t,
                        icon: Icons.aspect_ratio_rounded,
                        title: 'Aspect ratio',
                      ),
                      for (final (BoxFit fit, String label, String hint) in <(BoxFit, String, String)>[
                        (BoxFit.contain, 'Fit screen', 'Whole video visible'),
                        (BoxFit.cover, 'Fill screen', 'Crop to fill the screen'),
                        (BoxFit.fill, 'Stretch', 'Stretch to the screen'),
                      ])
                        _settingsOptionTile(
                          t,
                          title: label,
                          subtitle: hint,
                          selected: _fit == fit,
                          onTap: () {
                            if (mounted) {
                              setState(() => _fit = fit);
                            }
                            setSheetState(() {});
                          },
                        ),
                      if (!widget.isLocal) ...<Widget>[
                        const SizedBox(height: 8),
                        _settingsSectionHeader(
                          t,
                          icon: Icons.download_rounded,
                          title: 'Download',
                        ),
                        _settingsOptionTile(
                          t,
                          title: 'Download current quality',
                          subtitle: _currentQuality?.displayQuality ?? '',
                          selected: false,
                          leadingIcon: Icons.download_rounded,
                          onTap: () {
                            Navigator.of(sheetContext).pop();
                            unawaited(_downloadCurrentQuality());
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatSpeed(double speed) {
    final String text = speed.toStringAsFixed(2)
        .replaceFirst(RegExp(r'\.00$'), '')
        .replaceFirst(RegExp(r'0$'), '');
    return '${text}x';
  }

  Widget _settingsSectionHeader(
    SidifyTokens t, {
    required IconData icon,
    required String title,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 6),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 17, color: t.brand),
          const SizedBox(width: 7),
          Text(title, style: SidifyText.label(t.text)),
        ],
      ),
    );
  }

  Widget _settingsOptionTile(
    SidifyTokens t, {
    required String title,
    String subtitle = '',
    required bool selected,
    required VoidCallback onTap,
    IconData? leadingIcon,
  }) {
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(
        leadingIcon ??
            (selected
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked_rounded),
        color: selected || leadingIcon != null ? t.brand : t.text3,
        size: 21,
      ),
      title: Text(title, style: SidifyText.bodyS(t.text)),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, style: SidifyText.caption(t.text2)),
      onTap: onTap,
    );
  }

  Widget _settingsInfoText(SidifyTokens t, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
      child: Text(text, style: SidifyText.caption(t.text2)),
    );
  }

  Widget _buildLoadingOverlay(SidifyTokens t) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withValues(alpha: 0.38),
          alignment: Alignment.center,
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                CircularProgressIndicator(color: t.brand),
                const SizedBox(height: 18),
                Text(
                  _displayTitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SidifyText.titleM(Colors.white),
                ),
                if (_loadingSubtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    _loadingSubtitle,
                    textAlign: TextAlign.center,
                    style: SidifyText.caption(Colors.white70),
                  ),
                ],
                const SizedBox(height: 10),
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
                    onPressed: () => unawaited(_closePlayer()),
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

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final String? error = _errorMessage;

    return Scaffold(
      backgroundColor: Colors.black,
      body: MaterialVideoControlsTheme(
        normal: _controlsTheme,
        fullscreen: _controlsTheme,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Video(
              key: _videoKey,
              controller: _controller,
              controls: MaterialVideoControls,
              fit: _fit,
              fill: Colors.black,
              wakelock: true,
              pauseUponEnteringBackgroundMode: true,
              resumeUponEnteringForegroundMode: false,
              onEnterFullscreen: _enterFullscreenChrome,
              onExitFullscreen: _restorePortraitChrome,
            ),
            if (_loading) _buildLoadingOverlay(t),
            Positioned.fill(
              child: ValueListenableBuilder<bool>(
                valueListenable: _buffering,
                builder: (_, bool buffering, __) {
                  if (!buffering || _loading || error != null) {
                    return const SizedBox.shrink();
                  }
                  return const IgnorePointer(
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          CircularProgressIndicator(color: Colors.white),
                          SizedBox(height: 12),
                          Text(
                            'Buffering…',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            if (error != null) _buildErrorOverlay(t, error),
          ],
        ),
      ),
    );
  }
}


/// `1:02:03` / `42:10` — one formatter for the bar, the drag bubble and the
/// status line.
String _movieClock(Duration d) {
  final int h = d.inHours;
  final int m = d.inMinutes.remainder(60);
  final String s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// The player's own seek bar.
///
/// The stock material bar was the reason seeking felt broken: it is only 30 px
/// tall at the very bottom of the screen (over Android's gesture strip, where
/// a drag is often taken by the system), and on a plain tap it seeks to the
/// *previous* drag value instead of where the finger went down.
///
/// This one is a 32 px tall grab area mounted above the button row (well clear
/// of the bottom gesture strip), with a 5 px track and a 16 px thumb. A tap
/// lands exactly where the finger went down; a drag scrubs live and shows the
/// target timestamp above the thumb while the finger is on the bar.
class _MovieSeekBar extends StatefulWidget {
  const _MovieSeekBar({
    required this.player,
    required this.pendingSeek,
    required this.onSeekStart,
    required this.onSeek,
    required this.onSeekEnd,
  });

  final Player player;

  /// The timestamp a seek was asked for and has not been confirmed yet. While
  /// it is set the bar draws *that*, not the position events still arriving
  /// from where the video used to be.
  final ValueNotifier<Duration?> pendingSeek;

  final VoidCallback onSeekStart;
  final void Function(Duration target) onSeek;
  final VoidCallback onSeekEnd;

  @override
  State<_MovieSeekBar> createState() => _MovieSeekBarState();
}

class _MovieSeekBarState extends State<_MovieSeekBar> {
  static const Color _accent = Color(0xFFFA2D48);
  static const double _track = 5;
  static const double _height = 32;
  static const double _thumb = 16;

  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  Duration _buffer = Duration.zero;

  /// 0..1 while a finger is on the bar; null when it follows the video.
  double? _drag;

  @override
  void initState() {
    super.initState();
    _position = widget.player.state.position;
    _duration = widget.player.state.duration;
    _buffer = widget.player.state.buffer;
    widget.pendingSeek.addListener(_onPendingSeekChanged);
    _subs.addAll(<StreamSubscription<dynamic>>[
      widget.player.stream.position.listen((Duration value) {
        if (!mounted) return;
        setState(() => _position = value);
      }),
      widget.player.stream.duration.listen((Duration value) {
        if (!mounted) return;
        setState(() => _duration = value);
      }),
      widget.player.stream.buffer.listen((Duration value) {
        if (!mounted) return;
        setState(() => _buffer = value);
      }),
      widget.player.stream.completed.listen((bool done) {
        if (!mounted || !done) return;
        setState(() => _position = Duration.zero);
      }),
    ]);
  }

  @override
  void dispose() {
    widget.pendingSeek.removeListener(_onPendingSeekChanged);
    for (final StreamSubscription<dynamic> sub in _subs) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }

  void _onPendingSeekChanged() {
    if (mounted) setState(() {});
  }

  double get _played {
    final double? drag = _drag;
    if (drag != null) return drag;
    final int total = _duration.inMilliseconds;
    if (total <= 0) return 0;
    // A drag that has been let go of but not landed yet stays under the
    // finger's last position. Letting the stale position stream pull the thumb
    // back is what made a long seek look like it never happened.
    final Duration shown = widget.pendingSeek.value ?? _position;
    return (shown.inMilliseconds / total).clamp(0.0, 1.0);
  }

  double get _buffered {
    final int total = _duration.inMilliseconds;
    if (total <= 0) return 0;
    return (_buffer.inMilliseconds / total).clamp(0.0, 1.0);
  }

  void _seekToFraction(double fraction) {
    if (_duration <= Duration.zero) return;
    widget.onSeek(_duration * fraction.clamp(0.0, 1.0));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        double fractionOf(Offset local) => width <= 0
            ? 0
            : (local.dx / width).clamp(0.0, 1.0);
        final double played = _played;
        final double buffered = _buffered;
        final double maxThumbX = width > _thumb ? width - _thumb : 0;
        final double thumbX = (played * width - _thumb / 2)
            .clamp(0.0, maxThumbX);

        Widget bar(double fraction, Color color) => Positioned(
              left: 0,
              width: width * fraction,
              child: Container(
                height: _track,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            );

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails details) {
            final double fraction = fractionOf(details.localPosition);
            widget.onSeekStart();
            _seekToFraction(fraction);
            widget.onSeekEnd();
          },
          onHorizontalDragStart: (DragStartDetails details) {
            widget.onSeekStart();
            setState(() => _drag = fractionOf(details.localPosition));
          },
          onHorizontalDragUpdate: (DragUpdateDetails details) {
            setState(() => _drag = fractionOf(details.localPosition));
          },
          onHorizontalDragEnd: (DragEndDetails details) {
            final double? fraction = _drag;
            setState(() => _drag = null);
            if (fraction != null) _seekToFraction(fraction);
            widget.onSeekEnd();
          },
          onHorizontalDragCancel: () {
            setState(() => _drag = null);
            widget.onSeekEnd();
          },
          child: SizedBox(
            height: _height,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: <Widget>[
                bar(1, Colors.white24),
                bar(buffered, Colors.white38),
                bar(played, _accent),
                Positioned(
                  left: thumbX,
                  child: Container(
                    width: _thumb,
                    height: _thumb,
                    decoration: const BoxDecoration(
                      color: _accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                if (_drag != null)
                  Positioned(
                    left: (thumbX - 26).clamp(
                      0.0,
                      width > 52 ? width - 52 : 0.0,
                    ),
                    bottom: _height - 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        _movieClock(_duration * _drag!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
