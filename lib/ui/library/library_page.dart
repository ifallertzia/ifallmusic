import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/artist.dart';
import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/local_music_service.dart';
import '../../core/services/music_download_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../../core/utils/format.dart';
import '../../screens/lyrics_finder_screen.dart';
import '../../widgets/quality_badge.dart';
import '../artist/artist_router.dart';
import '../settings/backup_sheet.dart';
import '../settings/playlist_sync_sheet.dart';
import '../shell/shell_controller.dart';
import '../widgets/artwork.dart';
import '../widgets/media_cards.dart';
import '../widgets/song_tile.dart';
import 'playlist_detail_page.dart';

/// Number of sections the Library list can open. Regression guard:
/// [buildLibraryTabCounts] must return exactly this many entries.
@visibleForTesting
int get libraryTabCount => _LibraryTabSpec.all.length;

/// Per-section counters, in `_LibraryTabSpec.all` order:
/// Your Space · Liked · Playlists · Songs · Artists · On device · Downloads ·
/// History · Lyrics Finder.
@visibleForTesting
List<int> buildLibraryTabCounts({
  required LibraryService library,
  required MusicDownloadService downloads,
  required int onDeviceCount,
}) => <int>[
  0, // Your Space is the overview, not a counted collection.
  library.likedSongs.length,
  library.playlists.length,
  library.songs.length,
  library.artists.length,
  onDeviceCount,
  downloads.downloaded.length,
  library.history.length,
  0, // Lyrics Finder does not show a count.
];

/// Your saved music — one clean list.
///
/// The old horizontal tab strip is gone: every collection is a row in this list
/// and opens as its own pushed page. That keeps the library single-screen, and
/// means the system Back button always returns to this list instead of falling
/// through to Home.
class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  late final ShellController _shell = context.read<ShellController>();
  int _lastNonce = -1;

  @override
  void initState() {
    super.initState();
    _shell.addListener(_onShell);
    // A deep link that landed while this page was not yet mounted is
    // still honoured on the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _onShell());
  }

  /// Deep links (Home ▸ heart, Home ▸ download) still land on the right
  /// section, but as a pushed route so Back comes home to this list.
  void _onShell() {
    if (!mounted) return;
    if (_shell.libraryNonce == _lastNonce) return;
    _lastNonce = _shell.libraryNonce;
    final int target = _shell.libraryTab.clamp(
      0,
      _LibraryTabSpec.all.length - 1,
    );
    if (target == LibraryTabs.overview) return;
    _shell.clearLibraryTab();
    // Push after the frame so the route is never opened mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openSection(target);
    });
  }

  @override
  void dispose() {
    _shell.removeListener(_onShell);
    super.dispose();
  }

  void _openSection(int tab) {
    final Widget page = switch (tab) {
      LibraryTabs.liked => const LikedSongsPage(),
      LibraryTabs.playlists => const PlaylistsPage(),
      LibraryTabs.songs => const LibrarySongsPage(),
      LibraryTabs.artists => const LibraryArtistsPage(),
      LibraryTabs.onDevice => const OnDevicePage(),
      LibraryTabs.downloads => const LibraryDownloadsPage(),
      LibraryTabs.history => const LibraryHistoryPage(),
      LibraryTabs.lyrics => const LyricsFinderScreen(),
      _ => const SizedBox.shrink(),
    };
    if (page is SizedBox) return;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final MusicDownloadService downloads = context.watch<MusicDownloadService>();
    final LocalMusicService local = context.watch<LocalMusicService>();

    final List<({String title, String detail, IconData icon, int tab})>
    sections = <({String title, String detail, IconData icon, int tab})>[
      (
        title: 'Liked songs',
        detail: '${library.likedSongs.length} songs',
        icon: Icons.favorite_border_rounded,
        tab: LibraryTabs.liked,
      ),
      (
        title: 'Playlists',
        detail: '${library.playlists.length} playlists',
        icon: Icons.queue_music_rounded,
        tab: LibraryTabs.playlists,
      ),
      (
        title: 'Your songs',
        detail: '${library.songs.length} saved songs',
        icon: Icons.music_note_rounded,
        tab: LibraryTabs.songs,
      ),
      (
        title: 'Downloads',
        detail: '${downloads.downloaded.length} offline songs',
        icon: Icons.download_rounded,
        tab: LibraryTabs.downloads,
      ),
      (
        title: 'On this device',
        detail: '${local.songs.length} songs',
        icon: Icons.phone_android_rounded,
        tab: LibraryTabs.onDevice,
      ),
      (
        title: 'Recently played',
        detail: '${library.history.length} songs',
        icon: Icons.history_rounded,
        tab: LibraryTabs.history,
      ),
      (
        title: 'Artists',
        detail: '${library.artists.length} followed',
        icon: Icons.mic_none_rounded,
        tab: LibraryTabs.artists,
      ),
      (
        title: 'Lyrics Finder',
        detail: 'Find the words to any track',
        icon: Icons.lyrics_outlined,
        tab: LibraryTabs.lyrics,
      ),
    ];

    return AuroraBackdrop(
      intensity: 0.75,
      child: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _LibraryHeader(library: library),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 7, 16, 190),
                itemCount: sections.length + 1,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  indent: 52,
                ),
                itemBuilder: (BuildContext context, int index) {
                  if (index == 0) {
                    return const Padding(
                      padding: EdgeInsets.fromLTRB(2, 7, 2, 8),
                      child: Text(
                        'Your music, ready when you are.',
                        style: TextStyle(
                          fontSize: 12,
                          color: SaxifyColors.textMuted,
                        ),
                      ),
                    );
                  }
                  final section = sections[index - 1];
                  // Each row gets its own Material: ListTile paints its
                  // ink splash on the nearest Material, and the aurora
                  // backdrop's ColoredBox would hide it.
                  return Material(
                    type: MaterialType.transparency,
                    child: ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 2,
                        vertical: 1,
                      ),
                      leading: Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          color: context.accent.primary.withValues(alpha: 0.12),
                          border: Border.all(
                            color: context.accent.primary.withValues(alpha: 0.20),
                          ),
                        ),
                        child: Icon(section.icon, size: 19),
                      ),
                      title: Text(
                        section.title,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      subtitle: Text(
                        section.detail,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: SaxifyColors.textMuted,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        size: 19,
                      ),
                      onTap: () => _openSection(section.tab),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Metadata for the Library sections — one place, so the list, the counters and
/// the deep links all agree.
class _LibraryTabSpec {
  const _LibraryTabSpec({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;

  static const List<_LibraryTabSpec> all = <_LibraryTabSpec>[
    _LibraryTabSpec(
      label: 'Your Space',
      icon: Icons.grid_view_rounded,
      color: Color(0xFF94A3B8),
    ),
    _LibraryTabSpec(
      label: 'Liked',
      icon: Icons.favorite_rounded,
      color: Color(0xFFF43F5E),
    ),
    _LibraryTabSpec(
      label: 'Playlists',
      icon: Icons.queue_music_rounded,
      color: Color(0xFF8B5CF6),
    ),
    _LibraryTabSpec(
      label: 'Songs',
      icon: Icons.music_note_rounded,
      color: Color(0xFF3B82F6),
    ),
    _LibraryTabSpec(
      label: 'Artists',
      icon: Icons.mic_rounded,
      color: Color(0xFF10B981),
    ),
    _LibraryTabSpec(
      label: 'On device',
      icon: Icons.perm_media_rounded,
      color: Color(0xFF14B8A6),
    ),
    _LibraryTabSpec(
      label: 'Downloads',
      icon: Icons.download_rounded,
      color: Color(0xFFF59E0B),
    ),
    _LibraryTabSpec(
      label: 'History',
      icon: Icons.history_rounded,
      color: Color(0xFFEC4899),
    ),
    _LibraryTabSpec(
      label: 'Lyrics Finder',
      icon: Icons.lyrics_outlined,
      color: Color(0xFF06B6D4),
    ),
  ];
}

/// Shared page chrome for a library section: aurora backdrop, big title and a
/// back arrow that pops straight back to the Library list.
class LibrarySectionPage extends StatelessWidget {
  const LibrarySectionPage({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AuroraBackdrop(
      intensity: 0.75,
      // A section is pushed onto the APP navigator, which sits outside the
      // shell's Scaffold, so nothing above it supplies a Material. Every
      // Material widget in here (BackButton's InkWell, SongTile, the glass
      // tiles) would otherwise throw "No Material widget found".
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 6, 12, 2),
                child: Row(
                  children: <Widget>[
                    // A real BackButton: same behaviour and semantics as the
                    // system back gesture, so it always pops to the list.
                    const BackButton(),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SaxifyTheme.appleFont(
                              size: 22,
                              weight: FontWeight.w800,
                              letterSpacing: -0.8,
                            ),
                          ),
                          if (subtitle.isNotEmpty)
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: SaxifyColors.textMuted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.library});

  final LibraryService library;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 12, 4),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  'Your Space',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SaxifyTheme.appleFont(
                    size: 28,
                    weight: FontWeight.w800,
                    letterSpacing: -1.0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${library.likedSongs.length} liked · ${library.playlists.length} playlists · '
                  '${library.songs.length} songs',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: SaxifyColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          GlassIconButton(
            icon: Icons.backup_outlined,
            size: 42,
            tooltip: 'Backup / import library JSON',
            onPressed: () => showBackupSheet(context, library),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Liked Songs
class LikedSongsPage extends StatelessWidget {
  const LikedSongsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final PlaybackService playback = context.read<PlaybackService>();
    final List<Song> songs = library.likedSongs;

    return LibrarySectionPage(
      title: 'Liked Songs',
      subtitle: '${songs.length} songs',
      child: songs.isEmpty
          ? const SingleChildScrollView(
              child: EmptyState(
                icon: Icons.favorite_border_rounded,
                title: 'No liked songs yet',
                message:
                    'Tap the heart on any track and it will live here, saved on this device.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
              children: <Widget>[
                _CollectionHeader(
                  label: 'PLAYLIST',
                  title: 'Liked Songs',
                  subtitle: '${songs.length} songs',
                  coverUrl: songs.first.thumbnailUrl,
                  icon: Icons.favorite_rounded,
                  onPlay: () => playback.playQueue(songs),
                  onShuffle: () async {
                    await playback.playQueue(songs);
                    if (!playback.shuffleEnabled) {
                      await playback.toggleShuffle();
                    }
                  },
                ),
                for (int i = 0; i < songs.length; i++)
                  SongTile(
                    song: songs[i],
                    onTap: () => playback.playQueue(songs, startIndex: i),
                  ),
              ],
            ),
    );
  }
}

// ------------------------------------------------------------------ Playlists
class PlaylistsPage extends StatelessWidget {
  const PlaylistsPage({super.key});

  Future<void> _create(BuildContext context, LibraryService library) async {
    final TextEditingController controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Create playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (String v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name == null || name.trim().isEmpty) return;
    await library.createPlaylist(name);
  }

  void _openPlaylist(BuildContext context, Playlist playlist) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (BuildContext c) => PlaylistDetailPage(playlistId: playlist.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final SaxifyAccent accent = context.accent;

    return LibrarySectionPage(
      title: 'Playlists',
      subtitle: '${library.playlists.length} playlists',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: <Widget>[
          GlassPanel(
            glow: true,
            onTap: () => _create(context, library),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    gradient: accent.gradient,
                  ),
                  child: Icon(Icons.add_rounded, color: accent.onAccent),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(
                        'Create playlist',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: 3),
                      Text(
                        'Build your own universe of sound',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: SaxifyColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: accent.primary),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: GlassButton(
                  label: 'Generate all',
                  compact: true,
                  filled: false,
                  onPressed: () => shareAllPlaylistCodes(context),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: GlassButton(
                  label: 'Import code',
                  compact: true,
                  filled: false,
                  onPressed: () => showImportCodeSheet(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          if (library.playlists.isEmpty)
            const EmptyState(
              icon: Icons.queue_music_rounded,
              title: 'No playlists yet',
              message:
                  'Create one above, then use "Add to playlist" from any song menu.',
            )
          else
            for (final Playlist playlist in library.playlists)
              GlassPanel(
                padding: const EdgeInsets.all(12),
                radius: SaxifyTheme.radiusMd,
                onTap: () => _openPlaylist(context, playlist),
                child: Row(
                  children: <Widget>[
                    Artwork(
                      url: playlist.artwork,
                      size: 58,
                      radius: 12,
                      fallbackIcon: Icons.queue_music_rounded,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(
                            playlist.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${playlist.count} songs · ${Fmt.date(playlist.createdAt)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: SaxifyColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.more_vert_rounded,
                        size: 20,
                        color: SaxifyColors.textFaint,
                      ),
                      onPressed: () =>
                          _playlistMenu(context, library, playlist),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }

  void _playlistMenu(
    BuildContext context,
    LibraryService library,
    Playlist playlist,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => GlassSheet(
        title: playlist.name,
        subtitle: '${playlist.count} songs',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline_rounded),
              title: const Text('Rename'),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final TextEditingController controller = TextEditingController(
                  text: playlist.name,
                );
                final String? name = await showDialog<String>(
                  context: context,
                  builder: (BuildContext dialogContext) => AlertDialog(
                    title: const Text('Rename playlist'),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: const InputDecoration(hintText: 'New name'),
                      onSubmitted: (String v) =>
                          Navigator.of(dialogContext).pop(v),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(controller.text),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
                if (name != null && name.trim().isNotEmpty) {
                  await library.renamePlaylist(playlist.id, name);
                }
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: SaxifyColors.danger,
              ),
              title: const Text(
                'Delete playlist',
                style: TextStyle(color: SaxifyColors.danger),
              ),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final bool? confirmed = await showDialog<bool>(
                  context: context,
                  builder: (BuildContext dialogContext) => AlertDialog(
                    title: const Text('Delete playlist?'),
                    content: Text(
                      '"${playlist.name}" and its ${playlist.count} songs will be removed.',
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  await library.deletePlaylist(playlist.id);
                }
              },
            ),
            const SizedBox(height: 14),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- Songs
class LibrarySongsPage extends StatelessWidget {
  const LibrarySongsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final PlaybackService playback = context.read<PlaybackService>();
    final List<Song> songs = library.songs;

    return LibrarySectionPage(
      title: 'Your songs',
      subtitle: '${songs.length} saved songs',
      child: songs.isEmpty
          ? const SingleChildScrollView(
              child: EmptyState(
                icon: Icons.library_music_outlined,
                title: 'No saved songs yet',
                message:
                    'Songs you add to the library from the song menu will collect here.',
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '${songs.length} saved songs',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: SaxifyColors.textMuted,
                        ),
                      ),
                    ),
                    GlassButton(
                      label: 'Play all',
                      icon: Icons.play_arrow_rounded,
                      compact: true,
                      onPressed: () => playback.playQueue(songs),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                for (int i = 0; i < songs.length; i++)
                  SongTile(
                    song: songs[i],
                    onTap: () => playback.playQueue(songs, startIndex: i),
                  ),
              ],
            ),
    );
  }
}

// ------------------------------------------------------------------ Artists
class LibraryArtistsPage extends StatelessWidget {
  const LibraryArtistsPage({super.key});

  static const List<String> _indianArtists = <String>[
    'Arijit Singh',
    'Shreya Ghoshal',
    'A. R. Rahman',
    'Darshan Raval',
    'Sonu Nigam',
    'Lata Mangeshkar',
    'Kishore Kumar',
    'Asha Bhosle',
    'Udit Narayan',
    'Mohammed Rafi',
    'Kumar Sanu',
    'Jubin Nautiyal',
    'Armaan Malik',
    'Neha Kakkar',
    'Sunidhi Chauhan',
    'Vishal Mishra',
    'Mohit Chauhan',
    'Javed Ali',
    'Kailash Kher',
    'Papon',
    'Monali Thakur',
    'Palak Muchhal',
    'Sukhwinder Singh',
    'B Praak',
    'Diljit Dosanjh',
    'Sidhu Moose Wala',
    'AP Dhillon',
    'Guru Randhawa',
    'Badshah',
    'Yo Yo Honey Singh',
    'Shankar Mahadevan',
    'Vishal-Shekhar',
    'Pritam',
    'Amit Trivedi',
    'Anirudh Ravichander',
    'Sid Sriram',
    'S. P. Balasubrahmanyam',
    'K. S. Chithra',
    'Ilaiyaraaja',
    'Devi Sri Prasad',
    'Benny Dayal',
    'Hariharan',
    'Jasleen Royal',
    'Prateek Kuhad',
    'Ritviz',
    'Nucleya',
  ];

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final List<ArtistRef> followed = library.artists;

    return LibrarySectionPage(
      title: 'Artists',
      subtitle: '${followed.length} followed',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
        children: <Widget>[
          const SectionHeader(
            title: 'Indian artists',
            subtitle: 'Hindi and regional artists · tap a name for songs',
            padding: EdgeInsets.fromLTRB(4, 8, 4, 10),
          ),
          for (final String name in _indianArtists)
            GlassListTile(
              margin: const EdgeInsets.only(bottom: 6),
              onTap: () => openArtistByName(context, name: name),
              leading: ArtistAvatar(name: name, size: 42, ring: false),
              trailing: const Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: SaxifyColors.textFaint,
              ),
              child: Text(
                name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (followed.isNotEmpty) ...<Widget>[
            SectionHeader(
              title: 'Followed artists',
              subtitle: '${followed.length} saved on this device',
              padding: const EdgeInsets.fromLTRB(4, 22, 4, 10),
            ),
            for (final ArtistRef artist in followed)
              GlassListTile(
                margin: const EdgeInsets.only(bottom: 6),
                onTap: () => openArtistByName(
                  context,
                  name: artist.name,
                  channelId: artist.channelId,
                ),
                leading: ArtistAvatar(
                  name: artist.name,
                  imageUrl: artist.imageUrl,
                  size: 44,
                  ring: false,
                ),
                trailing: const Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: SaxifyColors.textFaint,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      artist.subscribers ?? 'Artist',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: SaxifyColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- Downloads
class LibraryDownloadsPage extends StatelessWidget {
  const LibraryDownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final MusicDownloadService downloads = context
        .watch<MusicDownloadService>();
    final PlaybackService playback = context.read<PlaybackService>();
    final List<MusicDownloadJob> saved = downloads.downloaded;
    final List<Song> songs = saved
        .map((MusicDownloadJob job) => job.song)
        .toList();
    final Map<String, String> sources = <String, String>{
      for (final MusicDownloadJob job in saved)
        if (job.offlinePath != null) job.song.id: job.offlinePath!,
    };
    final List<MusicDownloadJob> active = downloads.jobs
        .where(
          (MusicDownloadJob job) =>
              job.phase == MusicDownloadPhase.running ||
              job.phase == MusicDownloadPhase.idle,
        )
        .toList();
    final SaxifyAccent accent = context.accent;

    return LibrarySectionPage(
      title: 'Your Downloads',
      subtitle: '${saved.length} saved on this phone',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
        children: <Widget>[
          const SectionHeader(
            title: 'Your Downloads',
            subtitle: 'Saved on this phone · plays offline',
            padding: EdgeInsets.fromLTRB(4, 8, 4, 10),
          ),
          // ---- live downloads, each with its own percentage ----------------
          for (final MusicDownloadJob job in active)
            GlassPanel(
              radius: SaxifyTheme.radiusMd,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Artwork(url: job.song.thumbnailUrl, size: 44, radius: 10),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          job.song.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cancel download',
                        icon: const Icon(Icons.close_rounded, size: 18),
                        onPressed: () => downloads.cancel(job),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GlassProgress(
                    fraction: job.fraction,
                    indeterminate:
                        job.phase == MusicDownloadPhase.idle ||
                        job.fraction <= 0,
                    label: job.phase == MusicDownloadPhase.running
                        ? 'Downloading ${(job.fraction * 100).round()}%'
                        : 'Waiting in queue',
                  ),
                ],
              ),
            ),
          for (final job in downloads.jobs.where(
            (j) => j.phase == MusicDownloadPhase.failed,
          ))
            ListTile(
              leading: const Icon(Icons.error_outline),
              title: Text(
                job.song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(job.error ?? 'Download failed'),
              trailing: IconButton(
                tooltip: 'Retry download',
                icon: const Icon(Icons.refresh),
                onPressed: () => downloads.enqueue(job.song, playback),
              ),
            ),
          if (saved.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 4, 10),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      '${saved.length} songs saved',
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: SaxifyColors.textMuted,
                      ),
                    ),
                  ),
                  GlassButton(
                    label: 'Play all',
                    icon: Icons.play_arrow_rounded,
                    compact: true,
                    onPressed: () => playback.playOfflineQueue(songs, sources),
                  ),
                ],
              ),
            ),
          if (saved.isEmpty && active.isEmpty)
            const EmptyState(
              icon: Icons.download_outlined,
              title: 'No songs downloaded yet',
              message:
                  'Tap the download icon beside any song. Your files stay on this device and play offline.',
            ),
          for (final MusicDownloadJob job in saved)
            GlassListTile(
              margin: const EdgeInsets.only(bottom: 8),
              onTap: job.offlinePath == null
                  ? null
                  : () => playback.playOfflineSong(
                      job.song,
                      job.offlinePath!,
                    ),
              leading: Artwork(
                url: job.song.thumbnailUrl,
                size: 48,
                radius: 12,
              ),
              trailing: IconButton(
                tooltip: 'Delete download',
                onPressed: () => downloads.delete(job, playback: playback),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: SaxifyColors.danger,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    job.song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  QualityBadge(quality: job.song.quality),
                  const SizedBox(height: 3),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.offline_pin_rounded,
                        size: 13,
                        color: accent.primary,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          '${job.song.artist}${job.song.album == null ? '' : ' · ${job.song.album}'} · ${(job.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: SaxifyColors.textMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ History
class LibraryHistoryPage extends StatelessWidget {
  const LibraryHistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final PlaybackService playback = context.read<PlaybackService>();

    if (library.history.isEmpty) {
      return LibrarySectionPage(
        title: 'Recently played',
        subtitle: 'Nothing yet',
        child: const SingleChildScrollView(
          child: EmptyState(
            icon: Icons.history_rounded,
            title: 'No listening history',
            message: 'Play something and it will show up here automatically.',
          ),
        ),
      );
    }

    final List<Song> ordered = library.history
        .map((HistoryEntry e) => e.song)
        .toList();

    return LibrarySectionPage(
      title: 'Recently played',
      subtitle: '${library.history.length} songs',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${library.history.length} recently played',
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: SaxifyColors.textMuted,
                  ),
                ),
              ),
              GlassButton(
                label: 'Play all',
                icon: Icons.play_arrow_rounded,
                compact: true,
                onPressed: () => playback.playQueue(ordered),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Clear history',
                icon: const Icon(
                  Icons.delete_sweep_rounded,
                  size: 20,
                  color: SaxifyColors.textFaint,
                ),
                onPressed: library.clearHistory,
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (int i = 0; i < library.history.length; i++)
            SongTile(
              song: library.history[i].song,
              subtitle:
                  '${library.history[i].song.artist} · ${Fmt.relative(library.history[i].playedAt)}',
              onTap: () => playback.playQueue(ordered, startIndex: i),
            ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------------- On device
class OnDevicePage extends StatelessWidget {
  const OnDevicePage({super.key});

  @override
  Widget build(BuildContext context) {
    final LocalMusicService local = context.watch<LocalMusicService>();

    if (!local.hasScanned && local.songs.isEmpty) {
      return LibrarySectionPage(
        title: 'On this device',
        subtitle: 'Not scanned yet',
        child: EmptyState(
          icon: Icons.perm_media_rounded,
          title: 'On device',
          message: 'Show songs already saved on this phone.',
          actionLabel: 'Scan device music',
          onAction: () =>
              context.read<LocalMusicService>().scan(context: context),
        ),
      );
    }

    return LibrarySectionPage(
      title: 'On this device',
      subtitle: '${local.songs.length} songs on this phone',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    local.scanning
                        ? 'Scanning device music…'
                        : '${local.songs.length} songs on this device',
                    style: const TextStyle(
                      color: SaxifyColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ),
                TextButton.icon(
                  onPressed: local.scanning
                      ? null
                      : () => context.read<LocalMusicService>().scan(
                          context: context,
                        ),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Re-scan'),
                ),
              ],
            ),
          ),
          const SectionHeader(
            title: 'Songs',
            subtitle: 'Every audio file found on this phone',
            padding: EdgeInsets.fromLTRB(4, 4, 4, 8),
          ),
          if (local.songs.isEmpty)
            const EmptyState(
              icon: Icons.music_off_rounded,
              title: 'No local songs found',
              message: 'Tap re-scan after adding music files to your phone.',
            )
          else
            for (int i = 0; i < local.songs.length; i++)
              SongTile(
                song: local.songs[i],
                showMenu: false,
                subtitle: 'On device · ${local.songs[i].artist}',
                onTap: () => context.read<PlaybackService>().playQueue(
                  local.songs,
                  startIndex: i,
                ),
              ),
          if (local.albums.isNotEmpty) ...<Widget>[
            const SectionHeader(
              title: 'Albums',
              subtitle: 'Grouped from your device tags',
              padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
            ),
            for (final LocalAlbum album in local.albums)
              GlassListTile(
                margin: const EdgeInsets.only(bottom: 8),
                leading: Artwork(url: album.artworkUri, size: 52, radius: 8),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                onTap: () =>
                    context.read<PlaybackService>().playQueue(album.songs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      album.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${album.artist} · ${album.songs.length} songs',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SaxifyColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (local.artists.isNotEmpty) ...<Widget>[
            const SectionHeader(
              title: 'Artists',
              subtitle: 'Who is on this phone',
              padding: EdgeInsets.fromLTRB(4, 18, 4, 8),
            ),
            for (final LocalArtist artist in local.artists)
              GlassListTile(
                margin: const EdgeInsets.only(bottom: 8),
                leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                trailing: const Icon(Icons.chevron_right_rounded, size: 18),
                onTap: () =>
                    context.read<PlaybackService>().playQueue(artist.songs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      artist.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${artist.songs.length} songs · On device',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: SaxifyColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Shared gradient header for a song collection.
class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({
    required this.label,
    required this.title,
    required this.subtitle,
    required this.coverUrl,
    required this.icon,
    required this.onPlay,
    required this.onShuffle,
  });

  final String label;
  final String title;
  final String subtitle;
  final String coverUrl;
  final IconData icon;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  gradient: accent.gradient,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accent.primary.withValues(alpha: 0.35),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: coverUrl.isEmpty
                    ? Icon(icon, size: 40, color: accent.onAccent)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            Artwork(url: coverUrl, radius: 0),
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(
                                  icon,
                                  size: 20,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w800,
                        color: accent.primary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SaxifyTheme.appleFont(
                        size: 23,
                        weight: FontWeight.w800,
                        letterSpacing: -0.7,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: SaxifyColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: <Widget>[
              Expanded(
                child: GlassButton(
                  label: 'Play',
                  icon: Icons.play_arrow_rounded,
                  onPressed: onPlay,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 54,
                height: 54,
                child: GlassIconButton(
                  icon: Icons.shuffle_rounded,
                  size: 54,
                  onPressed: onShuffle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
