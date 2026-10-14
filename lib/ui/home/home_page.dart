import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/branding.dart';
import '../../core/models/album_card.dart';
import '../../core/models/artist.dart';
import '../../core/models/song.dart';
import '../../core/services/home_catalog.dart';
import '../../core/services/library_service.dart';
import '../../core/services/music_download_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/ifall_ui.dart';
import '../../core/utils/format.dart';
import '../../screens/music_browse_screen.dart';
import '../../services/yt_music_parser.dart';
import '../album/album_page.dart';
import '../artist/artist_router.dart';
import '../brands/brands_page.dart';
import '../shell/ifall_shell.dart';
import '../shell/shell_controller.dart';
import '../widgets/artwork.dart';
import '../widgets/media_cards.dart';
import '../widgets/song_tile.dart';
import 'home_cards.dart';
import '../widgets/liked_songs_artwork.dart';

/// **Home** — the canvas the listener lands on.
///
/// A big, tight title in a frosted top bar; a greeting; then rails that sit
/// directly on the page rather than inside boxes: *Made for you*, mood &
/// genres, the trending chart, new releases, music brands, top artists and
/// *Recommended for you*.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<bool> _scrolled = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<HomeCatalog>().load();
    });
  }

  void _onScroll() {
    final bool scrolled = _scroll.hasClients && _scroll.offset > 8;
    if (scrolled != _scrolled.value) _scrolled.value = scrolled;
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  void _openAlbum(AlbumCard album) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (BuildContext c) => AlbumPage(album: album)),
    );
  }

  void _openBrowse(MusicBrowseItem item) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => MusicBrowseScreen(item: item),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final HomeCatalog catalog = context.watch<HomeCatalog>();
    final SettingsService settings = context.watch<SettingsService>();
    final IfallPalette c = IfallPalette.of(context);

    return Stack(
      children: <Widget>[
        RefreshIndicator(
          color: c.accent,
          backgroundColor: c.surface,
          onRefresh: () => catalog.load(force: true),
          child: ListView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              top: 60 + MediaQuery.paddingOf(context).top,
              bottom: IfallInsets.bottom,
            ),
            children: <Widget>[
              const HomeListenTogetherCard(),
              _Hero(name: settings.displayName),
              if (catalog.loading) ...<Widget>[
                const IfallSectionHeader(
                  title: 'Made for you',
                  subtitle: 'Picked from what you keep playing',
                ),
                const _LoadingRail(),
              ] else ...<Widget>[
                if (catalog.error != null && catalog.madeForYou.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: IfallGlass(
                      radius: IfallUI.rLg,
                      blur: 0,
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'Home feed unavailable',
                            style: IfallText.section(c.onSurface),
                          ),
                          const SizedBox(height: 6),
                          Text(catalog.error!, style: IfallText.caption(c.onSurfaceVariant)),
                          const SizedBox(height: 14),
                          FilledButton(
                            onPressed: () => catalog.load(force: true),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  ),

                // ------------------------------------------------ Made for you
                if (catalog.madeForYou.isNotEmpty) ...<Widget>[
                  IfallSectionHeader(
                    title: 'Made for you',
                    subtitle: 'Picked from what you keep playing',
                    onSeeAll: () => context.read<ShellController>().goSearch(),
                  ),
                  SizedBox(
                    height: 196,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: catalog.madeForYou.length + 1,
                      itemBuilder: (BuildContext context, int i) {
                        final PlaybackService playback =
                            context.read<PlaybackService>();
                        if (i == 0) {
                          return LikedSongsCard(
                            count: context.watch<LibraryService>().likedSongs.length,
                            onTap: () => context.read<ShellController>().goLiked(),
                          );
                        }
                        final Song song = catalog.madeForYou[i - 1];
                        return SongCard(
                          song: song,
                          onTap: () => playback.playQueue(
                            catalog.madeForYou,
                            startIndex: i - 1,
                          ),
                        );
                      },
                    ),
                  ),
                ],

                // --------------------------------------------- mood & genres
                const IfallSectionHeader(
                  title: 'Mood & genres',
                  subtitle: 'Tap one to start a station',
                ),
                const HomeMoodGrid(),

                // --------------------------------------------------- trending
                if (catalog.trending.isNotEmpty) ...<Widget>[
                  IfallSectionHeader(
                    title: 'Trending now',
                    subtitle: 'Trending music discovery',
                    seeAllLabel: 'Show all',
                    onSeeAll: () => context.read<ShellController>().goSearch(
                          'Hindi top hit songs India 2026',
                        ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: IfallGlass(
                      radius: IfallUI.rLg,
                      blur: 0,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: <Widget>[
                          for (int i = 0; i < catalog.trending.length; i++)
                            SongTile(
                              song: catalog.trending[i],
                              rank: i + 1,
                              onTap: () => context
                                  .read<PlaybackService>()
                                  .playQueue(catalog.trending, startIndex: i),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],

                // --------------------------------------------- playlists rail
                if (catalog.playlistsForYou.isNotEmpty) ...<Widget>[
                  const IfallSectionHeader(
                    title: 'Playlists you may like',
                    subtitle: 'Based on your listening',
                  ),
                  SizedBox(
                    height: 224,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: catalog.playlistsForYou.length,
                      itemBuilder: (BuildContext context, int i) {
                        final item = catalog.playlistsForYou[i];
                        return AlbumTile(
                          coverUrl: item.artwork,
                          title: item.title,
                          artist: 'Playlist',
                          onTap: () => _openBrowse(item),
                        );
                      },
                    ),
                  ),
                ],

                // ----------------------------------------------- new releases
                const IfallSectionHeader(
                  title: 'New releases',
                  subtitle: 'Fresh albums & singles',
                  seeAllLabel: 'Browse',
                ),
                SizedBox(
                  height: 224,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: catalog.freshReleases.isNotEmpty
                        ? catalog.freshReleases.length
                        : HomeCatalog.newReleases.length,
                    itemBuilder: (BuildContext context, int i) {
                      if (catalog.freshReleases.isNotEmpty) {
                        final item = catalog.freshReleases[i];
                        return AlbumTile(
                          coverUrl: item.artwork,
                          title: item.title,
                          artist: 'Album',
                          onTap: () => _openBrowse(item),
                        );
                      }
                      final AlbumCard album = HomeCatalog.newReleases[i];
                      return AlbumTile(
                        coverUrl: album.coverUrl,
                        title: album.title,
                        artist: album.artist,
                        onTap: () => _openAlbum(album),
                      );
                    },
                  ),
                ),

                // ----------------------------------------------------- brands
                IfallSectionHeader(
                  title: 'Music brands',
                  subtitle: 'Official label channels',
                  seeAllLabel: 'All',
                  onSeeAll: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext c) => const BrandsPage(),
                    ),
                  ),
                ),
                const HomeBrandRow(),

                // ------------------------------------------------ top artists
                IfallSectionHeader(
                  title: 'Top artists',
                  subtitle: 'Commanding the charts right now',
                  seeAllLabel: 'Library',
                  onSeeAll: () => context.read<ShellController>().goLibrary(),
                ),
                SizedBox(
                  height: 176,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: HomeCatalog.topArtists.length,
                    itemBuilder: (BuildContext context, int i) {
                      final ArtistRef artist = HomeCatalog.topArtists[i];
                      return ArtistBubble(
                        name: artist.name,
                        imageUrl: catalog.photoFor(
                          artist.name,
                          fallback: artist.imageUrl,
                        ),
                        onTap: () => openArtistByName(
                          context,
                          name: artist.name,
                          channelId: artist.channelId,
                        ),
                      );
                    },
                  ),
                ),

                // ----------------------------------------------- recommended
                if (catalog.recommended.isNotEmpty) ...<Widget>[
                  const IfallSectionHeader(
                    title: 'Recommended for you',
                    subtitle: 'Because of your recent listening',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: IfallGlass(
                      radius: IfallUI.rLg,
                      blur: 0,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Column(
                        children: <Widget>[
                          for (int i = 0; i < catalog.recommended.length; i++)
                            SongTile(
                              song: catalog.recommended[i],
                              subtitle: catalog.recommended[i].artist,
                              onTap: () =>
                                  context.read<PlaybackService>().playQueue(
                                        catalog.recommended,
                                        startIndex: i,
                                      ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
              const SizedBox(height: 8),
              const _Footer(),
            ],
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: ValueListenableBuilder<bool>(
            valueListenable: _scrolled,
            builder: (BuildContext context, bool scrolled, Widget? child) =>
                HomeTopBar(scrolled: scrolled),
          ),
        ),
      ],
    );
  }
}

/// A shimmering placeholder rail shown while the feed loads.
class _LoadingRail extends StatelessWidget {
  const _LoadingRail();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 186,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 3,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (BuildContext context, int i) => SizedBox(
          width: 132,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              IfallShimmer(width: 132, height: 132),
              const SizedBox(height: 10),
              const IfallShimmer(width: 96, height: 12),
              const SizedBox(height: 6),
              const IfallShimmer(width: 66, height: 10),
            ],
          ),
        ),
      ),
    );
  }
}

/// The greeting card.
///
/// Built as a flexible column so the two big buttons can never overflow — on a
/// narrow phone they stack, on a wider one they sit side by side.
class _Hero extends StatelessWidget {
  const _Hero({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final HomeCatalog catalog = context.watch<HomeCatalog>();
    final PlaybackService playback = context.read<PlaybackService>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: IfallGlass(
        radius: IfallUI.rXl,
        blur: 0,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(IfallUI.rPill),
                color: c.accent.withValues(alpha: 0.16),
                border: Border.all(color: c.accent.withValues(alpha: 0.35)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.auto_awesome_rounded, size: 13, color: c.accent),
                  const SizedBox(width: 6),
                  Text(
                    IfallBranding.tagline.toUpperCase(),
                    style: IfallText.label(c.accent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            RichText(
              text: TextSpan(
                style: IfallText.style(26, weight: FontWeight.w800,
                    letterSpacing: -0.9, color: c.onSurface, height: 1.18),
                children: <InlineSpan>[
                  TextSpan(text: '${Fmt.greeting()}, '),
                  TextSpan(
                    text: '$name.',
                    style: TextStyle(color: c.accent),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Your universe of sound awaits.',
              style: IfallText.body(c.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool stack = constraints.maxWidth < 380;
                final Widget mix = _HeroButton(
                  label: "Play today's mix",
                  icon: Icons.play_arrow_rounded,
                  filled: true,
                  onTap: () async {
                    await catalog.load();
                    if (!context.mounted) return;
                    final List<Song> mix = <Song>[
                      ...catalog.madeForYou,
                      ...catalog.trending,
                      ...catalog.recommended,
                    ];
                    if (mix.isEmpty) {
                      context
                          .read<ShellController>()
                          .goSearch('Hindi trending songs India');
                      return;
                    }
                    await playback.playQueue(mix, startIndex: 0);
                  },
                );
                final Widget shuffle = _HeroButton(
                  label: 'Shuffle library',
                  icon: Icons.shuffle_rounded,
                  onTap: () {
                    final List<Song> liked =
                        context.read<LibraryService>().likedSongs;
                    final List<Song> pool = liked.isNotEmpty
                        ? liked
                        : <Song>[
                            ...catalog.madeForYou,
                            ...catalog.trending,
                          ];
                    if (pool.isEmpty) {
                      context.read<ShellController>().goSearch('top Hindi songs');
                      return;
                    }
                    playback.playQueue(
                      pool,
                      startIndex: DateTime.now().millisecondsSinceEpoch %
                          pool.length,
                    );
                  },
                );
                if (stack) {
                  return Column(
                    children: <Widget>[
                      mix,
                      const SizedBox(height: 10),
                      shuffle,
                    ],
                  );
                }
                return Row(
                  children: <Widget>[
                    Expanded(child: mix),
                    const SizedBox(width: 10),
                    Expanded(child: shuffle),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroButton extends StatelessWidget {
  const _HeroButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;

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
        onTap: onTap,
        borderRadius: BorderRadius.circular(IfallUI.rPill),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: filled ? c.accent : c.glass,
            borderRadius: BorderRadius.circular(IfallUI.rPill),
            border: Border.all(
              color: filled ? c.accent : c.outline.withValues(alpha: 0.9),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 18, color: ink),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IfallText.body(ink).copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The "Made with love" footer that closes Home.
class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 12),
      child: Column(
        children: <Widget>[
          Opacity(
            opacity: 0.7,
            child: Image.asset(
              'assets/images/ifall_logo.png',
              width: 44,
              height: 44,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Made with ❤️ by ${IfallBranding.author}',
            textAlign: TextAlign.center,
            style: IfallText.caption(c.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            '${IfallBranding.appName} ${IfallBranding.fullVersionLabel} · ${IfallBranding.tagline}',
            textAlign: TextAlign.center,
            style: IfallText.caption(c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
