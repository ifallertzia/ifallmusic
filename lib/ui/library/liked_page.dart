import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/playback_service.dart';
import '../widgets/collection_header.dart';
import '../widgets/sidify_widgets.dart';

/// Liked Songs: the heart cover, then everything you loved, newest first.
class LikedSongsPage extends StatelessWidget {
  const LikedSongsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final List<Song> songs = library.likedSongs;
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: CollectionHeader(
              cover: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[Color(0xFF5A1020), Color(0xFF2A0810)],
                  ),
                ),
                child: const Center(
                  child: Icon(Icons.favorite_rounded, size: 120, color: Colors.white),
                ),
              ),
              eyebrow: 'Playlist',
              title: 'Liked Songs',
              meta: '${songs.length} song${songs.length == 1 ? '' : 's'}',
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
            ),
          ),
          if (songs.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.favorite_border_rounded,
                title: 'Songs you love live here',
                desc: 'Tap the heart on any song and it will be waiting here.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 190),
              sliver: SliverList.builder(
                itemCount: songs.length,
                itemBuilder: (BuildContext context, int i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TrackRow(tracks: songs, index: i),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
