import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../models/song.dart';
import 'recommendation_engine.dart';
import 'recommendation_store.dart';
import 'vibe_ranker.dart';
import 'youtube_service.dart';

/// Builds home rails from the existing YouTube search — it does not add a
/// second music API.
class RecommendationService extends ChangeNotifier {
  RecommendationService({
    required YoutubeService youtube,
    RecommendationStore? store,
  })  : _youtube = youtube,
        _store = store ?? RecommendationStore();

  final YoutubeService _youtube;
  final RecommendationStore _store;

  RecommendationStore get store => _store;

  bool loading = false;
  bool ready = false;
  String? becauseQuery;
  List<Song> forYou = <Song>[];
  List<Song> becauseYouSearched = <Song>[];
  String? lastMood;
  String? lastQuery;

  Future<void> open() async {
    await _store.open();
    ready = _store.ready;
    notifyListeners();
  }

  /// Loads what is known on this device into the playback engine's vibe
  /// memory: recent plays (lighter weight — an earlier session), every liked
  /// song, and the local co-listening graph.
  ///
  /// This is what makes the very first "next" of a fresh launch already sound
  /// like the listener instead of like a generic chart.
  Future<void> hydrateVibe(VibeMemory memory, {List<Song> liked = const []}) async {
    try {
      if (!_store.ready) await open();
      final List<({String id, String title, String artist})> recent =
          await _store.recentTracks(limit: 40);
      memory.seedHistory(<VibeTrack>[
        for (final ({String id, String title, String artist}) track in recent)
          VibeTrack(
            id: track.id,
            title: track.title,
            artist: track.artist,
            weight: 0.6,
          ),
      ]);
      memory.seedTransitions(await _store.transitions());
      for (final Song song in liked) {
        memory.noteLike(song);
      }
    } catch (e) {
      debugPrint('[IfallMusic][Reco] vibe hydrate failed: $e');
    }
  }

  Future<void> notePlay(Song song) async {
    await _store.recordPlay(
      songId: song.id,
      title: song.title,
      artist: song.artist,
      genre: lastMood,
      moods: <String>[
        if (lastMood != null) lastMood!,
        if (lastQuery != null && lastQuery!.isNotEmpty) lastQuery!,
      ],
    );
  }

  Future<void> noteSearch(String query) async {
    lastQuery = query.trim();
    await _store.recordSearch(query);
  }

  Future<void> noteSkip(Song song) => _store.recordSkip(song.id);

  Future<void> noteLike(Song song) => _store.recordLike(song.id);

  void noteMood(String mood) {
    lastMood = mood;
  }

  Future<void> refresh({Song? current, bool force = false}) async {
    if (loading) return;
    if (ready && forYou.isNotEmpty && !force && current == null) return;
    loading = true;
    notifyListeners();
    try {
      if (!_store.ready) await open();
      final List<String> repeated = await _store.repeatedQueries();
      becauseQuery = repeated.isEmpty ? null : repeated.first;
      final List<String> recent = await _store.recentPlayedIds();
      final Set<String> skipped = await _store.skippedIds();
      final Set<String> liked = await _store.likedIds();

      final RecoTrack? anchor = current == null
          ? null
          : RecoTrack(
              id: current.id,
              title: current.title,
              artist: current.artist,
              genre: lastMood,
              moods: <String>[
                if (lastMood != null) lastMood!,
              ],
            );

      final List<Song> similarSongs = await _searchSafe(
        anchor == null ? 'top hits 2026' : '${anchor.artist} songs',
      );
      final List<Song> searchSongs = await _searchSafe(
        becauseQuery ?? lastQuery ?? 'new songs',
      );
      final List<Song> discovery = await _searchSafe('indie discovery mix');

      final RecoSignals signals = RecoSignals(
        current: anchor,
        recentIds: recent,
        repeatedQueries: repeated,
        likedIds: liked,
        skippedIds: skipped,
      );

      final List<RecoTrack> mixed = RecommendationEngine.mix(
        similar: similarSongs.map(_toTrack).toList(),
        searchDriven: searchSongs.map(_toTrack).toList(),
        discovery: discovery.map(_toTrack).toList(),
        signals: signals,
      );

      final Map<String, Song> byId = <String, Song>{
        for (final Song s in <Song>[...similarSongs, ...searchSongs, ...discovery]) s.id: s,
      };
      forYou = mixed.map((RecoTrack t) => byId[t.id]).whereType<Song>().toList();
      if (becauseQuery != null) {
        becauseYouSearched = searchSongs
            .where((Song s) => s.id != current?.id && !recent.take(10).contains(s.id))
            .take(8)
            .toList();
      } else {
        becauseYouSearched = <Song>[];
      }
      await _store.saveCache(jsonEncode(forYou.map((Song s) => s.toJson()).toList()));
    } catch (e) {
      debugPrint('[IfallMusic][Reco] refresh failed: $e');
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<List<Song>> _searchSafe(String query) async {
    try {
      return await _youtube
          .searchSongs(query, limit: 8)
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      debugPrint('[IfallMusic][Reco] search "$query" failed: $e');
      return <Song>[];
    }
  }

  RecoTrack _toTrack(Song song) => RecoTrack(
        id: song.id,
        title: song.title,
        artist: song.artist,
        thumbnailUrl: song.thumbnailUrl,
        channelId: song.channelId,
        durationMs: song.duration?.inMilliseconds,
        genre: lastMood,
        moods: <String>[
          if (lastMood != null) lastMood!,
        ],
      );
}
