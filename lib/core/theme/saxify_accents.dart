import 'package:flutter/material.dart';

/// One accent from the IfallMusic palette.
///
/// The reference site lets you "paint the colour across the whole app".
/// IfallMusic ships the same idea with a much bigger, deeper palette: 18
/// hand-picked accents (including **Silver**) plus a fully custom accent the
/// listener builds themselves with RGB sliders in Settings.
@immutable
class SaxifyAccent {
  const SaxifyAccent({
    required this.id,
    required this.label,
    required this.primary,
    required this.secondary,
    required this.tint,
    this.isCustom = false,
  });

  /// Stable key used for persistence (never reorder-dependent).
  final String id;

  /// Human readable name shown in Settings.
  final String label;

  /// Gradient start — the main colour of the app.
  final Color primary;

  /// Gradient end — used for depth in gradients and glows.
  final Color secondary;

  /// Soft, low-alpha wash used for card backgrounds / glows.
  final Color tint;

  /// True for the user-made accent.
  final bool isCustom;

  List<Color> get gradientColors => <Color>[primary, secondary];

  LinearGradient get gradient => LinearGradient(
        colors: gradientColors,
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  LinearGradient get horizontalGradient => LinearGradient(
        colors: gradientColors,
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
      );

  /// Fading backdrop used for the hero / player halo.
  LinearGradient get fadeGradient => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          primary.withValues(alpha: 0.32),
          secondary.withValues(alpha: 0.10),
          const Color(0xFF000000).withValues(alpha: 0.0),
        ],
      );

  /// Ink colour that stays readable on top of this accent. Light accents
  /// (Silver, Lime, Gold) get black ink — exactly like Apple Music does.
  Color get onAccent => _isLight(primary) ? Colors.black : Colors.white;

  static bool _isLight(Color c) {
    final double luminance = c.computeLuminance();
    return luminance > 0.45;
  }

  String get primaryHex => _hex(primary);
  String get secondaryHex => _hex(secondary);

  static String _hex(Color c) {
    String two(double v) => (v * 255).round().toRadixString(16).padLeft(2, '0');
    return '#${two(c.r)}${two(c.g)}${two(c.b)}'.toUpperCase();
  }

  SaxifyAccent copyWith({String? label, Color? primary, Color? secondary}) {
    final Color p = primary ?? this.primary;
    return SaxifyAccent(
      id: id,
      label: label ?? this.label,
      primary: p,
      secondary: secondary ?? this.secondary,
      tint: p.withValues(alpha: 0.18),
      isCustom: isCustom,
    );
  }

  /// Builds an accent from the listener's own RGB mix.
  static SaxifyAccent custom(Color primary, Color secondary) => SaxifyAccent(
        id: customAccentId,
        label: 'Your mix',
        primary: primary,
        secondary: secondary,
        tint: primary.withValues(alpha: 0.18),
        isCustom: true,
      );

  static const String customAccentId = 'custom-mix';
}

/// The IfallMusic palette — deep, vivid, made for a black background.
class SaxifyAccents {
  const SaxifyAccents._();

  // --------------------------------------------------------- signature tones
  static const SaxifyAccent violetPulse = SaxifyAccent(
    id: 'violet-pulse',
    label: 'Violet',
    primary: Color(0xFF8B5CF6),
    secondary: Color(0xFF4C1D95),
    tint: Color(0x2E8B5CF6),
  );

  static const SaxifyAccent indigoNight = SaxifyAccent(
    id: 'indigo-night',
    label: 'Indigo',
    primary: Color(0xFF6366F1),
    secondary: Color(0xFF1E1B4B),
    tint: Color(0x2E6366F1),
  );

  static const SaxifyAccent electricBlue = SaxifyAccent(
    id: 'electric-blue',
    label: 'Blue',
    primary: Color(0xFF3B82F6),
    secondary: Color(0xFF1E3A8A),
    tint: Color(0x2E3B82F6),
  );

  static const SaxifyAccent aqua = SaxifyAccent(
    id: 'aqua',
    label: 'Aqua',
    primary: Color(0xFF22D3EE),
    secondary: Color(0xFF0E7490),
    tint: Color(0x2E22D3EE),
  );

  static const SaxifyAccent teal = SaxifyAccent(
    id: 'teal',
    label: 'Teal',
    primary: Color(0xFF14B8A6),
    secondary: Color(0xFF115E59),
    tint: Color(0x2E14B8A6),
  );

  static const SaxifyAccent emerald = SaxifyAccent(
    id: 'emerald',
    label: 'Emerald',
    primary: Color(0xFF10B981),
    secondary: Color(0xFF065F46),
    tint: Color(0x2E10B981),
  );

  static const SaxifyAccent spotifyGreen = SaxifyAccent(
    id: 'neon-green',
    label: 'Neon',
    primary: Color(0xFF1ED760),
    secondary: Color(0xFF14833B),
    tint: Color(0x2E1ED760),
  );

  static const SaxifyAccent lime = SaxifyAccent(
    id: 'lime',
    label: 'Lime',
    primary: Color(0xFFA3E635),
    secondary: Color(0xFF3F6212),
    tint: Color(0x2EA3E635),
  );

  static const SaxifyAccent gold = SaxifyAccent(
    id: 'gold',
    label: 'Gold',
    primary: Color(0xFFFBBF24),
    secondary: Color(0xFFB45309),
    tint: Color(0x2EFBBF24),
  );

  static const SaxifyAccent amber = SaxifyAccent(
    id: 'amber',
    label: 'Amber',
    primary: Color(0xFFF59E0B),
    secondary: Color(0xFF7C2D12),
    tint: Color(0x2EF59E0B),
  );

  static const SaxifyAccent sunset = SaxifyAccent(
    id: 'sunset',
    label: 'Sunset',
    primary: Color(0xFFFB7185),
    secondary: Color(0xFFEA580C),
    tint: Color(0x2EFB7185),
  );

  static const SaxifyAccent crimson = SaxifyAccent(
    id: 'crimson',
    label: 'Crimson',
    primary: Color(0xFFEF4444),
    secondary: Color(0xFF7F1D1D),
    tint: Color(0x2EEF4444),
  );

  static const SaxifyAccent rose = SaxifyAccent(
    id: 'rose',
    label: 'Rose',
    primary: Color(0xFFF43F5E),
    secondary: Color(0xFF881337),
    tint: Color(0x2EF43F5E),
  );

  static const SaxifyAccent pink = SaxifyAccent(
    id: 'pink',
    label: 'Pink',
    primary: Color(0xFFEC4899),
    secondary: Color(0xFF831843),
    tint: Color(0x2EEC4899),
  );

  static const SaxifyAccent magenta = SaxifyAccent(
    id: 'magenta',
    label: 'Magenta',
    primary: Color(0xFFD946EF),
    secondary: Color(0xFF701A75),
    tint: Color(0x2ED946EF),
  );

  static const SaxifyAccent purple = SaxifyAccent(
    id: 'purple',
    label: 'Purple',
    primary: Color(0xFFA855F7),
    secondary: Color(0xFF581C87),
    tint: Color(0x2EA855F7),
  );

  /// Silver — the one the app was missing.
  static const SaxifyAccent silver = SaxifyAccent(
    id: 'silver',
    label: 'Silver',
    primary: Color(0xFFE2E8F0),
    secondary: Color(0xFF94A3B8),
    tint: Color(0x2EE2E8F0),
  );

  static const SaxifyAccent graphite = SaxifyAccent(
    id: 'graphite',
    label: 'Graphite',
    primary: Color(0xFF9AA3B2),
    secondary: Color(0xFF334155),
    tint: Color(0x2E9AA3B2),
  );

  static const List<SaxifyAccent> all = <SaxifyAccent>[
    violetPulse,
    indigoNight,
    electricBlue,
    aqua,
    teal,
    emerald,
    spotifyGreen,
    lime,
    gold,
    amber,
    sunset,
    crimson,
    rose,
    pink,
    magenta,
    purple,
    silver,
    graphite,
  ];

  /// How many of [all] are offered as one-tap swatches in Settings.
  static List<SaxifyAccent> get presets => all;

  static SaxifyAccent byId(String? id, {SaxifyAccent? custom}) {
    if (id == SaxifyAccent.customAccentId && custom != null) return custom;
    for (final SaxifyAccent accent in all) {
      if (accent.id == id) return accent;
    }
    return violetPulse;
  }

  static int indexOfId(String? id) {
    for (int i = 0; i < all.length; i++) {
      if (all[i].id == id) return i;
    }
    // A custom accent (or an unknown id) parks on the first swatch index, the
    // ThemeController keeps the custom colour itself.
    return 0;
  }
}

/// Makes the live accent reachable through `Theme.of(context)` so deep widgets
/// can paint themselves without an extra provider lookup.
@immutable
class SaxifyAccentExtension extends ThemeExtension<SaxifyAccentExtension> {
  const SaxifyAccentExtension(this.accent, {SaxifyAccent? qualityAccent})
    : qualityAccent = qualityAccent ?? accent;

  /// Accent used by the app-wide theme (neutral graphite by default).
  final SaxifyAccent accent;

  /// Current palette/custom colour reserved for song-quality text when the
  /// listener has not enabled coloured UI throughout the app.
  final SaxifyAccent qualityAccent;

  @override
  SaxifyAccentExtension copyWith({
    SaxifyAccent? accent,
    SaxifyAccent? qualityAccent,
  }) => SaxifyAccentExtension(
    accent ?? this.accent,
    qualityAccent: qualityAccent ?? this.qualityAccent,
  );

  @override
  SaxifyAccentExtension lerp(
    covariant ThemeExtension<SaxifyAccentExtension>? other,
    double t,
  ) {
    if (other is! SaxifyAccentExtension) return this;
    SaxifyAccent blend(SaxifyAccent from, SaxifyAccent to) => SaxifyAccent(
      id: t < 0.5 ? from.id : to.id,
      label: t < 0.5 ? from.label : to.label,
      primary: Color.lerp(from.primary, to.primary, t) ?? from.primary,
      secondary: Color.lerp(from.secondary, to.secondary, t) ?? from.secondary,
      tint: Color.lerp(from.tint, to.tint, t) ?? from.tint,
      isCustom: t < 0.5 ? from.isCustom : to.isCustom,
    );
    return SaxifyAccentExtension(
      blend(accent, other.accent),
      qualityAccent: blend(qualityAccent, other.qualityAccent),
    );
  }
}

/// Convenience accessors used across the UI.
extension SaxifyAccentX on BuildContext {
  SaxifyAccent get accent =>
      Theme.of(this).extension<SaxifyAccentExtension>()?.accent ?? SaxifyAccents.violetPulse;

  SaxifyAccent get qualityAccent =>
      Theme.of(this).extension<SaxifyAccentExtension>()?.qualityAccent ?? accent;
}
