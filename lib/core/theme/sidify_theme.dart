import 'package:flutter/material.dart';

/// The Sidify design tokens, ported from the web app's design system
/// (`globals.css` in Sidify-V2): a quiet, Apple-Music-like system — black
/// page, frosted glass chrome, white as the primary accent (selected chips
/// are white with black text) and one red reserved for the brand and for
/// "now playing".
///
/// Widgets read tokens through `context.sidify`, e.g.
/// `Text('Hi', style: TextStyle(color: context.sidify.text2))`.
@immutable
class SidifyTokens extends ThemeExtension<SidifyTokens> {
  const SidifyTokens({
    required this.bg,
    required this.surface,
    required this.raised,
    required this.raised2,
    required this.glass,
    required this.bar,
    required this.edge,
    required this.divider,
    required this.hairline,
    required this.fill,
    required this.fill2,
    required this.fill3,
    required this.text,
    required this.text2,
    required this.text3,
    required this.primary,
    required this.onPrimary,
    required this.brand,
    required this.playing,
    required this.danger,
    required this.lcd,
    required this.scrim,
    required this.isDark,
  });

  final Color bg;
  final Color surface;
  final Color raised;
  final Color raised2;

  /// Frosted chrome: `rgba(24,24,27,.74)` dark / `rgba(246,246,248,.8)` light.
  final Color glass;

  /// Floating pills: tab bar, mini player, menus.
  final Color bar;
  final Color edge;
  final Color divider;
  final Color hairline;
  final Color fill;
  final Color fill2;
  final Color fill3;
  final Color text;
  final Color text2;
  final Color text3;

  /// White in dark mode, black in light — selected chips, primary buttons.
  final Color primary;
  final Color onPrimary;

  /// The one brand red (#fa2d48), reserved for the logo & "now playing".
  final Color brand;
  final Color playing;
  final Color danger;
  final Color lcd;
  final Color scrim;
  final bool isDark;

  static const SidifyTokens dark = SidifyTokens(
    bg: Color(0xFF000000),
    surface: Color(0xFF0D0D0F),
    raised: Color(0xFF1C1C1E),
    raised2: Color(0xFF2C2C2E),
    glass: Color(0xBD18181B),
    bar: Color(0xB824242A),
    edge: Color(0x1AFFFFFF),
    divider: Color(0xFF2C2C2E),
    hairline: Color(0x14FFFFFF),
    fill: Color(0x12FFFFFF),
    fill2: Color(0x1FFFFFFF),
    fill3: Color(0x2EFFFFFF),
    text: Color(0xFFFFFFFF),
    text2: Color(0xFF8E8E93),
    text3: Color(0xFF636366),
    primary: Color(0xFFFFFFFF),
    onPrimary: Color(0xFF000000),
    brand: Color(0xFFFA2D48),
    playing: Color(0xFFFB4A62),
    danger: Color(0xFFFF453A),
    lcd: Color(0xFF2A2A2E),
    scrim: Color(0xC7000000),
    isDark: true,
  );

  static const SidifyTokens light = SidifyTokens(
    bg: Color(0xFFFFFFFF),
    surface: Color(0xFFF7F7F9),
    raised: Color(0xFFF2F2F7),
    raised2: Color(0xFFE5E5EA),
    glass: Color(0xCCF6F6F8),
    bar: Color(0xD1FAFAFC),
    edge: Color(0x17000000),
    divider: Color(0xFFE5E5EA),
    hairline: Color(0x14000000),
    fill: Color(0x0D000000),
    fill2: Color(0x14000000),
    fill3: Color(0x1F000000),
    text: Color(0xFF000000),
    text2: Color(0xFF6E6E73),
    text3: Color(0xFFAEAEB2),
    primary: Color(0xFF000000),
    onPrimary: Color(0xFFFFFFFF),
    brand: Color(0xFFFA2D48),
    playing: Color(0xFFFA2D48),
    danger: Color(0xFFFF3B30),
    lcd: Color(0xFFECECEF),
    scrim: Color(0x99000000),
    isDark: false,
  );

  static SidifyTokens of(BuildContext context) =>
      Theme.of(context).extension<SidifyTokens>() ??
      (Theme.of(context).brightness == Brightness.dark ? dark : light);

  @override
  SidifyTokens copyWith({
    Color? bg,
    Color? surface,
    Color? raised,
    Color? raised2,
    Color? glass,
    Color? bar,
    Color? edge,
    Color? divider,
    Color? hairline,
    Color? fill,
    Color? fill2,
    Color? fill3,
    Color? text,
    Color? text2,
    Color? text3,
    Color? primary,
    Color? onPrimary,
    Color? brand,
    Color? playing,
    Color? danger,
    Color? lcd,
    Color? scrim,
    bool? isDark,
  }) {
    return SidifyTokens(
      bg: bg ?? this.bg,
      surface: surface ?? this.surface,
      raised: raised ?? this.raised,
      raised2: raised2 ?? this.raised2,
      glass: glass ?? this.glass,
      bar: bar ?? this.bar,
      edge: edge ?? this.edge,
      divider: divider ?? this.divider,
      hairline: hairline ?? this.hairline,
      fill: fill ?? this.fill,
      fill2: fill2 ?? this.fill2,
      fill3: fill3 ?? this.fill3,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      primary: primary ?? this.primary,
      onPrimary: onPrimary ?? this.onPrimary,
      brand: brand ?? this.brand,
      playing: playing ?? this.playing,
      danger: danger ?? this.danger,
      lcd: lcd ?? this.lcd,
      scrim: scrim ?? this.scrim,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  SidifyTokens lerp(ThemeExtension<SidifyTokens>? other, double t) {
    if (other is! SidifyTokens) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return SidifyTokens(
      bg: mix(bg, other.bg),
      surface: mix(surface, other.surface),
      raised: mix(raised, other.raised),
      raised2: mix(raised2, other.raised2),
      glass: mix(glass, other.glass),
      bar: mix(bar, other.bar),
      edge: mix(edge, other.edge),
      divider: mix(divider, other.divider),
      hairline: mix(hairline, other.hairline),
      fill: mix(fill, other.fill),
      fill2: mix(fill2, other.fill2),
      fill3: mix(fill3, other.fill3),
      text: mix(text, other.text),
      text2: mix(text2, other.text2),
      text3: mix(text3, other.text3),
      primary: mix(primary, other.primary),
      onPrimary: mix(onPrimary, other.onPrimary),
      brand: mix(brand, other.brand),
      playing: mix(playing, other.playing),
      danger: mix(danger, other.danger),
      lcd: mix(lcd, other.lcd),
      scrim: mix(scrim, other.scrim),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

/// `context.sidify` — the tokens for the current theme.
extension SidifyContext on BuildContext {
  SidifyTokens get sidify => SidifyTokens.of(this);
}

/// The Sidify type scale (from the web utilities):
/// display 34/800, headline 30/800, section 22/700, title 20/700,
/// titleM 16/600, body 16, bodyS 14, label 12/600, caption 11/600,
/// eyebrow 11/700 uppercase.
abstract final class SidifyText {
  static TextStyle display(Color c) => TextStyle(
        fontSize: 34,
        height: 1.12,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.8,
        color: c,
      );

  static TextStyle headline(Color c) => TextStyle(
        fontSize: 30,
        height: 1.12,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.7,
        color: c,
      );

  static TextStyle section(Color c) => TextStyle(
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: c,
      );

  static TextStyle title(Color c) => TextStyle(
        fontSize: 20,
        height: 1.25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: c,
      );

  static TextStyle titleM(Color c) => TextStyle(
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: c,
      );

  static TextStyle body(Color c) =>
      TextStyle(fontSize: 16, height: 1.4, color: c);

  static TextStyle bodyS(Color c) =>
      TextStyle(fontSize: 14, height: 1.4, color: c);

  static TextStyle label(Color c) => TextStyle(
        fontSize: 12,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: c,
      );

  static TextStyle caption(Color c) => TextStyle(
        fontSize: 11,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.02,
        color: c,
      );

  static TextStyle eyebrow(Color c) => TextStyle(
        fontSize: 11,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.08,
        color: c,
      );
}

/// Builds the app theme for one brightness. The page is pure black (dark)
/// or white (light), exactly like the web app.
abstract final class SidifyTheme {
  static ThemeData build(Brightness brightness) {
    final bool dark = brightness == Brightness.dark;
    final SidifyTokens t = dark ? SidifyTokens.dark : SidifyTokens.light;
    final ColorScheme scheme = ColorScheme.fromSeed(
      seedColor: t.brand,
      brightness: brightness,
    ).copyWith(
      surface: t.bg,
      onSurface: t.text,
      primary: t.primary,
      onPrimary: t.onPrimary,
      error: t.danger,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: t.bg,
      canvasColor: t.bg,
      dividerColor: t.divider,
      splashFactory: InkRipple.splashFactory,
      highlightColor: t.fill,
      textTheme: TextTheme(
        displaySmall: SidifyText.display(t.text),
        headlineMedium: SidifyText.headline(t.text),
        titleLarge: SidifyText.title(t.text),
        titleMedium: SidifyText.titleM(t.text),
        bodyLarge: SidifyText.body(t.text),
        bodyMedium: SidifyText.bodyS(t.text),
        labelMedium: SidifyText.label(t.text2),
      ),
      iconTheme: IconThemeData(color: t.text),
      extensions: <ThemeExtension<dynamic>>[t],
    );
  }

  static ThemeData get dark => build(Brightness.dark);
  static ThemeData get light => build(Brightness.light);
}
