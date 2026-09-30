import 'package:flutter/material.dart';

import '../core/models/song.dart';
import '../core/theme/saxify_accents.dart';

/// A compact source-quality label. In the default neutral theme only the text
/// follows the user's rotating/custom colour; the rest of the app stays black
/// and understated unless they enable the full accent theme in Settings.
class QualityBadge extends StatelessWidget {
  const QualityBadge({
    super.key,
    required this.quality,
    this.compact = false,
  });

  final QualityTier quality;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final bool high = quality == QualityTier.high;
    final Color textColor = high ? context.qualityAccent.primary : Colors.white70;
    return Tooltip(
      message: high
          ? 'Album-master source, not a bitrate or lossless guarantee'
          : 'Audio from a video upload',
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 5 : 6,
          vertical: compact ? 2 : 3,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: .62),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          high ? 'High quality music' : 'Normal quality',
          maxLines: 1,
          style: TextStyle(
            color: textColor,
            fontSize: compact ? 7.5 : 9,
            fontWeight: FontWeight.w600,
            height: 1.05,
          ),
        ),
      ),
    );
  }
}
