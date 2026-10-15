import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'player_palette.dart';

/// Decorative flowing sine wave, not an audio amplitude analyser. Only the
/// phase is animated: the playhead always uses the real playback fraction.
class WaveformSeekBar extends StatefulWidget {
  const WaveformSeekBar({
    super.key,
    required this.value,
    required this.enabled,
    required this.playing,
    required this.artworkUrl,
    required this.reduceMotion,
    required this.onChanged,
    required this.onEnd,
  });

  final double value;
  final bool enabled, playing, reduceMotion;
  final String artworkUrl;
  final ValueChanged<double> onChanged;
  final ValueChanged<bool> onEnd;

  @override
  State<WaveformSeekBar> createState() => _WaveformSeekBarState();
}

class _WaveformSeekBarState extends State<WaveformSeekBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _phase = AnimationController(
    vsync: this, duration: const Duration(seconds: 3),
  );
  List<Color> _colors = const [Color(0xFFCCD0DA), Color(0xFFF2F3F7)];
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _loadPalette();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _animate();
  }

  @override
  void didUpdateWidget(WaveformSeekBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.artworkUrl != widget.artworkUrl) _loadPalette();
    _animate();
  }

  void _animate() {
    final animate = widget.playing && widget.enabled && !widget.reduceMotion &&
        !MediaQuery.disableAnimationsOf(context) && TickerMode.of(context);
    if (animate && !_phase.isAnimating) _phase.repeat();
    if (!animate) _phase.stop();
  }

  Future<void> _loadPalette() async {
    final generation = ++_generation;
    final palette = await MeshPaletteService.extract(widget.artworkUrl);
    if (!mounted || generation != _generation) return;
    setState(() {
      _colors = palette.colors.map((color) {
        final hsl = HSLColor.fromColor(color);
        return hsl.withLightness(0.72).toColor();
      }).toList();
    });
  }

  @override
  void dispose() {
    _phase.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    void adjust(double delta) {
      widget.onChanged((widget.value + delta).clamp(0.0, 1.0));
      widget.onEnd(true);
    }
    return Semantics(
      label: 'Playback position',
      value: '${(widget.value * 100).round()}%',
      enabled: widget.enabled,
      onIncrease: widget.enabled ? () => adjust(0.05) : null,
      onDecrease: widget.enabled ? () => adjust(-0.05) : null,
      child: LayoutBuilder(builder: (context, box) {
        void update(double dx) {
          if (box.maxWidth > 0) {
            widget.onChanged((dx / box.maxWidth).clamp(0.0, 1.0));
          }
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: widget.enabled ? (d) {
            update(d.localPosition.dx);
            widget.onEnd(true);
          } : null,
          onHorizontalDragStart: widget.enabled
              ? (d) => update(d.localPosition.dx) : null,
          onHorizontalDragUpdate: widget.enabled
              ? (d) => update(d.localPosition.dx) : null,
          onHorizontalDragEnd: widget.enabled ? (_) => widget.onEnd(true) : null,
          onHorizontalDragCancel: () => widget.onEnd(false),
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size(box.maxWidth, 40),
              painter: WaveformPainter(
                progress: widget.value, phase: _phase, colors: _colors,
              ),
            ),
          ),
        );
      }),
    );
  }
}

class WaveformPainter extends CustomPainter {
  WaveformPainter({required this.progress, required this.phase, required this.colors})
      : super(repaint: phase);

  final double progress;
  final Animation<double> phase;
  final List<Color> colors;

  // Smoothstep has zero derivative at either end: the wave meets the rail
  // at exactly y=0 with a horizontal tangent, regardless of its phase.
  static double envelope(double distance) {
    final t = (distance / 16).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final end = size.width * progress.clamp(0.0, 1.0);
    final y = size.height / 2;
    final paint = Paint()..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(end, y), Offset(size.width, y),
        paint..strokeWidth = 1.4..color = const Color(0x38FFFFFF));
    if (end > 0) {
      final path = Path()..moveTo(0, y);
      for (double x = 1; x < end; x += 1) {
        final amplitude = 4.5 * envelope(x) * envelope(end - x);
        path.lineTo(x, y + amplitude * math.sin(x * math.pi / 12 - phase.value * 2 * math.pi));
      }
      path.lineTo(end, y);
      paint..strokeWidth = 2..shader = LinearGradient(colors: colors)
          .createShader(Rect.fromLTWH(0, 0, size.width, size.height));
      canvas.drawPath(path, paint);
    }
    paint..shader = null..color = colors.last..strokeWidth = 1.6;
    canvas.drawLine(Offset(end, y - 7), Offset(end, y + 7), paint);
  }

  @override
  bool shouldRepaint(WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.colors != colors || oldDelegate.phase != phase;
}
