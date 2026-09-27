import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/artist.dart';
import '../models/playlist.dart';
import '../models/song.dart';
import '../utils/backup_codec.dart';

/// Likes, playlists, history, saved songs and followed artists.
///
/// Everything is JSON in shared_preferences, so the library survives process
/// death and app updates.
class LibraryService extends ChangeNotifier {
  LibraryService(this._prefs) {
    _liked = _readList(kLiked).map(Song.fromJson).toList();
    _songs = _readList(kSongs).map(Song.fromJson).toList();
    _history = _readRawList(kHistory).map(HistoryEntry.fromJson).toList();
    _playlists = _readRawList(kPlaylists).map(Playlist.fromJson).toList();
    _artists = _readRawList(kArtists).map(ArtistRef.fromJson).toList();
    _searchHistory = _prefs.getStringList(kSearchHistory) ?? <String>[];
  }

  final SharedPreferences _prefs;

  static const String kLiked = 'saxify.liked';
  static const String kSongs = 'saxify.songs';
  static const String kHistory = 'saxify.history';
  static const String kPlaylists = 'saxify.playlists';
  static const String kArtists = 'saxify.artists';
  static const String kSearchHistory = 'saxify.search_history';

  static const int _maxHistory = 120;
  static const int _maxSearchHistory = 8;

  late List<Song> _liked;
  late List<Song> _songs;
  late List<HistoryEntry> _history;
  late List<Playlist> _playlists;
  late List<ArtistRef> _artists;
  late List<String> _searchHistory;

  // -------------------------------------------------------------- read-only
  List<Song> get likedSongs => List<Song>.unmodifiable(_liked);
  List<Song> get songs => List<Song>.unmodifiable(_songs);
  List<HistoryEntry> get history => List<HistoryEntry>.unmodifiable(_history);
  List<Playlist> get playlists => List<Playlist>.unmodifiable(_playlists);
  List<ArtistRef> get artists => List<ArtistRef>.unmodifiable(_artists);
  List<String> get recentSearches => List<String>.unmodifiable(_searchHistory);

  bool isLiked(String songId) => _liked.any((Song s) => s.id == songId);
  bool isSaved(String songId) => _songs.any((Song s) => s.id == songId);
  bool isFollowing(String channelId) =>
      _artists.any((ArtistRef a) => a.channelId == channelId);

  Playlist? playlistById(String id) {
    for (final Playlist p in _playlists) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Artists you have played recently, best first — feeds the home
  /// recommendations.
  List<String> recentArtistNames({int limit = 5}) {
    final List<String> out = <String>[];
    for (final HistoryEntry e in _history) {
      final String name = e.song.artist.trim();
      if (name.isEmpty || name.toLowerCase() == 'unknown artist') continue;
      if (!out.contains(name)) out.add(name);
      if (out.length >= limit) break;
    }
    return out;
  }

  List<String> recentSongTitles({int limit = 5}) {
    final List<String> out = <String>[];
    for (final HistoryEntry e in _history) {
      if (!out.contains(e.song.title)) out.add(e.song.title);
      if (out.length >= limit) break;
    }
    return out;
  }

  // ------------------------------------------------------------------ likes
  void Function(Song song, bool liked)? onLikeChanged;
  void Function(String message)? onUserNotice;
  void Function()? onPlaylistsChanged;

  Future<void> toggleLike(Song song) async {
    final bool liked = !isLiked(song.id);
    if (!liked) {
      _liked.removeWhere((Song s) => s.id == song.id);
    } else {
      _liked.insert(0, song);
    }
    await _persistSongs(kLiked, _liked);
    notifyListeners();
    onLikeChanged?.call(song, liked);
    onUserNotice?.call(
      liked ? 'Added to Liked Songs' : 'Removed from Liked Songs',
    );
  }

  // ------------------------------------------------------------ your songs
  Future<void> toggleSaved(Song song) async {
    if (isSaved(song.id)) {
      _songs.removeWhere((Song s) => s.id == song.id);
    } else {
      _songs.insert(0, song);
    }
    await _persistSongs(kSongs, _songs);
    notifyListeners();
  }

  // --------------------------------------------------------------- playlists
  Future<Playlist> createPlaylist(String name) async {
    final Playlist playlist = Playlist(
      id: 'pl_${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'My Playlist' : name.trim(),
    );
    _playlists.insert(0, playlist);
    await _persistPlaylists();
    notifyListeners();
    onPlaylistsChanged?.call();
    onUserNotice?.call('Playlist created');
    return playlist;
  }

  Future<void> renamePlaylist(String id, String name) async {
    final Playlist? p = playlistById(id);
    if (p == null) return;
    p.name = name.trim().isEmpty ? p.name : name.trim();
    await _persistPlaylists();
    notifyListeners();
    onUserNotice?.call('Playlist renamed');
    onPlaylistsChanged?.call();
  }

  Future<void> deletePlaylist(String id) async {
    _playlists.removeWhere((Playlist p) => p.id == id);
    await _persistPlaylists();
    notifyListeners();
    onUserNotice?.call('Playlist deleted');
    onPlaylistsChanged?.call();
  }

  /// Returns false when the song was already in that playlist.
  Future<bool> addToPlaylist(String id, Song song) async {
    final Playlist? p = playlistById(id);
    if (p == null) return false;
    if (p.songs.any((Song s) => s.id == song.id)) return false;
    p.songs.add(song);
    await _persistPlaylists();
    notifyListeners();
    onPlaylistsChanged?.call();
    return true;
  }

  Future<void> removeFromPlaylist(String id, String songId) async {
    final Playlist? p = playlistById(id);
    if (p == null) return;
    p.songs.removeWhere((Song s) => s.id == songId);
    await _persistPlaylists();
    notifyListeners();
    onUserNotice?.call('Removed from playlist');
    onPlaylistsChanged?.call();
  }

  // ----------------------------------------------------------------- history
  /// Called the moment a track actually starts playing.
  Future<void> recordPlay(Song song) async {
    _history.removeWhere((HistoryEntry e) => e.song.id == song.id);
    _history.insert(0, HistoryEntry(song: song, playedAt: DateTime.now()));
    if (_history.length > _maxHistory) {
      _history = _history.sublist(0, _maxHistory);
    }
    await _persistHistory();
    notifyListeners();
  }

  Future<void> clearHistory() async {
    _history = <HistoryEntry>[];
    await _prefs.setString(kHistory, '[]');
    notifyListeners();
  }

  Future<void> removeHistoryEntry(String songId) async {
    _history.removeWhere((HistoryEntry e) => e.song.id == songId);
    await _persistHistory();
    notifyListeners();
  }

  // ---------------------------------------------------------------- artists
  Future<void> toggleFollow(ArtistRef artist) async {
    if (isFollowing(artist.channelId)) {
      _artists.removeWhere((ArtistRef a) => a.channelId == artist.channelId);
    } else {
      _artists.insert(0, artist);
    }
    await _persistRaw(
      kArtists,
      _artists.map((ArtistRef a) => a.toJson()).toList(),
    );
    notifyListeners();
  }

  // ----------------------------------------------------------------- search
  Future<void> rememberSearch(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return;
    _searchHistory.removeWhere((s) => s.toLowerCase() == q.toLowerCase());
    _searchHistory.insert(0, q);
    if (_searchHistory.length > _maxSearchHistory) {
      _searchHistory = _searchHistory.sublist(0, _maxSearchHistory);
    }
    await _prefs.setStringList(kSearchHistory, _searchHistory);
    notifyListeners();
  }

  Future<void> removeSearch(String query) async {
    _searchHistory.remove(query);
    await _prefs.setStringList(kSearchHistory, _searchHistory);
    notifyListeners();
  }

  Future<void> clearSearchHistory() async {
    _searchHistory = <String>[];
    await _prefs.remove(kSearchHistory);
    notifyListeners();
  }

  // ----------------------------------------------------------------- backup
  String exportBackup() => jsonEncode(<String, dynamic>{
    'app': 'saxify',
    'version': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'liked': _liked.map((Song s) => s.toJson()).toList(),
    'songs': _songs.map((Song s) => s.toJson()).toList(),
    'playlists': _playlists.map((Playlist p) => p.toJson()).toList(),
    'history': _history.map((HistoryEntry e) => e.toJson()).toList(),
    'artists': _artists.map((ArtistRef a) => a.toJson()).toList(),
  });

  String? validateBackup(String raw) => validateBackupJson(raw);

  /// Cloud or clipboard playlists are merged by name. Existing songs stay.
  Future<void> mergePlaylists(List<Playlist> incoming) async {
    _mergePlaylistList(incoming);
    await _persistPlaylists();
    notifyListeners();
    onPlaylistsChanged?.call();
  }

  /// [merge] unions by id/name. Otherwise the blob replaces the local library.
  Future<bool> importBackup(String raw, {bool merge = false}) async {
    if (validateBackupJson(raw) != null) return false;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return false;
      if (!merge) {
        _liked = _songsFrom(decoded['liked']);
        _songs = _songsFrom(decoded['songs']);
        _playlists = _rawListFrom(
          decoded['playlists'],
        ).map(Playlist.fromJson).toList();
        _history = _rawListFrom(
          decoded['history'],
        ).map(HistoryEntry.fromJson).toList();
        _artists = _rawListFrom(
          decoded['artists'],
        ).map(ArtistRef.fromJson).toList();
      } else {
        _liked = _mergeSongs(_liked, _songsFrom(decoded['liked']));
        _songs = _mergeSongs(_songs, _songsFrom(decoded['songs']));
        _mergePlaylistList(
          _rawListFrom(decoded['playlists']).map(Playlist.fromJson).toList(),
        );
        for (final HistoryEntry entry in _rawListFrom(
          decoded['history'],
        ).map(HistoryEntry.fromJson)) {
          if (entry.song.id.isEmpty) continue;
          if (_history.any((HistoryEntry e) => e.song.id == entry.song.id))
            continue;
          _history.add(entry);
        }
        for (final ArtistRef artist in _rawListFrom(
          decoded['artists'],
        ).map(ArtistRef.fromJson)) {
          if (!isFollowing(artist.channelId)) _artists.add(artist);
        }
      }
      await _persistSongs(kLiked, _liked);
      await _persistSongs(kSongs, _songs);
      await _persistPlaylists();
      await _persistHistory();
      await _persistRaw(
        kArtists,
        _artists.map((ArtistRef a) => a.toJson()).toList(),
      );
      notifyListeners();
      onPlaylistsChanged?.call();
      return true;
    } catch (e) {
      debugPrint('importBackup failed: $e');
      return false;
    }
  }

  void _mergePlaylistList(List<Playlist> incoming) {
    for (final Playlist remote in incoming) {
      Playlist? existing;
      for (final Playlist local in _playlists) {
        if (local.id == remote.id ||
            local.name.toLowerCase() == remote.name.toLowerCase()) {
          existing = local;
          break;
        }
      }
      if (existing == null) {
        _playlists.insert(0, remote);
        continue;
      }
      for (final Song song in remote.songs) {
        if (song.id.isEmpty) continue;
        if (!existing.songs.any((Song s) => s.id == song.id))
          existing.songs.add(song);
      }
    }
  }

  List<Song> _mergeSongs(List<Song> current, List<Song> incoming) {
    final List<Song> out = List<Song>.from(current);
    for (final Song song in incoming) {
      if (song.id.isEmpty) continue;
      if (!out.any((Song s) => s.id == song.id)) out.add(song);
    }
    return out;
  }

  // ------------------------------------------------------------- internals
  List<Map<String, dynamic>> _readList(String key) => _readRawList(key);

  List<Map<String, dynamic>> _readRawList(String key) {
    final String? raw = _prefs.getString(key);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    return _rawListFrom(_safeDecode(raw));
  }

  static Object? _safeDecode(String raw) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      return null;
    }
  }

  static List<Map<String, dynamic>> _rawListFrom(Object? value) {
    if (value is! List) return <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final Object? item in value) {
      if (item is Map) out.add(item.cast<String, dynamic>());
    }
    return out;
  }

  static List<Song> _songsFrom(Object? value) =>
      _rawListFrom(value).map(Song.fromJson).toList();

  Future<void> _persistSongs(String key, List<Song> songs) => _prefs.setString(
    key,
    jsonEncode(songs.map((Song s) => s.toJson()).toList()),
  );

  Future<void> _persistPlaylists() => _prefs.setString(
    kPlaylists,
    jsonEncode(_playlists.map((Playlist p) => p.toJson()).toList()),
  );

  Future<void> _persistHistory() => _prefs.setString(
    kHistory,
    jsonEncode(_history.map((HistoryEntry e) => e.toJson()).toList()),
  );

  Future<void> _persistRaw(String key, List<Map<String, dynamic>> items) =>
      _prefs.setString(key, jsonEncode(items));
}
