import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// `1:02:03` / `42:10` — one formatter for the bar, the drag bubble, the time
/// labels and the status line.
String movieClock(Duration d) {
  final Duration value = d.isNegative ? Duration.zero : d;
  final int h = value.inHours;
  final int m = value.inMinutes.remainder(60);
  final String s = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

/// The player's own seek bar.
///
/// The stock material bar was the reason seeking felt broken: it is only 30 px
/// tall at the very bottom of the screen (over Android's gesture strip, where
/// a drag is often taken by the system), and on a plain tap it seeks to the
/// *previous* drag value instead of where the finger went down.
///
/// This one is a 32 px tall grab area with a thin track and a round thumb. A
/// tap lands exactly where the finger went down; a drag scrubs live and shows
/// the target timestamp above the thumb while the finger is on the bar.
class MovieSeekBar extends StatefulWidget {
  const MovieSeekBar({
    super.key,
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
  State<MovieSeekBar> createState() => _MovieSeekBarState();
}

class _MovieSeekBarState extends State<MovieSeekBar> {
  static const double _track = 3.5;
  static const double _trackActive = 5;
  static const double _height = 32;
  static const double _thumb = 14;
  static const double _thumbActive = 18;

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
  void didUpdateWidget(covariant MovieSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pendingSeek != widget.pendingSeek) {
      oldWidget.pendingSeek.removeListener(_onPendingSeekChanged);
      widget.pendingSeek.addListener(_onPendingSeekChanged);
    }
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
        double fractionOf(Offset local) =>
            width <= 0 ? 0 : (local.dx / width).clamp(0.0, 1.0);
        final bool dragging = _drag != null;
        final double thumb = dragging ? _thumbActive : _thumb;
        final double track = dragging ? _trackActive : _track;
        final double played = _played;
        final double buffered = _buffered;
        final double maxThumbX = width > thumb ? width - thumb : 0;
        final double thumbX =
            (played * width - thumb / 2).clamp(0.0, maxThumbX);

        Widget bar(double fraction, Color color) => Positioned(
              left: 0,
              width: width * fraction,
              child: Container(
                height: track,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            );

        return Semantics(
          label: 'Seek bar',
          value: movieClock(_duration * played),
          child: GestureDetector(
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
                  bar(played, Colors.white),
                  Positioned(
                    left: thumbX,
                    child: Container(
                      width: thumb,
                      height: thumb,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(color: Colors.black38, blurRadius: 4),
                        ],
                      ),
                    ),
                  ),
                  if (dragging)
                    Positioned(
                      left: (thumbX - 22).clamp(
                        0.0,
                        width > 60 ? width - 60 : 0.0,
                      ),
                      bottom: _height - 2,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          movieClock(_duration * _drag!),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
