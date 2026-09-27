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
import '../../core/services/recommendation_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../../core/utils/format.dart';
import '../../data/labels.dart';
import '../../screens/music_browse_screen.dart';
import '../../widgets/brand_logo.dart';
import '../album/album_page.dart';
import '../artist/artist_router.dart';
import '../brands/brands_page.dart';
import '../settings/settings_page.dart';
import '../shell/shell_controller.dart';
import '../widgets/media_cards.dart';
import '../widgets/neon.dart';
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

  @override
  Widget build(BuildContext context) {
    final HomeCatalog catalog = context.watch<HomeCatalog>();
    final SettingsService settings = context.watch<SettingsService>();

    return AuroraBackdrop(
      intensity: 0.9,
      child: SafeArea(
        top: true,
        bottom: false,
        child: RefreshIndicator(
          color: context.accent.primary,
          backgroundColor: SaxifyColors.surface,
          onRefresh: () => catalog.load(force: true),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 200),
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
              if (catalog.loading) ...<Widget>[
                const SectionHeader(
                  title: 'Made for you',
                  subtitle: 'Picked from what you keep playing',
                ),
                const LoadingRail(itemCount: 3),
              ] else ...<Widget>[
                if (catalog.error != null && catalog.madeForYou.isEmpty)
                  EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: 'Home feed unavailable',
                    message: catalog.error,
                    actionLabel: 'Retry',
                    onAction: () => catalog.load(force: true),
                  ),

                // ------------------------------------------------ Made for you
                if (catalog.madeForYou.isNotEmpty) ...<Widget>[
                  SectionHeader(
                    title: 'Made for you',
                    subtitle: 'Picked from what you keep playing',
                    actionLabel: 'Explore',
                    onAction: () => context.read<ShellController>().goSearch(),
                  ),
                  HorizontalRail(
                    height: 200,
                    itemCount: catalog.madeForYou.length,
                    builder: (BuildContext c, int i) {
                      final Song song = catalog.madeForYou[i];
                      return SongCard(
                        song: song,
                        onTap: () => context.read<PlaybackService>().playQueue(
                          catalog.madeForYou,
                          startIndex: i,
                        ),
                      );
                    },
                  ),
                ],

                const SectionHeader(
                  title: 'Playlists you may like',
                  subtitle: 'ifallertzia server · based on your listening',
                ),
                if (catalog.playlistsForYou.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'Playlists will appear as your music feed refreshes.',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                else
                  HorizontalRail(
                    height: 232,
                    itemCount: catalog.playlistsForYou.length,
                    builder: (c, i) {
                      final item = catalog.playlistsForYou[i];
                      return AlbumTile(
                        coverUrl: item.artwork,
                        title: item.title,
                        artist: 'ifallertzia server playlist',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MusicBrowseScreen(item: item),
                          ),
                        ),
                      );
                    },
                  ),

                // ------------------------------------------------ Trending now
                if (catalog.trending.isNotEmpty) ...<Widget>[
                  SectionHeader(
                    title: 'Trending now',
                    subtitle: 'Trending music discovery',
                    actionLabel: 'Show all',
                    onAction: () => context.read<ShellController>().goSearch(
                      'Hindi top hit songs India 2026',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: GlassPanel(
                      padding: const EdgeInsets.symmetric(vertical: 6),
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

                // ------------------------------------------------ New releases
                SectionHeader(
                  title: 'New releases',
                  subtitle: 'Fresh albums & singles',
                  actionLabel: 'Browse',
                  onAction: () => context.read<ShellController>().goSearch(
                    'latest Hindi Bollywood songs 2026',
                  ),
                ),
                if (catalog.freshReleases.isNotEmpty)
                  HorizontalRail(
                    height: 232,
                    itemCount: catalog.freshReleases.length,
                    builder: (c, i) {
                      final item = catalog.freshReleases[i];
                      return AlbumTile(
                        coverUrl: item.artwork,
                        title: item.title,
                        artist: 'ifallertzia server album',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => MusicBrowseScreen(item: item),
                          ),
                        ),
                      );
                    },
                  )
                else
                  HorizontalRail(
                    height: 232,
                    itemCount: HomeCatalog.newReleases.length,
                    builder: (c, i) {
                      final album = HomeCatalog.newReleases[i];
                      return AlbumTile(
                        coverUrl: album.coverUrl,
                        title: album.title,
                        artist: album.artist,
                        onTap: () => _openAlbum(album),
                      );
                    },
                  ),

                // ------------------------------------------------ Brands
                SectionHeader(
                  title: 'Music brands',
                  subtitle: 'Official label channels',
                  actionLabel: 'All',
                  onAction: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const BrandsPage()),
                  ),
                ),
                const _BrandRow(),

                // ------------------------------------------------ Top artists
                SectionHeader(
                  title: 'Top artists',
                  subtitle: 'Commanding the charts right now',
                  actionLabel: 'Library',
                  onAction: () => context.read<ShellController>().goLibrary(),
                ),
                HorizontalRail(
                  height: 186,
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

                // ------------------------------------------------ Recommended
                const _SmartRails(),
                if (catalog.recommended.isNotEmpty) ...<Widget>[
                  const SectionHeader(
                    title: 'Recommended for you',
                    subtitle: 'Because of your recent listening',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: GlassPanel(
                      padding: const EdgeInsets.symmetric(vertical: 6),
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

              const SizedBox(height: 16),
              const _WhatsNewCard(),
            ],
          ),
        ),
      ),
    );
  }
}

/// Frosted header: wordmark on the left, downloads + library + settings on the
/// right. The download icon opens the Downloads section directly.
class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSettings});

  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final MusicDownloadService downloads = context
        .watch<MusicDownloadService>();
    final int activeDownloads = downloads.jobs
        .where(
          (MusicDownloadJob job) =>
              job.phase == MusicDownloadPhase.running ||
              job.phase == MusicDownloadPhase.idle,
        )
        .length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 2),
      child: Row(
        children: <Widget>[
          const Expanded(
            child: SaxifyWordmark(
              logoSize: 34,
              fontSize: 21,
              showSubtitle: true,
            ),
          ),
          GlassIconButton(
            icon: Icons.favorite_border_rounded,
            size: 42,
            tooltip: 'Liked songs',
            badgeCount: library.likedSongs.length,
            onPressed: () => context.read<ShellController>().goLiked(),
          ),
          const SizedBox(width: 8),
          GlassIconButton(
            icon: Icons.download_rounded,
            size: 42,
            tooltip: 'Downloads',
            badgeCount: activeDownloads,
            active: activeDownloads > 0,
            onPressed: () => context.read<ShellController>().goDownloads(),
          ),
          const SizedBox(width: 8),
          GlassIconButton(
            icon: Icons.settings_outlined,
            size: 42,
            tooltip: 'Settings',
            onPressed: onSettings,
          ),
        ],
      ),
    );
  }
}

/// Hero card. Built as a flexible column so the two big buttons can never
/// overflow — on a narrow phone they stack, on a wider one they sit side by side.
class _Hero extends StatelessWidget {
  const _Hero({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final HomeCatalog catalog = context.watch<HomeCatalog>();
    final PlaybackService playback = context.read<PlaybackService>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 4),
      child: GlassPanel(
        glow: true,
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(SaxifyTheme.radiusXl),
                    color: accent.primary.withValues(alpha: 0.16),
                    border: Border.all(
                      color: accent.primary.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        Icons.auto_awesome_rounded,
                        size: 13,
                        color: accent.primary,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        IfallBranding.tagline.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.3,
                          fontWeight: FontWeight.w800,
                          color: accent.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            RichText(
              text: TextSpan(
                style: SaxifyTheme.appleFont(
                  size: 27,
                  height: 1.18,
                  weight: FontWeight.w800,
                  letterSpacing: -0.9,
                  color: SaxifyColors.textPrimary,
                ),
                children: <InlineSpan>[
                  TextSpan(text: '${Fmt.greeting()}, '),
                  TextSpan(
                    text: '$name. ',
                    style: TextStyle(color: accent.primary),
                  ),
                  const TextSpan(
                    text: '\nYour universe of sound awaits.',
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.3,
                      fontWeight: FontWeight.w600,
                      color: SaxifyColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Instant search, offline downloads, a real-time studio equalizer and '
              'buttery background playback — all in one app.',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.55,
                color: SaxifyColors.textMuted,
              ),
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool stack = constraints.maxWidth < 420;
                final Widget mix = GlassButton(
                  label: "Play today's mix",
                  icon: Icons.play_arrow_rounded,
                  expand: true,
                  onPressed: () async {
                    await catalog.load();
                    if (!context.mounted) return;
                    final List<Song> mix = <Song>[
                      ...catalog.madeForYou,
                      ...catalog.trending,
                      ...catalog.recommended,
                    ];
                    if (mix.isEmpty) {
                      context.read<ShellController>().goSearch(
                        'Hindi trending songs India',
                      );
                      return;
                    }
                    await playback.playQueue(mix, startIndex: 0);
                  },
                );
                final Widget explore = GlassButton(
                  label: 'Explore music',
                  icon: Icons.explore_rounded,
                  filled: false,
                  expand: true,
                  onPressed: () => context.read<ShellController>().goSearch(),
                );
                if (stack) {
                  return Column(
                    children: <Widget>[
                      mix,
                      const SizedBox(height: 10),
                      explore,
                    ],
                  );
                }
                return Row(
                  children: <Widget>[
                    Expanded(child: mix),
                    const SizedBox(width: 10),
                    Expanded(child: explore),
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

class _SmartRails extends StatelessWidget {
  const _SmartRails();

  @override
  Widget build(BuildContext context) {
    final RecommendationService reco = context.watch<RecommendationService>();
    final PlaybackService playback = context.read<PlaybackService>();
    if (reco.forYou.isEmpty && reco.becauseYouSearched.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      children: <Widget>[
        if (reco.forYou.isNotEmpty) ...<Widget>[
          const SectionHeader(
            title: 'On repeat',
            subtitle: 'On-device mix from what you play and search',
          ),
          HorizontalRail(
            height: 200,
            itemCount: reco.forYou.length,
            builder: (BuildContext c, int i) {
              final Song song = reco.forYou[i];
              return SongCard(
                song: song,
                onTap: () => playback.playQueue(reco.forYou, startIndex: i),
              );
            },
          ),
        ],
        if (reco.becauseQuery != null &&
            reco.becauseYouSearched.isNotEmpty) ...<Widget>[
          SectionHeader(
            title: 'Because you searched ${reco.becauseQuery}',
            subtitle: 'Boosted after 2 searches in 3 days',
          ),
          for (int i = 0; i < reco.becauseYouSearched.length; i++)
            SongTile(
              song: reco.becauseYouSearched[i],
              onTap: () =>
                  playback.playQueue(reco.becauseYouSearched, startIndex: i),
            ),
        ],
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

/// "What's new" — the modern update notice, matching the reference site exactly:
/// a dated card that opens a clean, scrollable changelog sheet.
class _WhatsNewCard extends StatelessWidget {
  const _WhatsNewCard();

  static const String _version = 'Update 2.3.4';
  static const String _date = '27 Sept 2026';
  static const String _headline =
      'Playlists fixed, all-new ifallertzia server branding';

  static const List<String> _notes = <String>[
    'Home playlists now open and play reliably — no more "tracks unavailable".',
    'Fresh ifallertzia server branding across search, playlists and albums.',
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
