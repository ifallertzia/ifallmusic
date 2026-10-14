import 'package:flutter/material.dart';

import '../../config/branding.dart';
import '../../core/theme/saxify_theme.dart';
import '../../core/theme/ifall_ui.dart';

/// The Liked Songs sleeve.
///
/// Same identity as the app logo — the "I Fall Music" character (the little
/// guy in headphones) — only here he is *liking*: a soft green heart floats
/// where the logo's lettering used to be, in the logo's own green. Painting it
/// with the theme accent would break the identity, so the artwork stays exactly
/// as drawn and keeps its own colour.
class LikedSongsArtwork extends StatelessWidget {
  const LikedSongsArtwork({
    super.key,
    this.size = 42,
    this.radius = 10,
    this.showBadge = false,
  });

  /// Square side of the sleeve.
  final double size;

  /// Corner radius (0 → fully square, `size / 2` → circular).
  final double radius;

  /// Draws the small heart chip in the corner (rail cards).
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Image.asset(
              IfallBranding.likedSongsAsset,
              fit: BoxFit.cover,
              filterQuality: FilterQuality.medium,
              semanticLabel: 'Liked Songs',
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stack) =>
                      const ColoredBox(
                        color: Color(0xFFF3F5F3),
                        child: Icon(
                          Icons.favorite_rounded,
                          color: Color(0xFF003815),
                        ),
                      ),
            ),
            if (showBadge)
              Positioned(
                right: 7,
                bottom: 7,
                child: Container(
                  width: size * 0.26,
                  height: size * 0.26,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF003815),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.9),
                      width: 1.4,
                    ),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.favorite_rounded,
                    size: size * 0.14,
                    color: Colors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The first card of **Made for you** — Liked Songs, in the app's own colours.
///
/// Same footprint as the song cards beside it, so the rail keeps its rhythm:
/// the character sleeve, the title, and how many songs are inside.
class LikedSongsCard extends StatelessWidget {
  const LikedSongsCard({
    super.key,
    required this.count,
    required this.onTap,
    this.width = 162,
  });

  final int count;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SaxifyTheme.radiusMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              LikedSongsArtwork(
                size: width * 0.66,
                radius: 14,
                showBadge: true,
              ),
              const SizedBox(height: 10),
              const Text(
                'Liked Songs',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: FontWeight.w700,
                  color: IfallTokens.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                count == 1 ? '1 song · liked by you' : '$count songs · liked by you',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: IfallTokens.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
