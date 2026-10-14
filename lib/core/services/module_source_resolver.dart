import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fallback stream lookup through the listener's own "extra sources".
///
/// BitChord asks pluggable module sources for a track before it gives up;
/// IfallMusic's built-in resolver (Innertube rotation, then the legacy
/// youtube_explode chain) stays exactly as it is and remains the primary
/// engine. This rung only runs after both of those have failed, so a module
/// can rescue a track but can never make resolution worse than it was.
///
/// A source is a plain HTTP endpoint (Settings → Sources). It is asked with
/// `GET <url>?videoId=<id>&id=<id>&q=<artist title>` — or, when the URL
/// contains `{id}` / `{videoId}`, with the id substituted in place — and may
/// answer with any of:
///
///  * JSON `{"url": "https://…"}` (also `streamUrl`, `stream_url`,
///    `audioUrl`, `downloadUrl`, `link`, optionally nested under `data`,
///    or a JSON list whose first entry has one of those keys)
///  * a plain-text body that is itself the stream URL
///
/// Anything else — a timeout, a non-200, an unreadable shape, a non-HTTP
/// URL — is skipped silently and the next source is tried.
class ModuleSourceResolver {
  ModuleSourceResolver({http.Client? client, this.timeout = const Duration(seconds: 6)})
      : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;

  static const List<String> _urlKeys = <String>[
    'url',
    'streamUrl',
    'stream_url',
    'audioUrl',
    'audio_url',
    'downloadUrl',
    'download_url',
    'link',
  ];

  /// Asks each enabled source in order; returns the first usable stream URL.
  Future<String?> resolve({
    required String videoId,
    String title = '',
    String artist = '',
    required List<Map<String, dynamic>> sources,
  }) async {
    for (final Map<String, dynamic> source in sources) {
      if (source['enabled'] == false) continue;
      final String base = (source['url'] ?? '').toString().trim();
      if (base.isEmpty) continue;
      final String? hit = await _ask(base, videoId: videoId, title: title, artist: artist);
      if (hit != null) return hit;
    }
    return null;
  }

  Future<String?> _ask(
    String base, {
    required String videoId,
    required String title,
    required String artist,
  }) async {
    final Uri? uri = _endpoint(base, videoId: videoId, title: title, artist: artist);
    if (uri == null) return null;
    try {
      final http.Response response = await _client
          .get(uri, headers: const <String, String>{'Accept': 'application/json, text/plain'})
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      return extractStreamUrl(response.body);
    } catch (_) {
      // A dead module is a skipped rung, never an error.
      return null;
    }
  }

  Uri? _endpoint(
    String base, {
    required String videoId,
    required String title,
    required String artist,
  }) {
    String expanded = base;
    if (expanded.contains('{id}') || expanded.contains('{videoId}')) {
      expanded = expanded
          .replaceAll('{id}', Uri.encodeComponent(videoId))
          .replaceAll('{videoId}', Uri.encodeComponent(videoId));
      return Uri.tryParse(expanded);
    }
    final Uri? parsed = Uri.tryParse(base);
    if (parsed == null || !parsed.hasScheme) return null;
    final String query = artist.isNotEmpty && title.isNotEmpty
        ? '$artist $title'
        : (title.isNotEmpty ? title : artist);
    return parsed.replace(
      queryParameters: <String, String>{
        ...parsed.queryParameters,
        'videoId': videoId,
        'id': videoId,
        if (query.isNotEmpty) 'q': query,
      },
    );
  }

  /// Pulls a stream URL out of a module's answer, whatever shape it used.
  static String? extractStreamUrl(String body) {
    final String trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    if (_isHttpUrl(trimmed)) return trimmed;
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
    return _fromJson(decoded, depth: 0);
  }

  static String? _fromJson(Object? node, {required int depth}) {
    if (depth > 3 || node == null) return null;
    if (node is String) return _isHttpUrl(node.trim()) ? node.trim() : null;
    if (node is List) {
      for (final Object? item in node) {
        final String? hit = _fromJson(item, depth: depth + 1);
        if (hit != null) return hit;
      }
      return null;
    }
    if (node is Map) {
      for (final String key in _urlKeys) {
        final String? hit = _fromJson(node[key], depth: depth + 1);
        if (hit != null) return hit;
      }
      return _fromJson(node['data'], depth: depth + 1);
    }
    return null;
  }

  static bool _isHttpUrl(String value) {
    final Uri? uri = Uri.tryParse(value);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }
}
