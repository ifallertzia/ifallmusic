import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/models/album_card.dart';
import '../../core/models/song.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/youtube_service.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../widgets/artwork.dart';
import '../widgets/neon.dart';
import '../widgets/song_tile.dart';

/// The site's `/album/ytq-<base64>` route — an "album" is an encoded YouTube
/// search, so opening one just runs that query and shows the tracklist.
class AlbumPage extends StatefulWidget {
  const AlbumPage({super.key, required this.album});

  final AlbumCard album;

  @override
  State<AlbumPage> createState() => _AlbumPageState();
}

class _AlbumPageState extends State<AlbumPage> {
  late final Future<List<Song>> _future = _load();

  Future<List<Song>> _load() {
    final YoutubeService youtube = context.read<YoutubeService>();
    return youtube.searchSongs(widget.album.query, limit: 20);
  }

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final PlaybackService playback = context.read<PlaybackService>();

    return Scaffold(
      body: FutureBuilder<List<Song>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<List<Song>> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _AlbumSkeleton();
          }

          final List<Song> tracks = snapshot.data ?? <Song>[];
          final String cover = tracks.isNotEmpty
              ? tracks.first.thumbnailUrl
              : widget.album.coverUrl;
          final Duration total = tracks.fold<Duration>(
            Duration.zero,
            (Duration sum, Song s) => sum + (s.duration ?? Duration.zero),
          );

          return CustomScrollView(
            slivers: <Widget>[
              SliverAppBar(
                expandedHeight: 330,
                pinned: true,
                backgroundColor: SaxifyColors.background,
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Artwork(url: cover, radius: 0, fit: BoxFit.cover),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: <Color>[
                              Colors.black.withValues(alpha: 0.30),
                              Colors.black.withValues(alpha: 0.60),
                              SaxifyColors.background,
                            ],
                          ),
                        ),
                      ),
                      Positioned(
                        left: 20,
                        right: 20,
                        bottom: 16,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: <Widget>[
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: accent.primary.withValues(alpha: 0.30),
                                    blurRadius: 26,
                                    offset: const Offset(0, 10),
                                    spreadRadius: -6,
                                  ),
                                ],
                              ),
                              child: Artwork(
                                url: cover,
                                size: 116,
                                radius: 14,
                                fallbackIcon: Icons.album_rounded,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text(
                                    'ALBUM',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      letterSpacing: 1.6,
                                      fontWeight: FontWeight.w700,
                                      color: accent.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    widget.album.title,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 23,
                                      fontWeight: FontWeight.w700,
                                      height: 1.12,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    widget.album.artist,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        color: SaxifyColors.textSecondary),
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
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 6),
                  child: Row(
                    children: <Widget>[
                      NeonButton(
                        label: 'Play',
                        icon: Icons.play_arrow_rounded,
                        expand: true,
                        onPressed: tracks.isEmpty
                            ? null
                            : () => playback.playQueue(tracks, startIndex: 0),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: NeonButton(
                          label: 'Shuffle',
                          icon: Icons.shuffle_rounded,
                          filled: false,
                          onPressed: tracks.isEmpty
                              ? null
                              : () async {
                                  await playback.playQueue(tracks, startIndex: 0);
                                  if (!playback.shuffleEnabled) {
                                    await playback.toggleShuffle();
                                  }
                                },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Text(
                    '${tracks.length} tracks · ${_humanTotal(total)}',
                    style: const TextStyle(
                        fontSize: 12, color: SaxifyColors.textMuted),
                  ),
                ),
              ),
              if (tracks.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyState(
                    icon: Icons.album_rounded,
                    title: 'Nothing here yet',
                    message: 'This album search came back empty.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 140),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (BuildContext c, int i) => SongTile(
                        song: tracks[i],
                        rank: i + 1,
                        onTap: () => playback.playQueue(tracks, startIndex: i),
                      ),
                      childCount: tracks.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static String _humanTotal(Duration d) {
    if (d.inHours > 0) return '${d.inHours} hr ${d.inMinutes.remainder(60)} min';
    return '${d.inMinutes} min';
  }
}

class _AlbumSkeleton extends StatelessWidget {
  const _AlbumSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Column(
        children: <Widget>[
          SizedBox(height: 330, child: ColoredBox(color: SaxifyColors.surfaceAlt)),
          SizedBox(height: 20),
          LoadingRail(itemCount: 6, height: 64),
        ],
      ),
    );
  }
}
