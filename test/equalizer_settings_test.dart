import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('equalizer profile survives service recreation', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsService first = SettingsService(prefs);
    await first.setEqualizerProfile(
      name: 'Night drive',
      levels: <int>[-300, 100, 450],
      enabled: true,
    );

    final SettingsService restored = SettingsService(prefs);
    expect(restored.equalizerProfileName, 'Night drive');
    expect(restored.equalizerLevels, <int>[-300, 100, 450]);
    expect(restored.equalizerEnabled, isTrue);
  });

  test('custom equalizer presets can be saved and replaced by name', () async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsService settings = SettingsService(prefs);

    await settings.saveEqualizerCustomPreset('Warm', <int>[100, 200]);
    await settings.saveEqualizerCustomPreset('warm', <int>[300, 400]);

    expect(settings.equalizerCustomPresets, <Map<String, dynamic>>[
      <String, dynamic>{'name': 'warm', 'levels': <int>[300, 400]},
    ]);
  });
}
