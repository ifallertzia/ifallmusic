import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie_models.dart';

class MovieLibraryService extends ChangeNotifier {
  MovieLibraryService(this._prefs) {
    _watchlist = _decode('ifall.movies.watchlist');
    _history = _decode('ifall.movies.history');
  }

  final SharedPreferences _prefs;
  late List<MoviePost> _watchlist;
  late List<MoviePost> _history;

  List<MoviePost> get watchlist => List<MoviePost>.unmodifiable(_watchlist);
  List<MoviePost> get history => List<MoviePost>.unmodifiable(_history);

  bool contains(MoviePost post) => _watchlist.any((MoviePost item) => item.link == post.link);

  Future<void> toggleWatchlist(MoviePost post) async {
    if (contains(post)) {
      _watchlist.removeWhere((MoviePost item) => item.link == post.link);
    } else {
      _watchlist.insert(0, post);
    }
    await _store('ifall.movies.watchlist', _watchlist);
    notifyListeners();
  }

  Future<void> recordOpened(MoviePost post) async {
    _history.removeWhere((MoviePost item) => item.link == post.link);
    _history.insert(0, post);
    if (_history.length > 100) _history = _history.take(100).toList();
    await _store('ifall.movies.history', _history);
    notifyListeners();
  }

  /// Drops one title from Recently watched. True when something was removed.
  ///
  /// This is history only — a watchlist entry, a download or anything saved on
  /// the device is untouched.
  Future<bool> removeFromHistory(MoviePost post) async {
    final int before = _history.length;
    _history.removeWhere((MoviePost item) => item.link == post.link);
    if (_history.length == before) return false;
    await _store('ifall.movies.history', _history);
    notifyListeners();
    return true;
  }

  /// Empties Recently watched in one go.
  Future<void> clearHistory() async {
    if (_history.isEmpty) return;
    _history = <MoviePost>[];
    await _store('ifall.movies.history', _history);
    notifyListeners();
  }

  List<MoviePost> _decode(String key) {
    final String? value = _prefs.getString(key);
    if (value == null || value.isEmpty) return <MoviePost>[];
    try {
      final List<dynamic> decoded = jsonDecode(value) as List<dynamic>;
      return decoded
          .whereType<Map<String, dynamic>>()
          .map((Map<String, dynamic> item) => MoviePost(
                title: item['title'] as String? ?? '',
                link: item['link'] as String? ?? '',
                imageUrl: item['imageUrl'] as String? ?? '',
                fallbackImageUrl: item['fallbackImageUrl'] as String? ?? '',
                badge: item['badge'] as String? ?? '',
                subtitle: item['subtitle'] as String? ?? '',
              ))
          .where((MoviePost post) => post.link.isNotEmpty)
          .toList();
    } catch (_) {
      return <MoviePost>[];
    }
  }

  Future<void> _store(String key, List<MoviePost> posts) async {
    await _prefs.setString(
      key,
      jsonEncode(posts
          .map((MoviePost post) => <String, String>{
                'title': post.title,
                'link': post.link,
                'imageUrl': post.imageUrl,
                'fallbackImageUrl': post.fallbackImageUrl,
                'badge': post.badge,
                'subtitle': post.subtitle,
              })
          .toList()),
    );
  }
}
