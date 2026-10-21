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
import '../models/movie_models.dart';
import '../services/eon_movies_service.dart';
import '../services/movie_download_service.dart';

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
  final List<StreamSubscription<dynamic>> _subscriptions =
      <StreamSubscription<dynamic>>[];

  EonMoviesService? _moviesService;
  MovieDownloadService? _downloadService;
  PlaybackService? _musicPlayback;

  List<MovieQualityLink> _availableQualities = const <MovieQualityLink>[];
  MovieQualityLink? _currentQuality;
  List<MovieStreamCandidate> _candidates = const <MovieStreamCandidate>[];
  final Set<int> _failedCandidates = <int>{};
  int _candidateIndex = -1;

  Timer? _startupTimer;
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

  @override
  void initState() {
    super.initState();
    _availableQualities = _buildAvailableQualities();
    _currentQuality = widget.initialQuality;
    _player = Player();
    _controller = VideoController(_player);
    _controlsTheme = _buildControlsTheme();
    _listenToPlayer();
    final String qualityLabel = widget.initialQuality?.displayQuality ?? '';
    _setStatus(
      widget.isLocal
          ? 'Opening video…'
          : qualityLabel.isNotEmpty
              ? 'Finding streams for $qualityLabel…'
              : 'Finding streams…',
    );
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
    for (final StreamSubscription<dynamic> sub in _subscriptions) {
      unawaited(sub.cancel());
    }
    _statusText.dispose();
    _buffering.dispose();
    unawaited(_player.dispose());
    unawaited(_restorePortraitChrome());
    super.dispose();
  }

  List<MovieQualityLink> _buildAvailableQualities() {
    if (widget.isLocal) return const <MovieQualityLink>[];
    final MovieQualityLink initial = widget.initialQuality!;
    final List<MovieQualityLink> source = widget.qualities.isNotEmpty
        ? widget.qualities
        : <MovieQualityLink>[initial];
    final Map<String, MovieQualityLink> byId = <String, MovieQualityLink>{};
    for (final MovieQualityLink quality in source) {
      if (EonMoviesService.canAttemptOnlinePlayback(quality)) {
        byId.putIfAbsent(quality.id, () => quality);
      }
    }
    if (EonMoviesService.canAttemptOnlinePlayback(initial)) {
      byId.putIfAbsent(initial.id, () => initial);
    }
    return List<MovieQualityLink>.unmodifiable(byId.values);
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
      controlsHoverDuration: const Duration(seconds: 3),
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
      bottomButtonBar: <Widget>[
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
      buttonBarButtonColor: Colors.white,
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
        if (_ready && _errorMessage == null) {
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
      _armStartupTimer(generation);
    } catch (error) {
      if (_isCurrentGeneration(generation)) {
        _showFatalError('Could not play this downloaded file.');
      }
    }
  }

  Future<void> _resolveAndOpenQuality(
    MovieQualityLink quality, {
    Duration? start,
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
    _isResolving = true;
    _setStatus('Finding streams for ${quality.displayQuality}…');
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
      _candidateIndex = -1;
      _currentQuality = quality;

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
      if (_ready) {
        if (mounted) {
          setState(() => _loading = false);
        }
        _setStatus(_healthyStatusText());
        showAppNotice(
          'Could not switch quality. Please try again.',
          duration: const Duration(seconds: 2),
        );
      } else {
        _showFatalError(_friendlyError(error));
      }
    }
  }

  Future<void> _openNextCandidate({
    required int generation,
    required Duration start,
    required bool play,
  }) async {
    final int? next = _findNextCandidateIndex();
    if (next == null) {
      _showFatalError(
        'Connection problem — check your internet and tap Retry.',
      );
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

  Future<void> _openCandidate(
    int index, {
    required int generation,
    required Duration start,
    required bool play,
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
    _setStatus('Connecting to Ifallertzia…');
    if (mounted) {
      setState(() {
        _loading = true;
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
  }

  void _handlePosition(Duration position) {
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
    _startupTimer = Timer(
      Duration(seconds: widget.isLocal ? 20 : 35),
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
    _failedCandidates.add(failedIndex);
    _candidateHealthy = false;
    final Duration resumePosition = _lastKnownPosition;
    final bool shouldPlay = _desiredPlaying || !_ready;
    const String failedServer = 'Ifallertzia';

    if (mounted) {
      setState(() {
        _loading = true;
        _errorMessage = null;
      });
    }
    _setStatus('$failedServer failed. Trying another mirror…');

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

    final MovieQualityLink? quality = _currentQuality;
    if (quality == null) {
      _showFatalError('No playable quality is selected.');
      return;
    }
    _ready = false;
    await _resolveAndOpenQuality(quality, start: _lastKnownPosition);
  }

  Future<void> _switchToCandidate(int index) async {
    if (widget.isLocal || index < 0 || index >= _candidates.length) return;
    if (index == _candidateIndex && _candidateHealthy) return;

    final int generation = ++_generation;
    _startupTimer?.cancel();
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
    try {
      Duration target = _player.state.position + offset;
      if (target < Duration.zero) target = Duration.zero;
      final Duration duration = _player.state.duration;
      if (duration > Duration.zero && target > duration) target = duration;
      await _player.seek(target);
    } catch (_) {}
  }

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

  String _audioTrackLabel(AudioTrack track, int index) {
    final String title = (track.title ?? '').trim();
    final String base = title.isNotEmpty ? title : 'Audio ${index + 1}';
    final List<String> details = <String>[
      if ((track.language ?? '').trim().isNotEmpty)
        track.language!.trim().toUpperCase(),
      if ((track.codec ?? '').trim().isNotEmpty)
        track.codec!.trim().toUpperCase(),
      if ((track.channelscount ?? 0) > 0) '${track.channelscount} ch',
    ];
    return details.isEmpty ? base : '$base • ${details.join(' • ')}';
  }

  String _subtitleTrackLabel(SubtitleTrack track, int index) {
    final String title = (track.title ?? '').trim();
    final String base = title.isNotEmpty ? title : 'Subtitle ${index + 1}';
    final List<String> details = <String>[
      if ((track.language ?? '').trim().isNotEmpty)
        track.language!.trim().toUpperCase(),
      if ((track.codec ?? '').trim().isNotEmpty)
        track.codec!.trim().toUpperCase(),
    ];
    return details.isEmpty ? base : '$base • ${details.join(' • ')}';
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

  Future<void> _downloadCurrentQuality() async {
    final MovieDownloadService? service = _downloadService;
    final MovieDetail? detail = widget.detail;
    final MovieQualityLink? quality = _currentQuality;
    if (service == null || detail == null || quality == null) return;

    try {
      final MovieDownloadItem item = await service.enqueueDownload(
        detail: detail,
        quality: quality,
      );
      showAppNotice(
        item.status == MovieDownloadStatus.completed
            ? 'Already downloaded: $_displayTitle (${quality.displayQuality})'
            : 'Download started: $_displayTitle (${quality.displayQuality})',
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
                if (_displaySubtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 6),
                  Text(
                    _displaySubtitle,
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
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.78),
        alignment: Alignment.center,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline_rounded,
                size: 46,
                color: t.danger,
              ),
              const SizedBox(height: 16),
              Text(
                "Couldn't start playback",
                textAlign: TextAlign.center,
                style: SidifyText.titleM(Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: SidifyText.bodyS(Colors.white70),
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  FilledButton.icon(
                    onPressed: () => unawaited(_retryPlayback()),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Retry'),
                    style: FilledButton.styleFrom(
                      backgroundColor: t.brand,
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
