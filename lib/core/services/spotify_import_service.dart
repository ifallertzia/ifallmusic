import 'dart:convert';

import 'package:http/http.dart' as http;

/// Reads a **public** Spotify playlist without any account or API key.
///
/// Spotify's embed page (`open.spotify.com/embed/playlist/<id>`) ships the
/// playlist's track list as JSON inside the page, which is enough to rebuild
/// the playlist locally: every title/artist pair is matched against what
/// IfallMusic can actually play by the caller. Private playlists, albums and
/// anything the embed page will not render answer with no tracks, and the
/// import reports that instead of guessing.
class SpotifyImportService {
  SpotifyImportService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// The playlist id inside any Spotify playlist link, or `null`.
  static String? playlistId(String link) {
    final String value = link.trim();
    final RegExpMatch? uri = RegExp(r'spotify:playlist:([A-Za-z0-9]+)').firstMatch(value);
    if (uri != null) return uri.group(1);
    final RegExpMatch? url =
        RegExp(r'open\.spotify\.com/(?:embed/)?playlist/([A-Za-z0-9]+)').firstMatch(value);
    return url?.group(1);
  }

  /// Fetches the playlist's name and tracks; `null` when the link is not a
  /// readable public playlist.
  Future<({String name, List<({String title, String artist})> tracks})?> fetchPlaylist(
    String link,
  ) async {
    final String? id = playlistId(link);
    if (id == null) return null;
    try {
      final http.Response response = await _client
          .get(
            Uri.parse('https://open.spotify.com/embed/playlist/$id'),
            headers: const <String, String>{
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/126 Mobile Safari/537.36',
            },
          )
          .timeout(const Duration(seconds: 12));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return parseEmbedPage(response.body);
    } catch (_) {
      return null;
    }
  }

  /// Parses the embed page's embedded JSON. Pure, so it is unit-testable
  /// without a network.
  static ({String name, List<({String title, String artist})> tracks})? parseEmbedPage(
    String html,
  ) {
    final int listAt = html.indexOf('"trackList"');
    if (listAt < 0) return null;

    String name = 'Spotify playlist';
    final RegExpMatch? titleTag =
        RegExp(r'<title>([^<]+)</title>').firstMatch(html);
    if (titleTag != null) {
      final String raw = titleTag.group(1)!.trim();
      // "Some Mix - playlist by someone | Spotify" -> "Some Mix"
      final String cleaned = raw.split('|').first.split(' - playlist').first.trim();
      if (cleaned.isNotEmpty) name = cleaned;
    }

    final List<({String title, String artist})> tracks =
        <({String title, String artist})>[];
    final RegExp pair = RegExp(
      r'"title"\s*:\s*"((?:[^"\\]|\\.)*)"\s*,\s*"subtitle"\s*:\s*"((?:[^"\\]|\\.)*)"',
    );
    for (final RegExpMatch match in pair.allMatches(html.substring(listAt))) {
      final String title = _unescape(match.group(1)!);
      final String artist = _unescape(match.group(2)!);
      if (title.isEmpty) continue;
      tracks.add((title: title, artist: artist));
      if (tracks.length >= 200) break;
    }
    if (tracks.isEmpty) return null;
    return (name: name, tracks: tracks);
  }

  static String _unescape(String raw) {
    try {
      final Object? decoded = jsonDecode('"$raw"');
      return decoded is String ? decoded.trim() : raw.trim();
    } catch (_) {
      return raw.replaceAll(r'\"', '"').trim();
    }
  }
}
