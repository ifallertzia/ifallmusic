import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../../core/models/song.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/home_catalog.dart';
import '../../core/services/library_service.dart';
import '../../core/services/local_music_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/recommendation_service.dart';
import '../../core/services/youtube_service.dart';
import '../../core/theme/ifall_ui.dart';
import '../../data/labels.dart';
import '../../screens/music_browse_screen.dart';
import '../../services/yt_music_parser.dart';
import '../../services/yt_music_service.dart';
import '../artist/artist_router.dart';
import '../shell/ifall_shell.dart';
import '../shell/shell_controller.dart';
import '../widgets/artwork.dart';
import '../widgets/song_tile.dart';
import '../../widgets/brand_logo.dart';

/// What the result list is filtering for.
enum SearchKind { songs, artists, albums, playlists }

String searchKindLabel(SearchKind kind) => switch (kind) {
      SearchKind.songs => 'Songs',
      SearchKind.artists => 'Artists',
      SearchKind.albums => 'Albums',
      SearchKind.playlists => 'Playlists',
    };

/// **Search** — song-focused results biased toward the listener's own music,
/// plus one-tap mood/genre stations and the label channels.
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
  List<MusicBrowseItem> _browseResults = <MusicBrowseItem>[];
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
  SearchKind _kind = SearchKind.songs;

  String? _stationLabel;
  String? _stationQuery;
  int _lastStationNonce = -1;

  @override
  void initState() {
    super.initState();
    final String? initial = widget.initialQuery;
    if (initial != null && initial.isNotEmpty) {
      _controller.text = initial;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _runSearch(initial);
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Listen to the shell, not just read it: mood buttons and Show all update
    // an IndexedStack child without changing its route or remounting it.
    final ShellController shell = Provider.of<ShellController>(context);
    if (shell.stationNonce != _lastStationNonce) {
      _lastStationNonce = shell.stationNonce;
      final String? label = shell.stationLabel;
      final String? stationQuery = shell.stationQuery;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (label == null || label.isEmpty) {
          _closeStation();
          return;
        }
        _loadStation(label, stationQuery ?? label);
      });
    }
    if (shell.queryNonce == _lastNonce) return;
    _lastNonce = shell.queryNonce;
    final String? query = shell.pendingQuery;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (query == null || query.trim().isEmpty) {
        _reset();
        return;
      }
      _controller.text = query;
      _runSearch(query);
    });
  }

  void _reset() {
    _searchGeneration++;
    _debounce?.cancel();
    _cancel?.cancel();
    _browseResults = <MusicBrowseItem>[];
    _controller.clear();
    setState(() {
      _stationLabel = null;
      _stationQuery = null;
      _results = <Song>[];
      _activeQuery = '';
      _error = null;
      _loading = false;
    });
  }

  // ---------------------------------------------------------------- stations
  /// Opens a mood/genre station.
  ///
  /// Nothing here looks like a search: the box is cleared, the listener sees
  /// the station's name, and the tracks are fetched with the very same search
  /// call the app always used — just never echoed back as a query.
  Future<void> _loadStation(String label, String query) async {
    _debounce?.cancel();
    _cancel?.cancel('superseded');
    _cancel = CancelToken();
    final int generation = ++_searchGeneration;
    setState(() {
      _kind = SearchKind.songs;
      _stationLabel = label;
      _stationQuery = query;
      _controller.clear();
      _focusNode.unfocus();
      _activeQuery = '';
      _browseResults = <MusicBrowseItem>[];
      _results = <Song>[];
      _error = null;
      _loading = true;
    });
    try {
      final YoutubeService youtube = context.read<YoutubeService>();
      final LibraryService library = context.read<LibraryService>();
      context.read<RecommendationService>().noteSearch(query);
      final List<Song> results = await youtube.searchSongs(
        query,
        limit: 60,
        cancelToken: _cancel,
        onPartial: (List<Song> partial) {
          if (mounted && generation == _searchGeneration) {
            setState(() => _results = partial);
          }
        },
        onMusicAvailability: (bool available) => _musicAvailable = available,
      );
      if (!mounted || generation != _searchGeneration) return;
      await library.rememberSearch(query);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _loading = false;
        _error = 'Could not load $label right now.';
        _results = <Song>[];
      });
    }
  }

  void _closeStation() {
    _searchGeneration++;
    _debounce?.cancel();
    _cancel?.cancel();
    setState(() {
      _stationLabel = null;
      _stationQuery = null;
      _results = <Song>[];
      _browseResults = <MusicBrowseItem>[];
      _activeQuery = '';
      _error = null;
      _loading = false;
    });
  }

  void _leaveStation() {
    _closeStation();
    context.read<ShellController>().clearStation();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  Future<void> _runSearch(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return;
    _stationLabel = null;
    _stationQuery = null;

    _debounce?.cancel();
    _cancel?.cancel('superseded');
    _cancel = CancelToken();
    final int generation = ++_searchGeneration;
    setState(() {
      _loading = true;
      _error = null;
      _activeQuery = q;
      _results = <Song>[];
      _browseResults = <MusicBrowseItem>[];
      _musicAvailable = true;
    });

    try {
      final YoutubeService youtube = context.read<YoutubeService>();
      final LibraryService library = context.read<LibraryService>();
      final RecommendationService reco = context.read<RecommendationService>();
      reco.noteSearch(q);
      if (_kind != SearchKind.songs) {
        final MusicSearchResult result = await youtube.music.search(
          q,
          cancelToken: _cancel,
          filter: _kind == SearchKind.albums
              ? YtMusicService.albumsFilter
              : _kind == SearchKind.artists
                  ? YtMusicService.artistsFilter
                  : null,
        );
        if (!mounted || generation != _searchGeneration) return;
        final String kind = _kind == SearchKind.artists
            ? 'artist'
            : _kind == SearchKind.albums
                ? 'album'
                : 'playlist';
        setState(() {
          _browseResults =
              result.items.where((MusicBrowseItem i) => i.kind == kind).toList();
          _loading = false;
        });
        await library.rememberSearch(q);
        return;
      }
      final List<Song> results = await youtube.searchSongs(
        q,
        limit: 60,
        cancelToken: _cancel,
        onPartial: (List<Song> partial) {
          if (mounted && generation == _searchGeneration) {
            setState(() => _results = partial);
          }
        },
        onMusicAvailability: (bool available) => _musicAvailable = available,
      );
      if (!mounted || generation != _searchGeneration) return;
      await library.rememberSearch(q);
      if (!mounted || generation != _searchGeneration) return;
      setState(() {
        _results = results;
        _loading = false;
      });
      if (results.isEmpty) {
        showAppNotice('No results. Check your connection or try another song.');
      }
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
    final IfallPalette c = IfallPalette.of(context);
    final LibraryService library = context.watch<LibraryService>();
    final PlaybackService playback = context.read<PlaybackService>();
    final LocalMusicService localMusic = context.watch<LocalMusicService>();
    final List<Song> localResults = _kind == SearchKind.songs
        ? localMusic.search(_activeQuery, limit: 8)
        : <Song>[];
    final bool idle = _activeQuery.isEmpty && !_loading && _error == null;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Text(
                'Search',
                style: IfallText.display(c.onSurface),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: _SearchField(
                controller: _controller,
                focusNode: _focusNode,
                listening: _listening,
                accent: c.accent,
                surface: c.glass,
                hint: c.onSurfaceVariant,
                ink: c.onSurface,
                outline: c.outline,
                onSubmitted: _runSearch,
                onChanged: (String value) {
                  _debounce?.cancel();
                  _cancel?.cancel();
                  _searchGeneration++;
                  setState(() {
                    _stationLabel = null;
                    _stationQuery = null;
                    _results = <Song>[];
                    _browseResults = <MusicBrowseItem>[];
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
                onClear: _reset,
                onVoice: _voiceSearch,
              ),
            ),
            // The kind chips belong to searching; a station has no filter row,
            // it simply is its own list.
            if (_stationLabel == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: IfallChipRow(
                  labels: SearchKind.values.map(searchKindLabel).toList(),
                  selected: searchKindLabel(_kind),
                  onSelected: (String label) {
                    setState(() {
                      _kind = SearchKind.values.firstWhere(
                        (SearchKind k) => searchKindLabel(k) == label,
                        orElse: () => SearchKind.songs,
                      );
                    });
                    if (_controller.text.trim().isNotEmpty) {
                      _runSearch(_controller.text);
                    }
                  },
                ),
              ),
            Expanded(
              child: _stationLabel != null
                  ? _StationBody(
                      label: _stationLabel!,
                      subtitle: _loading && _results.isEmpty
                          ? 'Tuning the station…'
                          : '${_results.length} songs · playing from this station',
                      loading: _loading && _results.isEmpty,
                      error: _error,
                      songs: _results,
                      onPlay: () => playback.playQueue(_results, startIndex: 0),
                      onRefresh: () => _loadStation(
                        _stationLabel!,
                        _stationQuery ?? _stationLabel!,
                      ),
                      onClose: _leaveStation,
                    )
                  : _loading && _results.isEmpty
                      ? Center(
                          child: CircularProgressIndicator(color: c.accent),
                        )
                      : _error != null
                          ? IfallEmpty(
                              icon: Icons.cloud_off_rounded,
                              message: _error!,
                              actionLabel: 'Try again',
                              action: () => _runSearch(_activeQuery),
                            )
                          : _ResultsList(
                              idle: idle,
                              loading: _loading,
                              activeQuery: _activeQuery,
                              results: _results,
                              browseResults: _browseResults,
                              localResults: localResults,
                              musicAvailable: _musicAvailable,
                              recentSearches: library.recentSearches,
                              onRecentTap: (String q) {
                                _controller.text = q;
                                _runSearch(q);
                              },
                              onRecentRemove: library.removeSearch,
                              onRecentClear: library.clearSearchHistory,
                              onStartRadio: _results.isEmpty
                                  ? null
                                  : () => playback.playRadio(_results.first),
                            ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.listening,
    required this.accent,
    required this.surface,
    required this.hint,
    required this.ink,
    required this.outline,
    required this.onSubmitted,
    required this.onChanged,
    required this.onClear,
    required this.onVoice,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool listening;
  final Color accent;
  final Color surface;
  final Color hint;
  final Color ink;
  final Color outline;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final VoidCallback onVoice;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(IfallUI.rMd),
        border: Border.all(color: outline.withValues(alpha: 0.8)),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 12),
          Icon(Icons.search_rounded, size: 20, color: hint),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              onChanged: onChanged,
              style: IfallText.body(ink),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hintText: 'Songs, artists, albums, moods…',
                hintStyle: IfallText.body(hint),
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded, size: 18),
              color: hint,
              visualDensity: VisualDensity.compact,
            ),
          IconButton(
            onPressed: onVoice,
            icon: Icon(
              listening ? Icons.mic_rounded : Icons.mic_none_rounded,
              size: 20,
            ),
            color: listening ? IfallColors.accentRed : hint,
            tooltip: 'Voice search',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- station body

class _StationBody extends StatelessWidget {
  const _StationBody({
    required this.label,
    required this.subtitle,
    required this.loading,
    required this.songs,
    required this.onPlay,
    required this.onRefresh,
    required this.onClose,
    this.error,
  });

  final String label;
  final String subtitle;
  final bool loading;
  final List<Song> songs;
  final VoidCallback onPlay;
  final VoidCallback onRefresh;
  final VoidCallback onClose;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final PlaybackService playback = context.read<PlaybackService>();
    final int index0 = label.hashCode.abs() % 8;
    final Color tone = _tones[index0];

    return ListView(
      padding: EdgeInsets.only(bottom: IfallInsets.bottom),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: IfallGlass(
            radius: IfallUI.rXl,
            blur: 0,
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(IfallUI.rMd),
                    gradient: LinearGradient(
                      colors: <Color>[
                        tone.withValues(alpha: 0.9),
                        tone.withValues(alpha: 0.5),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.radio_rounded,
                    color: Colors.white,
                    size: 26,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  label,
                  style: IfallText.style(
                    24,
                    weight: FontWeight.w800,
                    letterSpacing: -0.7,
                    color: c.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(subtitle, style: IfallText.caption(c.onSurfaceVariant)),
                if (error != null) ...<Widget>[
                  const SizedBox(height: 10),
                  Text(
                    error!,
                    style: IfallText.caption(
                      c.isDark ? IfallColors.dangerLight : const Color(0xFFFF3B30),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: <Widget>[
                    _StationButton(
                      label: 'Play station',
                      icon: Icons.play_arrow_rounded,
                      filled: true,
                      enabled: songs.isNotEmpty,
                      onTap: onPlay,
                    ),
                    const SizedBox(width: 10),
                    _StationButton(
                      label: 'Refresh',
                      icon: Icons.refresh_rounded,
                      onTap: onRefresh,
                    ),
                    const SizedBox(width: 10),
                    _StationButton(
                      label: 'Close',
                      icon: Icons.close_rounded,
                      onTap: onClose,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (loading)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: LinearProgressIndicator(color: c.accent, minHeight: 2),
          ),
        for (int i = 0; i < songs.length; i++)
          SongTile(
            song: songs[i],
            startRadio: true,
            onTap: () => playback.playQueue(songs, startIndex: i),
          ),
      ],
    );
  }
}

const List<Color> _tones = <Color>[
  Color(0xFF7C3AED),
  Color(0xFFEC4899),
  Color(0xFF2563EB),
  Color(0xFF059669),
  Color(0xFFEA580C),
  Color(0xFF0891B2),
  Color(0xFFDB2777),
  Color(0xFF65A30D),
];

class _StationButton extends StatelessWidget {
  const _StationButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final Color ink = filled
        ? (ThemeData.estimateBrightnessForColor(c.accent) == Brightness.dark
            ? Colors.white
            : Colors.black)
        : c.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(IfallUI.rPill),
        child: Opacity(
          opacity: enabled ? 1 : 0.4,
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: filled ? c.accent : c.glass,
              borderRadius: BorderRadius.circular(IfallUI.rPill),
              border: Border.all(
                color: filled ? c.accent : c.outline.withValues(alpha: 0.9),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(icon, size: 16, color: ink),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: IfallText.caption(ink).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------- results

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.idle,
    required this.loading,
    required this.activeQuery,
    required this.results,
    required this.browseResults,
    required this.localResults,
    required this.musicAvailable,
    required this.recentSearches,
    required this.onRecentTap,
    required this.onRecentRemove,
    required this.onRecentClear,
    this.onStartRadio,
  });

  final bool idle;
  final bool loading;
  final String activeQuery;
  final List<Song> results;
  final List<MusicBrowseItem> browseResults;
  final List<Song> localResults;
  final bool musicAvailable;
  final List<String> recentSearches;
  final ValueChanged<String> onRecentTap;
  final ValueChanged<String> onRecentRemove;
  final VoidCallback onRecentClear;
  final VoidCallback? onStartRadio;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final PlaybackService playback = context.read<PlaybackService>();

    return ListView(
      padding: EdgeInsets.only(bottom: IfallInsets.bottom),
      children: <Widget>[
        if (recentSearches.isNotEmpty && idle)
          _RecentSearches(
            queries: recentSearches.take(8).toList(),
            onTap: onRecentTap,
            onRemove: onRecentRemove,
            onClear: onRecentClear,
          ),
        if (idle) const _ExploreMusic(),
        if (loading) LinearProgressIndicator(color: c.accent, minHeight: 2),
        if (!idle &&
            !loading &&
            localResults.isEmpty &&
            results.isEmpty &&
            browseResults.isEmpty)
          const IfallEmpty(
            icon: Icons.search_off_rounded,
            message: 'Check your connection or try another song.',
          ),
        if (!musicAvailable)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Music service unavailable — showing backup results',
              style: IfallText.caption(c.onSurfaceVariant),
            ),
          ),
        if (localResults.isNotEmpty) ...<Widget>[
          const IfallSectionHeader(
            title: 'On device',
            subtitle: 'Songs saved on this phone',
          ),
          for (int i = 0; i < localResults.length; i++)
            SongTile(
              song: localResults[i],
              showMenu: false,
              subtitle: 'On device · ${localResults[i].artist}',
              onTap: () => playback.playQueue(localResults, startIndex: i),
            ),
        ],
        for (final MusicBrowseItem item in browseResults)
          ListTile(
            leading: Artwork(url: item.artwork, size: 50),
            title: Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: IfallText.body(c.onSurface),
            ),
            subtitle: Text(item.kind, style: IfallText.caption(c.onSurfaceVariant)),
            trailing: Icon(
              Icons.chevron_right_rounded,
              color: c.onSurfaceVariant,
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (BuildContext c2) => MusicBrowseScreen(item: item),
              ),
            ),
          ),
        if (results.isNotEmpty) ...<Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '${results.length} results for “$activeQuery”',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IfallText.caption(c.onSurfaceVariant),
                  ),
                ),
                if (onStartRadio != null)
                  TextButton.icon(
                    onPressed: onStartRadio,
                    icon: const Icon(Icons.play_arrow_rounded, size: 17),
                    label: const Text('Start radio'),
                  ),
              ],
            ),
          ),
          for (int i = 0; i < results.length; i++)
            SongTile(
              song: results[i],
              onTap: () => playback.playQueue(results, startIndex: i),
            ),
        ],
      ],
    );
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
    final IfallPalette c = IfallPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        IfallSectionHeader(
          title: 'Recent searches',
          seeAllLabel: 'Clear',
          onSeeAll: onClear,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: <Widget>[
              for (final String q in queries)
                InputChip(
                  label: Text(q, style: IfallText.caption(c.onSurface)),
                  backgroundColor: c.glass,
                  side: BorderSide(color: c.outline.withValues(alpha: 0.7)),
                  deleteIconColor: c.onSurfaceVariant,
                  onPressed: () => onTap(q),
                  onDeleted: () => onRemove(q),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// The browse grid shown while nothing has been typed.
class _ExploreMusic extends StatelessWidget {
  const _ExploreMusic();

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final ShellController shell = context.read<ShellController>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const IfallSectionHeader(
          title: 'Browse music',
          subtitle: 'Tap a mood to start a station',
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: <Widget>[
              for (final (String label, String query) in HomeCatalog.moodGenres)
                _ExploreTile(
                  label: label,
                  onTap: () => shell.goStation(label, query),
                ),
            ],
          ),
        ),
        const IfallSectionHeader(
          title: 'Music brands',
          subtitle: 'Official label channels',
        ),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: MusicBrands.all.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (BuildContext context, int i) {
              final MusicBrand brand = MusicBrands.all[i];
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(IfallUI.rMd),
                  onTap: () => openArtistByName(
                    context,
                    name: brand.name,
                    channelId: brand.channelId,
                  ),
                  child: SizedBox(
                    width: 96,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        BrandLogo(brand: brand, size: 44),
                        const SizedBox(height: 8),
                        Text(
                          brand.name,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: IfallText.caption(c.onSurfaceVariant),
                        ),
                      ],
                    ),
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

class _ExploreTile extends StatelessWidget {
  const _ExploreTile({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final Color tone = _tones[label.hashCode.abs() % _tones.length];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(IfallUI.rMd),
        child: Container(
          width: (MediaQuery.sizeOf(context).width - 44) / 2,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(IfallUI.rMd),
            gradient: LinearGradient(
              colors: <Color>[
                tone.withValues(alpha: 0.85),
                tone.withValues(alpha: 0.45),
              ],
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      IfallText.body(Colors.white).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}
