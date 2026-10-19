import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../services/yt_music_parser.dart';
import '../../services/yt_music_service.dart';
import '../models/artist.dart';
import '../models/song.dart';
import 'radio_queue.dart';
import 'ai_song_filter.dart';
import 'vibe_ranker.dart';

/// Thin, typed wrapper around `YoutubeExplode`.
///
/// Every screen goes through this class so there is exactly one HTTP client,
/// one search entry point (`_yt.search`, the same call the original app used)
/// and one place to filter out live streams / broken rows.
class YoutubeService {
  YoutubeService() : _yt = YoutubeExplode();

  final YoutubeExplode _yt;
  final YtMusicService music = YtMusicService(
    gl: PlatformDispatcher.instance.locale.countryCode ?? 'IN',
    hl: PlatformDispatcher.instance.locale.languageCode == 'und'
        ? 'en'
        : PlatformDispatcher.instance.locale.languageCode,
  );

  /// Exposed for [PlaybackService], which owns the stream-manifest logic.
  YoutubeExplode get client => _yt;

  /// Recently served searches, newest last. Typing a query a second time —
  /// or coming back to it from a Home rail — is then instant and costs no
  /// network. Bounded so it can never grow with the session.
  final Map<String, List<Song>> _searchCache = <String, List<Song>>{};
  static const int _searchCacheLimit = 60;

  List<Song>? _cachedSearch(String key) {
    final List<Song>? hit = _searchCache.remove(key);
    if (hit == null) return null;
    // Re-insert to mark it most-recently used.
    _searchCache[key] = hit;
    return hit;
  }

  void _storeSearch(String key, List<Song> songs) {
    if (songs.isEmpty) return;
    _searchCache[key] = List<Song>.unmodifiable(songs);
    while (_searchCache.length > _searchCacheLimit) {
      _searchCache.remove(_searchCache.keys.first);
    }
  }

  // ------------------------------------------------------------------ search
  Future<List<Video>> search(String query, {int limit = 20}) async {
    final VideoSearchList results = await _yt.search.search(query);
    return results.where((v) => !v.isLive && !isLikelyAiSong(Song.fromVideo(v))).take(limit).toList();
  }

  /// Raw-query YTM-first music search with a separate YouTube fallback.
  Future<List<Song>> searchSongs(
    String query, {
    int limit = 20,
    String? subtitle,
    CancelToken? cancelToken,
    void Function(List<Song>)? onPartial,
    void Function(bool)? onMusicAvailability,
  }) async {
    final raw = YtMusicService.sanitize(query);
    if (raw.isEmpty || limit <= 0) return [];
    final String cacheKey = '$raw|$limit|${subtitle ?? ''}';
    final List<Song>? hit = _cachedSearch(cacheKey);
    if (hit != null) {
      // Replay the cached rows through the same callbacks a fresh search uses,
      // so the UI paints immediately without a loading flash. Callers get a
      // copy: the stored row itself stays immutable and shared.
      if (cancelToken?.isCancelled != true) {
        onPartial?.call(List<Song>.of(hit));
      }
      onMusicAvailability?.call(true);
      return List<Song>.of(hit);
    }
    List<Song> songs = [], all = [], fallback = [];
    var musicSucceeded = false;
    List<Song> merged() => withoutAiSongs(mergeMusicResults(songs, all, fallback))
        .take(limit)
        .map((s) => subtitle == null ? s : s.copyWith(subtitle: subtitle))
        .toList();
    void publish() {
      if (cancelToken?.isCancelled != true) onPartial?.call(merged());
    }

    await Future.wait([
      () async {
        try {
          songs = (await music.search(
            raw,
            filter: YtMusicService.songsFilter,
            cancelToken: cancelToken,
          )).tracks;
          musicSucceeded = true;
          publish();
        } catch (e) {
          debugPrint('YTM songs: $e');
        }
      }(),
      () async {
        try {
          all = (await music.search(raw, cancelToken: cancelToken)).tracks;
          musicSucceeded = true;
          publish();
        } catch (e) {
          debugPrint('YTM search: $e');
        }
      }(),
      () async {
        try {
          fallback = (await search(raw, limit: limit).timeout(
            const Duration(seconds: 8),
          )).where((v) => !v.isLive).map((v) => Song.fromVideo(v)).toList();
          publish();
        } catch (e) {
          debugPrint('YouTube fallback: $e');
        }
      }(),
    ]);
    if (cancelToken?.isCancelled != true)
      onMusicAvailability?.call(musicSucceeded);
    final List<Song> out = merged();
    _storeSearch(cacheKey, out);
    return out;
  }


  /// Standalone YouTube video shelf, independent from the YT Music results.
  Future<List<Song>> searchVideoSongs(String query, {int limit = 12}) async {
    final raw = YtMusicService.sanitize(query);
    if (raw.isEmpty) return [];
    final videos = await search(raw, limit: limit * 3);
    return videos.where((v) => looksLikeSong(
      title: v.title, author: v.author, duration: v.duration,
    )).map(Song.fromVideo).take(limit).toList();
  }

  Future<List<Song>> musicSongs(String query, {int limit = 20}) async {
    try {
      return (await music.search(
        query,
        filter: YtMusicService.songsFilter,
      )).tracks.where((s) => !isLikelyAiSong(s)).take(limit).toList();
    } catch (e) {
      debugPrint('YTM catalog: $e');
      return [];
    }
  }

  Future<List<Song>> browseTracks(MusicBrowseItem item) async {
    if (item.kind == 'artist') return musicSongs(item.title, limit: 50);
    // Primary path: the same browse call the web player makes when a playlist
    // or album is opened — no separate playlist-id round trip, so long
    // playlists and albums resolve reliably.
    List<Song> tracks = <Song>[];
    try {
      tracks = await music.browseTracks(item.id);
    } catch (e) {
      debugPrint('ifallertzia browse failed: $e');
    }
    if (item.kind == 'album' && tracks.isNotEmpty) {
      tracks = <Song>[
        for (final Song s in tracks)
          s.copyWith(
            album: s.album ?? item.title,
            albumId: s.albumId ?? item.id,
            thumbnailUrl: item.artwork.isNotEmpty
                ? item.artwork
                : (s.thumbnailUrl.isEmpty ? item.artwork : s.thumbnailUrl),
          ),
      ];
    }
    if (tracks.isNotEmpty) return tracks;
    // Fallback: resolve the playlist id, then fetch via the video client.
    try {
      final id = await music.playlistId(item.id);
      if (id == null) return [];
      return await _yt.playlists
          .getVideos(id)
          .take(100)
          .map(
            (v) => Song(
              id: v.id.value,
              title: v.title,
              artist: v.author,
              channelId: v.channelId.value,
              duration: v.duration,
              source: TrackSource.ytMusic,
              album: item.kind == 'album' ? item.title : null,
              albumId: item.kind == 'album' ? item.id : null,
              thumbnailUrl: item.kind == 'album' && item.artwork.isNotEmpty
                  ? item.artwork
                  : v.thumbnails.highResUrl,
            ),
          )
          .toList()
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      debugPrint('playlist fallback failed: $e');
      return [];
    }
  }

  /// A compact search modifier used throughout the app, including mood cards.
  /// Explicit regional language/genre requests are preserved; other searches
  /// start with Hindi/Indian music for the requested India-first experience.
  static String indianFirstQuery(String raw) {
    final String query = raw.trim();
    if (query.isEmpty) return 'Hindi songs India';
    final bool alreadyRegional = RegExp(
      r'\b(hindi|bollywood|indian|india|punjabi|tamil|telugu|marathi|bengali|kannada|malayalam|gujarati|bhajan|sufi|qawwali|ghazal)\b',
      caseSensitive: false,
    ).hasMatch(query);
    final bool hasMusicWord = RegExp(
      r'\b(song|songs|music|audio|bhajan|track|tracks|hits?)\b',
      caseSensitive: false,
    ).hasMatch(query);
    if (alreadyRegional) return hasMusicWord ? query : '$query songs';
    return 'Hindi song $query official audio';
  }

  /// Metadata-only song detector, exposed so the filter can be covered without
  /// network access. Label/VEVO/Bhakti channels and explicit song titles pass;
  /// obvious talk, gaming, news and tutorial uploads do not.
  static bool looksLikeSong({
    required String title,
    required String author,
    Duration? duration,
  }) {
    if (duration == null || duration.inSeconds < 25) {
      return false;
    }
    if (RegExp(r'\s-\s?Topic$', caseSensitive: false).hasMatch(author))
      return true;
    final String titleText = title.toLowerCase();
    final String authorText = author.toLowerCase();
    final RegExp notMusic = RegExp(
      r'\b(vlog|podcast|interview|reaction|review|tutorial|how to|news|gameplay|gaming|trailer|teaser|episode|full movie|short film|behind the scenes|making of|live stream|highlights)\b',
      caseSensitive: false,
    );
    if (notMusic.hasMatch(titleText)) return false;

    final RegExp musicTitle = RegExp(
      r'\b(song|songs|music|official audio|official video|music video|lyrics?|lyrical|soundtrack|ost|theme song|bhajan|aarti|kirtan|qawwali|ghazal|sufi|mantra|meditation music|lofi|lo-fi|remix|album|track|jukebox|non-?stop|all songs|full album)\b|गाना|गीत|भजन|आरती|कीर्तन|कव्वाली|ग़ज़ल|संगीत|सॉन्ग',
      caseSensitive: false,
    );
    final RegExp musicChannel = RegExp(
      r'\b(music|records?|recordings?|vevo|entertainment|films?|label|bhakti|sagar|saregama|t-series|zee music|sony music|tips music|ultra music|warner|universal|aditya music|lahari music|sun tv|official artist)\b',
      caseSensitive: false,
    );
    final bool plausibleSongLength = duration.inMinutes <= 15;
    final bool oshoMeditation =
        RegExp(
          r'\bosho\b',
          caseSensitive: false,
        ).hasMatch('$titleText $authorText') &&
        RegExp(
          r'\b(meditation|dynamic|kundalini|discourse|mantra|music)\b',
          caseSensitive: false,
        ).hasMatch(titleText);

    // Long-form uploads used to be dropped outright, which hid exactly the
    // things Indian listeners search for: Osho meditations and discourses, hour
    // long bhajan jukeboxes, lofi/chill mixes and study-playlists. They stay
    // rejected unless the title or the channel says "music".
    final bool longForm = duration.inHours >= 1;
    final bool longFormMusic = RegExp(
      r'\b(osho|meditation|mantra|bhajan|kirtan|aarti|satsang|discourse|pravachan|kundalini|dynamic|lofi|lo-?fi|chill|relax|sleep|study|instrumental|classical|raga|sufi|ghazal|piano|jazz|ambient|healing|devotional|jukebox|non-?stop|compilation|full album|all songs|mix|hours?|hours long)\b',
      caseSensitive: false,
    ).hasMatch('$titleText $authorText');
    if (longForm && !longFormMusic && !musicTitle.hasMatch(titleText))
      return false;

    return musicTitle.hasMatch(titleText) ||
        (plausibleSongLength && musicChannel.hasMatch(authorText)) ||
        oshoMeditation ||
        (longForm && longFormMusic);
  }

  /// One representative track for a query — used to build the home rails where
  /// each card is "the best match for this mood".
  Future<Song?> topSong(String query) async {
    try {
      final List<Song> songs = await searchSongs(query, limit: 1);
      return songs.isEmpty ? null : songs.first;
    } catch (e) {
      debugPrint('topSong("$query") failed: $e');
      return null;
    }
  }

  // ---------------------------------------------------------------- related
  /// Similar tracks, used both for "Recommended" and for the never-stop
  /// auto-next behaviour when a queue runs out.
  Future<List<Song>> similarSongs(
    String videoId, {
    int limit = 12,
    Set<String> exclude = const <String>{},
  }) async {
    final Video video = await _yt.videos.get(VideoId(videoId));
    final RelatedVideosList? related = await _yt.videos.getRelatedVideos(video);
    if (related == null) return <Song>[];

    final List<Song> out = <Song>[];
    final Set<String> seen = <String>{videoId, ...exclude};
    for (final Video v in related) {
      if (v.isLive ||
          !looksLikeSong(
            title: v.title,
            author: v.author,
            duration: v.duration,
          )) {
        continue;
      }
      if (seen.contains(v.id.value) || isLikelyAiSong(Song.fromVideo(v))) continue;
      seen.add(v.id.value);
      out.add(Song.fromVideo(v));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// The next tracks after [seed] — retrieve wide, then rank on the device.
  ///
  /// Stage 1 · retrieval. YouTube Music's own watch-next panel is the primary
  /// candidate source (it is the same panel the web player shows), widened by
  /// the related-videos graph and — when the listener has a vibe memory — the
  /// artists and words they have actually been enjoying this session. That is
  /// the cheap, honest stand-in for a two-tower retrieval: a few dozen
  /// candidates from several directions instead of one list from one query.
  ///
  /// Stage 2 · ranking. [VibeRanker] scores every candidate against the
  /// listener's memory (artist affinity, title-word affinity, the session's
  /// co-play graph, likes and skips) and orders them so each track sits close
  /// to the one before it.
  ///
  /// Without a [vibe] the behaviour is exactly the old one, which is what the
  /// unit tests and any non-personalised caller rely on.
  Future<List<Song>> radioSongs(
    Song seed, {
    Iterable<Song> history = const [],
    Set<String> exclude = const {},
    VibeMemory? vibe,
    int limit = 12,
  }) async {
    final candidates = <Song>[];
    final List<Song> historyList = history.toList();
    List<Song> distinct() => radioCandidates(
      seed,
      candidates,
      history: historyList,
      excludedIds: exclude,
      limit: limit,
    );
    try {
      final json = await music.request('next', {
        'videoId': seed.id,
        'isAudioOnly': true,
        'enablePersistentPlaylistPanel': true,
      });
      candidates.addAll(withoutAiSongs(parseMusicRadio(json).tracks));
    } catch (e) {
      debugPrint('YTM radio unavailable: ${e.runtimeType}');
    }
    if (distinct().length < 4) {
      try {
        candidates.addAll(
          await similarSongs(
            seed.id,
            limit: 24,
            exclude: exclude,
          ).timeout(const Duration(seconds: 8)),
        );
      } catch (e) {
        debugPrint('Related radio unavailable: ${e.runtimeType}');
      }
    }
    if (vibe != null) {
      candidates.addAll(await _vibeExpansion(seed, vibe));
    }
    if (distinct().length < 4) {
      candidates.addAll(await musicSongs('${seed.artist} songs', limit: 24));
    }
    if (vibe == null) return withoutAiSongs(distinct());

    // Rank the whole pool — never only what fit in the first slice.
    final List<Song> ranked = VibeRanker.rank(
      seed,
      candidates,
      profile: vibe.profile,
      excludedIds: exclude,
      limit: limit,
    );
    // Guarantee the queue can always move: if ranking came back thin, fall
    // back to the plain candidate list.
    if (ranked.length >= 4) return withoutAiSongs(ranked);
    final List<Song> plain = distinct();
    for (final Song song in plain) {
      if (ranked.length >= limit) break;
      if (ranked.any((Song s) => s.id == song.id)) continue;
      ranked.add(song);
    }
    return withoutAiSongs(ranked);
  }

  /// Extra candidates from what the listener's memory says they like: the
  /// artists they have been playing, and the words of the songs they loved.
  Future<List<Song>> _vibeExpansion(Song seed, VibeMemory vibe) async {
    final List<Song> out = <Song>[];
    final VibeProfile profile = vibe.profile;

    // Top artists of the session, anchored by the seed's own artist.
    final List<String> artists = <String>[
      if (artistKey(seed.artist).isNotEmpty) seed.artist,
      ...(_vibeArtists(profile)..removeWhere(
          (String a) => a == artistKey(seed.artist))),
    ].take(2).toList();
    for (final String artist in artists) {
      try {
        out.addAll(
          await musicSongs('$artist songs', limit: 20).timeout(
            const Duration(seconds: 8),
          ),
        );
      } catch (e) {
        debugPrint('vibe artist "$artist" unavailable: ${e.runtimeType}');
      }
    }

    // Words the listener keeps enjoying ("lofi", "arijit singh", …).
    final List<String> words = _vibeWords(profile);
    if (words.isNotEmpty) {
      try {
        out.addAll(
          await musicSongs('${seed.artist} ${words.join(' ')}', limit: 16)
              .timeout(const Duration(seconds: 8)),
        );
      } catch (e) {
        debugPrint('vibe words unavailable: ${e.runtimeType}');
      }
    }
    return out;
  }

  /// Artists with the strongest positive weight in the profile.
  List<String> _vibeArtists(VibeProfile profile) {
    final List<MapEntry<String, double>> entries = profile.artistWeights.entries
        .where((MapEntry<String, double> e) => e.value > 0.8 && e.key.length > 2)
        .toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) =>
          b.value.compareTo(a.value));
    return entries.take(4).map((MapEntry<String, double> e) => e.key).toList();
  }

  /// The three strongest non-name words of the listener's taste.
  List<String> _vibeWords(VibeProfile profile) {
    final List<MapEntry<String, double>> entries = profile.tokenWeights.entries
        .where((MapEntry<String, double> e) => e.value > 0.9 && e.key.length > 3)
        .toList()
      ..sort((MapEntry<String, double> a, MapEntry<String, double> b) =>
          b.value.compareTo(a.value));
    return entries.take(3).map((MapEntry<String, double> e) => e.key).toList();
  }

  // ---------------------------------------------------------------- channels
  Future<Channel> channel(String channelId) =>
      _yt.channels.get(ChannelId(channelId));

  /// Newest uploads of a channel. `getUploads` is a lazy stream — we only pull
  /// the first page worth of items.
  Future<List<Song>> channelUploads(String channelId, {int limit = 30}) async {
    final List<Video> uploads = await _yt.channels
        .getUploads(ChannelId(channelId))
        .take(limit)
        .toList();
    final List<Song> songs = <Song>[];
    for (final Video v in uploads) {
      if (v.isLive ||
          !looksLikeSong(
            title: v.title,
            author: v.author,
            duration: v.duration,
          )) {
        continue;
      }
      songs.add(Song.fromVideo(v));
    }
    return songs;
  }

  /// Channel metadata for a video we already have — used by the "open artist"
  /// action on a song row.
  Future<ArtistRef?> artistForVideo(String videoId) async {
    try {
      final Channel channel = await _yt.channels.getByVideo(VideoId(videoId));
      return ArtistRef(
        channelId: channel.id.value,
        name: channel.title,
        imageUrl: channel.logoUrl,
        subscribers: channel.subscribersCount?.toString(),
      );
    } catch (e) {
      debugPrint('artistForVideo($videoId) failed: $e');
      return null;
    }
  }

  /// Drops every cached search row (used when the listener clears cache).
  void clearSearchCache() => _searchCache.clear();

  void close() {
    _searchCache.clear();
    music.close();
    _yt.close();
  }
}
