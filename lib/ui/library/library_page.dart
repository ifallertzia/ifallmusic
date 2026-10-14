import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/branding.dart';

import '../../core/models/artist.dart';
import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/local_music_service.dart';
import '../../core/services/music_download_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/ifall_ui.dart';
import '../../core/utils/format.dart';
import '../../screens/lyrics_finder_screen.dart';
import '../artist/artist_router.dart';
import '../settings/backup_sheet.dart';
import '../settings/playlist_sync_sheet.dart';
import '../shell/shell_controller.dart';
import '../widgets/artwork.dart';
import '../widgets/media_cards.dart';
import '../widgets/song_tile.dart';
import 'playlist_detail_page.dart';
import '../shell/ifall_shell.dart';

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

    final List<({String title, String detail, IconData icon, int tab, Color tone})>
    sections = <({String title, String detail, IconData icon, int tab, Color tone})>[
      (
        title: 'Liked songs',
        detail: '${library.likedSongs.length} songs',
        icon: Icons.favorite_rounded,
        tab: LibraryTabs.liked,
        tone: const Color(0xFFF43F5E),
      ),
      (
        title: 'Playlists',
        detail: '${library.playlists.length} playlists',
        icon: Icons.queue_music_rounded,
        tab: LibraryTabs.playlists,
        tone: const Color(0xFF8B5CF6),
      ),
      (
        title: 'Your songs',
        detail: '${library.songs.length} saved songs',
        icon: Icons.music_note_rounded,
        tab: LibraryTabs.songs,
        tone: const Color(0xFF3B82F6),
      ),
      (
        title: 'Downloads',
        detail: '${downloads.downloaded.length} offline songs',
        icon: Icons.download_rounded,
        tab: LibraryTabs.downloads,
        tone: const Color(0xFFF59E0B),
      ),
      (
        title: 'On this device',
        detail: '${local.songs.length} songs',
        icon: Icons.phone_android_rounded,
        tab: LibraryTabs.onDevice,
        tone: const Color(0xFF14B8A6),
      ),
      (
        title: 'Recently played',
        detail: '${library.history.length} songs',
        icon: Icons.history_rounded,
        tab: LibraryTabs.history,
        tone: const Color(0xFFEC4899),
      ),
      (
        title: 'Artists',
        detail: '${library.artists.length} followed',
        icon: Icons.mic_rounded,
        tab: LibraryTabs.artists,
        tone: const Color(0xFF10B981),
      ),
      (
        title: 'Lyrics Finder',
        detail: 'Find the words to any track',
        icon: Icons.lyrics_outlined,
        tab: LibraryTabs.lyrics,
        tone: const Color(0xFF06B6D4),
      ),
    ];

    final IfallPalette c = IfallPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _LibraryHeader(library: library),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.only(bottom: IfallInsets.bottom, top: 4),
            itemCount: sections.length + 1,
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(18, 2, 18, 8),
                  child: Text(
                    'Your music, ready when you are.',
                    style: IfallText.caption(c.onSurfaceVariant),
                  ),
                );
              }
              final section = sections[index - 1];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 3),
                child: IfallGlass(
                  radius: IfallUI.rMd,
                  blur: 0,
                  onTap: () => _openSection(section.tab),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(11),
                          color: section.tone.withValues(alpha: 0.18),
                        ),
                        child: Icon(section.icon, size: 19, color: section.tone),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              section.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: IfallText.body(c.onSurface)
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              section.detail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: IfallText.caption(c.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 19,
                        color: c.onSurfaceVariant,
                      ),
                    ],
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
    final IfallPalette c = IfallPalette.of(context);
    // A section is pushed onto the APP navigator, which sits outside the
    // shell's Scaffold, so nothing above it supplies a Material. Every
    // Material widget in here (BackButton's InkWell, SongTile, the glass
    // tiles) would otherwise throw "No Material widget found".
    return Material(
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
                          style: IfallText.title(c.onSurface),
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: IfallText.caption(c.onSurfaceVariant),
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
    );
  }
}

class _LibraryHeader extends StatelessWidget {
  const _LibraryHeader({required this.library});

  final LibraryService library;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  'Your Space',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IfallText.display(c.onSurface),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.backup_outlined),
                tooltip: 'Backup / import library JSON',
                onPressed: () => showBackupSheet(context, library),
                color: c.onSurface,
              ),
            ],
          ),
          Text(
            '${library.likedSongs.length} liked · ${library.playlists.length} playlists · '
            '${library.songs.length} songs',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: IfallText.caption(c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Liked Songs

/// Liked songs, presented as a playlist: big header, shuffle + play, then the
/// tracks in the order they were liked.
class LikedSongsPage extends StatelessWidget {
  const LikedSongsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final PlaybackService playback = context.read<PlaybackService>();
    final List<Song> songs = library.likedSongs;

    return LibrarySectionPage(
      title: 'Liked Songs',
      subtitle: songs.isEmpty ? 'Nothing liked yet' : '${songs.length} songs',
      child: songs.isEmpty
          ? const IfallEmpty(
              icon: Icons.favorite_border_rounded,
              message:
                  'Tap the heart on any track and it will live here, saved on this device.',
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
    final IfallPalette c = IfallPalette.of(context);
    final List<Playlist> playlists = library.playlists;

    return LibrarySectionPage(
      title: 'Playlists',
      subtitle: '${playlists.length} playlists',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
        children: <Widget>[
          IfallGroup(
            children: <Widget>[
              IfallRow(
                icon: Icons.add_rounded,
                title: 'Create playlist',
                subtitle: 'Build your own universe of sound',
                onTap: () => _create(context, library),
              ),
              IfallRow(
                icon: Icons.qr_code_2_rounded,
                title: 'Share playlists',
                subtitle: 'Generate a code for every playlist',
                onTap: () => shareAllPlaylistCodes(context),
              ),
              IfallRow(
                icon: Icons.download_for_offline_rounded,
                title: 'Import a code',
                subtitle: 'Paste a playlist code you were sent',
                onTap: () => showImportCodeSheet(context),
              ),
            ],
          ),
          if (playlists.isEmpty)
            const IfallEmpty(
              icon: Icons.queue_music_rounded,
              message:
                  'Create a playlist above, then use "Add to playlist" from any song menu.',
            )
          else ...<Widget>[
            IfallSectionHeader(
              title: 'Your playlists',
              subtitle: '${playlists.length} saved on this device',
            ),
            IfallGroup(
              children: <Widget>[
                for (final Playlist playlist in playlists)
                  IfallRow(
                    title: playlist.name,
                    subtitle:
                        '${playlist.count} songs · ${Fmt.date(playlist.createdAt)}',
                    trailing: _PlaylistArtwork(playlist: playlist),
                    onTap: () => _openPlaylist(context, playlist),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Text(
                'Long-press is not needed — open a playlist and use the ⋮ menu '
                'to rename, share or delete it.',
                style: IfallText.caption(c.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PlaylistArtwork extends StatelessWidget {
  const _PlaylistArtwork({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Artwork(
          url: playlist.artwork,
          size: 46,
          radius: 10,
          fallbackIcon: Icons.queue_music_rounded,
        ),
        const SizedBox(width: 4),
        Icon(Icons.chevron_right_rounded, size: 18, color: IfallPalette.of(context).onSurfaceVariant),
      ],
    );
  }
}

// --------------------------------------------------------------------- Songs

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
          ? const IfallEmpty(
              icon: Icons.library_music_outlined,
              message:
                  'Songs you add to the library from the song menu collect here.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 40),
              children: <Widget>[
                _PlayAllRow(
                  label: '${songs.length} saved songs',
                  onPlay: () => playback.playQueue(songs),
                ),
                const SizedBox(height: 8),
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

class _PlayAllRow extends StatelessWidget {
  const _PlayAllRow({required this.label, required this.onPlay, this.trailing});

  final String label;
  final VoidCallback onPlay;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(label, style: IfallText.caption(c.onSurfaceVariant)),
          ),
          _PillButton(
            label: 'Play all',
            icon: Icons.play_arrow_rounded,
            filled: true,
            onTap: onPlay,
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
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
    final Color onAccent = ThemeData.estimateBrightnessForColor(c.accent) ==
            Brightness.dark
        ? Colors.white
        : Colors.black;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(IfallUI.rPill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(IfallUI.rPill),
            color: filled ? c.accent : Colors.transparent,
            border: filled ? null : Border.all(color: c.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 17, color: filled ? onAccent : c.onSurface),
              const SizedBox(width: 6),
              Text(
                label,
                style: IfallText.body(
                  filled ? onAccent : c.onSurface,
                ).copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ Artists

class LibraryArtistsPage extends StatelessWidget {
  const LibraryArtistsPage({super.key});

  /// BitChord-style starter list: the artists people search for first, so an
  /// empty library still has somewhere to go.
  static const List<String> suggestedArtists = <String>[
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
    final IfallPalette c = IfallPalette.of(context);

    return LibrarySectionPage(
      title: 'Artists',
      subtitle: followed.isEmpty
          ? 'Start from the suggestions'
          : '${followed.length} followed',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
        children: <Widget>[
          if (followed.isNotEmpty) ...<Widget>[
            IfallSectionHeader(
              title: 'Followed artists',
              subtitle: '${followed.length} saved on this device',
            ),
            IfallGroup(
              children: <Widget>[
                for (final ArtistRef artist in followed)
                  IfallRow(
                    title: artist.name,
                    subtitle: artist.subscribers ?? 'Artist',
                    trailing: ArtistAvatar(
                      name: artist.name,
                      imageUrl: artist.imageUrl,
                      size: 40,
                      ring: false,
                    ),
                    onTap: () => openArtistByName(
                      context,
                      name: artist.name,
                      channelId: artist.channelId,
                    ),
                  ),
              ],
            ),
          ],
          IfallSectionHeader(
            title: 'Suggested artists',
            subtitle: 'Hindi and regional · tap a name for songs',
          ),
          IfallGroup(
            footer:
                'Suggestions are alphabetical and never change what is saved on '
                'your device.',
            children: <Widget>[
              for (final String name in suggestedArtists)
                IfallRow(
                  title: name,
                  trailing: ArtistAvatar(name: name, size: 36, ring: false),
                  onTap: () => openArtistByName(context, name: name),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
            child: Text(
              'Follow an artist from their page and they move to the top of '
              'this list.',
              style: IfallText.caption(c.onSurfaceVariant),
            ),
          ),
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
    final IfallPalette c = IfallPalette.of(context);

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

    return LibrarySectionPage(
      title: 'Your Downloads',
      subtitle: '${saved.length} saved on this phone',
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 40),
        children: <Widget>[
          // ---- live downloads, each with its own percentage -------------
          if (active.isNotEmpty) ...<Widget>[
            IfallSectionHeader(
              title: 'In progress',
              subtitle: '${active.length} working',
            ),
            IfallGroup(
              children: <Widget>[
                for (final MusicDownloadJob job in active)
                  _ActiveDownloadRow(job: job, downloads: downloads),
              ],
            ),
          ],
          if (saved.isEmpty && active.isEmpty)
            const IfallEmpty(
              icon: Icons.download_outlined,
              message:
                  'Tap the download icon beside any song. Your files stay on this device and play offline.',
            ),
          if (saved.isNotEmpty) ...<Widget>[
            _PlayAllRow(
              label: '${saved.length} songs saved',
              onPlay: () => playback.playOfflineQueue(songs, sources),
            ),
            const SizedBox(height: 8),
            IfallGroup(
              footer: 'Downloaded files play with no network at all.',
              children: <Widget>[
                for (final MusicDownloadJob job in saved)
                  IfallRow(
                    title: job.song.title,
                    subtitle:
                        '${job.song.artist}${job.song.album == null ? '' : ' · ${job.song.album}'} · ${(job.size / (1024 * 1024)).toStringAsFixed(1)} MB',
                    trailing: Artwork(
                      url: job.song.thumbnailUrl,
                      size: 46,
                      radius: 10,
                    ),
                    onTap: job.offlinePath == null
                        ? null
                        : () => playback.playOfflineSong(
                            job.song,
                            job.offlinePath!,
                          ),
                  ),
                for (final MusicDownloadJob job in saved)
                  IfallRow(
                    danger: true,
                    icon: Icons.delete_outline_rounded,
                    title: 'Delete “${job.song.title}”',
                    onTap: () => downloads.delete(job, playback: playback),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
              child: Text(
                'Audio is stored in the app’s private folder, so uninstalling '
                '${IfallBranding.appName} removes it.',
                style: IfallText.caption(c.onSurfaceVariant),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActiveDownloadRow extends StatelessWidget {
  const _ActiveDownloadRow({required this.job, required this.downloads});

  final MusicDownloadJob job;
  final MusicDownloadService downloads;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final bool running = job.phase == MusicDownloadPhase.running;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Artwork(url: job.song.thumbnailUrl, size: 40, radius: 9),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  job.song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IfallText.body(c.onSurface),
                ),
              ),
              IconButton(
                tooltip: 'Cancel download',
                icon: const Icon(Icons.close_rounded, size: 18),
                color: c.onSurfaceVariant,
                onPressed: () => downloads.cancel(job),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: running && job.fraction > 0 ? job.fraction : null,
              minHeight: 4,
              backgroundColor: c.fill,
              valueColor: AlwaysStoppedAnimation<Color>(c.accent),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            running
                ? 'Downloading ${(job.fraction * 100).round()}%'
                : 'Waiting in queue',
            style: IfallText.caption(c.onSurfaceVariant),
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
      return const LibrarySectionPage(
        title: 'Recently played',
        subtitle: 'Nothing yet',
        child: IfallEmpty(
          icon: Icons.history_rounded,
          message: 'Play something and it will show up here automatically.',
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
          _PlayAllRow(
            label: '${library.history.length} recently played',
            onPlay: () => playback.playQueue(ordered),
            trailing: IconButton(
              tooltip: 'Clear history',
              icon: Icon(
                Icons.delete_sweep_rounded,
                size: 20,
                color: IfallPalette.of(context).onSurfaceVariant,
              ),
              onPressed: library.clearHistory,
            ),
          ),
          const SizedBox(height: 8),
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
    final IfallPalette c = IfallPalette.of(context);

    if (!local.hasScanned && local.songs.isEmpty) {
      return LibrarySectionPage(
        title: 'On this device',
        subtitle: 'Not scanned yet',
        child: IfallEmpty(
          icon: Icons.perm_media_rounded,
          message: 'Show songs already saved on this phone.',
          actionLabel: 'Scan device music',
          action: () => context.read<LocalMusicService>().scan(context: context),
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
            padding: const EdgeInsets.fromLTRB(6, 0, 6, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    local.scanning
                        ? 'Scanning device music…'
                        : '${local.songs.length} songs on this device',
                    style: IfallText.caption(c.onSurfaceVariant),
                  ),
                ),
                TextButton.icon(
                  onPressed: local.scanning
                      ? null
                      : () => context.read<LocalMusicService>().scan(
                          context: context,
                        ),
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Re-scan'),
                ),
              ],
            ),
          ),
          if (local.songs.isNotEmpty) ...<Widget>[
            IfallSectionHeader(
              title: 'Songs',
              subtitle: 'Every audio file found on this phone',
            ),
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
          ] else
            const IfallEmpty(
              icon: Icons.music_off_rounded,
              message: 'Tap re-scan after adding music files to your phone.',
            ),
          if (local.albums.isNotEmpty) ...<Widget>[
            IfallSectionHeader(
              title: 'Albums',
              subtitle: 'Grouped from your device tags',
            ),
            IfallGroup(
              children: <Widget>[
                for (final LocalAlbum album in local.albums)
                  IfallRow(
                    title: album.title,
                    subtitle: '${album.artist} · ${album.songs.length} songs',
                    trailing: Artwork(url: album.artworkUri, size: 46, radius: 8),
                    onTap: () =>
                        context.read<PlaybackService>().playQueue(album.songs),
                  ),
              ],
            ),
          ],
          if (local.artists.isNotEmpty) ...<Widget>[
            IfallSectionHeader(
              title: 'Artists',
              subtitle: 'Who is on this phone',
            ),
            IfallGroup(
              children: <Widget>[
                for (final LocalArtist artist in local.artists)
                  IfallRow(
                    title: artist.name,
                    subtitle: '${artist.songs.length} songs · On device',
                    trailing: CircleAvatar(
                      radius: 20,
                      backgroundColor: c.fill,
                      child: Icon(
                        Icons.person_rounded,
                        size: 18,
                        color: c.onSurfaceVariant,
                      ),
                    ),
                    onTap: () =>
                        context.read<PlaybackService>().playQueue(artist.songs),
                  ),
              ],
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
    final IfallPalette c = IfallPalette.of(context);
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
                  borderRadius: BorderRadius.circular(10),
                  color: c.accent.withValues(alpha: 0.16),
                  border: Border.all(color: c.accent.withValues(alpha: 0.35)),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: c.accent.withValues(alpha: 0.28),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                      spreadRadius: -8,
                    ),
                  ],
                ),
                child: coverUrl.isEmpty
                    ? Icon(icon, size: 40, color: c.accent)
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Stack(
                          fit: StackFit.expand,
                          children: <Widget>[
                            Artwork(url: coverUrl, radius: 0),
                            Align(
                              alignment: Alignment.bottomRight,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Icon(icon, size: 20, color: Colors.white),
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
                    Text(label, style: IfallText.label(c.accent)),
                    const SizedBox(height: 6),
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: IfallText.style(
                        23,
                        weight: FontWeight.w800,
                        letterSpacing: -0.7,
                        color: c.onSurface,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IfallText.caption(c.onSurfaceVariant),
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
                child: _CollectionButton(
                  label: 'Play',
                  icon: Icons.play_arrow_rounded,
                  filled: true,
                  onTap: onPlay,
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 54,
                height: 46,
                child: _CollectionButton(
                  label: '',
                  icon: Icons.shuffle_rounded,
                  onTap: onShuffle,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CollectionButton extends StatelessWidget {
  const _CollectionButton({
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
          height: 46,
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
              Icon(icon, size: 19, color: ink),
              if (label.isNotEmpty) ...<Widget>[
                const SizedBox(width: 7),
                Text(
                  label,
                  style: IfallText.body(ink)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
