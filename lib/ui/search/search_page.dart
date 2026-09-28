import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/models/album_card.dart';
import '../../core/models/song.dart';
import '../../core/services/home_catalog.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/library_service.dart';
import '../../core/services/local_music_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/recommendation_service.dart';
import '../../core/services/youtube_service.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../../data/labels.dart';
import '../../screens/music_browse_screen.dart';
import '../../services/yt_music_parser.dart';
import '../../services/yt_music_service.dart';
import '../album/album_page.dart';
import '../brands/brands_page.dart';
import '../shell/shell_controller.dart';
import '../widgets/artwork.dart';
import '../widgets/media_cards.dart';
import '../widgets/neon.dart';
import '../widgets/song_tile.dart';

enum _SearchKind { songs, artists, albums, playlists }

/// YTM-first source-grouped tracks and real album/artist/playlist discovery.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key, this.initialQuery});

  final String? initialQuery;

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  List<Song> _results = <Song>[];
  List<MusicBrowseItem> _browseResults = [];
  bool _loading = false;
  bool _musicAvailable = true;
  Timer? _debounce;
  CancelToken? _cancel;
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _listening = false;
  String? _error;
  String _activeQuery = '';
  int _lastNonce = -1;
  int _searchGeneration = 0;
  _SearchKind _kind = _SearchKind.songs;

  @override
  void initState() {
    super.initState();
    if (widget.initialQuery != null && widget.initialQuery!.isNotEmpty) {
      _controller.text = widget.initialQuery!;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runSearch(widget.initialQuery!);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen to the shell, not just read it: mood buttons and Show all update
    // an IndexedStack child without changing its route or remounting it.
    final ShellController shell = Provider.of<ShellController>(context);
    if (shell.queryNonce == _lastNonce) return;
    _lastNonce = shell.queryNonce;
    final String? query = shell.pendingQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (query == null || query.trim().isEmpty) {
        _searchGeneration++;
        _debounce?.cancel();
        _cancel?.cancel();
        _browseResults = [];
        _controller.clear();
        setState(() {
          _results = <Song>[];
          _activeQuery = '';
          _error = null;
          _loading = false;
        });
        return;
      }
      _controller.text = query;
      _runSearch(query);
    });
  }

  /// Same search entry point the app already used: `youtube.searchSongs`.
  Future<void> _runSearch(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return;

    _debounce?.cancel();
    _cancel?.cancel('superseded');
    _cancel = CancelToken();
    final int generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _activeQuery = q;
      _results = [];
      _browseResults = [];
      _musicAvailable = true;
    });

    try {
      final YoutubeService youtube = context.read<YoutubeService>();
      final LibraryService library = context.read<LibraryService>();
      final RecommendationService reco = context.read<RecommendationService>();
      reco.noteSearch(q);
      if (_kind != _SearchKind.songs) {
        final result = await youtube.music.search(
          q,
          cancelToken: _cancel,
          filter: _kind == _SearchKind.albums
              ? YtMusicService.albumsFilter
              : _kind == _SearchKind.artists
              ? YtMusicService.artistsFilter
              : null,
        );
        if (!mounted || generation != _searchGeneration) return;
        final kind = _kind == _SearchKind.artists
            ? 'artist'
            : _kind == _SearchKind.albums
            ? 'album'
            : 'playlist';
        setState(() {
          _browseResults = result.items.where((i) => i.kind == kind).toList();
          _loading = false;
        });
        await library.rememberSearch(q);
        return;
      }
      final List<Song> results = await youtube.searchSongs(
        q,
        limit: 60,
        cancelToken: _cancel,
        onPartial: (results) {
          if (mounted && generation == _searchGeneration) {
            setState(() => _results = results);
          }
        },
        onMusicAvailability: (available) {
          _musicAvailable = available;
        },
      );
      if (!mounted || generation != _searchGeneration) return;
      await library.rememberSearch(q);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = results;
        _loading = false;
      });
      if (results.isEmpty)
        showAppNotice('No results. Check your connection or try another song.');
    } catch (e) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _loading = false;
        _error = 'Search failed: $e';
        _results = <Song>[];
      });
    }
  }

  Future<void> _voiceSearch() async {
    if (_listening) {
      await _speech.stop();
      if (mounted) setState(() => _listening = false);
      return;
    }
    final bool ready = await _speech.initialize();
    if (!ready) {
      showAppNotice('Voice search is not available on this device.');
      return;
    }
    setState(() => _listening = true);
    await _speech.listen(
      onResult: (result) {
        final String words = result.recognizedWords.trim();
        if (words.isEmpty) return;
        _controller.text = words;
        if (result.finalResult) {
          _speech.stop();
          if (mounted) setState(() => _listening = false);
          _runSearch(words);
        }
      },
    );
  }

  @override
  void dispose() {
    _speech.cancel();
    _debounce?.cancel();
    _cancel?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final SaxifyAccent accent = context.accent;
    final PlaybackService playback = context.read<PlaybackService>();
    final LocalMusicService localMusic = context.watch<LocalMusicService>();
    final List<Song> localResults = _kind == _SearchKind.songs
        ? localMusic.search(_activeQuery, limit: 8)
        : <Song>[];
    final bool idle = _activeQuery.isEmpty && !_loading && _error == null;

    return AuroraBackdrop(
      intensity: 0.5,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: SafeArea(
          bottom: false,
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        textInputAction: TextInputAction.search,
                        onSubmitted: _runSearch,
                        onChanged: (value) {
                          _debounce?.cancel();
                          _cancel?.cancel();
                          _searchGeneration++;
                          setState(() {
                            _results = [];
                            _browseResults = [];
                            _loading = false;
                            _activeQuery = '';
                            _error = null;
                          });
                          if (value.trim().isNotEmpty) {
                            _debounce = Timer(
                              const Duration(milliseconds: 300),
                              () => _runSearch(value),
                            );
                          }
                        },
                        style: const TextStyle(fontSize: 14),
                        decoration: InputDecoration(
                          hintText: 'Songs, artists, albums, moods…',
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: accent.primary,
                          ),
                          suffixIcon: _controller.text.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: SaxifyColors.textFaint,
                                  ),
                                  onPressed: () {
                                    _debounce?.cancel();
                                    _cancel?.cancel();
                                    _searchGeneration++;
                                    _controller.clear();
                                    setState(() {
                                      _loading = false;
                                      _browseResults = [];
                                      _results = <Song>[];
                                      _activeQuery = '';
                                      _error = null;
                                    });
                                  },
                                ),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Voice search',
                      icon: Icon(
                        _listening ? Icons.mic_rounded : Icons.mic_none_rounded,
                        color: _listening ? Colors.redAccent : SaxifyColors.textFaint,
                      ),
                      onPressed: _voiceSearch,
                    ),
                    IconButton(
                      tooltip: 'Search',
                      icon: Icon(
                        Icons.arrow_forward_rounded,
                        color: accent.primary,
                      ),
                      onPressed: () => _runSearch(_controller.text),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 40,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: <Widget>[
                    for (final _SearchKind kind in _SearchKind.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_kindLabel(kind)),
                          selected: _kind == kind,
                          onSelected: (_) {
                            setState(() => _kind = kind);
                            if (_controller.text.trim().isNotEmpty) {
                              _runSearch(_controller.text);
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _loading && _results.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? EmptyState(
                        icon: Icons.cloud_off_rounded,
                        title: 'Something went wrong',
                        message: _error,
                        actionLabel: 'Try again',
                        onAction: () => _runSearch(_activeQuery),
                      )
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 140),
                        children: <Widget>[
                          if (library.recentSearches.isNotEmpty && idle)
                            _RecentSearches(
                              queries: library.recentSearches.take(8).toList(),
                              onTap: (String q) {
                                _controller.text = q;
                                _runSearch(q);
                              },
                              onRemove: library.removeSearch,
                              onClear: library.clearSearchHistory,
                            ),
                          if (idle) const _ExploreMusic(),
                          if (_loading) const LinearProgressIndicator(),
                          if (!idle &&
                              !_loading &&
                              localResults.isEmpty &&
                              _results.isEmpty &&
                              _browseResults.isEmpty)
                            const EmptyState(
                              icon: Icons.search_off,
                              title: 'No results',
                              message:
                                  'Check your connection or try another song.',
                            ),
                          if (!_musicAvailable)
                            const Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'ifallertzia server unavailable — showing backup results',
                                style: TextStyle(
                                  color: Colors.grey,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          if (localResults.isNotEmpty) ...<Widget>[
                            const SectionHeader(
                              title: 'On device',
                              subtitle: 'Songs saved on this phone',
                            ),
                            for (int i = 0; i < localResults.length; i++)
                              SongTile(
                                song: localResults[i],
                                showMenu: false,
                                subtitle: 'On device · ${localResults[i].artist}',
                                onTap: () => playback.playQueue(
                                  localResults,
                                  startIndex: i,
                                ),
                              ),
                          ],
                          for (final item in _browseResults)
                            ListTile(
                              leading: Artwork(url: item.artwork, size: 52),
                              title: Text(item.title),
                              subtitle: Text('ifallertzia server · ${item.kind}'),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => MusicBrowseScreen(item: item),
                                ),
                              ),
                            ),
                          if (_results.isNotEmpty) ...<Widget>[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                              child: Row(
                                children: <Widget>[
                                  Expanded(
                                    child: Text(
                                      '${_results.length} results for "$_activeQuery"',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: GoogleFonts.spaceGrotesk(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: SaxifyColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: () =>
                                        playback.playRadio(_results.first),
                                    icon: const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 18,
                                    ),
                                    label: const Text(
                                      'Start radio',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            for (final section in [
                              'ifallertzia server',
                              'Videos',
                              'More results',
                            ])
                              if (_section(section).isNotEmpty) ...[
                                SectionHeader(
                                  title: section,
                                  subtitle: section == 'ifallertzia server'
                                      ? 'Album-quality source audio'
                                      : null,
                                ),
                                for (final song in _section(section))
                                  SongTile(
                                    song: song,
                                    startRadio: true,
                                    onTap: () => playback.playRadio(song),
                                  ),
                              ],
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Song> _section(String section) => _results
      .where(
        (s) => section == 'More results'
            ? s.source == TrackSource.youtube
            : s.source == TrackSource.ytMusic &&
                  (section == 'ifallertzia server'
                      ? s.quality == QualityTier.high
                      : s.quality != QualityTier.high),
      )
      .toList();

  String _kindLabel(_SearchKind kind) {
    switch (kind) {
      case _SearchKind.songs:
        return 'Songs';
      case _SearchKind.artists:
        return 'Artists';
      case _SearchKind.albums:
        return 'Albums';
      case _SearchKind.playlists:
        return 'Playlists';
    }
  }
}

class _RecentSearches extends StatelessWidget {
  const _RecentSearches({
    required this.queries,
    required this.onTap,
    required this.onRemove,
    required this.onClear,
  });

  final List<String> queries;
  final ValueChanged<String> onTap;
  final ValueChanged<String> onRemove;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                'PREVIOUS SEARCHES',
                style: TextStyle(
                  fontSize: 10,
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w700,
                  color: context.accent.primary,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: onClear,
                child: const Text(
                  'Clear all',
                  style: TextStyle(fontSize: 12, color: SaxifyColors.textMuted),
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final String q in queries)
                InputChip(
                  label: Text(q, style: const TextStyle(fontSize: 12)),
                  onPressed: () => onTap(q),
                  onDeleted: () => onRemove(q),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ExploreMusic extends StatelessWidget {
  const _ExploreMusic();

  static const List<(String, String)> _featured = <(String, String)>[
    ('Trending India', 'Hindi trending songs India 2026'),
    ('Top Bollywood', 'top Hindi Bollywood songs India'),
    ('New Hindi', 'latest Hindi songs 2026'),
    ('Punjabi Hits', 'Punjabi trending songs India'),
    ('Devotional', 'Hindi bhajan devotional songs'),
    ('Osho', 'Osho meditation music discourse'),
  ];

  @override
  Widget build(BuildContext context) {
    final ShellController shell = context.read<ShellController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader(
          title: 'Explore Music',
          subtitle: 'India-first stations, ready before you search',
        ),
        const SectionHeader(
          title: 'Charts & Discoveries',
          padding: EdgeInsets.fromLTRB(20, 12, 20, 10),
        ),
        MoodGenreGrid(
          items: _featured,
          onSelected: (String query) => shell.goSearch(query),
        ),
        const SectionHeader(title: 'Moods & Genres'),
        MoodGenreGrid(
          items: HomeCatalog.moodGenres,
          onSelected: (String query) => shell.goSearch(query),
        ),
        const SectionHeader(title: 'New releases'),
        HorizontalRail(
          height: 210,
          itemCount: HomeCatalog.newReleases.length,
          builder: (BuildContext context, int i) {
            final AlbumCard album = HomeCatalog.newReleases[i];
            return AlbumTile(
              coverUrl: album.coverUrl,
              title: album.title,
              artist: album.artist,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => AlbumPage(album: album),
                ),
              ),
            );
          },
        ),
        const SectionHeader(title: 'Music brands'),
        SizedBox(
          height: 50,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: MusicBrands.all.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (BuildContext context, int i) {
              final brand = MusicBrands.all[i];
              return MoodChip(
                label: brand.name,
                icon: Icons.album_outlined,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BrandChannelPage(brand: brand),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
