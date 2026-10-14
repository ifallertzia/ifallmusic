import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/branding.dart';
import 'saxify_accents.dart';

/// The IfallMusic design language.
///
/// Everything sits on **true black** with frosted-glass panels floating above
/// it — the Apple-Music-inspired look. Heavy, tight typography; hairline
/// separators; a single accent that is painted across the whole app.
///
/// Every colour resolves through [IfallColors.of], so the Light theme is a
/// first-class citizen rather than an afterthought.
class IfallUI {
  const IfallUI._();

  // ------------------------------------------------------------------ shape
  static const double rSm = 10;
  static const double rMd = 14;
  static const double rLg = 20;
  static const double rXl = 28;
  static const double rPill = 999;

  /// The floating bars never grow past this, so a tablet keeps a sane layout.
  static const double maxBarWidth = 520;

  static const EdgeInsets pagePadding = EdgeInsets.symmetric(horizontal: 16);

  /// Blur sigma used by every frosted surface.
  static const double blur = 26;
}

/// Per-brightness tokens.
class IfallColors {
  const IfallColors._();

  static const Color black = Color(0xFF000000);
  static const Color white = Color(0xFFFFFFFF);

  /// Apple-Music red. Not the app accent — reserved for the spots that want
  /// exactly that red (the Replay rank badge, "Liked" hearts).
  static const Color accentRed = Color(0xFFFA2D48);

  static const Color green = Color(0xFF1DB954);
  static const Color amber = Color(0xFFFFB020);
  static const Color dangerLight = Color(0xFFFF453A);
}

/// The palette a widget actually paints with, resolved from the theme.
class IfallPalette {
  const IfallPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.outline,
    required this.accent,
    required this.glass,
    required this.glassStrong,
    required this.scrim,
  });

  final Brightness brightness;

  /// The floor every page is drawn against.
  final Color background;

  /// Frosted panels, sheets, cards.
  final Color surface;
  final Color surfaceVariant;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color outline;

  /// The live theme accent.
  final Color accent;

  /// Translucent white/black films laid over content.
  final Color glass;
  final Color glassStrong;

  /// Fades used behind text sitting on artwork.
  final Color scrim;

  bool get isDark => brightness == Brightness.dark;

  /// A neutral fill for chips, fields and progress tracks — one step above
  /// [background], one below [surface].
  Color get fill => surfaceVariant;

  /// The destructive colour for this brightness.
  Color get danger => isDark ? IfallColors.dangerLight : const Color(0xFFFF3B30);

  /// Builds the palette for [brightness], tinted by the live [accent].
  factory IfallPalette.of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool dark = theme.brightness == Brightness.dark;
    final Color accent = context.accentOrWhite;
    return IfallPalette(
      brightness: theme.brightness,
      background: dark ? IfallColors.black : IfallColors.white,
      surface: dark ? const Color(0xFF0D0D0F) : const Color(0xFFF7F7F9),
      surfaceVariant: dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7),
      onSurface: dark ? IfallColors.white : IfallColors.black,
      onSurfaceVariant: dark ? const Color(0xFF8E8E93) : const Color(0xFF6E6E73),
      outline: dark ? const Color(0xFF2C2C2E) : const Color(0xFFE5E5EA),
      accent: accent,
      glass: dark
          ? const Color(0x14FFFFFF)
          : const Color(0x0A000000),
      glassStrong: dark
          ? const Color(0x24FFFFFF)
          : const Color(0x14000000),
      scrim: dark
          ? Colors.black.withValues(alpha: 0.55)
          : Colors.white.withValues(alpha: 0.65),
    );
  }
}

/// Heavy, tight typography — SF Pro Display is the reference face; Inter is the
/// closest widely available match and the fallback chain keeps Apple platforms
/// on the real system font.
class IfallText {
  const IfallText._();

  static const List<String> fallback = <String>[
    'SF Pro Display',
    'SF Pro Text',
    '-apple-system',
    'Helvetica Neue',
    'Roboto',
  ];

  static TextStyle style(
    double size, {
    FontWeight weight = FontWeight.w600,
    Color? color,
    double letterSpacing = -0.3,
    double height = 1.25,
    TextOverflow? overflow,
    int? maxLines,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      overflow: overflow,
    ).copyWith(fontFamilyFallback: fallback);
  }

  /// The big page title (Home, Search, Library…).
  static TextStyle display(Color color) =>
      style(32, weight: FontWeight.w800, letterSpacing: -0.9, color: color);

  static TextStyle title(Color color) =>
      style(21, weight: FontWeight.w700, letterSpacing: -0.5, color: color);

  static TextStyle section(Color color) =>
      style(19, weight: FontWeight.w700, letterSpacing: -0.4, color: color);

  static TextStyle body(Color color) =>
      style(15, weight: FontWeight.w500, letterSpacing: -0.1, color: color, height: 1.35);

  static TextStyle caption(Color color) =>
      style(13, weight: FontWeight.w500, letterSpacing: 0, color: color);

  static TextStyle label(Color color) =>
      style(11.5, weight: FontWeight.w700, letterSpacing: 0.2, color: color);
}

/// Flat colour tokens for widgets that have not been threaded through
/// [IfallPalette] yet.
///
/// The app ships dark-only (`themeMode: ThemeMode.dark` in `main.dart`) and
/// these are exactly the values [IfallPalette] resolves for
/// [Brightness.dark] — so the two systems agree on every pixel and a widget
/// can be converted one file at a time.
class IfallTokens {
  const IfallTokens._();

  static const Color background = IfallColors.black;
  static const Color surface = Color(0xFF0D0D0F);
  static const Color surfaceAlt = Color(0xFF1C1C1E);
  static const Color border = Color(0xFF2C2C2E);
  static const Color hairline = Color(0x14FFFFFF);
  static const Color textPrimary = IfallColors.white;
  static const Color textSecondary = Color(0xFF8E8E93);
  static const Color textMuted = Color(0xFF8E8E93);
  static const Color textFaint = Color(0xFF6E6E73);
  static const Color danger = IfallColors.dangerLight;
  static const Color success = IfallColors.green;
}

/// The page floor: true black, optionally lifted by one very soft accent
/// bloom in the top corner.
///
/// BitChord keeps its backgrounds flat so the artwork is the only colour on
/// screen — this replaces the old animated aurora with that restraint.
class IfallBackdrop extends StatelessWidget {
  const IfallBackdrop({
    super.key,
    required this.child,
    this.intensity = 1,
  });

  final Widget child;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    if (intensity <= 0) {
      return ColoredBox(color: c.background, child: child);
    }
    return ColoredBox(
      color: c.background,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          Positioned(
            top: -220,
            right: -160,
            child: IgnorePointer(
              child: Container(
                width: 420,
                height: 420,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: <Color>[
                      c.accent.withValues(alpha: 0.10 * intensity),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- glass

/// A frosted panel: translucent fill, hairline border, blurred backdrop.
class IfallGlass extends StatelessWidget {
  const IfallGlass({
    super.key,
    required this.child,
    this.radius = IfallUI.rLg,
    this.padding,
    this.margin,
    this.blur = IfallUI.blur,
    this.color,
    this.border,
    this.width,
    this.height,
    this.onTap,
    this.glow = false,
    this.tint,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double blur;
  final Color? color;
  final Color? border;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  /// Adds a soft accent-coloured halo — reserved for the one panel on a page
  /// that should catch the eye.
  final bool glow;

  /// Overrides the panel's fill colour.
  final Color? tint;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    Widget panel = Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: tint ?? color ?? c.glass,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: border ?? c.outline.withValues(alpha: 0.7)),
        boxShadow: glow
            ? <BoxShadow>[
                BoxShadow(
                  color: c.accent.withValues(alpha: 0.18),
                  blurRadius: 30,
                  spreadRadius: -10,
                ),
              ]
            : null,
      ),
      child: child,
    );
    if (blur > 0) {
      panel = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: panel,
      );
    }
    panel = ClipRRect(borderRadius: BorderRadius.circular(radius), child: panel);
    if (onTap != null) {
      panel = Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: panel,
        ),
      );
    }
    if (margin != null) panel = Padding(padding: margin!, child: panel);
    return panel;
  }
}

// -------------------------------------------------------------------- top bar

/// The frosted top bar that sits on every page.
///
/// It is transparent until the content scrolls under it, at which point the
/// blur and a hairline fade in — the Telegram/Apple Music behaviour BitChord
/// is known for.
class IfallTopBar extends StatelessWidget implements PreferredSizeWidget {
  const IfallTopBar({
    super.key,
    this.title,
    this.titleWidget,
    this.leading,
    this.actions = const <Widget>[],
    this.scrolled = false,
    this.bottom,
    this.height = 54,
    this.centerTitle = false,
  });

  final String? title;
  final Widget? titleWidget;
  final Widget? leading;
  final List<Widget> actions;
  final bool scrolled;
  final PreferredSizeWidget? bottom;
  final double height;
  final bool centerTitle;

  @override
  Size get preferredSize =>
      Size.fromHeight(height + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: scrolled ? 22 : 0,
          sigmaY: scrolled ? 22 : 0,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: scrolled
                ? (c.isDark
                    ? Colors.black.withValues(alpha: 0.62)
                    : Colors.white.withValues(alpha: 0.78))
                : Colors.transparent,
            border: scrolled
                ? Border(
                    bottom: BorderSide(
                      color: c.outline.withValues(alpha: 0.6),
                      width: 0.5,
                    ),
                  )
                : null,
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: height,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Row(
                  children: <Widget>[
                    if (leading != null) leading! else const SizedBox(width: 10),
                    Expanded(
                      child: centerTitle
                          ? Center(child: _title(context, c))
                          : _title(context, c),
                    ),
                    ...actions,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _title(BuildContext context, IfallPalette c) {
    if (titleWidget != null) return titleWidget!;
    return Text(
      title ?? '',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: IfallText.display(c.onSurface),
    );
  }
}

// --------------------------------------------------------------- section head

/// "Made for you" + an optional chevron/"See all".
class IfallSectionHeader extends StatelessWidget {
  const IfallSectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onSeeAll,
    this.seeAllLabel = 'See all',
    this.padding = const EdgeInsets.fromLTRB(16, 22, 8, 10),
  });

  final String title;
  final String? subtitle;
  final VoidCallback? onSeeAll;
  final String seeAllLabel;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IfallText.section(c.onSurface),
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IfallText.caption(c.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              style: TextButton.styleFrom(
                foregroundColor: c.accent,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                seeAllLabel,
                style: IfallText.caption(c.accent).copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ settings

/// One settings row: icon, title, optional subtitle / value, trailing.
class IfallRow extends StatelessWidget {
  const IfallRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.trailing,
    this.value,
    this.onTap,
    this.danger = false,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? iconColor;
  final Widget? trailing;
  final String? value;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final Color text =
        danger ? (c.isDark ? IfallColors.dangerLight : const Color(0xFFFF3B30)) : c.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 21, color: iconColor ?? (danger ? text : c.accent)),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IfallText.body(text),
                    ),
                    if (subtitle != null) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: IfallText.caption(c.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              if (value != null) ...<Widget>[
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 130),
                  child: Text(
                    value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: IfallText.caption(c.onSurfaceVariant),
                  ),
                ),
              ],
              if (trailing != null) ...<Widget>[
                const SizedBox(width: 6),
                trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A settings row whose control is a switch.
class IfallSwitchRow extends StatelessWidget {
  const IfallSwitchRow({
    super.key,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return IfallRow(
      title: title,
      subtitle: subtitle,
      icon: icon,
      onTap: () => onChanged(!value),
      trailing: Switch.adaptive(
        value: value,
        activeColor: c.accent,
        onChanged: onChanged,
      ),
    );
  }
}

/// A settings row with a slider and a live value label.
class IfallSliderRow extends StatelessWidget {
  const IfallSliderRow({
    super.key,
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.subtitle,
    this.icon,
    this.divisions,
    this.format,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String Function(double value)? format;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (icon != null) ...<Widget>[
                Icon(icon, size: 20, color: c.accent),
                const SizedBox(width: 14),
              ],
              Expanded(
                child: Text(
                  title,
                  style: IfallText.body(c.onSurface),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                format != null ? format!(value) : value.toStringAsFixed(2),
                style: IfallText.caption(c.onSurfaceVariant)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          if (subtitle != null) ...<Widget>[
            const SizedBox(height: 2),
            Padding(
              padding: EdgeInsets.only(left: icon != null ? 34 : 0),
              child: Text(
                subtitle!,
                style: IfallText.caption(c.onSurfaceVariant),
              ),
            ),
          ],
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: c.accent,
            inactiveColor: c.glassStrong,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Apple-style segmented control inside a frosted track.
class IfallSegmented<T extends Object> extends StatelessWidget {
  const IfallSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.labelBuilder,
  });

  final T value;
  final List<T> options;
  final ValueChanged<T> onChanged;
  final String Function(T value)? labelBuilder;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return IfallGlass(
      radius: IfallUI.rMd,
      blur: 0,
      padding: const EdgeInsets.all(3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final T option in options)
            Expanded(
              child: _Segment(
                label: labelBuilder != null
                    ? labelBuilder!(option)
                    : option.toString(),
                selected: option == value,
                accent: c.accent,
                onSurface: c.onSurface,
                onTap: () => onChanged(option),
              ),
            ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  const _Segment({
    required this.label,
    required this.selected,
    required this.accent,
    required this.onSurface,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(IfallUI.rSm),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? accent : Colors.transparent,
            borderRadius: BorderRadius.circular(IfallUI.rSm),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: IfallText.caption(
              selected
                  ? (ThemeData.estimateBrightnessForColor(accent) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black)
                  : onSurface.withValues(alpha: 0.75),
            ).copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

/// A pill filter chip (genre / mood / library filter).
class IfallChip extends StatelessWidget {
  const IfallChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(IfallUI.rPill),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? c.accent : c.glass,
              borderRadius: BorderRadius.circular(IfallUI.rPill),
              border: Border.all(
                color: selected ? c.accent : c.outline.withValues(alpha: 0.8),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(
                    icon,
                    size: 15,
                    color: selected
                        ? (ThemeData.estimateBrightnessForColor(c.accent) ==
                                Brightness.dark
                            ? Colors.white
                            : Colors.black)
                        : c.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: IfallText.caption(
                    selected
                        ? (ThemeData.estimateBrightnessForColor(c.accent) ==
                                Brightness.dark
                            ? Colors.white
                            : Colors.black)
                        : c.onSurface,
                  ).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- sheets

/// The bottom-sheet scaffold every sheet in the app is built on.
Future<T?> showIfallSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool useRootNavigator = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    useRootNavigator: useRootNavigator,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.45),
    builder: builder,
  );
}

/// A sheet surface: grab handle, optional title, scrollable body.
class IfallSheet extends StatelessWidget {
  const IfallSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.maxHeightFactor = 0.92,
    this.padding = const EdgeInsets.fromLTRB(16, 6, 16, 24),
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final List<Widget> actions;
  final double maxHeightFactor;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final double bottom = MediaQuery.viewPaddingOf(context).bottom;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
      ),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(IfallUI.rXl),
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 34, sigmaY: 34),
          child: Container(
            decoration: BoxDecoration(
              color: c.isDark
                  ? const Color(0xF20D0D0F)
                  : const Color(0xFAF7F7F9),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(IfallUI.rXl),
              ),
              border: Border(
                top: BorderSide(color: c.outline.withValues(alpha: 0.8)),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const SizedBox(height: 8),
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.onSurfaceVariant.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  if (title != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 12, 12, 4),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  title!,
                                  style: IfallText.title(c.onSurface),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (subtitle != null) ...<Widget>[
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitle!,
                                    style: IfallText.caption(c.onSurfaceVariant),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          ...actions,
                        ],
                      ),
                    ),
                  Flexible(
                    child: SingleChildScrollView(
                      padding: padding,
                      child: child,
                    ),
                  ),
                  SizedBox(height: bottom > 0 ? 0 : 8),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A titled group of settings rows inside a frosted card.
class IfallGroup extends StatelessWidget {
  const IfallGroup({
    super.key,
    required this.children,
    this.title,
    this.footer,
  });

  final List<Widget> children;
  final String? title;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Text(
                title!.toUpperCase(),
                style: IfallText.label(c.onSurfaceVariant),
              ),
            ),
          IfallGlass(
            radius: IfallUI.rLg,
            blur: 0,
            color: c.glass,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < children.length; i++) ...<Widget>[
                  if (i > 0)
                    Divider(
                      height: 1,
                      indent: 16,
                      endIndent: 0,
                      color: c.outline.withValues(alpha: 0.5),
                    ),
                  children[i],
                ],
              ],
            ),
          ),
          if (footer != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
              child: Text(
                footer!,
                style: IfallText.caption(c.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------------- misc

/// Centred "nothing here yet" state with the mascot.
class IfallEmpty extends StatelessWidget {
  const IfallEmpty({
    super.key,
    required this.message,
    this.icon = Icons.music_note_rounded,
    this.action,
    this.actionLabel,
    this.compact = false,
  });

  final String message;
  final IconData icon;
  final VoidCallback? action;
  final String? actionLabel;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final double size = compact ? 54 : 84;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Opacity(
              opacity: 0.85,
              child: Image.asset(
                IfallBranding.logoAsset,
                width: size,
                height: size,
                fit: BoxFit.contain,
              ),
            ),
            if (message.isNotEmpty) ...<Widget>[
              SizedBox(height: compact ? 10 : 16),
              Text(
                message,
                textAlign: TextAlign.center,
                style: IfallText.body(c.onSurfaceVariant),
              ),
            ],
            if (action != null && actionLabel != null) ...<Widget>[
              const SizedBox(height: 16),
              FilledButton(
                onPressed: action,
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor:
                      ThemeData.estimateBrightnessForColor(c.accent) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(IfallUI.rPill),
                  ),
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A shimmering placeholder row used while a rail loads.
class IfallShimmer extends StatefulWidget {
  const IfallShimmer({super.key, this.width = double.infinity, this.height = 14});

  final double width;
  final double height;

  @override
  State<IfallShimmer> createState() => _IfallShimmerState();
}

class _IfallShimmerState extends State<IfallShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return AnimatedBuilder(
      animation: _c,
      builder: (BuildContext context, Widget? child) {
        final double t = (_c.value * 2) % 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.height / 2),
            gradient: LinearGradient(
              colors: <Color>[
                c.glass,
                c.glassStrong,
                c.glass,
              ],
              stops: <double>[
                (t - 0.3).clamp(0.0, 1.0),
                t.clamp(0.0, 1.0),
                (t + 0.3).clamp(0.0, 1.0),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Rounded, accent-tinted icon button used in top bars.
class IfallIconButton extends StatelessWidget {
  const IfallIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 22,
    this.color,
    this.filled = false,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final String? tooltip;
  final double size;
  final Color? color;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final Widget button = IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      iconSize: size,
      visualDensity: VisualDensity.compact,
      icon: Icon(icon, color: color ?? c.onSurface),
    );
    if (!filled) return button;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
      child: IfallGlass(
        radius: IfallUI.rPill,
        blur: 0,
        child: SizedBox(
          width: 34,
          height: 34,
          child: button,
        ),
      ),
    );
  }
}

/// A horizontal, scrollable row of filter chips.
class IfallChipRow extends StatelessWidget {
  const IfallChipRow({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.icons,
  });

  final List<String> labels;
  final String selected;
  final ValueChanged<String> onSelected;
  final List<IconData>? icons;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 0),
        itemBuilder: (BuildContext context, int i) {
          return IfallChip(
            label: labels[i],
            selected: labels[i] == selected,
            icon: icons != null && i < icons!.length ? icons![i] : null,
            onTap: () => onSelected(labels[i]),
          );
        },
      ),
    );
  }
}

/// Small helper: clamps a double the way the layout code keeps needing it.
double ifallClamp(double value, double min, double max) =>
    math.min(max, math.max(min, value));
