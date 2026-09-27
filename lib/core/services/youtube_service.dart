import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../services/yt_music_parser.dart';
import '../../services/yt_music_service.dart';
import '../models/artist.dart';
import '../models/song.dart';
import 'radio_queue.dart';

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

  // ------------------------------------------------------------------ search
  Future<List<Video>> search(String query, {int limit = 20}) async {
    final VideoSearchList results = await _yt.search.search(query);
    return results.take(limit).toList();
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
    List<Song> songs = [], all = [], fallback = [];
    var musicSucceeded = false;
    List<Song> merged() => mergeMusicResults(songs, all, fallback)
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
    return merged();
  }

  Future<List<Song>> musicSongs(String query, {int limit = 20}) async {
    try {
      return (await music.search(
        query,
        filter: YtMusicService.songsFilter,
      )).tracks.take(limit).toList();
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
      if (seen.contains(v.id.value)) continue;
      seen.add(v.id.value);
      out.add(Song.fromVideo(v));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// YTM's watch-next mix is keyed to the recording, not the search query.
  /// Fall back to related music and then artist discovery, never title search.
  Future<List<Song>> radioSongs(
    Song seed, {
    Iterable<Song> history = const [],
    Set<String> exclude = const {},
  }) async {
    final candidates = <Song>[];
    List<Song> distinct() => radioCandidates(
      seed,
      candidates,
      history: history,
      excludedIds: exclude,
    );
    try {
      final json = await music.request('next', {
        'videoId': seed.id,
        'isAudioOnly': true,
        'enablePersistentPlaylistPanel': true,
      });
      candidates.addAll(parseMusicRadio(json).tracks);
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
    if (distinct().length < 4) {
      candidates.addAll(await musicSongs('${seed.artist} songs', limit: 24));
    }
    return distinct();
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

  void close() {
    music.close();
    _yt.close();
  }
}
