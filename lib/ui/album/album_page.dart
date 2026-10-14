import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/album_card.dart';
import '../../core/models/song.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/youtube_service.dart';
import '../../core/theme/ifall_ui.dart';
import '../widgets/artwork.dart';
import '../widgets/song_tile.dart';

/// The site's `/album/ytq-<base64>` route — an "album" is an encoded YouTube
/// search, so opening one just runs that query and shows the tracklist.
///
/// BitChord-style layout: the sleeve fills the top of the page, the metadata
/// sits right under it on true black, and Play / Shuffle are the only two
/// buttons — both full-width pills.
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
    final IfallPalette c = IfallPalette.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: FutureBuilder<List<Song>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<List<Song>> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _AlbumSkeleton();
          }
          return _AlbumBody(album: widget.album, tracks: snapshot.data ?? <Song>[]);
        },
      ),
    );
  }
}

class _AlbumBody extends StatelessWidget {
  const _AlbumBody({required this.album, required this.tracks});

  final AlbumCard album;
  final List<Song> tracks;

  static String _humanTotal(Duration d) {
    if (d.inHours > 0) return '${d.inHours} hr ${d.inMinutes.remainder(60)} min';
    return '${d.inMinutes} min';
  }

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final PlaybackService playback = context.read<PlaybackService>();

    final String cover =
        tracks.isNotEmpty ? tracks.first.thumbnailUrl : album.coverUrl;
    final Duration total = tracks.fold<Duration>(
      Duration.zero,
      (Duration sum, Song s) => sum + (s.duration ?? Duration.zero),
    );
    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          expandedHeight: 340,
          pinned: true,
          backgroundColor: c.background,
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
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(IfallUI.rMd),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.4),
                              blurRadius: 26,
                              offset: const Offset(0, 10),
                              spreadRadius: -6,
                            ),
                          ],
                        ),
                        child: Artwork(
                          url: cover,
                          size: 118,
                          radius: IfallUI.rMd,
                          fallbackIcon: Icons.album_rounded,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text('ALBUM', style: IfallText.label(c.accent)),
                            const SizedBox(height: 6),
                            Text(
                              album.title,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: IfallText.style(
                                22,
                                weight: FontWeight.w800,
                                letterSpacing: -0.7,
                                height: 1.1,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              album.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: IfallText.caption(
                                Colors.white.withValues(alpha: 0.7),
                              ),
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: _PillButton(
                    label: 'Play',
                    icon: Icons.play_arrow_rounded,
                    filled: true,
                    enabled: tracks.isNotEmpty,
                    onTap: () => playback.playQueue(tracks, startIndex: 0),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _PillButton(
                    label: 'Shuffle',
                    icon: Icons.shuffle_rounded,
                    enabled: tracks.isNotEmpty,
                    onTap: () async {
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
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: Text(
              '${tracks.length} tracks · ${_humanTotal(total)}',
              style: IfallText.caption(c.onSurfaceVariant),
            ),
          ),
        ),
        if (tracks.isEmpty)
          SliverToBoxAdapter(
            child: IfallEmpty(
              icon: Icons.album_rounded,
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
  }

}

/// Small colour helper so the pill button below knows what to paint on.
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.filled = false,
    this.enabled = true,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool filled;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final Color onAccent =
        ThemeData.estimateBrightnessForColor(c.accent) == Brightness.dark
            ? Colors.white
            : Colors.black;
    final Color fg = filled ? onAccent : c.onSurface;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(IfallUI.rPill),
          child: Container(
            height: 46,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(IfallUI.rPill),
              color: filled ? c.accent : Colors.transparent,
              border: filled ? null : Border.all(color: c.outline),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 7),
                Text(
                  label,
                  style: IfallText.body(fg).copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumSkeleton extends StatelessWidget {
  const _AlbumSkeleton();

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: <Widget>[
          SizedBox(
            height: 340,
            child: ColoredBox(color: c.surfaceVariant),
          ),
          const SizedBox(height: 20),
          for (int i = 0; i < 6; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: IfallShimmer(height: 58),
            ),
        ],
      ),
    );
  }
}
