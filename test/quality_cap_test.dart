import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('per-network quality maps to a bitrate ceiling', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SettingsService settings =
        SettingsService(await SharedPreferences.getInstance());

    // Defaults: Wi-Fi is 'high' (no ceiling), mobile is 'medium'.
    expect(settings.qualityCapKbps('wifi'), isNull);
    expect(settings.qualityCapKbps('mobile'), 160);
    // An unknown transport must never silently downgrade audio.
    expect(settings.qualityCapKbps('other'), isNull);
    expect(settings.qualityCapKbps('none'), isNull);

    await settings.setQualityWifi('low');
    await settings.setQualityMobile('high');
    expect(settings.qualityCapKbps('wifi'), 96);
    expect(settings.qualityCapKbps('mobile'), isNull);

    await settings.setQualityMobile('medium');
    expect(settings.qualityCapKbps('mobile'), 160);
  });
}
