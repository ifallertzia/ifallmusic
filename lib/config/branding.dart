/// Single source of truth for the IfallMusic identity.
///
/// The app was previously branded Saxify. Every user-visible name, folder and
/// tagline now comes from here, so **IfallMusic wins everywhere** — the shell,
/// the notification, the download folder, the store label and the About card.
class IfallBranding {
  const IfallBranding._();

  static const double logoWidth = 512;
  static const double logoHeight = 512;
  static const String logoFormat = 'PNG (from supplied JPG artwork)';
  static const String logoAsset = 'assets/images/saxify_logo.png';
  static const String splashAsset = 'assets/images/saxify_splash.png';
  static const double splashLogoSize = 300;

  /// The name that wins — everywhere.
  static const String appName = 'IfallMusic';

  /// Kept for compatibility with older code paths that still ask for it.
  static const String legacyAppName = 'IfallMusic';

  static const String downloaderName = 'IfallMusic Downloader';
  static const String downloadFolderName = 'IfallMusic';
  static const String fileSuffix = '_ifallmusic';
  static const String author = 'Siddharth ifallertzia';
  static const String contactEmail = 'dastaanenajdik@gmail.com';
  /// Kept in step with pubspec.yaml by `scripts/sync_version.sh`, which CI runs
  /// on every version bump. Do not edit these three by hand.
  static const String versionLabel = '2.5.0';
  static const String buildLabel = '15';
  static const String tagline = 'Stream beyond limits';
  static const String userAgent = 'IfallMusic/2.5.0 (Flutter)';

  /// `2.4.0 (build 13)` — the string that tells one release from another.
  /// The build number is what Android compares when deciding whether an APK is
  /// an update, so it is shown to the user as well.
  static const String fullVersionLabel = '$versionLabel (build $buildLabel)';
  static const String websiteUrl = 'https://sidify.vercel.app';
  static const String latestDownloadMessage =
      'Check here for the latest app download link: sidify.vercel.app';
  static const String packageName = 'com.saxify.app';
}
