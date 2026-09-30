import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/services/settings_service.dart';
import 'package:ifallmusic/core/theme/saxify_accents.dart';
import 'package:ifallmusic/core/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The app now ships the Spotify Green (neon-green) look as its default, and
/// that accent is painted across the whole app rather than only on the
/// song-quality label.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a fresh install wears Spotify Green across the whole app', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsService settings = SettingsService(prefs);
    final ThemeController theme = ThemeController(settings);

    expect(settings.accentId, 'neon-green');
    expect(settings.accentAcrossApp, isTrue);
    expect(settings.autoRotateTheme, isFalse);
    expect(theme.accent.id, SaxifyAccents.spotifyGreen.id);
    expect(theme.accent.primary, const Color(0xFF1ED760));
    theme.dispose();
  });

  test('an older install migrates onto the green default exactly once', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsService.kAccentId: 'violet-pulse',
      SettingsService.kAccentAcrossApp: false,
      SettingsService.kAutoRotateTheme: true,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsService settings = SettingsService(prefs);

    await settings.applyGreenDefault();
    expect(settings.accentId, 'neon-green');
    expect(settings.accentAcrossApp, isTrue);
    expect(settings.autoRotateTheme, isFalse);

    // The listener's own choice wins after the one-shot migration.
    await settings.setAccentId('crimson');
    await settings.setAccentAcrossApp(false);
    await settings.applyGreenDefault();
    expect(settings.accentId, 'crimson');
    expect(settings.accentAcrossApp, isFalse);
  });

  test('opting out of colour still works, and a pinned colour still wins', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsService.kAccentId: 'crimson',
      SettingsService.kAccentAcrossApp: false,
      SettingsService.kAutoRotateTheme: false,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsService settings = SettingsService(prefs);
    final ThemeController theme = ThemeController(settings);

    expect(theme.accent.id, SaxifyAccents.graphite.id);
    expect(theme.paletteAccent.id, 'crimson');
    theme.dispose();
  });
}
