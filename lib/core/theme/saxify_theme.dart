import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import 'saxify_accents.dart';

/// IfallMusic surfaces.
///
/// Everything sits on **true black** (`#000000`) with Apple-style *liquid
/// glass* panels floating above it. The deeper the black, the more the accent
/// colours pop — exactly like the reference site.
class SaxifyColors {
  const SaxifyColors._();

  // -------------------------------------------------------------- the blacks
  /// Absolute black. Every screen, sheet and button rests on this.
  static const Color background = Color(0xFF000000);

  /// Slightly lifted black used for the bottom bar / sheets.
  static const Color surface = Color(0xFF07070A);

  /// Second level surface (inputs, elevated rows).
  static const Color surfaceAlt = Color(0xFF0D0D12);

  /// Legacy card tones — kept so older widgets still resolve, but the glass
  /// components in `glass.dart` are what the UI actually paints with.
  static const Color card = Color(0xFF101017);
  static const Color cardHover = Color(0xFF16161F);

  // ----------------------------------------------------------------- strokes
  static const Color border = Color(0x1FFFFFFF);
  static const Color borderStrong = Color(0x33FFFFFF);
  static const Color hairline = Color(0x14FFFFFF);

  // ------------------------------------------------------------------- glass
  /// Frosted glass fill (white film at ~5 % — the Apple "ultra thin" look).
  static const Color glass = Color(0x0DFFFFFF);
  static const Color glassStrong = Color(0x17FFFFFF);
  static const Color glassHighlight = Color(0x26FFFFFF);

  // ------------------------------------------------------------------- text
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB8FFFFFF);
  static const Color textMuted = Color(0x8AFFFFFF);
  static const Color textFaint = Color(0x5CFFFFFF);
  static const Color success = Color(0xFF34D399);
  static const Color danger = Color(0xFFFF6B6B);
}

/// Blur strengths used by the glass components.
class GlassBlur {
  const GlassBlur._();

  static const double thin = 12;
  static const double regular = 22;
  static const double thick = 34;

  static ImageFilter get thinFilter =>
      ImageFilter.blur(sigmaX: thin, sigmaY: thin);
  static ImageFilter get regularFilter =>
      ImageFilter.blur(sigmaX: regular, sigmaY: regular);
  static ImageFilter get thickFilter =>
      ImageFilter.blur(sigmaX: thick, sigmaY: thick);
}

/// Builds the whole [ThemeData] for a given accent.
class SaxifyTheme {
  const SaxifyTheme._();

  static const double radiusSm = 12;
  static const double radiusMd = 18;
  static const double radiusLg = 26;
  static const double radiusXl = 34;

  /// Apple-leaning type ramp. Inter is the closest widely available match to
  /// SF Pro; the fallback chain keeps iOS/macOS on the real system font.
  static TextStyle appleFont({
    required double size,
    FontWeight weight = FontWeight.w500,
    double? height,
    double? letterSpacing,
    Color? color,
  }) {
    final TextStyle base = GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: letterSpacing,
      color: color,
    );
    return base.copyWith(
      fontFamilyFallback: const <String>[
        'SF Pro Display',
        'SF Pro Text',
        '-apple-system',
        'Helvetica Neue',
        'Roboto',
      ],
    );
  }


  /// Light-theme counterparts of [SaxifyColors], used only by [build] when the
  /// listener has asked for the light look.
  static const _LightColors _light = _LightColors();

  static ThemeData build(
    SaxifyAccent accent, {
    SaxifyAccent? qualityAccent,
    Brightness brightness = Brightness.dark,
  }) {
    final bool dark = brightness == Brightness.dark;
    final Color pageBg = dark ? SaxifyColors.background : _light.background;
    final Color sheetBg = dark ? SaxifyColors.surface : _light.surface;
    final Color elevatedBg = dark ? SaxifyColors.surfaceAlt : _light.surfaceAlt;
    final Color cardBg = dark ? SaxifyColors.card : _light.card;
    final Color cardHoverBg = dark ? SaxifyColors.cardHover : _light.cardHover;
    final Color ink = dark ? SaxifyColors.textPrimary : _light.textPrimary;
    final Color inkSoft = dark ? SaxifyColors.textSecondary : _light.textSecondary;
    final Color inkMuted = dark ? SaxifyColors.textMuted : _light.textMuted;
    final Color inkFaint = dark ? SaxifyColors.textFaint : _light.textFaint;
    final Color hairline = dark ? SaxifyColors.hairline : _light.hairline;
    final Color stroke = dark ? SaxifyColors.border : _light.border;
    final Color film = dark ? SaxifyColors.glass : _light.glass;
    final Color filmStrong =
        dark ? SaxifyColors.glassHighlight : _light.glassHighlight;

    final TextTheme base = GoogleFonts.interTextTheme(
      ThemeData(brightness: brightness).textTheme,
    );

    final TextTheme textTheme = base
        .copyWith(
          displayLarge:
              base.displayLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.4),
          displayMedium:
              base.displayMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -1.1),
          displaySmall:
              base.displaySmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.8),
          headlineLarge:
              base.headlineLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.7),
          headlineMedium:
              base.headlineMedium?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
          headlineSmall:
              base.headlineSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.4),
          titleLarge:
              base.titleLarge?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
          titleMedium:
              base.titleMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.2),
          titleSmall:
              base.titleSmall?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
          bodyLarge: base.bodyLarge?.copyWith(height: 1.4),
          bodyMedium: base.bodyMedium?.copyWith(height: 1.38),
          bodySmall: base.bodySmall?.copyWith(height: 1.32),
          labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.1),
          labelMedium: base.labelMedium?.copyWith(fontWeight: FontWeight.w600, letterSpacing: 0.2),
        )
        .apply(
          bodyColor: ink,
          displayColor: ink,
        )
        .copyWith(
          bodyLarge: (base.bodyLarge ?? const TextStyle()).copyWith(
            fontFamilyFallback: const <String>[
              'SF Pro Text',
              '-apple-system',
              'Helvetica Neue',
              'Roboto',
            ],
          ),
        );

    final ColorScheme scheme = (dark
            ? const ColorScheme.dark()
            : const ColorScheme.light())
        .copyWith(
      primary: accent.primary,
      onPrimary: accent.onAccent,
      primaryContainer: accent.secondary,
      onPrimaryContainer: Colors.white,
      secondary: accent.secondary,
      onSecondary: Colors.white,
      tertiary: accent.secondary,
      surface: pageBg,
      onSurface: ink,
      surfaceContainerLowest: pageBg,
      surfaceContainerLow: sheetBg,
      surfaceContainer: elevatedBg,
      surfaceContainerHigh: cardBg,
      surfaceContainerHighest: cardHoverBg,
      onSurfaceVariant: inkSoft,
      outline: stroke,
      outlineVariant: hairline,
      error: SaxifyColors.danger,
      brightness: brightness,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: pageBg,
      canvasColor: pageBg,
      primaryColor: accent.primary,
      dividerColor: hairline,
      splashFactory: InkSparkle.splashFactory,
      splashColor: accent.primary.withValues(alpha: 0.08),
      highlightColor: accent.primary.withValues(alpha: 0.04),
      textTheme: textTheme,
      iconTheme: IconThemeData(color: inkSoft),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle:
            dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          fontSize: 21,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
          color: ink,
          fontFamily: GoogleFonts.inter().fontFamily,
        ),
      ),
      cardTheme: CardThemeData(
        color: film,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: stroke),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: hairline,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: film,
        hintStyle: TextStyle(color: inkFaint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          borderSide: BorderSide(color: stroke),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusXl),
          borderSide: BorderSide(color: accent.primary.withValues(alpha: 0.85), width: 1.4),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: film,
        selectedColor: accent.primary.withValues(alpha: 0.30),
        side: BorderSide(color: stroke),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        labelStyle: TextStyle(
          color: ink,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusXl),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent.primary,
        inactiveTrackColor: filmStrong,
        thumbColor: dark ? Colors.white : accent.primary,
        overlayColor: accent.primary.withValues(alpha: 0.18),
        trackHeight: 5,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: accent.primary,
        linearTrackColor: filmStrong,
        circularTrackColor: filmStrong,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: sheetBg,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
          side: BorderSide(color: stroke),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: dark ? const Color(0xF21A1A22) : const Color(0xF2FFFFFF),
        contentTextStyle: TextStyle(color: ink),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? Colors.white
              : inkMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> states) => states.contains(WidgetState.selected)
              ? accent.primary
              : filmStrong,
        ),
        trackOutlineColor: WidgetStatePropertyAll<Color>(stroke),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        indicatorColor: accent.primary.withValues(alpha: 0.20),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        height: 68,
        elevation: 0,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (Set<WidgetState> states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected)
                ? accent.primary
                : inkMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 11,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? accent.primary : inkMuted,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent.primary,
        unselectedLabelColor: inkMuted,
        indicatorColor: accent.primary,
        dividerColor: Colors.transparent,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w500),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: inkSoft,
        textColor: ink,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: inkSoft,
          highlightColor: (dark ? Colors.white : Colors.black).withValues(alpha: 0.06),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: accent.primary,
          foregroundColor: accent.onAccent,
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXl)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: accent.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          side: BorderSide(color: dark ? SaxifyColors.borderStrong : stroke),
          minimumSize: const Size(0, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusXl)),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        SaxifyAccentExtension(accent, qualityAccent: qualityAccent),
      ],
    );
  }
}

/// Light-theme counterparts of [SaxifyColors].
///
/// Kept private to [SaxifyTheme] so nothing outside the theme reaches for a
/// hard-coded light value; widgets ask [IfallPalette.of] instead.
class _LightColors {
  const _LightColors();

  final Color background = const Color(0xFFFFFFFF);
  final Color surface = const Color(0xFFF7F7F9);
  final Color surfaceAlt = const Color(0xFFF2F2F7);
  final Color card = const Color(0xFFFFFFFF);
  final Color cardHover = const Color(0xFFEFEFF4);
  final Color textPrimary = const Color(0xFF000000);
  final Color textSecondary = const Color(0xCC000000);
  final Color textMuted = const Color(0x99000000);
  final Color textFaint = const Color(0x66000000);
  final Color hairline = const Color(0x1A000000);
  final Color border = const Color(0x26000000);
  final Color glass = const Color(0x0A000000);
  final Color glassHighlight = const Color(0x14000000);
}
