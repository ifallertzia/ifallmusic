import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/album_card.dart';
import '../../core/models/artist.dart';
import '../../core/models/song.dart';
import '../../core/services/home_catalog.dart';
import '../../core/services/library_service.dart';
import '../../core/services/music_download_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/recommendation_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../../core/utils/format.dart';
import '../../data/labels.dart';
import '../../screens/music_browse_screen.dart';
import '../../services/yt_music_parser.dart';
import '../../widgets/brand_logo.dart';
import '../album/album_page.dart';
import '../artist/artist_router.dart';
import '../brands/brands_page.dart';
import '../settings/settings_page.dart';
import '../shell/shell_controller.dart';
import '../widgets/media_cards.dart';
import '../widgets/saxify_logo.dart';
import '../widgets/song_tile.dart';

/// Home — the site's layout, rebuilt in liquid glass on absolute black:
/// greeting hero, Made for you, personal playlists, Trending now, New releases,
/// Music brands, Top artists and Recommended for you.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<HomeCatalog>().load();
    });
  }

  void _openAlbum(AlbumCard album) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => AlbumPage(album: album),
      ),
    );
  }

  List<Song> _uniqueSongs(Iterable<Song> songs, {int limit = 100}) {
    final Set<String> seen = <String>{};
    return songs
        .where((Song song) => song.id.isNotEmpty && seen.add(song.id))
        .take(limit)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final HomeCatalog catalog = context.watch<HomeCatalog>();
    final SettingsService settings = context.watch<SettingsService>();
    final LibraryService library = context.watch<LibraryService>();
    final RecommendationService recommendations =
        context.watch<RecommendationService>();
    final PlaybackService playback = context.read<PlaybackService>();

    // Put on-device signals first, then the personalised feed. The same
    // de-duplicated list drives the poster grid.
    final List<Song> homePicks = _uniqueSongs(<Song>[
      ...recommendations.forYou,
      ...catalog.madeForYou,
      ...catalog.recommended,
      ...library.history.map((HistoryEntry entry) => entry.song),
      ...library.likedSongs,
      ...catalog.trending,
    ], limit: 16);

    return AuroraBackdrop(
      intensity: 0.18,
      child: SafeArea(
        top: true,
        bottom: false,
        child: RefreshIndicator(
          color: context.accent.primary,
          backgroundColor: SaxifyColors.surface,
          onRefresh: () => catalog.load(force: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 190),
            children: <Widget>[
              _TopBar(
                onSettings: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext c) => const SettingsPage(),
                    ),
                  );
                },
              ),
              _Hero(name: settings.displayName),
              const SectionHeader(
                title: 'Made for you',
                subtitle: 'Picked from the songs and artists you play',
                padding: EdgeInsets.fromLTRB(18, 12, 18, 8),
              ),
              if (homePicks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: homePicks.length.clamp(0, 16),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          crossAxisSpacing: 10,
                          mainAxisSpacing: 10,
                          childAspectRatio: 0.68,
                        ),
                    itemBuilder: (BuildContext c, int i) =>
                        RecommendationSongCard(
                          song: homePicks[i],
                          onTap: () => playback.playQueue(
                            homePicks,
                            startIndex: i,
                          ),
                        ),
                  ),
                )
              else if (catalog.loading)
                const _RecommendationLoadingGrid()
              else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Text(
                    catalog.error == null
                        ? 'Play or like a few songs and we\'ll build your mix here.'
                        : 'Your mix will appear as soon as the music feed is back.',
                    style: const TextStyle(
                      color: SaxifyColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ),

              if (catalog.error != null && homePicks.isEmpty && !catalog.loading)
                EmptyState(
                  icon: Icons.wifi_off_rounded,
                  title: 'Home feed unavailable',
                  message: catalog.error,
                  actionLabel: 'Retry',
                  onAction: () => catalog.load(force: true),
                ),

              if (catalog.trending.isNotEmpty) ...<Widget>[
                SectionHeader(
                  title: 'Trending now',
                  actionLabel: 'Show all',
                  onAction: () => context.read<ShellController>().goSearch(
                    'Hindi top hit songs India 2026',
                  ),
                ),
                HorizontalRail(
                  height: 196,
                  itemCount: catalog.trending.length,
                  builder: (BuildContext c, int i) => SongCard(
                    song: catalog.trending[i],
                    width: 144,
                    onTap: () => playback.playQueue(
                      catalog.trending,
                      startIndex: i,
                    ),
                  ),
                ),
              ],

              if (catalog.playlistsForYou.isNotEmpty) ...<Widget>[
                const SectionHeader(title: 'Playlists you may like'),
                HorizontalRail(
                  height: 216,
                  itemCount: catalog.playlistsForYou.length,
                  builder: (BuildContext c, int i) {
                    final MusicBrowseItem item = catalog.playlistsForYou[i];
                    return AlbumTile(
                      coverUrl: item.artwork,
                      title: item.title,
                      artist: 'Picked for your listening',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MusicBrowseScreen(item: item),
                        ),
                      ),
                    );
                  },
                ),
              ],

              SectionHeader(
                title: 'New releases',
                actionLabel: 'Browse',
                onAction: () => context.read<ShellController>().goSearch(
                  'latest Hindi Bollywood songs 2026',
                ),
              ),
              HorizontalRail(
                height: 218,
                itemCount: catalog.freshReleases.isNotEmpty
                    ? catalog.freshReleases.length
                    : HomeCatalog.newReleases.length,
                builder: (BuildContext c, int i) {
                  if (catalog.freshReleases.isNotEmpty) {
                    final MusicBrowseItem item = catalog.freshReleases[i];
                    return AlbumTile(
                      coverUrl: item.artwork,
                      title: item.title,
                      artist: 'Fresh album',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => MusicBrowseScreen(item: item),
                        ),
                      ),
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

              SectionHeader(
                title: 'Music brands',
                actionLabel: 'All',
                onAction: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const BrandsPage()),
                ),
              ),
              const _BrandRow(),

              SectionHeader(
                title: 'Top artists',
                actionLabel: 'Library',
                onAction: () => context.read<ShellController>().goLibrary(),
              ),
              HorizontalRail(
                height: 174,
                itemCount: HomeCatalog.topArtists.length,
                builder: (BuildContext c, int i) {
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
              const SizedBox(height: 10),
              const _SmartRails(),
              const SizedBox(height: 10),
              const _WhatsNewCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small, clean home header. The wordmark is deliberately compact so the
/// recommendations and covers get the space that matters.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final MusicDownloadService downloads = context.watch<MusicDownloadService>();
    final int activeDownloads = downloads.jobs
        .where(
          (MusicDownloadJob job) =>
              job.phase == MusicDownloadPhase.running ||
              job.phase == MusicDownloadPhase.idle,
        )
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 5, 10, 0),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: SaxifyWordmark(
              logoSize: 25,
              fontSize: 17,
              showSubtitle: false,
            ),
          ),
          IconButton(
            tooltip: 'Liked songs',
            visualDensity: VisualDensity.compact,
            onPressed: () => context.read<ShellController>().goLiked(),
            icon: const Icon(Icons.favorite_border_rounded, size: 21),
          ),
          Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              IconButton(
                tooltip: 'Downloads',
                visualDensity: VisualDensity.compact,
                onPressed: () => context.read<ShellController>().goDownloads(),
                icon: const Icon(Icons.download_rounded, size: 21),
              ),
              if (activeDownloads > 0)
                Positioned(
                  top: 5,
                  right: 5,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: context.accent.primary,
                      shape: BoxShape.circle,
                      border: Border.all(color: SaxifyColors.background, width: 1.5),
                    ),
                    child: const SizedBox(width: 7, height: 7),
                  ),
                ),
            ],
          ),
          IconButton(
            tooltip: 'Settings',
            visualDensity: VisualDensity.compact,
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined, size: 21),
          ),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 3),
      child: Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: '${Fmt.greeting()}, ',
              style: SaxifyTheme.appleFont(
                size: 21,
                weight: FontWeight.w500,
                letterSpacing: -0.35,
                color: SaxifyColors.textSecondary,
              ),
            ),
            TextSpan(
              text: name.trim().isEmpty ? 'User' : name.trim(),
              style: SaxifyTheme.appleFont(
                size: 21,
                weight: FontWeight.w700,
                letterSpacing: -0.4,
                color: SaxifyColors.textPrimary,
              ),
            ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

class _RecommendationLoadingGrid extends StatelessWidget {
  const _RecommendationLoadingGrid();

  @override
  Widget build(BuildContext context) {
    const Color skeleton = Color(0xFF17171D);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 16,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 0.68,
        ),
        itemBuilder: (BuildContext context, int index) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(SaxifyTheme.radiusMd),
                child: Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[skeleton, Color(0xFF0C0C10)],
                        ),
                      ),
                    ),
                    Positioned(
                      top: 9,
                      left: 9,
                      child: Container(
                        width: 58,
                        height: 17,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 9,
                      right: 9,
                      child: Container(
                        width: 35,
                        height: 35,
                        decoration: const BoxDecoration(
                          color: Color(0xFF24242B),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: 110,
              height: 12,
              decoration: BoxDecoration(
                color: skeleton,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            const SizedBox(height: 6),
            Container(
              width: 72,
              height: 9,
              decoration: BoxDecoration(
                color: skeleton,
                borderRadius: BorderRadius.circular(7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmartRails extends StatelessWidget {
  const _SmartRails();

  @override
  Widget build(BuildContext context) {
    final RecommendationService reco = context.watch<RecommendationService>();
    final PlaybackService playback = context.read<PlaybackService>();
    if (reco.becauseQuery == null || reco.becauseYouSearched.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: <Widget>[
        SectionHeader(
          title: 'Because you searched ${reco.becauseQuery}',
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
        ),
        for (int i = 0; i < reco.becauseYouSearched.length; i++)
          SongTile(
            dense: true,
            song: reco.becauseYouSearched[i],
            onTap: () => playback.playQueue(
              reco.becauseYouSearched,
              startIndex: i,
            ),
          ),
      ],
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: MusicBrands.all.length,
        separatorBuilder: (BuildContext context, int index) =>
            const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final MusicBrand brand = MusicBrands.all[i];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => BrandChannelPage(brand: brand),
              ),
            ),
            child: SizedBox(
              width: 110,
              child: Column(
                children: [
                  BrandLogo(brand: brand, size: 52),
                  const SizedBox(height: 8),
                  Text(
                    brand.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WhatsNewCard extends StatelessWidget {
  const _WhatsNewCard();

  static const String _version = 'Update 2.5.2';
  static const String _date = '30 Sept 2026';
  static const String _headline =
      'A smoother player, a one-screen library, and a fresh green look';

  static const List<String> _notes = <String>[
    'Your library is one clean list now — open Liked, Downloads or Artists and Back returns you to the list.',
    'Lyrics sit at the bottom of the player: scroll to open them, with a bouncing arrow showing the way.',
    'A denser 4-up home grid, Spotify Green as the default look, and faster playback and search.',
  ];

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: GlassPanel(
        glow: true,
        onTap: () => _showNotes(context),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: <Widget>[
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: accent.gradient,
              ),
              child: Icon(Icons.auto_awesome_rounded, color: accent.onAccent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'UPDATE NOTICE · $_date',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w800,
                      color: accent.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "What's new",
                    style: SaxifyTheme.appleFont(
                      size: 16,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _headline,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: SaxifyColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: SaxifyColors.textFaint,
            ),
          ],
        ),
      ),
    );
  }

  void _showNotes(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) => GlassSheet(
        title: "What's new",
        subtitle: 'IfallMusic $_version · $_date',
        maxHeightFactor: 0.85,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: <Widget>[
            Text(
              _headline,
              style: SaxifyTheme.appleFont(
                size: 17,
                weight: FontWeight.w700,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 14),
            for (final String note in _notes)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 16,
                        color: sheetContext.accent.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        note,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: SaxifyColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            GlassButton(
              label: 'Got it',
              expand: true,
              onPressed: () => Navigator.of(sheetContext).pop(),
            ),
          ],
        ),
      ),
    );
  }
}
