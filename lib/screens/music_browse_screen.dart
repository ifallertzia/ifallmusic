import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/models/song.dart';
import '../core/services/music_download_service.dart';
import '../core/services/playback_service.dart';
import '../core/services/youtube_service.dart';
import '../services/yt_music_parser.dart';
import '../ui/downloads/storage_permission.dart';
import '../ui/widgets/song_tile.dart';

class MusicBrowseScreen extends StatefulWidget {
  const MusicBrowseScreen({super.key, required this.item});
  final MusicBrowseItem item;
  @override
  State<MusicBrowseScreen> createState() => _MusicBrowseScreenState();
}

class _MusicBrowseScreenState extends State<MusicBrowseScreen> {
  late Future<List<Song>> _tracks;
  @override
  void initState() {
    super.initState();
    _tracks = context.read<YoutubeService>().browseTracks(widget.item);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.item.title)),
    body: FutureBuilder<List<Song>>(
      future: _tracks,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done)
          return const Center(child: CircularProgressIndicator());
        final tracks = snap.data ?? <Song>[];
        if (tracks.isEmpty)
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Tracks unavailable. Check your connection.'),
                TextButton(
                  onPressed: () => setState(
                    () => _tracks = context.read<YoutubeService>().browseTracks(
                      widget.item,
                    ),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        return ListView(
          children: [
            Wrap(
              spacing: 12,
              children: [
                TextButton.icon(
                  onPressed: () =>
                      context.read<PlaybackService>().playQueue(tracks),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Play all'),
                ),
                TextButton.icon(
                  onPressed: () async {
                    if (!await StoragePermission.ensure(context) ||
                        !context.mounted)
                      return;
                    final downloads = context.read<MusicDownloadService>();
                    final playback = context.read<PlaybackService>();
                    for (final song in tracks) {
                      downloads.enqueue(song, playback);
                    }
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Tracks added to downloads'),
                      ),
                    );
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('Download all'),
                ),
              ],
            ),
            for (int i = 0; i < tracks.length; i++)
              SongTile(
                song: tracks[i],
                onTap: () => context.read<PlaybackService>().playQueue(
                  tracks,
                  startIndex: i,
                ),
              ),
          ],
        );
      },
    ),
  );
}
