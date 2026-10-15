/// Compile-time distribution flags for F-Droid vs GitHub/sideload builds.
///
/// F-Droid recipe passes:
///   `--dart-define=FDROID=true --dart-define=FLAVOR=fdroid`
///
/// GitHub Actions release APKs omit both defines, so the in-app updater stays
/// enabled there.
class FossBuild {
  const FossBuild._();

  static const String flavor =
      String.fromEnvironment('FLAVOR', defaultValue: '');

  static const bool fdroidDefine =
      bool.fromEnvironment('FDROID', defaultValue: false);

  /// True when this binary is the F-Droid distribution.
  static bool get isFdroid =>
      fdroidDefine || flavor.toLowerCase() == 'fdroid';

  /// GitHub Releases APK updater + install-permission UI.
  static bool get githubUpdaterEnabled => !isFdroid;
}
