import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/album_card.dart';
import '../../core/models/song.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/youtube_service.dart';
import '../../services/yt_music_parser.dart';
import '../widgets/collection_header.dart';
import '../widgets/sidify_widgets.dart';

/// An album, the site's way: the sleeve full-bleed at the top, fading into
/// its own colour, then the numbered track list. In this app an album is
/// resolved by the engine from the card's query (or by browsing a real
/// album/playlist id), exactly as before.
class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.album}) : browseItem = null;

  AlbumPage.fromBrowse({super.key, required MusicBrowseItem item})
      : album = AlbumCard(
          query: item.id,
          title: item.title,
          artist: item.kind,
          coverVideoId: null,
        ),
        browseItem = item;

  final AlbumCard album;
  final MusicBrowseItem? browseItem;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  late Future<List<Song>> _tracks;

  @override
  void initState() {
    super.initState();
    final YoutubeService youtube = context.read<YoutubeService>();
    _tracks = widget.browseItem != null
        ? youtube.browseTracks(widget.browseItem!)
        : youtube.searchSongs(widget.album.query, limit: 24);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<Song>>(
        future: _tracks,
        builder: (BuildContext context, AsyncSnapshot<List<Song>> snap) {
          final List<Song> songs = snap.data ?? <Song>[];
          final bool loading = snap.connectionState != ConnectionState.done;
          return CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: <Widget>[
              SliverToBoxAdapter(
                child: CollectionHeader(
                  artwork: widget.browseItem?.artwork ??
                      (songs.isNotEmpty
                          ? songs.first.thumbnailUrl
                          : widget.album.coverUrl),
                  title: widget.album.title,
                  subtitle: widget.album.artist,
                  meta: loading
                      ? 'Loading…'
                      : '${songs.length} song${songs.length == 1 ? '' : 's'}',
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
              if (loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      children: <Widget>[
                        SidifySkeleton(height: 52, radius: 8),
                        SizedBox(height: 8),
                        SidifySkeleton(height: 52, radius: 8),
                        SizedBox(height: 8),
                        SidifySkeleton(height: 52, radius: 8),
                      ],
                    ),
                  ),
                )
              else if (songs.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.album_rounded,
                    title: 'No songs found',
                    desc: 'This album did not answer. Try again in a moment.',
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
                        numbered: true,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
