import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/branding.dart';
import '../../core/models/album_card.dart';
import '../../core/models/song.dart';
import '../../core/services/artwork_cache.dart';
import '../../core/services/library_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../../core/utils/format.dart';
import 'song_menu.dart';

/// Shared building blocks of the Sidify interface — a port of the web app's
/// `ui.tsx` + `cards.tsx` + `TrackRow.tsx` to Flutter: the same sizes, radii
/// and colours, so every section reads like the site.

// ---------------------------------------------------------------------------
// Logo — use the uploaded Spotify + YouTube Music merged mark everywhere.
// ---------------------------------------------------------------------------

/// The logo mark on its own, in a rounded square like the site's mark.
class SidifyLogoMark extends StatelessWidget {
  const SidifyLogoMark({super.key, this.size = 32, this.radius});

  final double size;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius ?? size * 0.24),
      child: Image.asset(
        SidifyBranding.markAsset,
        width: size,
        height: size,
        fit: BoxFit.cover,
      ),
    );
  }
}

/// Mark + "Sidify", for headers (the site's sidebar lockup).
class SidifyLogoFull extends StatelessWidget {
  const SidifyLogoFull({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SidifyLogoMark(size: size),
        const SizedBox(width: 10),
        Text(
          'Sidify',
          style: TextStyle(
            fontSize: 19,
            height: 1,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: context.sidify.text,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Artwork — one cached provider everywhere; the logo is the fallback sleeve,
// so a missing cover never shows a broken-image glyph.
// ---------------------------------------------------------------------------

class Artwork extends StatelessWidget {
  const Artwork({
    super.key,
    required this.url,
    this.size,
    this.width,
    this.height,
    this.radius = 7,
    this.round = false,
    this.fit = BoxFit.cover,
  });

  final String url;
  final double? size;
  final double? width;
  final double? height;
  final double radius;
  final bool round;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final double w = width ?? size ?? 56;
    final double h = height ?? size ?? 56;
    final SidifyTokens t = context.sidify;
    final Widget fallback = Container(
      width: w,
      height: h,
      color: t.raised,
      alignment: Alignment.center,
      child: Icon(Icons.music_note_rounded, color: t.text3, size: w * 0.4),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(round ? w / 2 : radius),
      child: SizedBox(
        width: w,
        height: h,
        // On-device songs carry `content://`/`file://` album-art URIs we cannot
        // decode here — show a plain music note, never the app logo.
        child: ArtworkCache.isPlaceholder(url)
            ? fallback
            : Image(
                image: ArtworkCache.providerFor(url),
                width: w,
                height: h,
                fit: fit,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => fallback,
                frameBuilder: (_, Widget child, int? frame, bool sync) =>
                    (sync || frame != null) ? child : fallback,
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Glass — the frosted chrome of the tab bar, mini player and menus.
// ---------------------------------------------------------------------------

/// Liquid glass: the surface the floating dock (mini player + tab bar) is made
/// of — a genuinely see-through pane rather than a tinted card. Three things
/// sell it:
///
///  * **the backdrop is frosted, then re-lit.** One `BackdropFilter` blurs
///    whatever is behind the pane and the pane itself is painted at a third of
///    its opacity, so the page shows straight through the dock while text
///    stays legible on the frost.
///  * **light behaves like it does on glass.** A bright specular top edge, a
///    quiet middle, bounce light along the bottom, a hairline rim, and a
///    second rim 1.6px inside it — the two surfaces that make a thin pane read
///    as a solid piece of glass.
///  * **it moves.** [sheen] drags the specular streak across the pane while the
///    dock folds, so the glass looks like it is flowing into place instead of
///    being resized.
///
/// Geometry is entirely the caller's — radius, padding and child are passed
/// straight through, so this changes how a surface *looks*, never how much
/// room it takes. Two structural details matter for the finish:
///
///  * the ambient shadow is painted **outside** the clip (a shadow inside a
///    [ClipRRect] is clipped away and never reaches the screen) and shadows
///    never affect layout, so the pane keeps its exact footprint;
///  * the edge hairline is a gradient stroke painted *over* the content, so
///    it reads as the pane's lit rim instead of a border drawn underneath.
///
/// Falls back to a flat surface when the user turns glass off in Settings, and
/// to a cheaper frost when high-performance mode is on.
class GlassBox extends StatelessWidget {
  const GlassBox({
    super.key,
    required this.child,
    this.radius = 18,
    this.bar = false,
    this.padding,
    this.sheen = 0,
    this.borderRadius,
    this.density,
  });

  final Widget child;

  /// Corner radius for a pane with four equal corners. [borderRadius] wins
  /// when it is given (a sheet, which is only round at the top).
  final double radius;
  final bool bar;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;

  /// How much denser than a floating pill the pane is. The dock is left at 1
  /// — thin enough to see the page straight through — while a sheet that holds
  /// real controls asks for more glass over the frost (≈1.65 reads as frosted
  /// rather than as clear).
  final double? density;

  /// 0 = at rest, 1 = folded into the bar's row. Shifts the highlight.
  final double sheen;

  /// Frost strength. High enough that a page scrolling behind the dock turns
  /// into soft colour instead of noise; one filter per pane, on a surface the
  /// size of a pill, is what keeps it affordable.
  double _sigma(bool eco) => eco ? (bar ? 14 : 10) : (bar ? 36 : 28);

  /// Wide, soft shadow that lifts the pane off the page.
  BoxShadow _ambient(SidifyTokens t) => BoxShadow(
        color: Colors.black.withValues(alpha: t.isDark ? 0.52 : 0.18),
        blurRadius: bar ? 30 : 24,
        spreadRadius: -6,
        offset: const Offset(0, 14),
      );

  /// Tight contact shadow right under the edge — what makes it float rather
  /// than hover.
  BoxShadow _contact(SidifyTokens t) => BoxShadow(
        color: Colors.black.withValues(alpha: t.isDark ? 0.38 : 0.12),
        blurRadius: 8,
        spreadRadius: -4,
        offset: const Offset(0, 2),
      );

  static double _mix(double a, double b, double t) => a + (b - a) * t;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final SettingsService settings = context.watch<SettingsService>();
    final BorderRadius corners =
        borderRadius ?? BorderRadius.circular(radius);
    final Widget content = Container(padding: padding, child: child);

    if (!settings.liquidGlass) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: t.raised,
          borderRadius: corners,
          border: Border.all(color: t.edge, width: 0.75),
          boxShadow: <BoxShadow>[_ambient(t), _contact(t)],
        ),
        child: content,
      );
    }

    // The pane: charcoal glass, a touch deeper towards the bottom so it still
    // reads as a surface when pure-black artwork sits behind it.
    final Color pane = bar ? t.bar : t.glass;
    final double d = (density ?? 1.0).clamp(0.4, 2.4);
    final double paneTop = ((t.isDark ? 0.44 : 0.58) * d).clamp(0.0, 1.0);
    final double paneBottom = ((t.isDark ? 0.28 : 0.46) * d).clamp(0.0, 1.0);
    final double sigma = _sigma(settings.highPerformance);
    final double glow = Curves.easeInOutSine.transform(sheen.clamp(0.0, 1.0));

    return DecoratedBox(
      // The shadow sits outside the clip: inside a ClipRRect it would be cut
      // away and never reach the screen. Shadows are paint-only, so the pane
      // keeps the exact footprint the caller asked for.
      decoration: BoxDecoration(
        borderRadius: corners,
        boxShadow: <BoxShadow>[_ambient(t), _contact(t)],
      ),
      child: ClipRRect(
        // Everything below is clipped to the pane, so the frost can never
        // bleed past the rounded silhouette.
        borderRadius: corners,
        child: BackdropFilter(
          // `clamp` keeps the blur from eating a dark fringe out of the pixels
          // just outside the pane's own silhouette.
          filter: ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: ui.TileMode.clamp,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[
                  pane.withValues(alpha: paneTop),
                  pane.withValues(alpha: paneBottom),
                ],
              ),
            ),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: DecoratedBox(
                    // Specular: a lit top rim travelling towards the left as
                    // the surface folds, a quiet middle, and the faint bounce
                    // light along the bottom edge — restrained, never neon.
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment(_mix(-0.30, 0.55, glow), -1),
                        end: Alignment(_mix(0.65, -0.15, glow), 1),
                        colors: <Color>[
                          Colors.white.withValues(
                              alpha: t.isDark ? 0.22 : 0.50),
                          Colors.white.withValues(
                              alpha: t.isDark ? 0.07 : 0.18),
                          Colors.white.withValues(alpha: 0),
                          Colors.black.withValues(
                              alpha: t.isDark ? 0.14 : 0.06),
                        ],
                        stops: const <double>[0, 0.15, 0.56, 1],
                      ),
                    ),
                  ),
                ),
                content,
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      foregroundPainter: _GlassEdgePainter(corners, t, glow),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The two rims of a glass pane plus the streak of light riding along the
/// leading edge. Painted inside the clip so it never adds a pixel to the
/// surface.
class _GlassEdgePainter extends CustomPainter {
  const _GlassEdgePainter(this.corners, this.tokens, this.sheen);

  final BorderRadius corners;
  final SidifyTokens tokens;
  final double sheen;

  /// A caller asks for a capsule with a radius of 999 — bigger than any pane.
  /// Brought back to the largest radius the box can actually hold, so the
  /// second rim sits *inside* the first instead of on top of it.
  static Radius _fit(Radius r, double limit) => Radius.elliptical(
        math.min(r.x, limit),
        math.min(r.y, limit),
      );

  /// The same corner, one sheet-thickness in.
  static Radius _inner(Radius r) => Radius.elliptical(
        math.max(r.x - 1.1, 0.0),
        math.max(r.y - 1.1, 0.0),
      );

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bool dark = tokens.isDark;
    final Color light = dark ? Colors.white : Colors.black;
    // Half a pixel in, so the stroke straddles the pane's own silhouette.
    final Rect rect = (Offset.zero & size).deflate(0.5);
    final double limit = rect.shortestSide / 2;
    final BorderRadius c = BorderRadius.only(
      topLeft: _fit(corners.topLeft, limit),
      topRight: _fit(corners.topRight, limit),
      bottomLeft: _fit(corners.bottomLeft, limit),
      bottomRight: _fit(corners.bottomRight, limit),
    );
    final RRect rrect = c.toRRect(rect);

    // The rim: bright where the light hits the top edge, all but gone along
    // the bottom.
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          <Color>[
            light.withValues(alpha: dark ? 0.44 : 0.22),
            light.withValues(alpha: dark ? 0.13 : 0.09),
            light.withValues(alpha: dark ? 0.06 : 0.05),
          ],
          <double>[0, 0.45, 1],
        ),
    );

    // The inner surface, 1.6px in and lit from underneath: the second edge
    // that reads as thickness.
    final Rect inner = (Offset.zero & size).deflate(1.6);
    if (inner.shortestSide > 3) {
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          inner,
          topLeft: _inner(c.topLeft),
          topRight: _inner(c.topRight),
          bottomLeft: _inner(c.bottomLeft),
          bottomRight: _inner(c.bottomRight),
        ),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7
          ..shader = ui.Gradient.linear(
            rect.bottomCenter,
            rect.topCenter,
            <Color>[
              light.withValues(alpha: dark ? 0.22 : 0.12),
              light.withValues(alpha: 0),
            ],
            <double>[0, 0.6],
          ),
      );
    }

    // A soft specular streak along the leading edge. Only on wide panes — a
    // round button is already nothing but edge.
    final double w = size.width;
    final double h = size.height;
    if (w > h * 1.4 && h > 12) {
      final Rect halo = Rect.fromLTWH(
        -w * 0.18 + sheen * w * 0.26,
        -h * 0.62,
        w * 0.86,
        h * 1.9,
      );
      canvas.drawArc(
        halo,
        math.pi * 1.02,
        math.pi * 0.40,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..strokeCap = StrokeCap.round
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 3.5)
          ..color = Colors.white.withValues(alpha: dark ? 0.34 : 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_GlassEdgePainter oldDelegate) =>
      oldDelegate.corners != corners ||
      oldDelegate.tokens != tokens ||
      oldDelegate.sheen != sheen;
}

// ---------------------------------------------------------------------------
// Page furniture
// ---------------------------------------------------------------------------

/// Big page title (34/800 on phones, like the site's `PageTitle`).
class PageTitle extends StatelessWidget {
  const PageTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SidifyText.display(context.sidify.text),
            ),
          ),
          if (trailing != null)
            Padding(padding: const EdgeInsets.only(bottom: 4), child: trailing!),
        ],
      ),
    );
  }
}

/// A section heading: 22/700, with a chevron when it leads somewhere.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onMore,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onMore;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final Widget head = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: SidifyText.section(t.text),
          ),
        ),
        if (onMore != null)
          Icon(Icons.chevron_right_rounded, size: 20, color: t.text2),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: t.text2,
                      ),
                    ),
                  ),
                if (onMore != null)
                  GestureDetector(onTap: onMore, child: head)
                else
                  head,
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// A horizontal shelf of cards, edge-to-edge with 16px page padding.
class Shelf extends StatelessWidget {
  const Shelf({super.key, required this.children, this.gap = 14});

  final List<Widget> children;
  final double gap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
        physics: const BouncingScrollPhysics(),
        itemCount: children.length,
        separatorBuilder: (_, __) => SizedBox(width: gap),
        itemBuilder: (_, int i) => children[i],
      ),
    );
  }
}

/// Gives a [Shelf] the height its square cards need (card + two text lines).
class SongShelf extends StatelessWidget {
  const SongShelf({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final double w = MediaQuery.sizeOf(context).width;
    final double card = w < 600 ? 148 : 168;
    return SizedBox(height: card + 52, child: Shelf(children: children));
  }
}

class ShelfSection extends StatelessWidget {
  const ShelfSection({
    super.key,
    required this.title,
    this.subtitle,
    this.onMore,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onMore;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(title: title, subtitle: subtitle, onMore: onMore),
          SongShelf(children: children),
        ],
      ),
    );
  }
}

class SidifySkeleton extends StatelessWidget {
  const SidifySkeleton({super.key, this.width, this.height, this.radius = 8});

  final double? width;
  final double? height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.sidify.fill,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.desc,
    this.icon,
    this.action,
  });

  final String title;
  final String? desc;
  final IconData? icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
      child: Column(
        children: <Widget>[
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: t.fill, shape: BoxShape.circle),
            child: icon != null
                ? Icon(icon, size: 26, color: t.text2)
                : const SidifyLogoMark(size: 64),
          ),
          const SizedBox(height: 16),
          Text(title, textAlign: TextAlign.center, style: SidifyText.title(t.text)),
          if (desc != null) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              desc!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, height: 1.45, color: t.text2),
            ),
          ],
          if (action != null) ...<Widget>[
            const SizedBox(height: 20),
            action!,
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons, chips, switches (ui.tsx)
// ---------------------------------------------------------------------------

enum SidifyButtonVariant { primary, secondary, ghost, danger, brand }

class SidifyButton extends StatelessWidget {
  const SidifyButton({
    super.key,
    required this.label,
    this.onTap,
    this.variant = SidifyButtonVariant.primary,
    this.icon,
    this.small = false,
  });

  final String label;
  final VoidCallback? onTap;
  final SidifyButtonVariant variant;
  final IconData? icon;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final (Color bg, Color fg) = switch (variant) {
      SidifyButtonVariant.primary => (t.primary, t.onPrimary),
      SidifyButtonVariant.secondary => (t.fill2, t.text),
      SidifyButtonVariant.ghost => (Colors.transparent, t.text),
      SidifyButtonVariant.danger => (t.danger.withValues(alpha: 0.12), t.danger),
      SidifyButtonVariant.brand => (t.brand, Colors.white),
    };
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: small ? 14 : 20,
              vertical: small ? 8 : 11,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: small ? 15 : 17, color: fg),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: small ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Round icon button: `plain` (ghost), `fill` (chip-grey) or `art` (on artwork).
class SidifyIconButton extends StatelessWidget {
  const SidifyIconButton({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.size = 32,
    this.iconSize = 17,
    this.tone = 'plain',
    this.active = false,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final String tone; // plain | fill | art
  final bool active;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final Color bg = switch (tone) {
      'fill' => active ? t.primary : t.fill,
      'art' => active
          ? Colors.white.withValues(alpha: 0.35)
          : Colors.white.withValues(alpha: 0.18),
      _ => active ? t.fill2 : Colors.transparent,
    };
    final Color fg = color ??
        (tone == 'art'
            ? Colors.white
            : tone == 'fill' && active
                ? t.onPrimary
                : t.text);
    return Tooltip(
      message: label,
      child: Material(
        color: bg,
        shape: const CircleBorder(),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(icon, size: iconSize, color: fg),
          ),
        ),
      ),
    );
  }
}

/// A row of chips; the selected one is white with black text.
class SidifyChips extends StatelessWidget {
  const SidifyChips({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.small = false,
  });

  final String value;
  final List<(String, String)> options; // (id, label)
  final ValueChanged<String> onChanged;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: <Widget>[
          for (final (String id, String label) in options)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Material(
                color: id == value ? t.primary : t.fill,
                borderRadius: BorderRadius.circular(999),
                child: InkWell(
                  onTap: () => onChanged(id),
                  borderRadius: BorderRadius.circular(999),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: small ? 12 : 16,
                      vertical: small ? 7 : 8,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: small ? 12 : 13,
                        fontWeight: FontWeight.w600,
                        color: id == value ? t.onPrimary : t.text,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// iOS-style switch: white track and dark knob when on (dark theme).
class SidifySwitch extends StatelessWidget {
  const SidifySwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return Semantics(
      label: label,
      toggled: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 50,
          height: 30,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: value ? t.primary : t.fill3,
            borderRadius: BorderRadius.circular(999),
          ),
          child: AnimatedAlign(
            duration: const Duration(milliseconds: 200),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: value ? t.onPrimary : Colors.white,
                shape: BoxShape.circle,
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Grouped settings-style list (iOS fashion)
// ---------------------------------------------------------------------------

class SidifyGroup extends StatelessWidget {
  const SidifyGroup({super.key, this.header, this.footer, required this.children});

  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (header != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                header!.toUpperCase(),
                style: SidifyText.eyebrow(t.text2),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              color: t.raised.withValues(alpha: 0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: <Widget>[
                for (int i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: Divider(height: 0.5, thickness: 0.5, color: t.hairline),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 8),
              child: Text(
                footer!,
                style: TextStyle(fontSize: 12.5, height: 1.45, color: t.text2),
              ),
            ),
        ],
      ),
    );
  }
}

class SidifyGroupRow extends StatelessWidget {
  const SidifyGroupRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.onTap,
    this.danger = false,
    this.chevron = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;
  final bool chevron;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    // An empty title means the leading icon *is* the label (the Speed row):
    // no text column at all, so the trailing control gets the row's width and
    // can wrap instead of fighting a word for the same line.
    final bool hasText = title.isNotEmpty || subtitle != null;
    final Widget row = Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 19, color: danger ? t.danger : t.text),
            const SizedBox(width: 12),
          ],
          if (hasText)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      color: danger ? t.danger : t.text,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: t.text2,
                      ),
                    ),
                ],
              ),
            )
          else if (trailing != null)
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: trailing!,
              ),
            )
          else if (chevron)
            const Spacer(),
          if (hasText && trailing != null) ...<Widget>[
            const SizedBox(width: 8),
            trailing!,
          ],
          if (chevron)
            Icon(Icons.chevron_right_rounded, size: 18, color: t.text3),
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }
}

// ---------------------------------------------------------------------------
// Playing indicator — the three bars that mark the playing row.
// ---------------------------------------------------------------------------

class PlayingBars extends StatefulWidget {
  const PlayingBars({super.key, this.paused = false, this.size = 12, this.color});

  final bool paused;
  final double size;
  final Color? color;

  @override
  State<PlayingBars> createState() => _PlayingBarsState();
}

class _PlayingBarsState extends State<PlayingBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (!widget.paused) _c.repeat();
  }

  @override
  void didUpdateWidget(PlayingBars old) {
    super.didUpdateWidget(old);
    if (widget.paused && _c.isAnimating) _c.stop();
    if (!widget.paused && !_c.isAnimating) _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.color ?? context.sidify.playing;
    final double barW = widget.size / 4.5;
    return SizedBox(
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              for (int i = 0; i < 3; i++) ...<Widget>[
                if (i > 0) SizedBox(width: barW * 0.7),
                Container(
                  width: barW,
                  height: widget.size *
                      (0.3 +
                          0.7 *
                              (0.5 +
                                  0.5 *
                                      _wave(i))),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  double _wave(int i) {
    final double phase = (_c.value + i * 0.22) % 1.0;
    final double x = phase * 2 - 1;
    return 1 - x * x;
  }
}

// ---------------------------------------------------------------------------
// Cards (cards.tsx)
// ---------------------------------------------------------------------------

const double kCardW = 148;

/// Square card for albums / browse items / playlists.
class SquareCard extends StatelessWidget {
  const SquareCard({
    super.key,
    required this.title,
    this.subtitle,
    this.artwork = '',
    this.arts,
    this.onTap,
    this.round = false,
    this.badge,
    this.width = kCardW,
  });

  final String title;
  final String? subtitle;
  final String artwork;
  final List<String>? arts;
  final VoidCallback? onTap;
  final bool round;
  final Widget? badge;

  /// Card width; 0 = stretch to the width the parent offers (grid cells).
  final double width;

  @override
  Widget build(BuildContext context) {
    if (width > 0) return _card(context, width);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) =>
          _card(context, c.maxWidth),
    );
  }

  Widget _card(BuildContext context, double width) {
    final SidifyTokens t = context.sidify;
    final bool mosaic = arts != null && arts!.length >= 4;
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment:
              round ? CrossAxisAlignment.center : CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                if (mosaic)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: width,
                      height: width,
                      child: GridView.count(
                        crossAxisCount: 2,
                        physics: const NeverScrollableScrollPhysics(),
                        children: <Widget>[
                          for (final String a in arts!.take(4))
                            Artwork(url: a, width: width / 2, height: width / 2, radius: 0),
                        ],
                      ),
                    ),
                  )
                else
                  Artwork(
                    url: artwork.isNotEmpty ? artwork : (arts?.first ?? ''),
                    width: width,
                    height: width,
                    radius: 12,
                    round: round,
                  ),
                if (badge != null)
                  Positioned(top: 8, left: 8, child: badge!),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: round ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: t.text,
              ),
            ),
            if (subtitle != null)
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: round ? TextAlign.center : TextAlign.start,
                style: TextStyle(fontSize: 13, color: t.text2),
              ),
          ],
        ),
      ),
    );
  }
}

/// A single song as a card: tapping plays it within its shelf.
class SongCard extends StatelessWidget {
  const SongCard({
    super.key,
    required this.tracks,
    required this.index,
    this.label = '',
    this.width = kCardW,
  });

  final List<Song> tracks;
  final int index;
  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    final Song t = tracks[index];
    final PlaybackService playback = context.watch<PlaybackService>();
    final bool isCurrent = playback.current?.id == t.id;
    final SidifyTokens tok = context.sidify;
    return GestureDetector(
      onTap: () => playback.playQueue(tracks, startIndex: index),
      onLongPress: () => showSongMenu(context, t),
      child: SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Stack(
              children: <Widget>[
                Artwork(url: t.thumbnailUrl, width: width, height: width, radius: 12),
                if (isCurrent)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: PlayingBars(
                          paused: !playback.isPlaying,
                          size: 12,
                          color: tok.playing,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              t.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isCurrent ? tok.playing : tok.text,
              ),
            ),
            Text(
              t.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: tok.text2),
            ),
          ],
        ),
      ),
    );
  }
}

class AlbumCardWidget extends StatelessWidget {
  const AlbumCardWidget({super.key, required this.album, required this.onTap});

  final AlbumCard album;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SquareCard(
      title: album.title,
      subtitle: album.artist,
      artwork: album.coverUrl,
      onTap: onTap,
    );
  }
}

class ArtistCardWidget extends StatelessWidget {
  const ArtistCardWidget({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.onTap,
  });

  final String name;
  final String imageUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SquareCard(
      title: name,
      subtitle: 'Artist',
      artwork: imageUrl,
      onTap: onTap,
      round: true,
    );
  }
}

/// The tall "Top picks" hero card: full-bleed art, scrim, eyebrow + title.
class HeroCard extends StatelessWidget {
  const HeroCard({
    super.key,
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.artwork = '',
    this.onTap,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final String artwork;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final double w = MediaQuery.sizeOf(context).width;
    final double cardW = (w * 0.7).clamp(200.0, 320.0);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: cardW,
        height: cardW / 0.92,
        decoration: BoxDecoration(
          color: context.sidify.raised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.sidify.edge, width: 0.5),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (ArtworkCache.isNetworkArtwork(artwork))
              Image(
                image: ArtworkCache.providerFor(artwork),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              )
            else
              Container(color: context.sidify.raised2),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.transparent,
                    Color(0x1A000000),
                    Color(0xC7000000),
                  ],
                  stops: <double>[0, 0.35, 1],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 16,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (eyebrow != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        eyebrow!.toUpperCase(),
                        style: SidifyText.eyebrow(
                          Colors.white.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      height: 1.15,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.3,
                      color: Colors.white,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

/// Compact row (quick picks): 48px artwork, title/artist, "…" menu.
class CompactRow extends StatelessWidget {
  const CompactRow({
    super.key,
    required this.tracks,
    required this.index,
    this.label = '',
  });

  final List<Song> tracks;
  final int index;
  final String label;

  @override
  Widget build(BuildContext context) {
    final Song t = tracks[index];
    final PlaybackService playback = context.watch<PlaybackService>();
    final bool isCurrent = playback.current?.id == t.id;
    final SidifyTokens tok = context.sidify;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => playback.playQueue(tracks, startIndex: index),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 60,
          padding: const EdgeInsets.only(right: 4),
          child: Row(
            children: <Widget>[
              Stack(
                children: <Widget>[
                  Artwork(url: t.thumbnailUrl, size: 48, radius: 7),
                  if (isCurrent)
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Center(
                        child: PlayingBars(
                          paused: !playback.isPlaying,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: isCurrent ? tok.playing : tok.text,
                      ),
                    ),
                    Text(
                      t.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: tok.text2),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.more_horiz_rounded, size: 17, color: tok.text2),
                onPressed: () => showSongMenu(context, t),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Quick picks: columns of four compact rows scrolling sideways together.
/// On a phone each column is a full-width page of four rows.
class QuickPicks extends StatelessWidget {
  const QuickPicks({super.key, required this.tracks, this.label = ''});

  final List<Song> tracks;
  final String label;

  @override
  Widget build(BuildContext context) {
    final double w = MediaQuery.sizeOf(context).width;
    final double colW = (w * 0.88).clamp(280.0, 400.0);
    final List<List<int>> columns = <List<int>>[];
    for (int i = 0; i < tracks.length; i += 4) {
      columns.add(List<int>.generate(
        (tracks.length - i).clamp(0, 4),
        (int k) => i + k,
      ));
    }
    return SizedBox(
      height: 248,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        physics: const BouncingScrollPhysics(),
        itemCount: columns.length,
        separatorBuilder: (_, __) => const SizedBox(width: 16),
        itemBuilder: (_, int ci) => SizedBox(
          width: colW,
          child: Column(
            children: <Widget>[
              for (final int i in columns[ci])
                CompactRow(tracks: tracks, index: i, label: label),
            ],
          ),
        ),
      ),
    );
  }
}

/// One song in a list (TrackRow.tsx): 52px artwork or a track number, title
/// and artist, a heart when liked, the duration, and the "…" menu — with a
/// hairline under the text.
class TrackRow extends StatelessWidget {
  const TrackRow({
    super.key,
    required this.tracks,
    required this.index,
    this.numbered = false,
    this.subtitle,
    this.onRemove,
    this.onTap,
  });

  final List<Song> tracks;
  final int index;
  final bool numbered;
  final String? subtitle;
  final VoidCallback? onRemove;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Song t = tracks[index];
    final PlaybackService playback = context.watch<PlaybackService>();
    final LibraryService library = context.watch<LibraryService>();
    final bool isCurrent = playback.current?.id == t.id;
    final bool liked = library.isLiked(t.id);
    final SidifyTokens tok = context.sidify;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () => playback.playQueue(tracks, startIndex: index),
        onLongPress: () => showSongMenu(context, t),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: SizedBox(
            height: numbered ? 52 : 64,
            child: Row(
              children: <Widget>[
                if (numbered)
                  SizedBox(
                    width: 28,
                    child: Center(
                      child: isCurrent
                          ? PlayingBars(
                              paused: !playback.isPlaying,
                              size: 12,
                              color: tok.playing,
                            )
                          : Text(
                              '${index + 1}',
                              style: TextStyle(fontSize: 15, color: tok.text2),
                            ),
                    ),
                  )
                else
                  Stack(
                    children: <Widget>[
                      Artwork(url: t.thumbnailUrl, size: 52, radius: 6),
                      if (isCurrent)
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: PlayingBars(
                              paused: !playback.isPlaying,
                              size: 13,
                              color: Colors.white,
                            ),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: tok.divider, width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 15,
                                  color: isCurrent ? tok.playing : tok.text,
                                ),
                              ),
                              Text(
                                subtitle ?? t.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, color: tok.text2),
                              ),
                            ],
                          ),
                        ),
                        if (liked)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Icon(
                              Icons.favorite_rounded,
                              size: 15,
                              color: tok.playing,
                            ),
                          ),
                        if (t.duration != null)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              Fmt.duration(t.duration),
                              style: TextStyle(
                                fontSize: 13,
                                color: tok.text2,
                                fontFeatures: const <FontFeature>[
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
                        if (onRemove != null)
                          IconButton(
                            icon: Icon(Icons.close_rounded,
                                size: 16, color: tok.text2),
                            onPressed: onRemove,
                          )
                        else
                          IconButton(
                            icon: Icon(Icons.more_horiz_rounded,
                                size: 18, color: tok.text2),
                            onPressed: () => showSongMenu(context, t),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Mood / genre tile (Explore): a solid colour with a duotone of the cover,
/// the name top-left. [colorHex] like `#7aaed0`.
class MoodCard extends StatelessWidget {
  const MoodCard({
    super.key,
    required this.title,
    required this.colorHex,
    this.artwork = '',
    this.onTap,
  });

  final String title;
  final String colorHex;
  final String artwork;
  final VoidCallback? onTap;

  static Color parse(String hex) {
    final String h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    final Color base = parse(colorHex);
    final Color dark = Color.lerp(base, Colors.black, 0.08) ?? base;
    final bool hasArt = artwork.isNotEmpty && ArtworkCache.isNetworkArtwork(artwork);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: dark,
          borderRadius: BorderRadius.circular(18),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            if (hasArt)
              // The site's mood tile: a duotone sleeve filling the right 72% of
              // the card, tinted toward the mood colour.
              Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.72,
                  heightFactor: 1,
                  child: Container(
                    color: Color.lerp(base, Colors.black, 0.55),
                    child: Opacity(
                      opacity: 0.9,
                      child: Image(
                        image: ArtworkCache.providerFor(artwork),
                        fit: BoxFit.cover,
                        color: Color.lerp(base, Colors.white, 0.7),
                        colorBlendMode: BlendMode.modulate,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ),
                ),
              ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: <Color>[Color(0x3D000000), Colors.transparent],
                ),
              ),
            ),
            Positioned(
              top: 12,
              left: 14,
              right: 12,
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.15,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  shadows: <Shadow>[
                    Shadow(color: Color(0x59000000), blurRadius: 6),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
