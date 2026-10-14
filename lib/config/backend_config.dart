import '../config/branding.dart';

/// Every remote URL the app talks to, outside the music engine.
///
/// The YouTube search / stream resolver is intentionally NOT configured here.
/// It stays inside [YoutubeService] and [PlaybackService]. **Downloads are
/// 100% on-device** — there is no downloader backend any more.
class BackendConfig {
  const BackendConfig._();

  /// Playlist share / restore. Confirmed in the v2 brief.
  static const String playlistBase =
      'https://saxifyappbackend-for-playlist.onrender.com';

  static const String clientHeader = 'X-IfallMusic-Client';
  static const String clientValue = 'flutter';

  static const Duration connectTimeout = Duration(seconds: 20);
  static const Duration coldStartTimeout = Duration(seconds: 45);
  static const int maxRetries = 2;

  static Map<String, String> jsonHeaders({String? userAgent}) =>
      <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        clientHeader: clientValue,
        'User-Agent': userAgent ?? SidifyBranding.userAgent,
      };

  static Map<String, String> downloadHeaders({String? userAgent}) =>
      <String, String>{
        'Accept': '*/*',
        clientHeader: clientValue,
        'User-Agent': userAgent ?? SidifyBranding.userAgent,
      };
}
