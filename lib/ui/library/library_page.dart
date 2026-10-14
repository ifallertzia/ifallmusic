import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/artist.dart';
import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../artist/artist_page.dart';
import '../shell/sidify_routes.dart';
import '../shell/sidify_shell_controller.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/sidify_widgets.dart';
import 'downloads_page.dart';
import 'history_page.dart';
import 'liked_page.dart';
import 'local_music_page.dart';
import 'lyrics_finder_page.dart';
import 'replay_page.dart';

/// The Library, as the site lays it out: Replay cards, the quick links
/// (Liked Songs, History, Downloads, Lyrics finder, Listen Together),
/// Playlists (grid or list, pinnable), followed Artists and Recently played.
class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final LibraryService library = context.watch<LibraryService>();
    final bool grid = settings.libraryLayout != 'list';

    final List<Playlist> playlists = <Playlist>[...library.playlists];
    final List<String> pinned = settings.pinnedPlaylists;
    playlists.sort((Playlist a, Playlist b) {
      final int pa = pinned.contains(a.id) ? 0 : 1;
      final int pb = pinned.contains(b.id) ? 0 : 1;
      return pa.compareTo(pb);
    });
    final List<Song> recent = <Song>[
      for (final HistoryEntry e in library.history) e.song,
    ];

    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 190),
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          PageTitle(
            'Library',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SidifyIconButton(
                  icon: grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  label: grid ? 'Show as list' : 'Show as grid',
                  tone: 'fill',
                  size: 34,
                  onTap: () => settings
                      .setLibraryLayout(grid ? 'list' : 'grid'),
                ),
                const SizedBox(width: 8),
                SidifyIconButton(
                  icon: Icons.add_rounded,
                  label: 'New playlist',
                  tone: 'fill',
                  size: 34,
                  onTap: () => _createPlaylist(context),
                ),
              ],
            ),
          ),
          const _ReplayRow(),
          _links(context),
          _playlists(context, playlists, pinned, grid),
          if (library.artists.isNotEmpty)
            ShelfSection(
              title: 'Artists',
              children: <Widget>[
                for (final ArtistRef a in library.artists)
                  ArtistCardWidget(
                    name: a.name,
                    imageUrl: a.imageUrl,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArtistPage(
                          name: a.name,
                          channelId: a.channelId,
                          imageUrl: a.imageUrl,
                        ),
                        settings: const RouteSettings(name: SidifyRoutes.artist),
                      ),
                    ),
                  ),
              ],
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
        ],
      ),
    );
  }

  Future<void> _createPlaylist(BuildContext context) async {
    final String? name = await askPlaylistName(context);
    if (name == null || name.trim().isEmpty || !context.mounted) return;
    final Playlist p =
        await context.read<LibraryService>().createPlaylist(name.trim());
    if (context.mounted) openPlaylist(context, p);
  }

  Widget _links(BuildContext context) {
    final SidifyTokens t = context.sidify;
    Widget link(IconData icon, String label, VoidCallback onTap) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 54),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 24,
                  child: Icon(icon, size: 22, color: t.playing),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: t.hairline, width: 0.5),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            label,
                            style: TextStyle(fontSize: 17, color: t.text),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded,
                            size: 20, color: t.text3),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    void push(Widget page, String name) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => page,
          settings: RouteSettings(name: name),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        children: <Widget>[
          link(Icons.favorite_rounded, 'Liked Songs',
              () => push(const LikedSongsPage(), 'sidify/liked')),
          link(Icons.history_rounded, 'History',
              () => push(const HistoryPage(), 'sidify/history')),
          link(Icons.download_rounded, 'Downloads',
              () => push(const DownloadsPage(), 'sidify/downloads')),
          link(Icons.lyrics_rounded, 'Lyrics finder',
              () => push(const LyricsFinderPage(), 'sidify/lyrics-finder')),
          link(Icons.smartphone_rounded, 'On this device',
              () => push(const LocalMusicPage(), 'sidify/on-device')),
          link(Icons.people_rounded, 'Listen Together',
              () => context.read<SidifyShellController>().goTogether()),
        ],
      ),
    );
  }

  Widget _playlists(
    BuildContext context,
    List<Playlist> playlists,
    List<String> pinned,
    bool grid,
  ) {
    final SettingsService settings = context.read<SettingsService>();
    void togglePin(Playlist p) {
      final List<String> next = <String>[...pinned];
      if (next.contains(p.id)) {
        next.remove(p.id);
      } else {
        next.insert(0, p.id);
      }
      settings.setPinnedPlaylists(next);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SectionHeader(title: 'Playlists'),
          if (grid)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 22,
                  crossAxisSpacing: 14,
                  childAspectRatio: 0.78,
                ),
                itemCount: playlists.length + 1,
                itemBuilder: (BuildContext context, int i) {
                  if (i == 0) return _newPlaylistCard(context);
                  final Playlist p = playlists[i - 1];
                  final bool isPinned = pinned.contains(p.id);
                  return Stack(
                    children: <Widget>[
                      SquareCard(
                        width: 0, // stretch to the grid cell
                        title: p.name,
                        subtitle:
                            '${p.count} song${p.count == 1 ? '' : 's'}',
                        arts: p.songs
                            .take(4)
                            .map((Song s) => s.thumbnailUrl)
                            .toList(),
                        artwork: p.artwork,
                        onTap: () => openPlaylist(context, p),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: GestureDetector(
                          onTap: () => togglePin(p),
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.55),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.push_pin_rounded,
                              size: 13,
                              color: isPinned
                                  ? context.sidify.playing
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                children: <Widget>[
                  _newPlaylistRow(context),
                  for (final Playlist p in playlists)
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => openPlaylist(context, p),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 68,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Row(
                            children: <Widget>[
                              Artwork(
                                url: p.artwork,
                                size: 52,
                                radius: 8,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    Row(
                                      children: <Widget>[
                                        if (pinned.contains(p.id)) ...<Widget>[
                                          Icon(
                                            Icons.push_pin_rounded,
                                            size: 12,
                                            color: context.sidify.playing,
                                          ),
                                          const SizedBox(width: 5),
                                        ],
                                        Flexible(
                                          child: Text(
                                            p.name,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: context.sidify.text,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    Text(
                                      'Playlist · ${p.count} song${p.count == 1 ? '' : 's'}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: context.sidify.text2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              SidifyIconButton(
                                icon: Icons.push_pin_rounded,
                                label: pinned.contains(p.id) ? 'Unpin' : 'Pin',
                                size: 32,
                                iconSize: 15,
                                color: pinned.contains(p.id)
                                    ? context.sidify.playing
                                    : context.sidify.text2,
                                onTap: () => togglePin(p),
                              ),
                            ],
                          ),
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

  Widget _newPlaylistCard(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return GestureDetector(
      onTap: () => _createPlaylist(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: t.fill3, width: 1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.add_rounded, size: 34, color: t.text2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'New playlist',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: t.text),
          ),
        ],
      ),
    );
  }

  Widget _newPlaylistRow(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _createPlaylist(context),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          height: 68,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: <Widget>[
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  border: Border.all(color: t.fill3, width: 1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.add_rounded, size: 22, color: t.text2),
              ),
              const SizedBox(width: 12),
              Text('New playlist', style: TextStyle(fontSize: 16, color: t.text)),
            ],
          ),
        ),
      ),
    );
  }
}

/// The Replay entry cards (the site's ReplayRow): wallet-style cards with
/// your minutes, top artist and top song, from on-device history.
class _ReplayRow extends StatelessWidget {
  const _ReplayRow();

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final int year = DateTime.now().year;
    final SidifyTokens t = context.sidify;
    final List<HistoryEntry> history = library.history;

    if (history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        child: GestureDetector(
          onTap: () => _open(context),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.edge, width: 0.5),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: t.brand,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '${year % 100}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Replay $year',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                      ),
                      Text(
                        'Your top songs and artists show up here as you listen.',
                        style: TextStyle(fontSize: 13, color: t.text2),
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

    final ReplayStats stats = ReplayStats.fromHistory(history);
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: SizedBox(
        height: 118,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          physics: const BouncingScrollPhysics(),
          children: <Widget>[
            _ReplayCard(
              label: 'Replay $year',
              value: '${stats.minutes} min',
              detail: '${stats.plays} plays · ${stats.activeDays} days',
              artwork: stats.topSong?.thumbnailUrl ?? '',
              onTap: () => _open(context),
            ),
            if (stats.topArtist != null)
              _ReplayCard(
                label: 'Top artist',
                value: stats.topArtist!.artist,
                detail: '${stats.topArtist!.count} plays',
                artwork: stats.topArtist!.thumbnailUrl,
                onTap: () => _open(context),
              ),
            if (stats.topSong != null)
              _ReplayCard(
                label: 'Top song',
                value: stats.topSong!.title,
                detail: '${stats.topSong!.artist} · ${stats.topSong!.count} plays',
                artwork: stats.topSong!.thumbnailUrl,
                onTap: () => context
                    .read<PlaybackService>()
                    .playSong(stats.topSong!.song),
              ),
          ],
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const ReplayPage(),
        settings: const RouteSettings(name: 'sidify/replay'),
      ),
    );
  }
}

class _ReplayCard extends StatelessWidget {
  const _ReplayCard({
    required this.label,
    required this.value,
    required this.detail,
    required this.artwork,
    required this.onTap,
  });

  final String label;
  final String value;
  final String detail;
  final String artwork;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 230,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.raised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.edge, width: 0.5),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    label.toUpperCase(),
                    style: SidifyText.eyebrow(t.text2),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: t.text,
                    ),
                  ),
                  Text(
                    detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: t.text2),
                  ),
                  const SizedBox(height: 8),
                  const Row(
                    children: <Widget>[
                      SidifyLogoMark(size: 16),
                      SizedBox(width: 5),
                      Text(
                        'Sidify',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (artwork.isNotEmpty)
              Artwork(url: artwork, size: 58, radius: 10),
          ],
        ),
      ),
    );
  }
}
