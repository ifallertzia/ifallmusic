import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/song.dart';
import 'native_bridge.dart';

class LocalAlbum {
  const LocalAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.artworkUri,
    required this.songs,
  });

  final String id;
  final String title;
  final String artist;
  final String artworkUri;
  final List<Song> songs;
}

class LocalArtist {
  const LocalArtist({
    required this.id,
    required this.name,
    required this.songs,
  });

  final String id;
  final String name;
  final List<Song> songs;
}

class LocalMusicService extends ChangeNotifier {
  LocalMusicService(this._prefs) {
    _loadCached();
  }

  static const String _cacheKey = 'saxify.local_music.cache.v1';

  final SharedPreferences _prefs;
  final List<Song> _songs = <Song>[];
  bool _scanning = false;
  String? _lastError;

  List<Song> get songs => List<Song>.unmodifiable(_songs);

  /// Lowercase search text per song, built once and reused. Searching used to
  /// lowercase every title/artist/album on every keystroke, which is thousands
  /// of string allocations per frame on a big library.
  final Map<String, String> _haystacks = <String, String>{};

  String _haystack(Song song) => _haystacks.putIfAbsent(
    song.id,
    () =>
        '${song.title}\n${song.artist}\n${song.album ?? ''}'.toLowerCase(),
  );

  /// Last query and its rows, so a rebuild with the same text is free.
  String _searchKey = '';
  List<Song> _searchHits = <Song>[];

  bool get scanning => _scanning;
  String? get lastError => _lastError;
  bool get hasScanned => _prefs.containsKey(_cacheKey);

  List<LocalAlbum> get albums {
    final Map<String, List<Song>> grouped = <String, List<Song>>{};
    for (final Song song in _songs) {
      grouped.putIfAbsent(song.albumId ?? 'unknown', () => <Song>[]).add(song);
    }
    final List<LocalAlbum> out = grouped.entries.map((MapEntry<String, List<Song>> e) {
      final Song first = e.value.first;
      return LocalAlbum(
        id: e.key,
        title: first.album ?? 'Unknown album',
        artist: first.artist,
        artworkUri: first.thumbnailUrl,
        songs: List<Song>.unmodifiable(e.value),
      );
    }).toList();
    out.sort((LocalAlbum a, LocalAlbum b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return out;
  }

  List<LocalArtist> get artists {
    final Map<String, List<Song>> grouped = <String, List<Song>>{};
    for (final Song song in _songs) {
      grouped.putIfAbsent(song.artistId ?? song.artist, () => <Song>[]).add(song);
    }
    final List<LocalArtist> out = grouped.entries.map((MapEntry<String, List<Song>> e) {
      return LocalArtist(id: e.key, name: e.value.first.artist, songs: List<Song>.unmodifiable(e.value));
    }).toList();
    out.sort((LocalArtist a, LocalArtist b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  List<Song> search(String query, {int limit = 8}) {
    final String q = query.trim().toLowerCase();
    if (q.isEmpty) return <Song>[];
    if (q != _searchKey) {
      _searchKey = q;
      _searchHits = _songs
          .where((Song song) => _haystack(song).contains(q))
          .take(limit)
          .toList();
    }
    // Fresh list, same contract the old implementation gave callers.
    return List<Song>.of(_searchHits);
  }

  /// Drops memoised search state after the on-device library changes.
  void _invalidateSearch() {
    _haystacks.clear();
    _searchKey = '';
    _searchHits = <Song>[];
  }

  void _loadCached() {
    final String? raw = _prefs.getString(_cacheKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _songs
        ..clear()
        ..addAll(decoded.whereType<Map>().map((Map item) => Song.fromJson(item.cast<String, dynamic>())));
    } catch (_) {
      _songs.clear();
    }
    _invalidateSearch();
  }

  Future<bool> ensurePermission(BuildContext context) async {
    if (!Platform.isAndroid) return true;
    final int sdk = await NativeBridge.sdkInt();
    final Permission permission = sdk >= 33 ? Permission.audio : Permission.storage;
    final PermissionStatus current = await permission.status;
    if (current.isGranted) return true;
    if (!context.mounted) return false;
    final bool? allow = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: const Text('Find music on this device?'),
        content: const Text(
          'IfallMusic needs audio permission to show songs already saved on your phone. '
          'Downloads made by IfallMusic stay in the existing Downloads tab.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (allow != true) return false;
    final PermissionStatus status = await permission.request();
    return status.isGranted;
  }

  Future<void> scan({BuildContext? context}) async {
    if (_scanning) return;
    if (context != null && !await ensurePermission(context)) return;
    _scanning = true;
    _lastError = null;
    notifyListeners();
    try {
      final List<LocalAudioFile> files = await NativeBridge.listLocalAudio();
      _songs
        ..clear()
        ..addAll(files.map(_toSong));
      _invalidateSearch();
      await _prefs.setString(
        _cacheKey,
        jsonEncode(_songs.map((Song song) => song.toJson()).toList()),
      );
    } catch (e) {
      _lastError = e.toString();
    } finally {
      _scanning = false;
      notifyListeners();
    }
  }

  Song _toSong(LocalAudioFile file) => Song(
        id: 'local:${file.id}',
        title: file.title.isEmpty ? 'Unknown title' : file.title,
        artist: file.artist.isEmpty ? 'Unknown artist' : file.artist,
        thumbnailUrl: file.albumId > 0
            ? 'content://media/external/audio/albumart/${file.albumId}'
            : '',
        duration: Duration(milliseconds: file.durationMs),
        artistId: file.artistId.toString(),
        album: file.album.isEmpty ? null : file.album,
        albumId: file.albumId.toString(),
        source: TrackSource.localDevice,
        localUri: 'content://media/external/audio/media/${file.id}',
      );
}
