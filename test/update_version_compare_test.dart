import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/services/update_service.dart';

/// Guards the rule that keeps updates installable: an update is offered when the
/// semantic version rises, OR when the version is unchanged and the build number
/// (Android `versionCode`, pubspec's `+N`) rises.
///
/// A flat build number is why Android rejects an APK with
/// "package conflicts with an existing package", so this comparison must never
/// regress.
void main() {
  group('UpdateService.isNewer (semantic version)', () {
    test('detects a higher version', () {
      expect(UpdateService.isNewer('2.3.6', '2.4.0'), isTrue);
      expect(UpdateService.isNewer('2.3.6', '2.3.7'), isTrue);
      expect(UpdateService.isNewer('2.3.6', '3.0.0'), isTrue);
    });

    test('rejects an equal or lower version', () {
      expect(UpdateService.isNewer('2.4.0', '2.4.0'), isFalse);
      expect(UpdateService.isNewer('2.4.0', '2.3.6'), isFalse);
      expect(UpdateService.isNewer('3.0.0', '2.9.9'), isFalse);
    });

    test('compares numerically, not lexicographically', () {
      // String compare would wrongly say '2.4.10' < '2.4.9'.
      expect(UpdateService.isNewer('2.4.9', '2.4.10'), isTrue);
      expect(UpdateService.isNewer('2.4.10', '2.4.9'), isFalse);
      expect(UpdateService.isNewer('2.9.0', '2.11.0'), isTrue);
    });

    test('tolerates a leading v, a build suffix and short versions', () {
      expect(UpdateService.isNewer('2.3.6+12', '2.4.0+13'), isTrue);
      expect(UpdateService.isNewer('2.4', '2.4.1'), isTrue);
      expect(UpdateService.isNewer('2.4.0', '2.4'), isFalse);
    });

    test('treats unparsable components as zero instead of throwing', () {
      expect(UpdateService.isNewer('2.4.0', '2.4.beta'), isFalse);
      expect(UpdateService.isNewer('', '0.0.1'), isTrue);
    });
  });

  group('UpdateService.isNewerBuild (version, then build number)', () {
    test('a higher version wins regardless of build number', () {
      expect(UpdateService.isNewerBuild('2.3.6', 12, '2.4.0', 13), isTrue);
      // Older version with a much larger build number is still not an update.
      expect(UpdateService.isNewerBuild('2.4.0', 13, '2.3.6', 99), isFalse);
    });

    test('same version, higher build number is an update', () {
      expect(UpdateService.isNewerBuild('2.4.0', 13, '2.4.0', 14), isTrue);
      expect(UpdateService.isNewerBuild('2.4.0', 13, '2.4.0', 130), isTrue);
    });

    test('same version, equal or lower build number is not an update', () {
      expect(UpdateService.isNewerBuild('2.4.0', 13, '2.4.0', 13), isFalse);
      expect(UpdateService.isNewerBuild('2.4.0', 14, '2.4.0', 13), isFalse);
    });

    test('an unknown build number falls back to the version alone', () {
      expect(UpdateService.isNewerBuild('2.4.0', 13, '2.4.0', null), isFalse);
      expect(UpdateService.isNewerBuild('2.3.6', 12, '2.4.0', null), isTrue);
    });
  });

  group('UpdateInfo', () {
    UpdateInfo info({
      String current = '2.3.6',
      int currentBuild = 12,
      String latest = '2.4.0',
      int? latestBuild,
      String? apkUrl = 'https://example.test/app-release.apk',
    }) {
      return UpdateInfo(
        currentVersion: current,
        currentBuildNumber: currentBuild,
        latestVersion: latest,
        latestBuildNumber: latestBuild,
        apkUrl: apkUrl,
      );
    }

    test('hasUpdate follows the version-then-build rule', () {
      expect(info(latestBuild: 13).hasUpdate, isTrue);
      expect(
        info(current: '2.4.0', currentBuild: 13, latest: '2.4.0', latestBuild: 13)
            .hasUpdate,
        isFalse,
      );
      expect(
        info(current: '2.4.0', currentBuild: 13, latest: '2.4.0', latestBuild: 14)
            .hasUpdate,
        isTrue,
      );
    });

    test('downloadable requires an APK asset URL', () {
      expect(info().downloadable, isTrue);
      expect(info(apkUrl: null).downloadable, isFalse);
      expect(info(apkUrl: '').downloadable, isFalse);
    });

    test('labels show the build number so a rebuild is visibly different', () {
      final UpdateInfo i = info(latestBuild: 13);
      expect(i.currentLabel, '2.3.6 (build 12)');
      expect(i.latestLabel, '2.4.0 (build 13)');
    });

    test('labels omit the build number when it is unknown', () {
      expect(info(latestBuild: null).latestLabel, '2.4.0');
      expect(info(currentBuild: 0).currentLabel, '2.3.6');
    });

    test('sizeLabel renders megabytes, or nothing when size is unknown', () {
      expect(info().sizeLabel, '');
      expect(
        UpdateInfo(
          currentVersion: '2.3.6',
          latestVersion: '2.4.0',
          sizeBytes: 52428800,
        ).sizeLabel,
        '50.0 MB',
      );
      expect(
        UpdateInfo(
          currentVersion: '2.3.6',
          latestVersion: '2.4.0',
          sizeBytes: 0,
        ).sizeLabel,
        '',
      );
    });
  });
}
