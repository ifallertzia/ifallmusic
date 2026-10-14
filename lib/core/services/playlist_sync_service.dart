import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../config/backend_config.dart';
import '../../config/branding.dart';
import '../models/playlist.dart';
import '../models/song.dart';

/// Cloud codes for playlists. Failures return null — they never throw into UI.
class PlaylistSyncService {
  const PlaylistSyncService._();

  static const String baseUrl = BackendConfig.playlistBase;

  static Future<String?> shareSinglePlaylist(
    String title,
    List<Map<String, dynamic>> songs, {
    bool copyToClipboard = true,
  }) async {
    try {
      final http.Response res = await http
          .post(
            Uri.parse('$baseUrl/playlist'),
            headers: BackendConfig.jsonHeaders(),
            body: jsonEncode(<String, Object?>{
              'title': title,
              'songs': songs,
              'app': SidifyBranding.appName,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return await _codeFrom(res, copyToClipboard);
    } catch (e) {
      _log('shareSingle: $e');
    }
    return null;
  }

  static Future<String?> shareAllPlaylists(
    List<Map<String, dynamic>> allPlaylists, {
    bool copyToClipboard = true,
    String title = 'IfallMusic library',
  }) async {
    try {
      final http.Response res = await http
          .post(
            Uri.parse('$baseUrl/playlist/all'),
            headers: BackendConfig.jsonHeaders(),
            body: jsonEncode(<String, Object?>{
              'title': title,
              'playlists': allPlaylists,
              'app': SidifyBranding.appName,
            }),
          )
          .timeout(const Duration(seconds: 20));
      return await _codeFrom(res, copyToClipboard);
    } catch (e) {
      _log('shareAll: $e');
    }
    return null;
  }

  static Future<Map<String, dynamic>?> fetchPlaylist(String id) async {
    final String code = id.trim();
    if (code.isEmpty) return null;
    try {
      final http.Response res = await http
          .get(
            Uri.parse('$baseUrl/playlist/$code'),
            headers: BackendConfig.jsonHeaders(),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final Object? decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return decoded.cast<String, dynamic>();
      }
      _log('fetch ${res.statusCode}');
    } catch (e) {
      _log('fetch: $e');
    }
    return null;
  }

  /// Bulk restore. The live backend may not have this route yet — callers
  /// should fall back to [fetchPlaylist].
  static Future<Map<String, dynamic>?> fetchAll(String code) async {
    final String id = code.trim();
    if (id.isEmpty) return null;
    try {
      final http.Response res = await http
          .get(
            Uri.parse('$baseUrl/playlist/all/$id'),
            headers: BackendConfig.jsonHeaders(),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 200) {
        final Object? decoded = jsonDecode(res.body);
        if (decoded is Map) return decoded.cast<String, dynamic>();
      }
    } catch (e) {
      _log('fetchAll: $e');
    }
    return null;
  }

  static List<Playlist> playlistsFromPayload(Map<String, dynamic> data) {
    final Object? many = data['playlists'];
    if (many is List) {
      return many
          .whereType<Map>()
          .map((Map item) => Playlist.fromJson(item.cast<String, dynamic>()))
          .where((Playlist p) => p.songs.isNotEmpty || p.name.isNotEmpty)
          .toList();
    }
    final String title = (data['title'] ?? data['name'] ?? 'Imported playlist').toString();
    final Object? songs = data['songs'];
    if (songs is List) {
      return <Playlist>[
        Playlist(
          id: 'cloud_${data['id'] ?? data['code'] ?? DateTime.now().millisecondsSinceEpoch}',
          name: title,
          songs: songs
              .whereType<Map>()
              .map((Map item) => Song.fromJson(item.cast<String, dynamic>()))
              .where((Song s) => s.id.isNotEmpty)
              .toList(),
        ),
      ];
    }
    return <Playlist>[];
  }

  static Future<String?> _codeFrom(http.Response res, bool copy) async {
    if (res.statusCode != 200 && res.statusCode != 201) {
      _log('status ${res.statusCode} ${res.body}');
      return null;
    }
    final Object? decoded = jsonDecode(res.body);
    if (decoded is! Map) return null;
    final Object? code = decoded['id'] ?? decoded['code'];
    if (code == null) return null;
    final String text = code.toString();
    if (copy) {
      await Clipboard.setData(ClipboardData(text: text));
    }
    return text;
  }

  static void _log(String message) => debugPrint('[IfallMusic][Sync] $message');
}
