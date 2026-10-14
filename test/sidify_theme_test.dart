import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/services/settings_service.dart';
import 'package:ifallmusic/core/theme/sidify_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Sidify tokens', () {
    test('dark is the site look: black page, white primary, brand red', () {
      const SidifyTokens t = SidifyTokens.dark;
      expect(t.bg, const Color(0xFF000000));
      expect(t.primary, const Color(0xFFFFFFFF));
      expect(t.onPrimary, const Color(0xFF000000));
      expect(t.brand, const Color(0xFFFA2D48));
      expect(t.danger, const Color(0xFFFF453A));
    });

    test('light mirrors: white page, black primary', () {
      const SidifyTokens t = SidifyTokens.light;
      expect(t.bg, const Color(0xFFFFFFFF));
      expect(t.primary, const Color(0xFF000000));
      expect(t.onPrimary, const Color(0xFFFFFFFF));
    });

    test('theme carries the tokens as an extension', () {
      final ThemeData dark = SidifyTheme.build(Brightness.dark);
      expect(dark.extension<SidifyTokens>(), SidifyTokens.dark);
      expect(dark.scaffoldBackgroundColor, const Color(0xFF000000));
      final ThemeData light = SidifyTheme.build(Brightness.light);
      expect(light.extension<SidifyTokens>(), SidifyTokens.light);
    });
  });

  group('settings theme mode', () {
    test('dark is the default and mapping round-trips', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final SettingsService settings = SettingsService(prefs);
      expect(settings.themeMode, ThemeMode.dark);
      await settings.setThemeMode(ThemeMode.light);
      expect(settings.themeMode, ThemeMode.light);
      expect(settings.themeModeRaw, 'light');
      await settings.setThemeMode(ThemeMode.system);
      expect(settings.themeMode, ThemeMode.system);
      await settings.setThemeMode(ThemeMode.dark);
      expect(settings.themeMode, ThemeMode.dark);
    });
  });

  group('sidify UI keys', () {
    test('library layout and dock prefs persist', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final SettingsService settings = SettingsService(prefs);
      expect(settings.libraryLayout, 'grid');
      await settings.setLibraryLayout('list');
      expect(settings.libraryLayout, 'list');
      await settings.setPinnedPlaylists(<String>['p1', 'p2']);
      expect(settings.pinnedPlaylists, <String>['p1', 'p2']);
    });
  });
}
