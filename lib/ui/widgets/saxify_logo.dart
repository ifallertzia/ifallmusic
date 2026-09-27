import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/branding.dart';
import '../../core/theme/saxify_accents.dart';

/// Original user-supplied IfallMusic artwork, unchanged by accent themes.
class SaxifyLogo extends StatelessWidget {
  const SaxifyLogo({
    super.key,
    this.size = 40,
    this.accent,
    this.showTile = true,
    this.strokeColor,
  });

  final double size;
  final SaxifyAccent? accent;
  final bool showTile;

  /// Override the S colour (defaults to white for contrast on the gradient).
  final Color? strokeColor;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(showTile ? size * .2 : 0),
    child: Image.asset(
      IfallBranding.logoAsset,
      width: size,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: 'IfallMusic logo',
    ),
  );
}

/// Logo tile + wordmark, the way the site's sidebar shows it.
class SaxifyWordmark extends StatelessWidget {
  const SaxifyWordmark({
    super.key,
    this.logoSize = 34,
    this.fontSize = 20,
    this.showSubtitle = false,
    this.accent,
  });

  final double logoSize;
  final double fontSize;
  final bool showSubtitle;
  final SaxifyAccent? accent;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent effective =
        accent ??
        Theme.of(context).extension<SaxifyAccentExtension>()?.accent ??
        SaxifyAccents.violetPulse;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SaxifyLogo(size: logoSize, accent: effective),
        SizedBox(width: logoSize * 0.3),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ShaderMask(
              shaderCallback: (Rect bounds) =>
                  effective.horizontalGradient.createShader(bounds),
              child: Text(
                IfallBranding.appName,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: fontSize,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: Colors.white,
                ),
              ),
            ),
            if (showSubtitle)
              const Text(
                'Stream beyond limits',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF8D87A6)),
              ),
          ],
        ),
      ],
    );
  }
}
