import 'package:flutter/material.dart';

import '../core/models/song.dart';
import '../core/theme/saxify_accents.dart';

class QualityBadge extends StatelessWidget {
  const QualityBadge({super.key, required this.quality});
  final QualityTier quality;
  @override
  Widget build(BuildContext context) {
    final high = quality == QualityTier.high;
    final color = high ? context.accent.primary : Colors.grey;
    return Tooltip(
      message: high
          ? 'Album-master source, not a bitrate or lossless guarantee'
          : 'Audio from a video upload',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .10),
          border: Border.all(color: color.withValues(alpha: .45)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          high ? 'High quality music' : 'Normal quality',
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
