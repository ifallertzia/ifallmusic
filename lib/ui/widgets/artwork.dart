import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../config/branding.dart';
import '../../core/services/artwork_cache.dart';

/// Network artwork that reuses one [ImageProvider] everywhere.
///
/// A route push used to rebuild [Image.network] and flash white. The shared
/// provider plus the IfallMusic logo fallback keeps the sleeve visible.
///
/// Shape policy: every thumbnail in the app renders as a sharp, premium
/// square with at most [maxThumbRadius] (≈8 px) corner rounding — never
/// pill-shaped or heavily rounded. Callers may still pass `radius: 0` for
/// full-bleed covers; anything larger is clamped so the whole app stays
/// consistent without touching every call site. Sizes are never altered.
class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    this.size,
    this.width,
    this.height,
    this.radius = maxThumbRadius,
    this.fit = BoxFit.cover,
    this.fallbackIcon = Icons.music_note_rounded,
  });

  /// The app-wide corner radius cap for artwork thumbnails.
  static const double maxThumbRadius = 8;

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
    // Fully circular artwork (radius >= half the side) is an avatar — brand
    // logos / artist bubbles — and keeps its shape. Everything else is a
    // thumbnail and gets the sharp, premium square treatment.
    final double minSide = math.min(w, h);
    final bool circular = minSide.isFinite && radius >= minSide / 2;
    final double r = radius <= 0
        ? 0
        : (circular ? radius : math.min(radius, maxThumbRadius));
    final double iconSize = (w.isFinite && h.isFinite)
        ? math.max(16.0, math.min(w, h) * 0.4)
        : 48.0;
    final Widget placeholder = _Fallback(iconSize: iconSize, icon: fallbackIcon);

    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
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
  const _Fallback({required this.iconSize, required this.icon});

  final double iconSize;
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
              Icon(icon, color: Colors.white.withValues(alpha: 0.9), size: iconSize),
        ),
      ],
    );
  }
}
