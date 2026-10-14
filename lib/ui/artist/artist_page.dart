import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/artist.dart';
import '../../core/models/song.dart';
import '../../core/services/artist_service.dart';
import '../../core/services/home_catalog.dart';
import '../../core/services/library_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/youtube_service.dart';
import '../widgets/collection_header.dart';
import '../widgets/sidify_widgets.dart';

/// An artist, the site's way: the round photo, the name, a Follow action,
/// then their top songs. Resolution keeps the engine's old honesty — a
/// confident profile photo when one exists, their channel when it matches,
/// and their songs either way.
class ArtistPage extends StatefulWidget {
  const ArtistPage({super.key, required this.name, this.channelId, this.imageUrl});

  final String name;
  final String? channelId;
  final String? imageUrl;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  List<Song> _songs = <Song>[];
  String _photo = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _photo = widget.imageUrl ?? '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final YoutubeService youtube = context.read<YoutubeService>();
    final ArtistService artists = context.read<ArtistService>();
    final HomeCatalog catalog = context.read<HomeCatalog>();
    final String cached =
        catalog.photoFor(widget.name, fallback: widget.imageUrl ?? '');
    if (cached.isNotEmpty && _photo.isEmpty) _photo = cached;

    List<Song> songs = <Song>[];
    final String? channelId = widget.channelId;
    if (channelId != null && channelId.isNotEmpty) {
      try {
        songs = await youtube.channelUploads(channelId, limit: 30);
      } catch (_) {}
    }
    if (songs.isEmpty) {
      try {
        songs = await youtube.searchSongs('${widget.name} songs', limit: 30);
      } catch (_) {}
    }
    try {
      final ArtistProfile profile = await artists.resolve(widget.name);
      if (profile.imageUrl.isNotEmpty) _photo = profile.imageUrl;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final String followId = widget.channelId ?? '';
    final bool following =
        followId.isNotEmpty && library.isFollowing(followId);
    final String displayPhoto = _photo;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: CollectionHeader(
              artwork: displayPhoto,
              round: true,
              eyebrow: 'Artist',
              title: widget.name,
              meta: _loading
                  ? 'Loading…'
                  : '${_songs.length} song${_songs.length == 1 ? '' : 's'}',
              onPlay: _songs.isEmpty
                  ? null
                  : () => context
                      .read<PlaybackService>()
                      .playQueue(_songs, startIndex: 0),
              onShuffle: _songs.isEmpty
                  ? null
                  : () {
                      final List<Song> shuffled = List<Song>.of(_songs)
                        ..shuffle();
                      context
                          .read<PlaybackService>()
                          .playQueue(shuffled, startIndex: 0);
                    },
              action: followId.isEmpty
                  ? null
                  : HeaderAction(
                      icon: following
                          ? Icons.check_rounded
                          : Icons.person_add_rounded,
                      label: following ? 'Following' : 'Follow',
                      active: following,
                      onTap: () => library.toggleFollow(
                        ArtistRef(
                          channelId: followId,
                          name: widget.name,
                          imageUrl: displayPhoto,
                        ),
                      ),
                    ),
            ),
          ),
          if (_loading)
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
          else if (_songs.isEmpty)
            const SliverToBoxAdapter(
              child: EmptyState(
                icon: Icons.person_off_rounded,
                title: 'No songs found',
                desc: 'This artist did not answer. Try again in a moment.',
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.only(bottom: 190),
              sliver: SliverList.builder(
                itemCount: _songs.length,
                itemBuilder: (BuildContext context, int i) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: TrackRow(tracks: _songs, index: i),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
