import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../settings/playlist_sync_sheet.dart';
import '../widgets/artwork.dart';
import '../widgets/neon.dart';
import '../widgets/song_tile.dart';

/// A user playlist's detail screen.
class PlaylistDetailPage extends StatelessWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final PlaybackService playback = context.read<PlaybackService>();
    final SaxifyAccent accent = context.accent;

    final Playlist? playlist = library.playlistById(playlistId);

    if (playlist == null) {
      return Scaffold(
        body: SafeArea(
          child: EmptyState(
            icon: Icons.queue_music_rounded,
            title: 'Playlist not found',
            message: 'It may have been deleted.',
            actionLabel: 'Go back',
            onAction: () => Navigator.of(context).maybePop(),
          ),
        ),
      );
    }

    final List<Song> songs = playlist.songs;

    return Scaffold(
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            expandedHeight: 260,
            backgroundColor: SaxifyColors.background,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: <Color>[
                          accent.primary.withValues(alpha: 0.35),
                          accent.secondary.withValues(alpha: 0.12),
                          SaxifyColors.background,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 18,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            gradient: songs.isEmpty ? accent.gradient : null,
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: accent.primary.withValues(alpha: 0.35),
                                blurRadius: 28,
                                offset: const Offset(0, 12),
                                spreadRadius: -8,
                              ),
                            ],
                          ),
                          child: songs.isEmpty
                              ? const Icon(Icons.queue_music_rounded,
                                  size: 40, color: Colors.black87)
                              : ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Artwork(
                                    url: playlist.artwork,
                                    size: 112,
                                    radius: 0,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text('PLAYLIST',
                                  style: TextStyle(
                                      fontSize: 10,
                                      letterSpacing: 1.5,
                                      fontWeight: FontWeight.w700,
                                      color: accent.primary)),
                              const SizedBox(height: 6),
                              Text(
                                playlist.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 22, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 5),
                              Text('${playlist.count} songs',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: SaxifyColors.textSecondary)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
              child: Row(
                children: <Widget>[
                  NeonButton(
                    label: 'Play',
                    icon: Icons.play_arrow_rounded,
                    expand: true,
                    onPressed: songs.isEmpty
                        ? null
                        : () => playback.playQueue(songs),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Share code',
                    onPressed: () => sharePlaylistCode(context, playlist),
                    icon: const Icon(Icons.ios_share_rounded),
                  ),
                  IconButton(
                    onPressed: songs.isEmpty
                        ? null
                        : () async {
                            await playback.playQueue(songs);
                            if (!playback.shuffleEnabled) {
                              await playback.toggleShuffle();
                            }
                          },
                    icon: const Icon(Icons.shuffle_rounded),
                    style: IconButton.styleFrom(
                      backgroundColor: SaxifyColors.surfaceAlt,
                      foregroundColor: SaxifyColors.textPrimary,
                      minimumSize: const Size(48, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (songs.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.music_note_rounded,
                title: 'This playlist is empty',
                message:
                    'Use “Add to playlist” from any song’s menu to fill it up.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 140),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext c, int i) => SongTile(
                    song: songs[i],
                    onTap: () => playback.playQueue(songs, startIndex: i),
                    onLongPress: () => _removeDialog(context, library, playlist, i),
                  ),
                  childCount: songs.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _removeDialog(BuildContext context, LibraryService library,
      Playlist playlist, int index) async {
    final Song song = playlist.songs[index];
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Remove from playlist?'),
        content: Text('"${song.title}" will be removed from "${playlist.name}".'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await library.removeFromPlaylist(playlist.id, song.id);
    }
  }
}
