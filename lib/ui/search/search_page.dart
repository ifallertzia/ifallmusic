import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/youtube_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../../services/yt_music_parser.dart';
import '../../services/yt_music_service.dart';
import '../artist/artist_page.dart';
import '../explore/explore_page.dart';
import '../shell/sidify_routes.dart';
import '../shell/sidify_shell_controller.dart';
import '../widgets/sidify_widgets.dart';

/// Search, as the site does it: one field, chips for Top results / Songs /
/// Albums / Artists, recent searches when the field is empty, and browse
/// categories underneath. Results stream in as the catalogue answers.
class SearchPage extends StatefulWidget {
  const SearchPage({super.key});

  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  String _term = '';
  String _tab = 'all';
  int _shellNonce = 0;

  List<Song> _songs = <Song>[];
  List<MusicBrowseItem> _albums = <MusicBrowseItem>[];
  List<MusicBrowseItem> _artists = <MusicBrowseItem>[];
  bool _loading = false;
  bool _failed = false;
  int _requestId = 0;

  static const List<(String, String)> _tabs = <(String, String)>[
    ('all', 'Top results'),
    ('songs', 'Songs'),
    ('albums', 'Albums'),
    ('artists', 'Artists'),
  ];

  @override
  void initState() {
    super.initState();
    MoodCoverCatalog.instance.addListener(_coversChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focus.requestFocus();
      MoodCoverCatalog.instance.ensure(context.read<YoutubeService>());
    });
  }

  @override
  void dispose() {
    MoodCoverCatalog.instance.removeListener(_coversChanged);
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _coversChanged() {
    if (mounted) setState(() {});
  }

  void _adoptShellQuery(SidifyShellController shell) {
    if (shell.searchNonce == _shellNonce) return;
    _shellNonce = shell.searchNonce;
    if (shell.searchQuery.isEmpty) return;
    _controller.text = shell.searchQuery;
    _controller.selection =
        TextSelection.collapsed(offset: _controller.text.length);
    _run(shell.searchQuery.trim());
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      _run(value.trim());
    });
  }

  Future<void> _run(String term) async {
    if (term == _term && term.isNotEmpty) return;
    setState(() {
      _term = term;
      _failed = false;
      if (term.isEmpty) {
        _songs = <Song>[];
        _albums = <MusicBrowseItem>[];
        _artists = <MusicBrowseItem>[];
        _loading = false;
      } else {
        _loading = true;
      }
    });
    if (term.isEmpty) return;
    final int id = ++_requestId;
    final YoutubeService youtube = context.read<YoutubeService>();
    // The three shelves load side by side; each handles its own errors.
    _loadSongs(youtube, term, id);
    _loadBrowse(youtube, term, id, albums: true);
    _loadBrowse(youtube, term, id, albums: false);
  }

  Future<void> _loadSongs(YoutubeService youtube, String term, int id) async {
    try {
      final List<Song> results = await youtube.searchSongs(
        term,
        limit: 30,
        onPartial: (List<Song> partial) {
          if (mounted && id == _requestId && partial.isNotEmpty) {
            setState(() {
              _songs = partial;
              _loading = false;
            });
          }
        },
      );
      if (!mounted || id != _requestId) return;
      setState(() {
        _songs = results;
        _loading = false;
      });
      if (results.isNotEmpty) {
        context.read<LibraryService>().rememberSearch(term);
      }
    } catch (_) {
      if (mounted && id == _requestId) {
        setState(() {
          _loading = false;
          _failed = _songs.isEmpty;
        });
      }
    }
  }

  Future<void> _loadBrowse(
    YoutubeService youtube,
    String term,
    int id, {
    required bool albums,
  }) async {
    try {
      final MusicSearchResult result = await youtube.music.search(
        term,
        filter: albums
            ? YtMusicService.albumsFilter
            : YtMusicService.artistsFilter,
      );
      if (!mounted || id != _requestId) return;
      final String kind = albums ? 'album' : 'artist';
      setState(() {
        final List<MusicBrowseItem> items = result.items
            .where((MusicBrowseItem i) => i.kind == kind)
            .toList();
        if (albums) {
          _albums = items;
        } else {
          _artists = items;
        }
      });
    } catch (_) {
      // A missing shelf never fails the search.
    }
  }

  @override
  Widget build(BuildContext context) {
    _adoptShellQuery(context.watch<SidifyShellController>());
    final SidifyTokens t = context.sidify;
    return SafeArea(
      bottom: false,
      child: Column(
        children: <Widget>[
          const PageTitle('Search'),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: t.fill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.edge, width: 0.5),
              ),
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 12),
                  Icon(Icons.search_rounded, size: 19, color: t.text2),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      focusNode: _focus,
                      onChanged: _onChanged,
                      onSubmitted: (String v) => _run(v.trim()),
                      style: TextStyle(fontSize: 16, color: t.text),
                      decoration: InputDecoration(
                        hintText: 'Songs, albums, artists…',
                        hintStyle: TextStyle(color: t.text2),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  if (_controller.text.isNotEmpty)
                    IconButton(
                      icon: Icon(Icons.close_rounded, size: 18, color: t.text2),
                      onPressed: () {
                        _controller.clear();
                        _run('');
                      },
                    ),
                ],
              ),
            ),
          ),
          if (_term.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SidifyChips(
                value: _tab,
                options: _tabs,
                onChanged: (String v) => setState(() => _tab = v),
              ),
            ),
          Expanded(
            child: _term.isEmpty
                ? _emptyState(context)
                : _results(context),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final SidifyTokens t = context.sidify;
    final List<String> history = library.recentSearches;
    return ListView(
      padding: const EdgeInsets.only(bottom: 190),
      physics: const BouncingScrollPhysics(),
      children: <Widget>[
        if (history.isNotEmpty) ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Recent searches',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: library.clearSearchHistory,
                  child: Text('Clear', style: TextStyle(color: t.text2)),
                ),
              ],
            ),
          ),
          for (final String q in history)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {
                  _controller.text = q;
                  _run(q);
                },
                child: Container(
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: <Widget>[
                      Icon(Icons.history_rounded, size: 19, color: t.text2),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          q,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 15.5, color: t.text),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, size: 16, color: t.text2),
                        onPressed: () => library.removeSearch(q),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 20),
        ],
        const SectionHeader(title: 'Browse categories'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.72,
            ),
            itemCount: kSidifyMoods.length + kSidifyGenres.length,
            itemBuilder: (BuildContext context, int i) {
              final List<SidifyMood> all = <SidifyMood>[
                ...kSidifyMoods,
                ...kSidifyGenres,
              ];
              final SidifyMood m = all[i];
              return MoodCard(
                title: m.title,
                colorHex: m.color,
                artwork: MoodCoverCatalog.instance.coverFor(m),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ExploreMoodPage(mood: m),
                    settings: const RouteSettings(name: 'sidify/mood'),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _results(BuildContext context) {
    if (_loading && _songs.isEmpty && _albums.isEmpty && _artists.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_failed) {
      return EmptyState(
        icon: Icons.cloud_off_rounded,
        title: 'Search did not answer',
        desc: 'Check the connection and try again.',
        action: SidifyButton(
          label: 'Try again',
          variant: SidifyButtonVariant.secondary,
          small: true,
          onTap: () {
            final String term = _term;
            _term = '';
            _run(term);
          },
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 190),
      physics: const BouncingScrollPhysics(),
      children: <Widget>[
        if (_tab == 'all' || _tab == 'songs') ...<Widget>[
          if (_songs.isNotEmpty)
            const SectionHeader(title: 'Songs')
          else if (_tab == 'songs')
            const EmptyState(
              icon: Icons.music_off_rounded,
              title: 'No songs found',
              desc: 'Try a different spelling or another song.',
            ),
          for (int i = 0;
              i < _songs.length && (_tab == 'songs' || i < 8);
              i++)
            TrackRow(tracks: _songs, index: i),
          const SizedBox(height: 24),
        ],
        if ((_tab == 'all' || _tab == 'albums') && _albums.isNotEmpty) ...<Widget>[
          ShelfSection(
            title: 'Albums',
            children: <Widget>[
              for (final MusicBrowseItem item in _albums)
                SquareCard(
                  title: item.title,
                  artwork: item.artwork,
                  onTap: () => openBrowse(context, item),
                ),
            ],
          ),
        ],
        if ((_tab == 'all' || _tab == 'artists') && _artists.isNotEmpty)
          ShelfSection(
            title: 'Artists',
            children: <Widget>[
              for (final MusicBrowseItem item in _artists)
                ArtistCardWidget(
                  name: item.title,
                  imageUrl: item.artwork,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ArtistPage(
                        name: item.title,
                        channelId: item.id,
                      ),
                      settings: const RouteSettings(name: SidifyRoutes.artist),
                    ),
                  ),
                ),
            ],
          ),
        if (!_loading &&
            _songs.isEmpty &&
            _albums.isEmpty &&
            _artists.isEmpty)
          const EmptyState(
            icon: Icons.search_off_rounded,
            title: 'No results',
            desc: 'Nothing matched that search. Try another song, album or artist.',
          ),
      ],
    );
  }
}
