import 'dart:ui';

import 'package:flutter/material.dart';

import 'saxify_accents.dart';
import 'saxify_theme.dart';

/// ---------------------------------------------------------------------------
/// IfallMusic "Liquid Glass" design system.
///
/// Apple-style frosted panels on **absolute black**. Everything the app shows
/// (cards, buttons, sheets, the player, the tab bar) is built from these pieces
/// so the whole UI stays consistent and premium on every phone size.
///
/// Layout rules baked in here (they are what stops the UI from breaking on
/// small screens):
///   * text always shrinks / ellipsises instead of overflowing,
///   * buttons keep a real minimum tap target and grow horizontally only,
///   * no fixed pixel widths for content that comes from user data.
/// ---------------------------------------------------------------------------

/// Soft, deep accent glow painted *behind* the black UI so the glass has
/// something to refract. Kept subtle: black stays black.
class AuroraBackdrop extends StatelessWidget {
  const AuroraBackdrop({super.key, required this.child, this.intensity = 1});

  final Widget child;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return ColoredBox(
      color: SaxifyColors.background,
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -180,
            left: -120,
            right: -120,
            child: IgnorePointer(
              child: Container(
                height: 420,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.4, -0.6),
                    radius: 0.9,
                    colors: <Color>[
                      accent.primary.withValues(alpha: 0.22 * intensity),
                      accent.primary.withValues(alpha: 0.06 * intensity),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -220,
            left: -140,
            right: -140,
            child: IgnorePointer(
              child: Container(
                height: 460,
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0.5, 0.7),
                    radius: 0.95,
                    colors: <Color>[
                      accent.secondary.withValues(alpha: 0.18 * intensity),
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

/// A frosted glass surface. This is the single primitive every card, bar and
/// sheet in the app is made of.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = SaxifyTheme.radiusLg,
    this.blur = true,
    this.blurSigma = GlassBlur.regular,
    this.onTap,
    this.glow = false,
    this.tint,
    this.borderColor,
    this.strength = 1,
    this.clip = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool blur;
  final double blurSigma;
  final VoidCallback? onTap;
  final bool glow;
  final Color? tint;
  final Color? borderColor;
  final double strength;
  final bool clip;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final BorderRadius br = BorderRadius.circular(radius);

    final BoxDecoration decoration = BoxDecoration(
      borderRadius: br,
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          (tint ?? Colors.white).withValues(alpha: 0.085 * strength),
          (tint ?? Colors.white).withValues(alpha: 0.028 * strength),
        ],
      ),
      border: Border.all(
        color: borderColor ?? Colors.white.withValues(alpha: 0.10),
      ),
      boxShadow: <BoxShadow>[
        if (glow)
          BoxShadow(
            color: accent.primary.withValues(alpha: 0.28),
            blurRadius: 40,
            spreadRadius: -12,
            offset: const Offset(0, 14),
          ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.55),
          blurRadius: 26,
          spreadRadius: -14,
          offset: const Offset(0, 12),
        ),
      ],
    );

    Widget surface = DecoratedBox(
      decoration: decoration,
      child: Padding(padding: padding, child: child),
    );

    if (blur) {
      surface = ClipRRect(
        borderRadius: br,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: surface,
        ),
      );
    } else if (clip) {
      surface = ClipRRect(borderRadius: br, child: surface);
    }

    // A hairline highlight along the top edge — the "glass lip".
    surface = Stack(
      children: <Widget>[
        surface,
        Positioned(
          top: 0,
          left: radius * 0.8,
          right: radius * 0.8,
          child: IgnorePointer(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Colors.transparent,
                    Colors.white.withValues(alpha: 0.30),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );

    if (onTap == null) return surface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: br,
        splashColor: accent.primary.withValues(alpha: 0.10),
        highlightColor: accent.primary.withValues(alpha: 0.05),
        child: surface,
      ),
    );
  }
}

/// Big, colourful, liquid-glass button. Used for every primary action.
///
/// * `expand` makes it fill the available width without ever overflowing.
/// * the label scales down / ellipsises inside its own row, so long text and
///   large system fonts can never push the icon out of the button.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.filled = true,
    this.expand = false,
    this.compact = false,
    this.radius,
    this.trailing,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;
  final bool expand;
  final bool compact;
  final double? radius;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final BorderRadius br = BorderRadius.circular(radius ?? SaxifyTheme.radiusXl);
    final double height = compact ? 44 : 54;
    final Color fg = filled ? accent.onAccent : SaxifyColors.textPrimary;

    final Widget content = Row(
      mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          Icon(icon, size: compact ? 17 : 19, color: fg),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: compact ? 13 : 14.5,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
              color: fg,
            ),
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );

    final Widget body = ClipRRect(
      borderRadius: br,
      child: BackdropFilter(
        filter: GlassBlur.regularFilter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: br,
            gradient: filled
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      accent.primary.withValues(alpha: 0.98),
                      accent.secondary.withValues(alpha: 0.88),
                    ],
                  )
                : LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Colors.white.withValues(alpha: 0.12),
                      Colors.white.withValues(alpha: 0.05),
                    ],
                  ),
            border: Border.all(
              color: filled
                  ? Colors.white.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.14),
            ),
            boxShadow: <BoxShadow>[
              if (filled)
                BoxShadow(
                  color: accent.primary.withValues(alpha: 0.34),
                  blurRadius: 26,
                  spreadRadius: -10,
                  offset: const Offset(0, 10),
                ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.5),
                blurRadius: 18,
                spreadRadius: -10,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 22),
            child: Center(child: content),
          ),
        ),
      ),
    );

    final Widget sized = SizedBox(
      width: expand ? double.infinity : null,
      height: height,
      child: body,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: br,
        child: sized,
      ),
    );
  }
}

/// Circular frosted icon button — the Apple-style control for toolbars.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.size = 44,
    this.iconSize = 20,
    this.tooltip,
    this.active = false,
    this.badgeCount = 0,
  });

  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final String? tooltip;
  final bool active;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final Widget button = ClipRRect(
      borderRadius: BorderRadius.circular(size / 2),
      child: BackdropFilter(
        filter: GlassBlur.regularFilter,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? accent.primary.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.07),
            border: Border.all(
              color: active
                  ? accent.primary.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: iconSize,
              color: active ? accent.primary : SaxifyColors.textPrimary,
            ),
          ),
        ),
      ),
    );

    final Widget wrapped = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        customBorder: const CircleBorder(),
        child: button,
      ),
    );

    if (badgeCount <= 0) {
      return tooltip == null ? wrapped : Tooltip(message: tooltip!, child: wrapped);
    }

    return Tooltip(
      message: tooltip ?? '',
      child: Stack(
        clipBehavior: Clip.none,
        children: <Widget>[
          wrapped,
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              constraints: const BoxConstraints(minWidth: 17),
              decoration: BoxDecoration(
                color: accent.primary,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: SaxifyColors.background, width: 1.5),
              ),
              child: Text(
                badgeCount > 99 ? '99+' : '$badgeCount',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 9.5,
                  height: 1.3,
                  fontWeight: FontWeight.w800,
                  color: accent.onAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Section title + optional action, styled for the black glass look.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    this.padding = const EdgeInsets.fromLTRB(18, 20, 16, 10),
    this.icon,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final EdgeInsets padding;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (icon != null) ...<Widget>[
                      Icon(icon, size: 17, color: accent.primary),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: SaxifyTheme.appleFont(
                          size: 20,
                          weight: FontWeight.w700,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                if (subtitle != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    subtitle!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.35,
                      color: SaxifyColors.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (actionLabel != null)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: TextButton(
                onPressed: onAction,
                style: TextButton.styleFrom(
                  foregroundColor: accent.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                child: Text(actionLabel!.toUpperCase()),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom-sheet shell with the frosted glass treatment.
class GlassSheet extends StatelessWidget {
  const GlassSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.maxHeightFactor = 0.9,
  });

  final Widget child;
  final String? title;
  final String? subtitle;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    final Size screen = MediaQuery.sizeOf(context);
    return SafeArea(
      top: false,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screen.height * maxHeightFactor),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(SaxifyTheme.radiusLg)),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0B0B0F).withValues(alpha: 0.92),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(SaxifyTheme.radiusLg)),
                  border: Border(
                    top: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const SizedBox(height: 10),
                    Container(
                      width: 44,
                      height: 4.5,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    if (title != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SaxifyTheme.appleFont(
                                size: 19,
                                weight: FontWeight.w700,
                                letterSpacing: -0.4,
                              ),
                            ),
                            if (subtitle != null) ...<Widget>[
                              const SizedBox(height: 3),
                              Text(
                                subtitle!,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: SaxifyColors.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    Flexible(child: child),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted progress bar with the live percentage printed inside it.
class GlassProgress extends StatelessWidget {
  const GlassProgress({
    super.key,
    required this.fraction,
    this.height = 6,
    this.label,
    this.indeterminate = false,
  });

  final double fraction;
  final double height;
  final String? label;
  final bool indeterminate;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final double value = fraction.isNaN ? 0 : fraction.clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (label != null) ...<Widget>[
          Text(
            label!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: accent.primary,
            ),
          ),
          const SizedBox(height: 5),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(height),
          child: SizedBox(
            height: height,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: ColoredBox(color: Colors.white.withValues(alpha: 0.10)),
                ),
                if (indeterminate)
                  Positioned.fill(
                    child: LinearProgressIndicator(
                      minHeight: height,
                      backgroundColor: Colors.transparent,
                      valueColor: AlwaysStoppedAnimation<Color>(accent.primary),
                    ),
                  )
                else
                  FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value == 0 ? 0.02 : value,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[accent.primary, accent.secondary],
                        ),
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Flat glass row used for list items (no blur — fast inside long lists).
class GlassListTile extends StatelessWidget {
  const GlassListTile({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    this.radius = SaxifyTheme.radiusMd,
    this.margin = const EdgeInsets.only(bottom: 8),
    this.selected = false,
    this.leading,
    this.trailing,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsets padding;
  final double radius;
  final EdgeInsets margin;
  final bool selected;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final BorderRadius br = BorderRadius.circular(radius);
    return Padding(
      padding: margin,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: br,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: br,
              color: selected
                  ? accent.primary.withValues(alpha: 0.16)
                  : Colors.white.withValues(alpha: 0.045),
              border: Border.all(
                color: selected
                    ? accent.primary.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.08),
              ),
            ),
            child: Padding(
              padding: padding,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  if (leading != null) ...<Widget>[
                    leading!,
                    const SizedBox(width: 12),
                  ],
                  Expanded(child: child),
                  if (trailing != null) ...<Widget>[
                    const SizedBox(width: 8),
                    trailing!,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Empty-state placeholder, black + glass.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    accent.primary.withValues(alpha: 0.30),
                    accent.secondary.withValues(alpha: 0.10),
                  ],
                ),
                border: Border.all(color: accent.primary.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, size: 34, color: accent.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: SaxifyTheme.appleFont(
                size: 18,
                weight: FontWeight.w700,
                letterSpacing: -0.3,
              ),
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13,
                  color: SaxifyColors.textMuted,
                  height: 1.5,
                ),
              ),
            ],
            if (actionLabel != null) ...<Widget>[
              const SizedBox(height: 22),
              GlassButton(
                label: actionLabel!,
                onPressed: onAction,
                compact: true,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shimmer skeleton used while a rail loads.
class LoadingRail extends StatelessWidget {
  const LoadingRail({super.key, this.itemCount = 5, this.height = 64});

  final int itemCount;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        for (int i = 0; i < itemCount; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(
              children: <Widget>[
                _Shimmer(width: height - 8, height: height - 8),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const _Shimmer(width: 190, height: 11),
                      const SizedBox(height: 8),
                      const _Shimmer(width: 110, height: 9),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.width, required this.height});

  final double width;
  final double height;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, _) {
        final double t = _controller.value;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            gradient: LinearGradient(
              begin: Alignment(-1.5 + t * 3, 0),
              end: Alignment(-0.5 + t * 3, 0),
              colors: <Color>[
                Colors.white.withValues(alpha: 0.05),
                Colors.white.withValues(alpha: 0.13),
                Colors.white.withValues(alpha: 0.05),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Hairline divider with an accent fade at the start.
class NeonDivider extends StatelessWidget {
  const NeonDivider({super.key, this.height = 1});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            context.accent.primary.withValues(alpha: 0.55),
            Colors.white.withValues(alpha: 0.06),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

/// Small frosted pill used for tags/features.
class GlassTag extends StatelessWidget {
  const GlassTag(this.label, {super.key, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SaxifyTheme.radiusXl),
        color: Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 13, color: SaxifyColors.textMuted),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: SaxifyColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
