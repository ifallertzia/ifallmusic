import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/services/settings_service.dart';
import 'package:ifallmusic/core/theme/saxify_accents.dart';
import 'package:ifallmusic/core/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('neutral appearance is the default for a standard palette color', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsService.kAccentId: 'electric-blue',
      SettingsService.kAutoRotateTheme: false,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsService settings = SettingsService(prefs);
    final ThemeController theme = ThemeController(settings);

    expect(theme.accent.id, SaxifyAccents.graphite.id);
    expect(theme.paletteAccent.id, 'electric-blue');

    final int blueIndex = SaxifyAccents.indexOfId('electric-blue');
    await theme.cycle();
    final String nextPaletteId =
        SaxifyAccents.all[(blueIndex + 1) % SaxifyAccents.all.length].id;
    expect(theme.paletteAccent.id, nextPaletteId);
    expect(theme.accent.id, SaxifyAccents.graphite.id);

    await theme.setAccentAcrossApp(true);
    expect(theme.accent.id, nextPaletteId);
    await theme.setAccentAcrossApp(false);
    expect(theme.paletteAccent.id, nextPaletteId);
    theme.dispose();
  });

  test('an existing custom RGB theme survives the new appearance setting', () async {
    const Color primary = Color(0xFFFF5A36);
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsService.kAccentId: SaxifyAccent.customAccentId,
      SettingsService.kCustomAccentPrimary: 0xFFFF5A36,
      SettingsService.kCustomAccentSecondary: 0xFF8A1B55,
      SettingsService.kAutoRotateTheme: false,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsService settings = SettingsService(prefs);
    final ThemeController theme = ThemeController(settings);

    expect(theme.accentAcrossApp, isTrue);
    expect(theme.accent.primary, primary);
    await theme.setAccentAcrossApp(false);
    expect(theme.accent.id, SaxifyAccents.graphite.id);
    expect(theme.paletteAccent.primary, primary);
    expect(prefs.getInt(SettingsService.kCustomAccentPrimary), 0xFFFF5A36);
    expect(prefs.getInt(SettingsService.kCustomAccentSecondary), 0xFF8A1B55);
    theme.dispose();
  });
}
