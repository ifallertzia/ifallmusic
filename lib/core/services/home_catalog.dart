import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../services/yt_music_parser.dart';
import '../../services/yt_music_service.dart';
import '../models/album_card.dart';
import '../models/artist.dart';
import '../models/song.dart';
import 'artist_service.dart';
import 'library_service.dart';
import 'youtube_service.dart';

/// Everything the Home screen shows.
///
/// The web app's home is a set of rails: Made for you, personalised playlists, Trending
/// now, New releases, Top artists and Recommended for you. The mobile app builds
/// the same rails — "Made for you" and "Recommended" are personalised from what
/// you actually listened to, the rest mirror the site's curated shelves.
class HomeCatalog extends ChangeNotifier {
  HomeCatalog({
    required YoutubeService youtube,
    required LibraryService library,
    ArtistService? artists,
  }) : _youtube = youtube,
       _library = library,
       _artists = artists {
    _library.addListener(_personalChanged);
    _refreshTimer = Timer.periodic(
      const Duration(minutes: 30),
      (_) => load(force: true),
    );
  }
  Timer? _refreshTimer, _personalTimer;
  DateTime? _lastLoad;
  bool _disposed = false;
  final List<MusicBrowseItem> playlistsForYou = [];
  final List<MusicBrowseItem> freshReleases = [];
  void _personalChanged() {
    _personalTimer?.cancel();
    final elapsed = _lastLoad == null
        ? 120
        : DateTime.now().difference(_lastLoad!).inSeconds;
    _personalTimer = Timer(
      Duration(seconds: (120 - elapsed).clamp(2, 120)),
      () => load(force: true),
    );
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _refreshTimer?.cancel();
    _personalTimer?.cancel();
    _library.removeListener(_personalChanged);
    super.dispose();
  }

  Future<void> _browseRails() async {
    final artists = _library.recentArtistNames(limit: 3);
    final queries = artists.isEmpty
        ? ['Hindi music playlists', 'Bollywood playlists']
        : artists.map((a) => '$a playlists').toList();
    final results = await Future.wait(
      queries.map((q) async {
        try {
          return (await _youtube.music.search(
            q,
          )).items.where((i) => i.kind == 'playlist').toList();
        } catch (_) {
          return <MusicBrowseItem>[];
        }
      }),
    );
    final seen = <String>{};
    final items = results
        .expand((i) => i)
        .where((i) => seen.add(i.id))
        .take(12)
        .toList();
    if (items.isNotEmpty) {
      playlistsForYou
        ..clear()
        ..addAll(items);
      notifyListeners();
    }
    try {
      final now = DateTime.now();
      final releases = await _youtube.music.search(
        'new releases India ${now.year} ${now.month}',
        filter: YtMusicService.albumsFilter,
      );
      if (releases.items.isNotEmpty) {
        freshReleases
          ..clear()
          ..addAll(releases.items.where((i) => i.kind == 'album'));
        notifyListeners();
      }
    } catch (_) {}
  }

  final YoutubeService _youtube;
  final LibraryService _library;
  final ArtistService? _artists;

  /// Real artist faces for the Top artists rail. The rail used to fall back to
  /// the app logo because every [ArtistRef] shipped with an empty image — this
  /// map is filled from Deezer/iTunes the first time Home loads.
  final Map<String, String> artistPhotos = <String, String>{};

  /// Photo for an artist name: resolved face first, then whatever the model
  /// carried, otherwise empty (the widget then draws initials, never the logo).
  String photoFor(String name, {String fallback = ''}) {
    final String resolved = artistPhotos[name] ?? '';
    if (resolved.isNotEmpty) return resolved;
    return fallback;
  }

  Future<void> _resolveArtistPhotos() async {
    final ArtistService? artists = _artists;
    if (artists == null) return;
    final List<ArtistRef> pending = topArtists
        .where((ArtistRef a) => (artistPhotos[a.name] ?? '').isEmpty)
        .toList();
    if (pending.isEmpty) return;
    for (int start = 0; start < pending.length; start += 4) {
      final List<ArtistRef> batch = pending.skip(start).take(4).toList();
      await Future.wait(<Future<void>>[
        for (final ArtistRef artist in batch)
          () async {
            try {
              final ArtistProfile profile = await artists
                  .resolve(artist.name)
                  .timeout(const Duration(seconds: 12));
              if (profile.imageUrl.isNotEmpty) {
                artistPhotos[artist.name] = profile.imageUrl;
              }
            } catch (_) {}
          }(),
      ]);
      notifyListeners();
    }
  }

  bool loading = true;
  bool refreshing = false;
  String? error;
  bool _loaded = false;
  Future<void>? _loadOperation;

  List<Song> madeForYou = <Song>[];
  List<Song> trending = <Song>[];
  List<Song> recommended = <Song>[];

  /// Release shelves are deliberately India-first; every card opens a song-only search.
  static const List<AlbumCard> newReleases = <AlbumCard>[
    AlbumCard(
      query: 'latest Hindi Bollywood songs 2026 official audio',
      title: 'Bollywood Fresh',
      artist: 'Hindi · 2026',
      coverVideoId: 'NwgOjWWTwyM',
    ),
    AlbumCard(
      query: 'new Hindi indie songs 2026',
      title: 'Hindi Indie',
      artist: 'India · Indie',
      coverVideoId: '8lGpmDxT98o',
    ),
    AlbumCard(
      query: 'latest Punjabi songs 2026 official audio',
      title: 'Punjabi Heat',
      artist: 'Punjabi · 2026',
      coverVideoId: 'p9EAwHf6XjI',
    ),
    AlbumCard(
      query: 'Hindi devotional bhajan 2026',
      title: 'Bhakti & Devotion',
      artist: 'Hindi · Bhajan',
      coverVideoId: '3Xl2N5OQKME',
    ),
    AlbumCard(
      query: 'Hindi lofi chill songs',
      title: 'Hindi Lo-Fi',
      artist: 'Chill · India',
      coverVideoId: '0zdlvwZ8yuw',
    ),
    AlbumCard(
      query: 'Tamil Telugu latest songs 2026',
      title: 'South Indian Hits',
      artist: 'Tamil · Telugu',
      coverVideoId: 'ThdQv0PFUsc',
    ),
  ];

  static const List<ArtistRef> topArtists = <ArtistRef>[
    ArtistRef(channelId: '', name: 'Arijit Singh', imageUrl: ''),
    ArtistRef(channelId: '', name: 'Shreya Ghoshal', imageUrl: ''),
    ArtistRef(channelId: '', name: 'A. R. Rahman', imageUrl: ''),
    ArtistRef(channelId: '', name: 'Sonu Nigam', imageUrl: ''),
    ArtistRef(channelId: '', name: 'Lata Mangeshkar', imageUrl: ''),
    ArtistRef(channelId: '', name: 'Jubin Nautiyal', imageUrl: ''),
    ArtistRef(channelId: '', name: 'Diljit Dosanjh', imageUrl: ''),
    ArtistRef(channelId: '', name: 'Anirudh Ravichander', imageUrl: ''),
    ArtistRef(channelId: '', name: 'Darshan Raval', imageUrl: ''),
    ArtistRef(channelId: '', name: 'Neha Kakkar', imageUrl: ''),
    ArtistRef(channelId: '', name: 'Kishore Kumar', imageUrl: ''),
  ];

  /// India-first mood and genre shelves. Every label is a tappable song station.
  static const List<(String, String)> moodGenres = <(String, String)>[
    ('Bollywood', 'Hindi Bollywood hit songs'),
    ('Hindi Pop', 'Hindi pop songs India'),
    ('Hindi Indie', 'Hindi indie songs India'),
    ('Punjabi', 'Punjabi hit songs India'),
    ('Devotional', 'Hindi bhajan devotional songs'),
    ('Workout', 'Hindi workout gym songs'),
    ('Chill', 'Hindi chill songs relaxing'),
    ('Lo-Fi', 'Hindi lofi songs chill beats'),
    ('Romance', 'Hindi romantic love songs'),
    ('Sufi', 'Hindi Sufi songs India'),
    ('Qawwali', 'Indian qawwali songs'),
    ('Ghazal', 'Hindi ghazal songs'),
    ('Retro', 'Hindi old retro songs'),
    ('Classical', 'Indian classical instrumental music'),
    ('Party', 'Hindi party dance songs'),
    ('Focus', 'Indian instrumental focus music'),
    ('Road Trip', 'Hindi road trip songs'),
    ('Marathi', 'Marathi hit songs'),
    ('Bengali', 'Bengali songs India'),
    ('Tamil', 'Tamil hit songs'),
    ('Telugu', 'Telugu hit songs'),
    ('Osho', 'Osho meditation music discourse'),
    ('Pop', 'pop hits 2026'),
    ('Chill', 'chill vibes songs'),
    ('Focus', 'deep focus instrumental music'),
    ('Party', 'party dance songs'),
    ('Romance', 'romantic love songs'),
    ('Classical', 'classical piano instrumental'),
    ('Workout', 'workout edm songs'),
    ('Lo-Fi Beats', 'lofi beats to relax'),
  ];

  static const List<String> _trendingQueries = <String>[
    'Hindi trending songs India 2026',
    'latest Bollywood Hindi songs official audio',
    'Punjabi trending songs India 2026',
    'Hindi romantic hit songs',
    'Hindi devotional bhajan trending',
    'Hindi indie pop songs India',
    'Tamil Telugu trending songs India',
    'Hindi retro evergreen songs',
    'Hindi workout songs playlist',
    'Indian lofi chill songs',
  ];

  static const List<String> _madeForYouFallback = <String>[
    'Hindi romantic songs playlist',
    'Hindi lofi chill songs',
    'Bollywood soft songs',
    'Hindi pop hits India',
    'Hindi devotional bhajan songs',
    'Punjabi love songs',
  ];

  static const List<String> _recommendedFallback = <String>[
    'Hindi indie songs India',
    'latest Bollywood songs Hindi',
    'Hindi retro hit songs',
    'Indian classical instrumental',
    'Hindi sufi songs',
    'Hindi workout songs',
    'Osho meditation music',
    'Punjabi party songs',
  ];

  /// Loads each shelf automatically on first use. Concurrent callers (for
  /// example the Home screen and Today's Mix button) share one request.
  Future<void> load({bool force = false}) {
    if (_disposed) return Future<void>.value();
    if (_loaded && !force) return Future<void>.value();
    final Future<void>? inFlight = _loadOperation;
    if (inFlight != null) return inFlight;

    final Future<void> operation = Future<void>.microtask(_performLoad);
    _loadOperation = operation;
    return operation.whenComplete(() {
      if (identical(_loadOperation, operation)) _loadOperation = null;
    });
  }

  Future<void> _performLoad() async {
    if (_loaded) {
      refreshing = true;
    } else {
      loading = true;
    }
    error = null;
    _lastLoad = DateTime.now();
    unawaited(_browseRails());
    notifyListeners();

    try {
      final List<List<String>> queries = <List<String>>[
        _madeForYouQueries(),
        _trendingQueries,
        _recommendedQueries(),
      ];

      final List<List<Song>> rails = await Future.wait(<Future<List<Song>>>[
        _rail(queries[0], 6, musicOnly: true),
        _rail(queries[1], 10),
        _rail(queries[2], 8),
      ]);
      if (rails.every((List<Song> shelf) => shelf.isEmpty)) {
        throw StateError('The music service returned no catalog results');
      }

      if (rails[0].isNotEmpty) madeForYou = rails[0];
      trending = rails[1];
      recommended = rails[2];
      _loaded = true;
      error = null;
      notifyListeners();
      // Faces are fetched after the shelves so Home paints instantly.
      unawaited(_resolveArtistPhotos());
    } catch (e) {
      error = 'Could not load your home feed. Pull down to try again.';
      debugPrint('HomeCatalog.load failed: $e');
    } finally {
      loading = false;
      refreshing = false;
      notifyListeners();
    }
  }

  /// Fetches a few stations at a time to avoid firing twenty YouTube requests
  /// simultaneously on slower phones or mobile connections.
  Future<List<Song>> _rail(
    List<String> queries,
    int limit, {
    bool musicOnly = false,
  }) async {
    final List<Song> songs = <Song>[];
    final List<String> selected = queries.take(limit).toList();
    for (int start = 0; start < selected.length; start += 4) {
      final List<String> batch = selected.skip(start).take(4).toList();
      final List<Song?> results = await Future.wait(<Future<Song?>>[
        for (final String query in batch)
          musicOnly
              ? _youtube
                    .musicSongs(query, limit: 1)
                    .then((songs) => songs.isEmpty ? null : songs.first)
              : _youtube.topSong(query),
      ]);
      songs.addAll(results.whereType<Song>());
    }
    return songs;
  }

  /// "Made for you": artists you actually played, then curated fallbacks.
  List<String> _madeForYouQueries() {
    final List<String> personal = <String>[];
    for (final String artist in _library.recentArtistNames(limit: 3)) {
      personal.add('best of $artist');
    }
    for (final Song song in _library.likedSongs.take(2)) {
      personal.add('songs like ${song.title}');
    }
    return <String>[...personal, ..._madeForYouFallback];
  }

  /// "Recommended for you": your recent listening first, then discovery picks.
  List<String> _recommendedQueries() {
    final List<String> personal = <String>[];
    for (final String title in _library.recentSongTitles(limit: 3)) {
      personal.add('songs like $title');
    }
    for (final String artist in _library.recentArtistNames(limit: 2)) {
      personal.add('$artist mix');
    }
    return <String>[...personal, ..._recommendedFallback];
  }
}
