import 'package:flutter/material.dart';

import '../core/models/song.dart';

/// A tiny premium mark for album-master sources.
///
/// Ordinary sources render nothing at all — no "Normal quality" label — so the
/// rows keep their rhythm. The badge is a small gold plate: micro "HD"
/// lettering pressed into the background with a premium crest on top. It is
/// deliberately small enough to sit next to a title without competing with it.
class QualityBadge extends StatelessWidget {
  const QualityBadge({
    super.key,
    required this.quality,
    this.compact = false,
  });

  final QualityTier quality;
  final bool compact;

  static const Color _goldTop = Color(0xFFFFF0BE);
  static const Color _goldMid = Color(0xFFE3B04B);
  static const Color _goldBottom = Color(0xFFA9761A);

  @override
  Widget build(BuildContext context) {
    if (quality != QualityTier.high) return const SizedBox.shrink();

    final double width = compact ? 19 : 22;
    final double height = compact ? 12.5 : 14.5;
    const Color ink = Color(0xFF3B2606);

    return Tooltip(
      message: 'Premium · album-master source',
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4.5),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[_goldTop, _goldMid, _goldBottom],
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: const Color(0xFFE3B04B).withValues(alpha: 0.35),
              blurRadius: 6,
              offset: const Offset(0, 1.5),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4.5),
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // Pressed-in micro lettering: HD HD HD across the plate.
              Positioned.fill(
                child: FittedBox(
                  fit: BoxFit.fill,
                  child: Opacity(
                    opacity: 0.30,
                    child: Text(
                      'HD HD',
                      style: TextStyle(
                        fontSize: 6,
                        height: 1,
                        letterSpacing: 0.4,
                        fontWeight: FontWeight.w800,
                        color: ink.withValues(alpha: 0.9),
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Icon(
                  Icons.workspace_premium_rounded,
                  size: compact ? 8.5 : 10,
                  color: ink.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
