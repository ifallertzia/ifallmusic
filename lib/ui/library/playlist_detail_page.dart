import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/ifall_ui.dart';
import '../settings/playlist_sync_sheet.dart';
import '../widgets/artwork.dart';
import '../widgets/song_tile.dart';

/// A user playlist's detail screen — BitChord's warm gradient header, black
/// body, one accent-coloured Play pill.
class PlaylistDetailPage extends StatelessWidget {
  const PlaylistDetailPage({super.key, required this.playlistId});

  final String playlistId;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final LibraryService library = context.watch<LibraryService>();

    final Playlist? playlist = library.playlistById(playlistId);

    if (playlist == null) {
      return Scaffold(
        backgroundColor: c.background,
        body: SafeArea(
          child: IfallEmpty(
            icon: Icons.queue_music_rounded,
            message: 'This playlist may have been deleted.',
            actionLabel: 'Go back',
            action: () => Navigator.of(context).maybePop(),
          ),
        ),
      );
    }

    return _PlaylistBody(playlist: playlist);
  }
}

class _PlaylistBody extends StatelessWidget {
  const _PlaylistBody({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final PlaybackService playback = context.read<PlaybackService>();
    final LibraryService library = context.watch<LibraryService>();
    final List<Song> songs = playlist.songs;
    final Color onAccent =
        ThemeData.estimateBrightnessForColor(c.accent) == Brightness.dark
            ? Colors.white
            : Colors.black;

    return Scaffold(
      backgroundColor: c.background,
      body: CustomScrollView(
        slivers: <Widget>[
          SliverAppBar(
            pinned: true,
            expandedHeight: 260,
            backgroundColor: c.background,
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
                          c.accent.withValues(alpha: 0.35),
                          c.accent.withValues(alpha: 0.12),
                          c.background,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 18,
                    right: 18,
                    bottom: 18,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        Container(
                          width: 112,
                          height: 112,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(IfallUI.rMd),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.45),
                                blurRadius: 28,
                                offset: const Offset(0, 12),
                                spreadRadius: -8,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(IfallUI.rMd),
                            child: songs.isEmpty
                                ? ColoredBox(
                                    color: c.fill,
                                    child: Icon(
                                      Icons.queue_music_rounded,
                                      size: 40,
                                      color: c.onSurfaceVariant,
                                    ),
                                  )
                                : Artwork(
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
                              Text('PLAYLIST', style: IfallText.label(c.accent)),
                              const SizedBox(height: 6),
                              Text(
                                playlist.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: IfallText.style(
                                  22,
                                  weight: FontWeight.w800,
                                  letterSpacing: -0.7,
                                  color: c.onSurface,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                '${playlist.count} songs',
                                style: IfallText.caption(c.onSurfaceVariant),
                              ),
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
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: FilledButton.icon(
                        onPressed: songs.isEmpty
                            ? null
                            : () => playback.playQueue(songs),
                        style: FilledButton.styleFrom(
                          backgroundColor: c.accent,
                          foregroundColor: onAccent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(IfallUI.rPill),
                          ),
                        ),
                        icon: const Icon(Icons.play_arrow_rounded),
                        label: Text(
                          'Play',
                          style: IfallText.body(onAccent).copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    tooltip: 'Share code',
                    onPressed: () => sharePlaylistCode(context, playlist),
                    icon: Icon(Icons.ios_share_rounded, color: c.onSurface),
                  ),
                  IconButton(
                    tooltip: 'Shuffle',
                    onPressed: songs.isEmpty
                        ? null
                        : () async {
                            await playback.playQueue(songs);
                            if (!playback.shuffleEnabled) {
                              await playback.toggleShuffle();
                            }
                          },
                    icon: Icon(Icons.shuffle_rounded, color: c.onSurface),
                    style: IconButton.styleFrom(
                      backgroundColor: c.fill,
                      minimumSize: const Size(48, 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (songs.isEmpty)
            SliverToBoxAdapter(
              child: IfallEmpty(
                icon: Icons.music_note_rounded,
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
                    onLongPress: () =>
                        _removeDialog(context, library, playlist, i),
                  ),
                  childCount: songs.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _removeDialog(
    BuildContext context,
    LibraryService library,
    Playlist playlist,
    int index,
  ) async {
    final Song song = playlist.songs[index];
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Remove from playlist?'),
        content: Text(
          '"${song.title}" will be removed from "${playlist.name}".',
        ),
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
