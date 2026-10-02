import 'package:flutter/material.dart';

import '../../config/branding.dart';
import '../../core/services/artwork_cache.dart';
import '../../core/theme/saxify_theme.dart';

/// Network artwork that reuses one [ImageProvider] everywhere.
///
/// A route push used to rebuild [Image.network] and flash white. The shared
/// provider plus the IfallMusic logo fallback keeps the sleeve visible.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    this.size,
    this.width,
    this.height,
    this.radius = SaxifyTheme.radiusSm,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.music_note_rounded,
  });

  final String url;
  final double? size;
  final double? width;
  final double? height;
  final double radius;
  final BoxFit fit;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final double w = width ?? size ?? 56;
    final double h = height ?? size ?? 56;
    final Widget placeholder = _Fallback(radius: radius, icon: fallbackIcon);

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: w,
        height: h,
        child: Image(
          image: ArtworkCache.providerFor(url),
          width: w,
          height: h,
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
              placeholder,
          frameBuilder: (BuildContext context, Widget child, int? frame, bool sync) {
            if (sync || frame != null) return child;
            return placeholder;
          },
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  const _Fallback({required this.radius, required this.icon});

  final double radius;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[Color(0xFF1E1A2E), Color(0xFF0D0B14)],
            ),
          ),
        ),
        Image.asset(
          IfallBranding.splashAsset,
          fit: BoxFit.cover,
          errorBuilder: (BuildContext context, Object error, StackTrace? stack) =>
              Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: radius * 1.6),
        ),
      ],
    );
  }
}
