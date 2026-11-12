import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

import 'movie_seek_bar.dart';

/// The movie player's control layer, drawn over the video.
///
/// One widget serves both layouts. In portrait it sits on the 16:9 video at
/// the top of the page; in landscape ([immersive]) it covers the whole screen
/// and adds the "Play on TV" button to the top bar. Nothing here owns
/// playback: every button calls back into the page, which owns the one
/// [Player] — so a rotation only rebuilds these widgets and never touches the
/// stream, the position, the tracks or the speed.
///
/// Layout:
///
/// * top — back, title (+ status line), [Play on TV], CC, Settings
/// * centre — Lock on the left, −10 s, Play/Pause exactly centred, +10 s
/// * bottom — time, seek bar, duration, aspect ratio, PiP, fullscreen
///
/// **Lock.** Tapping the Lock button hides every control at once and shows a
/// small lock chip for [lockIndicatorDuration]; the video keeps playing. While
/// locked a single opaque layer swallows every touch — a tap anywhere only
/// brings the chip back (it never pauses, seeks or unlocks), double taps and
/// drags do nothing. Only a tap on the chip itself unlocks, which restores
/// the controls and the gestures.
class MoviePlayerControls extends StatefulWidget {
  const MoviePlayerControls({
    super.key,
    required this.player,
    required this.title,
    required this.status,
    required this.pendingSeek,
    required this.locked,
    required this.lockPoke,
    required this.toast,
    required this.immersive,
    required this.interactive,
    required this.showCast,
    required this.showPip,
    required this.aspectLabel,
    required this.onBack,
    required this.onSubtitles,
    required this.onSettings,
    required this.onCast,
    required this.onPip,
    required this.onToggleFullscreen,
    required this.onCycleAspect,
    required this.onSeekRelative,
    required this.onSeekStart,
    required this.onSeekTo,
    this.onDownload,
  });

  /// How long the lock chip stays up after locking or after a tap.
  static const Duration lockIndicatorDuration = Duration(seconds: 2);

  /// How long the controls stay up while the video is playing.
  static const Duration autoHideAfter = Duration(seconds: 4);

  final Player player;
  final String title;

  /// The line under the title ("Buffering…", "Season 1 • Episode 2 • 720p").
  final ValueListenable<String> status;
  final ValueNotifier<Duration?> pendingSeek;

  /// Whether the controls are locked. Owned by the page so the system back
  /// button can respect it too.
  final ValueNotifier<bool> locked;

  /// Bumped by the page when something outside this widget (the system back
  /// button) was pressed while locked: the lock chip is shown again.
  final ValueListenable<int> lockPoke;

  /// A short message shown over the video ("Aspect ratio: Fill"). The page
  /// sets it and clears it; null means nothing is shown.
  final ValueListenable<String?> toast;

  /// Landscape / fullscreen layout.
  final bool immersive;

  /// False while the stream is still being found or has failed: only the back
  /// button and the title are shown, because nothing else can work yet.
  final bool interactive;

  final bool showCast;
  final bool showPip;

  /// The current aspect mode's name, used as the button's tooltip.
  final String aspectLabel;

  final VoidCallback onBack;
  final VoidCallback onSubtitles;
  final VoidCallback onSettings;
  final VoidCallback onCast;
  final VoidCallback onPip;
  final VoidCallback onToggleFullscreen;
  final VoidCallback onCycleAspect;
  final void Function(Duration offset) onSeekRelative;
  final VoidCallback onSeekStart;
  final void Function(Duration target) onSeekTo;

  /// Saves the playing title for offline viewing. Shown in the landscape top
  /// bar (the portrait layout has its own Download button under the video);
  /// null for a file that is already on the device.
  final VoidCallback? onDownload;

  @override
  State<MoviePlayerControls> createState() => _MoviePlayerControlsState();
}

class _MoviePlayerControlsState extends State<MoviePlayerControls> {
  static const Duration _fade = Duration(milliseconds: 220);

  final List<StreamSubscription<dynamic>> _subs =
      <StreamSubscription<dynamic>>[];

  bool _visible = true;
  bool _lockIndicatorVisible = false;
  bool _playing = false;
  bool _buffering = false;

  Timer? _hideTimer;
  Timer? _lockTimer;
  Timer? _seekHintTimer;

  /// −1 / +1 while the double-tap "10 seconds" hint is on screen.
  int _seekHint = 0;
  Offset? _doubleTapAt;

  /// Horizontal drag-to-seek on the picture.
  Duration? _dragFrom;
  Duration? _dragTarget;
  double _dragDx = 0;

  bool get _locked => widget.locked.value;

  @override
  void initState() {
    super.initState();
    _playing = widget.player.state.playing;
    _buffering = widget.player.state.buffering;
    widget.locked.addListener(_onLockedChanged);
    widget.lockPoke.addListener(_showLockIndicator);
    _subs.addAll(<StreamSubscription<dynamic>>[
      widget.player.stream.playing.listen((bool playing) {
        if (!mounted) return;
        setState(() => _playing = playing);
        if (playing) {
          _restartHideTimer();
        } else {
          // A paused video keeps its controls: there is nothing to watch that
          // they would be in the way of.
          _hideTimer?.cancel();
          if (!_locked && !_visible) setState(() => _visible = true);
        }
      }),
      widget.player.stream.buffering.listen((bool buffering) {
        if (!mounted || _buffering == buffering) return;
        setState(() => _buffering = buffering);
      }),
    ]);
    _restartHideTimer();
  }

  @override
  void didUpdateWidget(covariant MoviePlayerControls oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.locked != widget.locked) {
      oldWidget.locked.removeListener(_onLockedChanged);
      widget.locked.addListener(_onLockedChanged);
    }
    if (oldWidget.lockPoke != widget.lockPoke) {
      oldWidget.lockPoke.removeListener(_showLockIndicator);
      widget.lockPoke.addListener(_showLockIndicator);
    }
    if (oldWidget.immersive != widget.immersive && !_locked) {
      // A rotation shows the new layout's controls once, then hides them
      // again on the usual timer.
      _visible = true;
      _restartHideTimer();
    }
    if (!oldWidget.interactive && widget.interactive && !_locked) {
      _visible = true;
      _restartHideTimer();
    }
  }

  @override
  void dispose() {
    widget.locked.removeListener(_onLockedChanged);
    widget.lockPoke.removeListener(_showLockIndicator);
    _hideTimer?.cancel();
    _lockTimer?.cancel();
    _seekHintTimer?.cancel();
    for (final StreamSubscription<dynamic> sub in _subs) {
      unawaited(sub.cancel());
    }
    super.dispose();
  }

  // ------------------------------------------------------------ visibility

  void _restartHideTimer() {
    _hideTimer?.cancel();
    if (_locked || !widget.interactive) return;
    _hideTimer = Timer(MoviePlayerControls.autoHideAfter, () {
      if (!mounted || _locked) return;
      // Never hide under a finger that is dragging, or over a paused picture.
      if (_dragTarget != null || !widget.player.state.playing) return;
      setState(() => _visible = false);
    });
  }

  void _toggleVisible() {
    if (_locked) return;
    if (!widget.interactive) {
      if (!_visible) setState(() => _visible = true);
      return;
    }
    setState(() => _visible = !_visible);
    if (_visible) _restartHideTimer();
  }

  void _poke() {
    if (_locked) return;
    _restartHideTimer();
  }

  // ------------------------------------------------------------------ lock

  void _onLockedChanged() {
    if (!mounted) return;
    if (_locked) {
      _hideTimer?.cancel();
      _clearDrag();
      setState(() {
        _visible = false;
        _seekHint = 0;
      });
      _showLockIndicator();
    } else {
      _lockTimer?.cancel();
      setState(() {
        _lockIndicatorVisible = false;
        _visible = true;
      });
      _restartHideTimer();
    }
  }

  void _lock() {
    if (_locked) return;
    widget.locked.value = true;
  }

  void _unlock() {
    if (!_locked) return;
    widget.locked.value = false;
  }

  /// Shows the lock chip and (re)starts its two seconds. Called on lock and on
  /// every tap while locked, so repeated taps simply keep it up.
  void _showLockIndicator() {
    if (!mounted || !_locked) return;
    _lockTimer?.cancel();
    if (!_lockIndicatorVisible) {
      setState(() => _lockIndicatorVisible = true);
    }
    _lockTimer = Timer(MoviePlayerControls.lockIndicatorDuration, () {
      if (!mounted) return;
      setState(() => _lockIndicatorVisible = false);
    });
  }

  // -------------------------------------------------------------- gestures

  void _handleDoubleTap(double width) {
    if (_locked || !widget.interactive) return;
    final Offset? at = _doubleTapAt;
    if (at == null || width <= 0) return;
    final double x = at.dx / width;
    if (x < 0.4) {
      _seekBy(-1);
    } else if (x > 0.6) {
      _seekBy(1);
    } else {
      unawaited(widget.player.playOrPause());
      _poke();
    }
  }

  void _seekBy(int direction) {
    widget.onSeekRelative(Duration(seconds: 10 * direction));
    _seekHintTimer?.cancel();
    setState(() => _seekHint = direction);
    _seekHintTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) setState(() => _seekHint = 0);
    });
    _poke();
  }

  void _dragStart(DragStartDetails details) {
    if (_locked || !widget.interactive) return;
    if (widget.player.state.duration <= Duration.zero) return;
    _hideTimer?.cancel();
    final Duration from =
        widget.pendingSeek.value ?? widget.player.state.position;
    setState(() {
      _dragFrom = from;
      _dragTarget = from;
      _dragDx = 0;
    });
  }

  void _dragUpdate(DragUpdateDetails details, double width) {
    final Duration? from = _dragFrom;
    if (from == null || width <= 0) return;
    _dragDx += details.primaryDelta ?? 0;
    final Duration duration = widget.player.state.duration;
    // A full-width swipe covers two minutes: fine enough to land on a line of
    // dialogue, long enough to skip a scene.
    final int deltaMs = (_dragDx / width * 120000).round();
    Duration target = from + Duration(milliseconds: deltaMs);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    setState(() => _dragTarget = target);
  }

  void _dragEnd() {
    final Duration? from = _dragFrom;
    final Duration? target = _dragTarget;
    _clearDrag();
    if (from == null || target == null) return;
    if ((target - from).abs() >= const Duration(seconds: 1)) {
      widget.onSeekStart();
      widget.onSeekTo(target);
    }
    _poke();
  }

  void _clearDrag() {
    if (_dragFrom == null && _dragTarget == null) return;
    if (mounted) {
      setState(() {
        _dragFrom = null;
        _dragTarget = null;
        _dragDx = 0;
      });
    } else {
      _dragFrom = null;
      _dragTarget = null;
      _dragDx = 0;
    }
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final bool locked = _locked;
    final bool showControls = _visible && !locked;
    final bool immersive = widget.immersive;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final bool wide = width >= 560;
        // Landscape keeps clear of the notch / rounded corners; portrait sits
        // inside the page's own safe area already.
        final EdgeInsets safe = immersive
            ? MediaQuery.paddingOf(context)
            : EdgeInsets.zero;
        final double side = immersive ? 16 : 6;
        final EdgeInsets inset = EdgeInsets.fromLTRB(
          (safe.left > side ? safe.left : side),
          (safe.top > 0 ? safe.top : 0) + (immersive ? 8 : 2),
          (safe.right > side ? safe.right : side),
          (safe.bottom > 0 ? safe.bottom : 0) + (immersive ? 10 : 2),
        );
        final double playSize = immersive ? 72 : (height < 190 ? 52 : 60);
        final double skipSize = immersive ? 52 : 44;

        return Material(
          type: MaterialType.transparency,
          child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1. The picture's own gestures: tap to show / hide, double tap
            //    to skip, horizontal drag to scrub.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _toggleVisible,
                onDoubleTapDown: (TapDownDetails details) =>
                    _doubleTapAt = details.localPosition,
                onDoubleTap: () => _handleDoubleTap(width),
                onHorizontalDragStart: _dragStart,
                onHorizontalDragUpdate: (DragUpdateDetails details) =>
                    _dragUpdate(details, width),
                onHorizontalDragEnd: (_) => _dragEnd(),
                onHorizontalDragCancel: _clearDrag,
              ),
            ),

            // 2. Scrims so white controls read on a bright scene.
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: showControls ? 1 : 0,
                  duration: _fade,
                  curve: Curves.easeOut,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: <double>[0, 0.28, 0.62, 1],
                        colors: <Color>[
                          Color(0xB3000000),
                          Color(0x26000000),
                          Color(0x26000000),
                          Color(0xCC000000),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 3. Buffering ring (also when the controls are hidden).
            if (_buffering && widget.interactive && !showControls)
              const Positioned.fill(
                child: IgnorePointer(child: Center(child: _BufferingRing())),
              ),

            // 4. Double-tap / drag feedback.
            if (_seekHint != 0 && !locked)
              Positioned.fill(
                child: IgnorePointer(
                  child: Align(
                    alignment: _seekHint < 0
                        ? const Alignment(-0.72, 0)
                        : const Alignment(0.72, 0),
                    child: _HintPill(
                      icon: _seekHint < 0
                          ? Icons.fast_rewind_rounded
                          : Icons.fast_forward_rounded,
                      text: _seekHint < 0 ? '−10 seconds' : '+10 seconds',
                    ),
                  ),
                ),
              ),
            if (_dragTarget != null && _dragFrom != null && !locked)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: _HintPill(
                      icon: _dragTarget! >= _dragFrom!
                          ? Icons.fast_forward_rounded
                          : Icons.fast_rewind_rounded,
                      text: '${movieClock(_dragTarget!)}  '
                          '(${_signed(_dragTarget! - _dragFrom!)})',
                    ),
                  ),
                ),
              ),

            // 5. The controls themselves.
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !showControls,
                child: AnimatedOpacity(
                  opacity: showControls ? 1 : 0,
                  duration: _fade,
                  curve: Curves.easeOut,
                  child: Listener(
                    behavior: HitTestBehavior.translucent,
                    onPointerDown: (_) => _poke(),
                    child: Padding(
                      padding: inset,
                      child: Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          Align(
                            alignment: Alignment.topCenter,
                            child: _buildTopBar(immersive),
                          ),
                          if (widget.interactive) ...<Widget>[
                            // Play/Pause is centred on the picture itself,
                            // independent of the lock button beside it.
                            Align(
                              alignment: Alignment.center,
                              child: _buildCentre(playSize, skipSize, immersive),
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.only(left: immersive ? 6 : 4),
                                child: _RoundButton(
                                  icon: Icons.lock_open_rounded,
                                  tooltip: 'Lock controls',
                                  size: immersive ? 46 : 40,
                                  iconSize: immersive ? 22 : 20,
                                  onPressed: _lock,
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment.bottomCenter,
                              child: _buildBottom(wide, immersive),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // 6. Locked: one layer takes every touch; only the chip unlocks.
            if (locked)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // Only a plain tap recogniser here (no double-tap one), so a
                  // tap on the chip unlocks at once instead of waiting out the
                  // double-tap window.
                  onTap: _showLockIndicator,
                  onHorizontalDragStart: (_) => _showLockIndicator(),
                  onVerticalDragStart: (_) => _showLockIndicator(),
                  child: Padding(
                    padding: inset,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Padding(
                        padding: EdgeInsets.only(left: immersive ? 6 : 4),
                        child: IgnorePointer(
                          ignoring: !_lockIndicatorVisible,
                          child: AnimatedOpacity(
                            opacity: _lockIndicatorVisible ? 1 : 0,
                            duration: _fade,
                            child: _LockChip(onUnlock: _unlock),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 7. Short messages ("Aspect ratio: Fill") — shown even while the
            //    controls are hidden.
            Positioned(
              top: inset.top + (immersive ? 56 : 46),
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: ValueListenableBuilder<String?>(
                  valueListenable: widget.toast,
                  builder: (_, String? message, __) {
                    return AnimatedSwitcher(
                      duration: const Duration(milliseconds: 160),
                      child: message == null || message.isEmpty
                          ? const SizedBox.shrink()
                          : Center(
                              key: ValueKey<String>(message),
                              child: _HintPill(text: message),
                            ),
                    );
                  },
                ),
              ),
            ),
          ],
          ),
        );
      },
    );
  }

  static String _signed(Duration delta) {
    final String sign = delta.isNegative ? '−' : '+';
    return '$sign${movieClock(delta.abs())}';
  }

  Widget _buildTopBar(bool immersive) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _IconAction(
          icon: Icons.arrow_back_ios_new_rounded,
          tooltip: 'Back',
          iconSize: 20,
          onPressed: widget.onBack,
        ),
        const SizedBox(width: 2),
        Expanded(
          child: ValueListenableBuilder<String>(
            valueListenable: widget.status,
            builder: (_, String status, __) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: immersive ? 16 : 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                  // While a stream is still being found the status is shown
                  // under the spinner, not twice.
                  if (status.isNotEmpty && widget.interactive)
                    Text(
                      status,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: immersive ? 12 : 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
        if (widget.interactive) ...<Widget>[
          if (immersive && widget.showCast)
            _IconAction(
              icon: Icons.cast_rounded,
              tooltip: 'Play on TV',
              onPressed: widget.onCast,
            ),
          if (immersive && widget.onDownload != null)
            _IconAction(
              icon: Icons.download_rounded,
              tooltip: 'Download',
              onPressed: widget.onDownload!,
            ),
          _IconAction(
            icon: Icons.closed_caption_outlined,
            tooltip: 'Subtitles',
            onPressed: widget.onSubtitles,
          ),
          _IconAction(
            icon: Icons.settings_outlined,
            tooltip: 'Playback settings',
            onPressed: widget.onSettings,
          ),
        ],
      ],
    );
  }

  Widget _buildCentre(double playSize, double skipSize, bool immersive) {
    final double gap = immersive ? 44 : 26;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _IconAction(
          icon: Icons.replay_10_rounded,
          tooltip: 'Back 10 seconds',
          size: skipSize,
          iconSize: skipSize * 0.68,
          onPressed: () => widget.onSeekRelative(const Duration(seconds: -10)),
        ),
        SizedBox(width: gap),
        _PlayPauseButton(
          size: playSize,
          playing: _playing,
          buffering: _buffering,
          onPressed: () => unawaited(widget.player.playOrPause()),
        ),
        SizedBox(width: gap),
        _IconAction(
          icon: Icons.forward_10_rounded,
          tooltip: 'Forward 10 seconds',
          size: skipSize,
          iconSize: skipSize * 0.68,
          onPressed: () => widget.onSeekRelative(const Duration(seconds: 10)),
        ),
      ],
    );
  }

  Widget _buildBottom(bool wide, bool immersive) {
    final Widget position = _TimeLabel(
      player: widget.player,
      pendingSeek: widget.pendingSeek,
      total: false,
    );
    final Widget total = _TimeLabel(
      player: widget.player,
      pendingSeek: widget.pendingSeek,
      total: true,
    );
    final Widget bar = MovieSeekBar(
      player: widget.player,
      pendingSeek: widget.pendingSeek,
      onSeekStart: widget.onSeekStart,
      onSeek: widget.onSeekTo,
      onSeekEnd: _poke,
    );
    final List<Widget> actions = <Widget>[
      _IconAction(
        icon: Icons.aspect_ratio_rounded,
        tooltip: 'Aspect ratio: ${widget.aspectLabel}',
        size: 40,
        iconSize: 21,
        onPressed: widget.onCycleAspect,
      ),
      if (widget.showPip)
        _IconAction(
          icon: Icons.picture_in_picture_alt_rounded,
          tooltip: 'Picture in picture',
          size: 40,
          iconSize: 21,
          onPressed: widget.onPip,
        ),
      _IconAction(
        icon: immersive
            ? Icons.fullscreen_exit_rounded
            : Icons.fullscreen_rounded,
        tooltip: immersive ? 'Exit fullscreen' : 'Fullscreen',
        size: 40,
        iconSize: 26,
        onPressed: widget.onToggleFullscreen,
      ),
    ];

    if (wide) {
      // Landscape: one long line — time, bar, duration, then the buttons.
      return Row(
        children: <Widget>[
          const SizedBox(width: 6),
          position,
          const SizedBox(width: 12),
          Expanded(child: bar),
          const SizedBox(width: 12),
          total,
          const SizedBox(width: 6),
          ...actions,
        ],
      );
    }

    // Portrait: the bar keeps the full width between the two times, and the
    // buttons sit on their own line underneath so it stays long enough to aim.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
          children: <Widget>[
            const SizedBox(width: 8),
            position,
            const SizedBox(width: 10),
            Expanded(child: bar),
            const SizedBox(width: 10),
            total,
            const SizedBox(width: 8),
          ],
        ),
        SizedBox(
          height: 36,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: actions,
          ),
        ),
      ],
    );
  }
}

/// `12:34` — the current position, or the total duration when [total] is set.
class _TimeLabel extends StatefulWidget {
  const _TimeLabel({
    required this.player,
    required this.pendingSeek,
    required this.total,
  });

  final Player player;
  final ValueNotifier<Duration?> pendingSeek;
  final bool total;

  @override
  State<_TimeLabel> createState() => _TimeLabelState();
}

class _TimeLabelState extends State<_TimeLabel> {
  StreamSubscription<Duration>? _sub;
  Duration _value = Duration.zero;

  @override
  void initState() {
    super.initState();
    _value = widget.total
        ? widget.player.state.duration
        : widget.player.state.position;
    final Stream<Duration> stream = widget.total
        ? widget.player.stream.duration
        : widget.player.stream.position;
    _sub = stream.listen((Duration value) {
      if (!mounted) return;
      // Whole seconds only: the label does not need sixty rebuilds a second.
      if (value.inSeconds == _value.inSeconds) return;
      setState(() => _value = value);
    });
    if (!widget.total) widget.pendingSeek.addListener(_onPending);
  }

  void _onPending() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    if (!widget.total) widget.pendingSeek.removeListener(_onPending);
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Duration shown =
        widget.total ? _value : (widget.pendingSeek.value ?? _value);
    return Text(
      movieClock(shown),
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
      ),
    );
  }
}

/// A plain white icon button with a generous touch target.
class _IconAction extends StatelessWidget {
  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 23,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: InkResponse(
          onTap: onPressed,
          radius: size * 0.6,
          highlightColor: Colors.white24,
          splashColor: Colors.white24,
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: iconSize,
              color: Colors.white,
              shadows: const <Shadow>[
                Shadow(color: Colors.black45, blurRadius: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon on a soft translucent disc (the Lock button).
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.size = 44,
    this.iconSize = 22,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: Colors.white.withValues(alpha: 0.14),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, size: iconSize, color: Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayPauseButton extends StatelessWidget {
  const _PlayPauseButton({
    required this.size,
    required this.playing,
    required this.buffering,
    required this.onPressed,
  });

  final double size;
  final bool playing;
  final bool buffering;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final String label = playing ? 'Pause' : 'Play';
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        label: label,
        child: SizedBox(
          width: size,
          height: size,
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              Material(
                color: Colors.white.withValues(alpha: 0.16),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onPressed,
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 140),
                      transitionBuilder:
                          (Widget child, Animation<double> animation) {
                        return ScaleTransition(
                          scale: Tween<double>(begin: 0.8, end: 1)
                              .animate(animation),
                          child: FadeTransition(
                            opacity: animation,
                            child: child,
                          ),
                        );
                      },
                      child: Icon(
                        playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        key: ValueKey<bool>(playing),
                        size: size * 0.62,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
              if (buffering)
                const IgnorePointer(
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BufferingRing extends StatelessWidget {
  const _BufferingRing();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 46,
      height: 46,
      child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white),
    );
  }
}

/// A small dark pill for transient messages over the picture.
class _HintPill extends StatelessWidget {
  const _HintPill({required this.text, this.icon});

  final String text;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 18, color: Colors.white),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The chip shown while the controls are locked. It is the only thing on the
/// screen that reacts to a tap — and tapping it unlocks.
class _LockChip extends StatelessWidget {
  const _LockChip({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Unlock controls',
      child: Semantics(
        button: true,
        label: 'Unlock controls',
        child: Material(
          color: Colors.black.withValues(alpha: 0.6),
          shape: StadiumBorder(
            side: BorderSide(color: Colors.white.withValues(alpha: 0.18)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onUnlock,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.lock_rounded, size: 20, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Tap to unlock',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
