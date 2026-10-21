import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/album_card.dart';
import '../../core/models/artist.dart';
import '../../core/models/song.dart';
import '../../core/services/home_catalog.dart';
import '../../core/services/library_service.dart';
import '../../core/services/listen_together_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/youtube_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../../services/yt_music_parser.dart';
import '../artist/artist_page.dart';
import '../library/history_page.dart';
import '../library/liked_page.dart';
import '../settings/settings_page.dart';
import '../shell/sidify_routes.dart';
import '../shell/sidify_shell_controller.dart';
import '../widgets/sidify_widgets.dart';

/// Home, as the site lays it out: a small logo lockup and greeting, Top
/// picks heroes, Quick picks, Recently played, the Listen Together invite,
/// Recommended, New releases, Trending, Artists and From your Liked Songs.
///
/// The rails come from the same engine catalog the app has always used —
/// only the clothes are Sidify's now.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Song> _quick = <Song>[];
  String _quickSeedId = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeCatalog>().load();
    });
  }

  String get _greeting {
    final int h = DateTime.now().hour;
    if (h < 5) return 'Good night';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  void _seedQuickPicks(Song? seed, List<Song> fallback) {
    if (seed == null || seed.id == _quickSeedId) return;
    _quickSeedId = seed.id;
    context
        .read<YoutubeService>()
        .similarSongs(seed.id, limit: 16)
        .then((List<Song> songs) {
      if (!mounted) return;
      setState(() {
        _quick = songs.where((Song s) => s.id != seed.id).toList();
      });
    }).catchError((_) {
      if (mounted) setState(() => _quick = fallback);
    });
  }

  @override
  Widget build(BuildContext context) {
    final HomeCatalog catalog = context.watch<HomeCatalog>();
    final LibraryService library = context.watch<LibraryService>();
    final PlaybackService playback = context.watch<PlaybackService>();
    final SettingsService settings = context.watch<SettingsService>();

    final List<Song> recent = <Song>[
      for (final HistoryEntry e in library.history) e.song,
    ];
    final List<Song> liked = library.likedSongs;
    final Song? seed = playback.current ?? (recent.isNotEmpty ? recent.first : null);
    final List<Song> recommended = catalog.recommended;
    final List<Song> trending = catalog.trending;
    _seedQuickPicks(
      seed,
      <Song>[...recommended, ...trending],
    );
    final List<Song> quick = _quick.isNotEmpty
        ? _quick
        : <Song>[...recommended, ...trending].take(16).toList();

    final String firstName = settings.displayName.split(' ').first;
    final bool loading = catalog.loading && catalog.madeForYou.isEmpty;

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 190),
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          _header(context, firstName),
          if (loading)
            _loadingShelves()
          else ...<Widget>[
            _topPicks(context, catalog, liked, recent, seed, trending),
            if (quick.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    SectionHeader(
                      title: 'Quick picks',
                      subtitle:
                          seed != null ? 'Inspired by ${seed.title}' : 'Start here',
                    ),
                    QuickPicks(tracks: quick, label: 'Quick picks'),
                  ],
                ),
              ),
            if (recent.isNotEmpty)
              ShelfSection(
                title: 'Recently played',
                onMore: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const HistoryPage(),
                    settings: const RouteSettings(name: 'sidify/history'),
                  ),
                ),
                children: <Widget>[
                  for (int i = 0; i < recent.length && i < 20; i++)
                    SongCard(tracks: recent, index: i, label: 'Recently played'),
                ],
              ),
            _roomInvite(context),
            if (recommended.isNotEmpty)
              ShelfSection(
                title: 'Recommended for you',
                children: <Widget>[
                  for (int i = 0; i < recommended.length; i++)
                    SongCard(tracks: recommended, index: i, label: 'Recommended'),
                ],
              ),
            if (catalog.freshReleases.isNotEmpty)
              ShelfSection(
                title: 'New releases',
                children: <Widget>[
                  for (final item in catalog.freshReleases)
                    SquareCard(
                      title: item.title,
                      artwork: item.artwork,
                      onTap: () => openBrowse(context, item),
                    ),
                ],
              )
            else
              ShelfSection(
                title: 'New releases',
                children: <Widget>[
                  for (final AlbumCard a in HomeCatalog.newReleases)
                    AlbumCardWidget(
                      album: a,
                      onTap: () => openAlbum(context, a, musicOnly: true),
                    ),
                ],
              ),
            if (trending.isNotEmpty)
              ShelfSection(
                title: 'Trending now',
                children: <Widget>[
                  for (int i = 0; i < trending.length; i++)
                    SongCard(tracks: trending, index: i, label: 'Trending now'),
                ],
              ),
            if (catalog.madeForYou.isNotEmpty)
              ShelfSection(
                title: 'Made for you',
                children: <Widget>[
                  for (int i = 0; i < catalog.madeForYou.length; i++)
                    SongCard(
                      tracks: catalog.madeForYou,
                      index: i,
                      label: 'Made for you',
                    ),
                ],
              ),
            ShelfSection(
              title: 'Artists to follow',
              children: <Widget>[
                for (final ArtistRef a in HomeCatalog.topArtists)
                  ArtistCardWidget(
                    name: a.name,
                    imageUrl: catalog.photoFor(a.name, fallback: a.imageUrl),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArtistPage(
                          name: a.name,
                          channelId: a.channelId.isEmpty ? null : a.channelId,
                        ),
                        settings: const RouteSettings(name: SidifyRoutes.artist),
                      ),
                    ),
                  ),
              ],
            ),
            if (liked.isNotEmpty)
              ShelfSection(
                title: 'From your Liked Songs',
                onMore: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LikedSongsPage(),
                    settings: const RouteSettings(name: 'sidify/liked'),
                  ),
                ),
                children: <Widget>[
                  for (int i = 0; i < liked.length && i < 20; i++)
                    SongCard(tracks: liked, index: i, label: 'Liked Songs'),
                ],
              ),
          ],
          if (catalog.error != null && !loading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Some shelves could not load. Your library still works.',
                style: TextStyle(fontSize: 13, color: context.sidify.text2),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, String firstName) {
    final SidifyTokens t = context.sidify;
    final JamService jam = context.watch<JamService>();
    final SidifyShellController shell =
        context.read<SidifyShellController>();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const SidifyLogoMark(size: 22),
                    const SizedBox(width: 8),
                    Text(
                      'Sidify',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: t.text2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  firstName.isEmpty ? _greeting : '$_greeting, $firstName',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SidifyText.display(t.text),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: <Widget>[
                GestureDetector(
                  onTap: () => shell.goTogether(),
                  child: Container(
                    height: 36,
                    padding: EdgeInsets.symmetric(
                      horizontal: jam.isConnected ? 12 : 0,
                    ),
                    width: jam.isConnected ? null : 36,
                    decoration: BoxDecoration(
                      color: jam.isConnected ? t.brand : t.fill,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Icon(
                          Icons.people_rounded,
                          size: 18,
                          color: jam.isConnected ? Colors.white : t.text,
                        ),
                        if (jam.isConnected) ...<Widget>[
                          const SizedBox(width: 4),
                          Text(
                            '${jam.members.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SidifyIconButton(
                  icon: Icons.movie_creation_outlined,
                  label: 'Switch to movies',
                  tone: 'fill',
                  size: 36,
                  iconSize: 18,
                  onTap: () => shell.switchMode(),
                ),
                const SizedBox(width: 8),
                SidifyIconButton(
                  icon: Icons.settings_rounded,
                  label: 'Settings',
                  tone: 'fill',
                  size: 36,
                  iconSize: 18,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsPage(),
                      settings: const RouteSettings(name: SidifyRoutes.settings),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topPicks(
    BuildContext context,
    HomeCatalog catalog,
    List<Song> liked,
    List<Song> recent,
    Song? seed,
    List<Song> trending,
  ) {
    final PlaybackService playback = context.read<PlaybackService>();
    final List<Widget> heroes = <Widget>[];
    if (liked.isNotEmpty || recent.isNotEmpty) {
      heroes.add(
        HeroCard(
          eyebrow: 'Made for you',
          title: 'Your Mix',
          subtitle: 'Songs you love, and more like them',
          artwork: (liked.isNotEmpty ? liked.first : recent.first).thumbnailUrl,
          onTap: () {
            final List<Song> pool = <Song>[
              ...liked.take(40),
              ...recent.take(20),
              ...catalog.recommended.take(15),
            ]..shuffle();
            playback.playQueue(pool, startIndex: 0);
          },
        ),
      );
    }
    if (seed != null) {
      heroes.add(
        HeroCard(
          eyebrow: 'Because you listened to',
          title: seed.title,
          subtitle: '${seed.artist} · Song radio',
          artwork: seed.thumbnailUrl,
          onTap: () => playback.playRadio(seed),
        ),
      );
    }
    // Your top artist: the name you play most, from your own history.
    final Map<String, int> counts = <String, int>{};
    final Map<String, Song> byArtist = <String, Song>{};
    for (final HistoryEntry e in libraryHistory(context)) {
      counts[e.song.artist] = (counts[e.song.artist] ?? 0) + 1;
      byArtist[e.song.artist] = e.song;
    }
    String? topArtist;
    int best = 0;
    counts.forEach((String artist, int n) {
      if (n > best) {
        best = n;
        topArtist = artist;
      }
    });
    if (topArtist != null && topArtist != seed?.artist) {
      final Song s = byArtist[topArtist]!;
      heroes.add(
        HeroCard(
          eyebrow: 'Your top artist',
          title: '$topArtist Radio',
          subtitle: 'Their songs and similar music',
          artwork: s.thumbnailUrl,
          onTap: () => playback.playRadio(s),
        ),
      );
    }
    if (trending.isNotEmpty) {
      heroes.add(
        HeroCard(
          eyebrow: 'Trending',
          title: "Today's Hits",
          subtitle:
              trending.take(3).map((Song s) => s.artist).join(', '),
          artwork: trending.first.thumbnailUrl,
          onTap: () => playback.playQueue(trending, startIndex: 0),
        ),
      );
    }
    // New music: YouTube Music releases only — never plain YT video results.
    if (catalog.freshReleases.isNotEmpty) {
      for (final MusicBrowseItem item in catalog.freshReleases.take(2)) {
        heroes.add(
          HeroCard(
            eyebrow: 'New music',
            title: item.title,
            subtitle: 'New release',
            artwork: item.artwork,
            onTap: () => openBrowse(context, item),
          ),
        );
      }
    } else {
      for (final AlbumCard a in HomeCatalog.newReleases.take(2)) {
        heroes.add(
          HeroCard(
            eyebrow: 'New music',
            title: a.title,
            subtitle: a.artist,
            artwork: a.coverUrl,
            onTap: () => openAlbum(context, a, musicOnly: true),
          ),
        );
      }
    }
    if (heroes.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(title: 'Top picks for you'),
          SizedBox(
            height: (MediaQuery.sizeOf(context).width * 0.7).clamp(200.0, 320.0) / 0.92 + 4,
            child: Shelf(gap: 14, children: heroes),
          ),
        ],
      ),
    );
  }

  List<HistoryEntry> libraryHistory(BuildContext context) =>
      context.read<LibraryService>().history;

  Widget _roomInvite(BuildContext context) {
    final JamService jam = context.watch<JamService>();
    if (jam.isConnected) return const SizedBox.shrink();
    final SidifyTokens t = context.sidify;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 36),
      child: GestureDetector(
        onTap: () => context.read<SidifyShellController>().goTogether(),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.raised,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.edge, width: 0.5),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: t.brand,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.people_rounded, size: 28, color: Colors.white),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            'Listen together',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.2,
                              color: t.text,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: t.fill2,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Coming soon',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: t.text2,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Start a room, share the code, and everyone hears the '
                      'same song at the same moment.',
                      style: TextStyle(
                        fontSize: 13.5,
                        height: 1.35,
                        color: t.text2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _loadingShelves() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const SidifySkeleton(width: 200, height: 24, radius: 6),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              for (int i = 0; i < 3; i++) ...<Widget>[
                const SidifySkeleton(width: 148, height: 200, radius: 12),
                const SizedBox(width: 12),
              ],
            ],
          ),
          const SizedBox(height: 34),
          const SidifySkeleton(width: 160, height: 24, radius: 6),
          const SizedBox(height: 14),
          for (int i = 0; i < 4; i++) ...<Widget>[
            const SidifySkeleton(height: 60, radius: 8),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}
