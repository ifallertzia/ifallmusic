import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import '../../core/models/artist.dart';
import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/youtube_service.dart';
import '../../core/theme/ifall_ui.dart';
import '../../core/utils/format.dart';
import '../widgets/artwork.dart';
import '../widgets/song_tile.dart';

/// The site's `/artist/<channelId>` route.
///
/// BitChord-style: the banner bleeds to the top edge, the circular portrait
/// locks to the bottom-left of it, and Play all / Follow / Shuffle are the only
/// three controls.
class ArtistPage extends StatefulWidget {
  const ArtistPage({
    super.key,
    required this.channelId,
    this.fallbackName,
    this.fallbackImageUrl,
  });

  final String channelId;
  final String? fallbackName;
  final String? fallbackImageUrl;

  @override
  State<ArtistPage> createState() => _ArtistPageState();
}

class _ArtistPageState extends State<ArtistPage> {
  late final Future<_ArtistData> _future = _load();

  Future<_ArtistData> _load() async {
    final YoutubeService youtube = context.read<YoutubeService>();
    final Channel channel = await youtube.channel(widget.channelId);
    List<Song> uploads = <Song>[];
    try {
      uploads = await youtube.channelUploads(widget.channelId, limit: 40);
    } catch (e) {
      debugPrint('Artist uploads unavailable: $e');
    }
    if (uploads.isEmpty) {
      final String artist = widget.fallbackName?.trim().isNotEmpty == true
          ? widget.fallbackName!.trim()
          : channel.title;
      uploads = await youtube.searchSongs('$artist Hindi songs', limit: 30);
    }
    return _ArtistData(channel: channel, uploads: uploads);
  }

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: FutureBuilder<_ArtistData>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<_ArtistData> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const _ArtistSkeleton();
          }
          if (snapshot.hasError || snapshot.data == null) {
            return SafeArea(
              child: IfallEmpty(
                icon: Icons.person_off_rounded,
                message:
                    'We could not load this channel. Pull back and try again.',
                actionLabel: 'Go back',
                action: () => Navigator.of(context).maybePop(),
              ),
            );
          }
          return _ArtistBody(
            channelId: widget.channelId,
            data: snapshot.data!,
          );
        },
      ),
    );
  }
}

class _ArtistBody extends StatelessWidget {
  const _ArtistBody({required this.channelId, required this.data});

  final String channelId;
  final _ArtistData data;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final LibraryService library = context.watch<LibraryService>();
    final PlaybackService playback = context.read<PlaybackService>();

    final ArtistRef ref = ArtistRef(
      channelId: channelId,
      name: data.channel.title,
      imageUrl: data.channel.logoUrl,
      subscribers: data.channel.subscribersCount?.toString(),
    );
    final bool following = library.isFollowing(channelId);
    final List<Song> uploads = data.uploads;

    return CustomScrollView(
      slivers: <Widget>[
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          backgroundColor: c.background,
          foregroundColor: c.onSurface,
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Artwork(
                  url: data.channel.bannerUrl,
                  radius: 0,
                  fit: BoxFit.cover,
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        Colors.black.withValues(alpha: 0.35),
                        c.background.withValues(alpha: 0.92),
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
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: c.accent.withValues(alpha: 0.7),
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: Artwork(
                            url: data.channel.logoUrl,
                            size: 80,
                            radius: 40,
                            fallbackIcon: Icons.person_rounded,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text('ARTIST', style: IfallText.label(c.accent)),
                            const SizedBox(height: 5),
                            Text(
                              data.channel.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: IfallText.style(
                                25,
                                weight: FontWeight.w800,
                                letterSpacing: -0.8,
                                height: 1.1,
                                color: Colors.white,
                              ),
                            ),
                            if (data.channel.subscribersCount != null) ...<Widget>[
                              const SizedBox(height: 5),
                              Text(
                                '${Fmt.count(data.channel.subscribersCount)} followers',
                                style: IfallText.caption(
                                  Colors.white.withValues(alpha: 0.7),
                                ),
                              ),
                            ],
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
                  child: _PillButton(
                    label: 'Play all',
                    icon: Icons.play_arrow_rounded,
                    filled: true,
                    enabled: uploads.isNotEmpty,
                    onTap: () => playback.playQueue(uploads, startIndex: 0),
                  ),
                ),
                const SizedBox(width: 10),
                _IconButtonTile(
                  icon: following
                      ? Icons.check_rounded
                      : Icons.person_add_alt_1_rounded,
                  active: following,
                  tooltip: following ? 'Following' : 'Follow',
                  onTap: () => library.toggleFollow(ref),
                ),
                const SizedBox(width: 10),
                _IconButtonTile(
                  icon: Icons.shuffle_rounded,
                  tooltip: 'Shuffle',
                  onTap: uploads.isEmpty
                      ? null
                      : () async {
                          await playback.playQueue(uploads, startIndex: 0);
                          if (!playback.shuffleEnabled) {
                            await playback.toggleShuffle();
                          }
                        },
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: IfallSectionHeader(
            title: 'Latest releases',
            subtitle: '${uploads.length} tracks',
          ),
        ),
        if (uploads.isEmpty)
          SliverToBoxAdapter(
            child: IfallEmpty(
              icon: Icons.music_off_rounded,
              message:
                  'This channel has not published anything we can read.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 140),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (BuildContext c, int i) => SongTile(
                  song: uploads[i],
                  rank: i + 1,
                  showArtwork: true,
                  onTap: () => playback.playQueue(uploads, startIndex: i),
                ),
                childCount: uploads.length,
              ),
            ),
          ),
      ],
    );
  }
}

class _IconButtonTile extends StatelessWidget {
  const _IconButtonTile({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(IfallUI.rMd),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(IfallUI.rMd),
              color: c.fill,
              border: Border.all(color: active ? c.accent : c.outline),
            ),
            child: Icon(
              icon,
              size: 20,
              color: active ? c.accent : c.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width pill used for the page's primary actions.
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

class _ArtistData {
  const _ArtistData({required this.channel, required this.uploads});

  final Channel channel;
  final List<Song> uploads;
}

class _ArtistSkeleton extends StatelessWidget {
  const _ArtistSkeleton();

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: <Widget>[
          SizedBox(height: 300, child: ColoredBox(color: c.surfaceVariant)),
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
