import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/movie_models.dart';

/// Where a person stopped watching one title.
class MovieResumePoint {
  const MovieResumePoint({
    required this.position,
    required this.duration,
    required this.updatedAtMs,
  });

  final Duration position;
  final Duration duration;
  final int updatedAtMs;
}

/// Remembers, per movie / episode / downloaded file, where playback stopped —
/// so backing out of the player and opening the same title later picks up
/// from that moment instead of from the beginning.
///
/// One small JSON map in shared preferences, keyed by a stable id of the
/// title (never by a stream URL, which changes with every mirror), capped at
/// [maxEntries] so it cannot grow without bound.
class MovieResumeStore {
  MovieResumeStore._();

  static const String prefsKey = 'ifall.movies.resume.v1';
  static const int maxEntries = 300;

  /// Below this there is nothing worth resuming: the title simply restarts.
  static const Duration minimumPosition = Duration(seconds: 15);

  /// Within this of the end the title counts as finished.
  static const Duration finishedTail = Duration(seconds: 45);

  /// …and so does anything past this share of it (end credits).
  static const double finishedFraction = 0.96;

  /// A stable id for one playable thing.
  ///
  /// A movie is its page; an episode is its page plus the season / episode it
  /// names; a downloaded or on-device file is its own record id. Quality is
  /// deliberately not part of the key — 480p and 1080p of the same movie
  /// share one position.
  static String keyFor({
    MovieDetail? detail,
    MovieQualityLink? quality,
    MovieDownloadItem? localItem,
  }) {
    if (localItem != null) {
      final String id = localItem.id.trim();
      if (id.isNotEmpty) return 'local|$id';
      return 'local|${localItem.savedPath}';
    }
    if (detail == null) return '';
    final String page = detail.webUrl.trim().isNotEmpty
        ? _stablePage(detail.webUrl)
        : (detail.cleanTitle.isNotEmpty ? detail.cleanTitle : detail.title)
            .trim()
            .toLowerCase();
    if (page.isEmpty) return '';
    final String season = (quality?.seasonLabel ?? '').trim().toLowerCase();
    final String episode = (quality?.episodeLabel ?? '').trim().toLowerCase();
    final String provider = detail.provider.id;
    if (season.isEmpty && episode.isEmpty) return '$provider|$page';
    return '$provider|$page|$season|$episode';
  }

  /// The page without its host: catalogs move between mirror domains, and the
  /// same title on a new mirror is still the same title.
  static String _stablePage(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null || uri.path.isEmpty || uri.path == '/') {
      return url.trim().toLowerCase();
    }
    final String path = uri.path.replaceAll(RegExp(r'/+$'), '').toLowerCase();
    return uri.hasQuery ? '$path?${uri.query}' : path;
  }

  /// Whether [position] of [duration] is worth coming back to.
  static bool isResumable(Duration position, Duration duration) {
    if (position < minimumPosition) return false;
    if (duration <= Duration.zero) return true;
    if (duration - position <= finishedTail) return false;
    return position.inMilliseconds <
        duration.inMilliseconds * finishedFraction;
  }

  static Map<String, dynamic> _read(SharedPreferences prefs) {
    final String raw = prefs.getString(prefsKey) ?? '';
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return <String, dynamic>{};
  }

  /// The saved position for [key], or null when the title should start from
  /// the beginning.
  static Future<MovieResumePoint?> load(String key) async {
    if (key.isEmpty) return null;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Object? entry = _read(prefs)[key];
      if (entry is! Map) return null;
      final int positionMs = (entry['p'] as num?)?.toInt() ?? 0;
      final int durationMs = (entry['d'] as num?)?.toInt() ?? 0;
      final MovieResumePoint point = MovieResumePoint(
        position: Duration(milliseconds: positionMs),
        duration: Duration(milliseconds: durationMs),
        updatedAtMs: (entry['t'] as num?)?.toInt() ?? 0,
      );
      return isResumable(point.position, point.duration) ? point : null;
    } catch (_) {
      return null;
    }
  }

  /// Records [position] for [key]. A position that is not worth resuming (the
  /// first seconds, or the end credits) clears the entry instead, so a
  /// finished movie starts over next time.
  static Future<void> save(
    String key, {
    required Duration position,
    required Duration duration,
  }) async {
    if (key.isEmpty) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> all = _read(prefs);
      if (!isResumable(position, duration)) {
        if (all.remove(key) == null) return;
      } else {
        all[key] = <String, dynamic>{
          'p': position.inMilliseconds,
          'd': duration.inMilliseconds,
          't': DateTime.now().millisecondsSinceEpoch,
        };
        if (all.length > maxEntries) {
          final List<MapEntry<String, dynamic>> byAge = all.entries.toList()
            ..sort((MapEntry<String, dynamic> a, MapEntry<String, dynamic> b) {
              int age(Object? v) =>
                  v is Map ? ((v['t'] as num?)?.toInt() ?? 0) : 0;
              return age(a.value).compareTo(age(b.value));
            });
          for (final MapEntry<String, dynamic> old
              in byAge.take(all.length - maxEntries)) {
            all.remove(old.key);
          }
        }
      }
      await prefs.setString(prefsKey, jsonEncode(all));
    } catch (_) {
      // Remembering a position must never get in the way of playback.
    }
  }

  static Future<void> clear(String key) async {
    if (key.isEmpty) return;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> all = _read(prefs);
      if (all.remove(key) == null) return;
      await prefs.setString(prefsKey, jsonEncode(all));
    } catch (_) {}
  }
}
