import 'package:flutter/material.dart';

import '../core/models/song.dart';

/// The one and only quality mark: a small gold square with **HD** written on it.
///
/// Kept deliberately plain — a single flat square, a single word, no crest, no
/// gradient, and no second badge anywhere near it. Anything below album-master
/// quality renders nothing at all.
class QualityBadge extends StatelessWidget {
  const QualityBadge({
    super.key,
    required this.quality,
    this.compact = false,
  });

  final QualityTier quality;
  final bool compact;

  // Classic gold plate, dark pressed-in lettering.
  static const Color _gold = Color(0xFFE8B92F);
  static const Color _ink = Color(0xFF3B2905);

  @override
  Widget build(BuildContext context) {
    if (quality != QualityTier.high) return const SizedBox.shrink();

    final double side = compact ? 14 : 16;

    return Tooltip(
      message: 'HD',
      child: Container(
        width: side,
        height: side,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _gold,
          borderRadius: BorderRadius.circular(side * 0.22),
        ),
        child: Text(
          'HD',
          style: TextStyle(
            fontSize: compact ? 6.5 : 7.5,
            height: 1,
            letterSpacing: 0.2,
            fontWeight: FontWeight.w900,
            color: _ink,
          ),
        ),
      ),
    );
  }
}
