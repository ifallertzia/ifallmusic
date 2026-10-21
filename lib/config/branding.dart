/// Single source of truth for the Sidify identity.
///
/// The app is **Sidify** everywhere a person can see it — the launcher label,
/// the shell, the notification, the About card and every heading in the app.
///
/// Two things deliberately do **not** change with the name, because changing
/// them would break updates for everyone who already has the app installed:
///
///   * the Android package id ([packageName] / `applicationId`) — Android
///     only accepts an update over an existing install when the package id
///     *and* the signing certificate both match, and
///   * the on-device storage layout ([downloadFolderName], [fileSuffix] and
///     every shared-preferences key) — renaming those would orphan the
///     library, settings and downloads people already have.
///
/// So: Sidify on the surface, the same app underneath.
class SidifyBranding {
  const SidifyBranding._();

  static const double logoWidth = 1024;
  static const double logoHeight = 1024;
  static const String logoFormat = 'PNG (uploaded Spotify + YouTube Music mark)';

  /// The combined Spotify + YouTube Music mark cropped from the latest upload.
  /// It is used at larger sizes, including the welcome screen and About card.
  static const String logoAsset = 'assets/images/sidify_logo.png';

  /// The uploaded combined mark, used in the home header, empty states and
  /// the liked-songs sleeve fallback.
  static const String markAsset = 'assets/images/sidify_mark.png';

  /// Kept for the artwork fallback in the engine: the mark, never a letter.
  static const String splashAsset = markAsset;

  /// The Liked Songs sleeve keeps using the mark.
  static const String likedSongsAsset = markAsset;
  static const double splashLogoSize = 300;

  /// The name that wins — everywhere a person can see it.
  static const String appName = 'Sidify';

  /// Kept for compatibility with older code paths that still ask for it.
  static const String legacyAppName = appName;

  static const String downloaderName = 'Sidify Downloader';

  /// INTERNAL storage folder. Not a display name: existing installs already
  /// keep their offline songs under this folder, so it stays exactly as it
  /// was or every download would vanish on update.
  static const String downloadFolderName = 'IfallMusic';

  /// INTERNAL file suffix for downloaded files. Same reasoning as above.
  static const String fileSuffix = '_ifallmusic';
  static const String author = 'Siddharth';
  static const String contactEmail = 'dastaanenajdik@gmail.com';

  /// Kept in step with pubspec.yaml by `scripts/sync_version.sh`, which CI runs
  /// on every version bump. Do not edit these three by hand.
  static const String versionLabel = '2.10.0';
  static const String buildLabel = '44';
  static const String tagline = 'Stream beyond limits';
  static const String userAgent = 'Sidify/2.10.0 (Flutter)';

  /// `versionLabel (build buildLabel)` — the string that tells releases apart.
  /// The build number is what Android compares when deciding whether an APK is
  /// an update, so it is shown to the user as well.
  static const String fullVersionLabel = '$versionLabel (build $buildLabel)';
  static const String websiteUrl = 'https://sidify.vercel.app';
  static const String latestDownloadMessage =
      'Check here for the latest app download link: sidify.vercel.app';

  /// The Android package id. MUST match the installed app's package id or
  /// Android refuses the update — it is not a branding string.
  static const String packageName = 'com.ifallmusic.app';
}

