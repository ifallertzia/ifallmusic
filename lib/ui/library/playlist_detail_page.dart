import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/library_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../widgets/collection_header.dart';
import '../widgets/sidify_widgets.dart';
import '../widgets/song_menu.dart';

/// A playlist opened: the mosaic sleeve, Play / Shuffle, then the songs —
/// with rename, remove and delete through the "…" at the top.
class PlaylistDetailPage extends StatelessWidget {
  const PlaylistDetailPage({super.key, required this.playlist});

  final Playlist playlist;

  Playlist? _live(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    for (final Playlist p in library.playlists) {
      if (p.id == playlist.id) return p;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final Playlist? live = _live(context);
    if (live == null) {
      return Scaffold(
        body: SafeArea(
          child: Column(
            children: <Widget>[
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              const EmptyState(
                icon: Icons.playlist_remove_rounded,
                title: 'This playlist is gone',
                desc: 'It was deleted, so there is nothing to show.',
              ),
            ],
          ),
        ),
      );
    }
    final List<Song> songs = live.songs;
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: CollectionHeader(
              artwork: live.artwork,
              arts: songs
                  .take(4)
                  .map((Song s) => s.thumbnailUrl)
                  .toList(),
              eyebrow: 'Playlist',
              title: live.name,
              meta:
                  '${songs.length} song${songs.length == 1 ? '' : 's'}',
              onPlay: songs.isEmpty
                  ? null
                  : () => context
                      .read<PlaybackService>()
                      .playQueue(songs, startIndex: 0),
              onShuffle: songs.isEmpty
                  ? null
                  : () {
                      final List<Song> shuffled = List<Song>.of(songs)
                        ..shuffle();
                      context
                          .read<PlaybackService>()
                          .playQueue(shuffled, startIndex: 0);
                    },
              action: HeaderAction(
                icon: Icons.more_horiz_rounded,
                label: 'Playlist options',
                onTap: () => _options(context, live),
              ),
            ),
          ),
          if (songs.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.queue_music_rounded,
                title: 'No songs yet',
                desc: 'Add songs from any song\'s "…" menu.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 190),
              sliver: SliverList.builder(
                itemCount: songs.length,
                itemBuilder: (BuildContext context, int i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TrackRow(
                    tracks: songs,
                    index: i,
                    onRemove: () => context
                        .read<LibraryService>()
                        .removeFromPlaylist(live.id, songs[i].id),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _options(BuildContext context, Playlist playlist) async {
    final LibraryService library = context.read<LibraryService>();
    await showSidifySheet(
      context,
      title: playlist.name,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _sheetItem(context, Icons.edit_rounded, 'Rename', () async {
            Navigator.of(context).pop();
            final String? name = await _askRename(context, playlist.name);
            if (name != null && name.trim().isNotEmpty) {
              await library.renamePlaylist(playlist.id, name.trim());
            }
          }),
          _sheetItem(context, Icons.delete_rounded, 'Delete playlist',
              () async {
            Navigator.of(context).pop();
            await library.deletePlaylist(playlist.id);
            showAppNotice('Playlist deleted');
          }, danger: true),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Widget _sheetItem(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    bool danger = false,
  }) {
    final SidifyTokens t = context.sidify;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: <Widget>[
              Icon(icon, size: 19, color: danger ? t.danger : t.text),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 15.5,
                  color: danger ? t.danger : t.text,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _askRename(BuildContext context, String current) {
    final TextEditingController controller =
        TextEditingController(text: current);
    final SidifyTokens t = context.sidify;
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: t.raised,
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Rename playlist', style: SidifyText.title(t.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: t.text),
          onSubmitted: (String v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: t.text2)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: Text('Save', style: TextStyle(color: t.text)),
          ),
        ],
      ),
    );
  }
}
