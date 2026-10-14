import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/library_service.dart';
import '../../core/services/listen_together_service.dart';
import '../../core/services/music_download_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/utils/format.dart';
import '../artist/artist_page.dart';
import '../shell/sidify_routes.dart';
import '../widgets/sidify_widgets.dart';
import '../widgets/song_menu.dart';
import 'lyrics_view.dart';
import 'player_palette.dart';
import 'player_sheets.dart';

/// Now Playing — full screen, over everything (the web app's `NowPlaying`).
/// The artwork's own colours make the backdrop; the artwork eases down when
/// paused; lyrics and the queue take the artwork's place.
class FullPlayerPage extends StatefulWidget {
  const FullPlayerPage({super.key});

  @override
  State<FullPlayerPage> createState() => _FullPlayerPageState();
}

class _FullPlayerPageState extends State<FullPlayerPage> {
  String _view = 'art'; // art | lyrics | queue
  double _dragDy = 0;

  void _toggleView(String v) => setState(() => _view = _view == v ? 'art' : v);

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final SettingsService settings = context.watch<SettingsService>();
    final Song? song = playback.current;
    if (song == null) {
      return const Scaffold(backgroundColor: Colors.black, body: SizedBox.shrink());
    }
    final bool reduce = settings.reduceMotion;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          MeshBackdropFor(
            artworkUrl: song.thumbnailUrl,
            dynamicColor: settings.dynamicColor,
          ),
          SafeArea(
            child: Column(
              children: <Widget>[
                // Header — also the drag handle.
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragUpdate: (DragUpdateDetails d) =>
                      _dragDy += d.delta.dy,
                  onVerticalDragEnd: (_) {
                    if (_dragDy > 90) Navigator.of(context).pop();
                    _dragDy = 0;
                  },
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 10, 0),
                    child: Column(
                      children: <Widget>[
                        Container(
                          width: 36,
                          height: 5,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        Row(
                          children: <Widget>[
                            _glassBtn(
                              Icons.keyboard_arrow_down_rounded,
                              'Close',
                              () => Navigator.of(context).pop(),
                              size: 36,
                              iconSize: 24,
                            ),
                            Expanded(
                              child: _playingFrom(context),
                            ),
                            _glassBtn(
                              Icons.more_horiz_rounded,
                              'More',
                              () => showSongMenu(context, song),
                              size: 36,
                              iconSize: 22,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: _view == 'art'
                      ? _artwork(context, song, playback, reduce)
                      : _view == 'lyrics'
                          ? Column(
                              children: <Widget>[
                                _compactHead(context, song),
                                Expanded(
                                  child: LyricsPane(
                                    key: ValueKey<String>(song.id),
                                    song: song,
                                  ),
                                ),
                              ],
                            )
                          : Column(
                              children: <Widget>[
                                _compactHead(context, song),
                                const Expanded(child: _PlayerQueue()),
                              ],
                            ),
                ),
                if (_view == 'art') _titleRow(context, song),
                _scrubber(context, song, playback),
                _transport(context, playback),
                _volumeRow(context, playback),
                _bottomRow(context, song, playback),
                _upNext(context, playback),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _playingFrom(BuildContext context) {
    final JamService jam = context.watch<JamService>();
    final bool inRoom = jam.isConnected;
    return Column(
      children: <Widget>[
        Text(
          inRoom ? 'LISTEN TOGETHER' : 'PLAYING FROM',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.08,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ),
        Text(
          inRoom ? 'Sidify room ${jam.code ?? ''}' : 'Sidify',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ],
    );
  }

  Widget _artwork(
    BuildContext context,
    Song song,
    PlaybackService playback,
    bool reduce,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 12),
        child: AnimatedScale(
          scale: playback.isPlaying || reduce ? 1 : 0.88,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
          child: AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: 50,
                    offset: const Offset(0, 24),
                  ),
                ],
              ),
              child: Artwork(url: song.thumbnailUrl, radius: 12),
            ),
          ),
        ),
      ),
    );
  }

  Widget _compactHead(BuildContext context, Song song) {
    final LibraryService library = context.watch<LibraryService>();
    final bool liked = library.isLiked(song.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 10, 26, 4),
      child: Row(
        children: <Widget>[
          Artwork(url: song.thumbnailUrl, size: 56, radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          _likeCircle(liked, () => library.toggleLike(song)),
        ],
      ),
    );
  }

  Widget _likeCircle(bool liked, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: liked ? 0.34 : 0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(
          liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          size: 17,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _titleRow(BuildContext context, Song song) {
    final LibraryService library = context.watch<LibraryService>();
    final bool liked = library.isLiked(song.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 12, 30, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: Colors.white,
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Navigator.of(context).pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ArtistPage(
                          name: song.artist,
                          channelId: song.channelId ?? song.artistId,
                        ),
                        settings: const RouteSettings(name: SidifyRoutes.artist),
                      ),
                    );
                  },
                  child: Text(
                    song.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 18,
                      height: 1.15,
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _likeCircle(liked, () => library.toggleLike(song)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => showSongMenu(context, song),
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.more_horiz_rounded, size: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _scrubber(BuildContext context, Song song, PlaybackService playback) {
    final MusicDownloadService downloads =
        context.watch<MusicDownloadService>();
    final bool downloaded = downloads.isDownloaded(song.id);
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 10, 30, 0),
      child: StreamBuilder<Duration>(
        stream: playback.positionStream,
        initialData: playback.position,
        builder: (BuildContext context, AsyncSnapshot<Duration> snap) {
          final Duration pos = snap.data ?? playback.position;
          final Duration dur = playback.duration.inMilliseconds > 0
              ? playback.duration
              : (song.duration ?? Duration.zero);
          final double max = dur.inMilliseconds.toDouble();
          return Column(
            children: <Widget>[
              _SidifySlider(
                value: max > 0
                    ? (pos.inMilliseconds / max).clamp(0.0, 1.0)
                    : 0,
                onSeek: (double f) =>
                    playback.seekTo(Duration(milliseconds: (max * f).round())),
              ),
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 56,
                    child: Text(Fmt.duration(pos), style: _timeStyle),
                  ),
                  Expanded(
                    child: Text(
                      downloaded ? 'OFFLINE' : 'SIDIFY',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.06,
                        color: Colors.white.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 56,
                    child: Text(
                      '-${Fmt.duration(dur - pos)}',
                      textAlign: TextAlign.right,
                      style: _timeStyle,
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  static final TextStyle _timeStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: Colors.white.withValues(alpha: 0.55),
    fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  );

  Widget _transport(BuildContext context, PlaybackService playback) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: <Widget>[
          _transportBtn(
            Icons.skip_previous_rounded,
            42,
            60,
            () => playback.previous(),
          ),
          _transportBtn(
            playback.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
            58,
            76,
            () => playback.togglePlayPause(),
            loading: playback.isLoading,
          ),
          _transportBtn(Icons.skip_next_rounded, 42, 60, () => playback.next()),
        ],
      ),
    );
  }

  Widget _transportBtn(
    IconData icon,
    double iconSize,
    double box,
    VoidCallback onTap, {
    bool loading = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: box,
        height: box,
        alignment: Alignment.center,
        child: loading
            ? const SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5),
              )
            : Icon(icon, size: iconSize, color: Colors.white),
      ),
    );
  }

  Widget _volumeRow(BuildContext context, PlaybackService playback) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 2, 30, 0),
      child: Row(
        children: <Widget>[
          Icon(
            playback.volume == 0
                ? Icons.volume_off_rounded
                : Icons.volume_down_rounded,
            size: 16,
            color: Colors.white.withValues(alpha: 0.55),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _SidifySlider(
              value: playback.volume.clamp(0.0, 1.0),
              onSeek: playback.setVolume,
              live: true,
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.volume_up_rounded,
            size: 16,
            color: Colors.white.withValues(alpha: 0.55),
          ),
        ],
      ),
    );
  }

  Widget _bottomRow(BuildContext context, Song song, PlaybackService playback) {
    final bool isQueue = _view == 'queue';
    return Padding(
      padding: const EdgeInsets.fromLTRB(30, 12, 30, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          // Left: the playback panel (was the lyrics toggle) — swapped as
          // asked so playback opens from here and lyrics lives in the capsule.
          _glyphToggle(
            Icons.spatial_audio_rounded,
            'Playback',
            false,
            () => showPlaybackSheet(context),
          ),
          Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: isQueue
                  ? <Widget>[
                      _capsuleBtn(
                        Icons.shuffle_rounded,
                        'Shuffle',
                        playback.shuffleEnabled,
                        () => playback.toggleShuffle(),
                      ),
                      _capsuleDivider(),
                      _capsuleBtn(
                        playback.loopMode == LoopMode.one
                            ? Icons.repeat_one_rounded
                            : Icons.repeat_rounded,
                        'Repeat',
                        playback.loopMode != LoopMode.off,
                        () => playback.cycleLoopMode(),
                      ),
                      _capsuleDivider(),
                      _capsuleBtn(
                        Icons.all_inclusive_rounded,
                        'AutoPlay',
                        context.watch<SettingsService>().autoplay,
                        () => context
                            .read<SettingsService>()
                            .setAutoplay(
                              !context.read<SettingsService>().autoplay,
                            ),
                      ),
                    ]
                  : <Widget>[
                      _capsuleBtn(
                        Icons.lyrics_rounded,
                        'Lyrics',
                        _view == 'lyrics',
                        () => _toggleView('lyrics'),
                        wide: true,
                      ),
                      _capsuleDivider(),
                      _DownloadCapsule(song: song),
                    ],
            ),
          ),
          _glyphToggle(
            Icons.queue_music_rounded,
            'Queue',
            isQueue,
            () => _toggleView('queue'),
          ),
        ],
      ),
    );
  }

  Widget _glyphToggle(
    IconData icon,
    String label,
    bool on,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 22,
          color: on ? Colors.black : Colors.white.withValues(alpha: 0.85),
        ),
      ),
    );
  }

  Widget _capsuleBtn(
    IconData icon,
    String label,
    bool on,
    VoidCallback onTap, {
    bool wide = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 36,
        constraints: BoxConstraints(minWidth: wide ? 44 : 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: on ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              icon,
              size: 19,
              color: on ? Colors.black : Colors.white.withValues(alpha: 0.85),
            ),
          ],
        ),
      ),
    );
  }

  Widget _capsuleDivider() => Container(
        width: 1,
        height: 20,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        color: Colors.white.withValues(alpha: 0.15),
      );

  Widget _upNext(BuildContext context, PlaybackService playback) {
    final Song? next = playback.nextUp;
    if (next == null) return const SizedBox(height: 8);
    return GestureDetector(
      onTap: () => setState(() => _view = 'queue'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(30, 10, 30, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'UP NEXT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.06,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(width: 8),
            Artwork(url: next.thumbnailUrl, size: 20, radius: 4),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '${next.title} · ${next.artist}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  color: Colors.white.withValues(alpha: 0.55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _glassBtn(
    IconData icon,
    String label,
    VoidCallback onTap, {
    double size = 34,
    double iconSize = 18,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: iconSize, color: Colors.white),
      ),
    );
  }
}

/// The capsule's download cell — the seat the Listen Together icon used to
/// have (the room is still one tap away from Home, Library and Settings).
///
/// Tap it and the song is saved for offline listening: the arrow becomes a
/// ring, the percentage counts up in the middle while the ring fills, and a
/// tick lands when the file is on the device. Tapping again while it is still
/// coming down cancels it, exactly like the "…" menu does.
///
/// It reads the same [MusicDownloadService] the Downloads page does, so the
/// ring stays honest when a download was started somewhere else, and it keeps
/// the capsule's 36px height and 44px minimum cell width.
class _DownloadCapsule extends StatelessWidget {
  const _DownloadCapsule({required this.song});

  final Song song;

  Future<void> _tap(
    MusicDownloadService downloads,
    PlaybackService playback,
    MusicDownloadJob? job,
    bool active,
    bool done,
  ) async {
    if (done) {
      showAppNotice('Saved on this device');
      return;
    }
    if (active) {
      downloads.cancel(job);
      showAppNotice('Download cancelled');
      return;
    }
    final MusicDownloadJob result = await downloads.enqueue(song, playback);
    if (result.phase == MusicDownloadPhase.done) {
      showAppNotice('Saved for offline listening');
    }
  }

  @override
  Widget build(BuildContext context) {
    final MusicDownloadService downloads =
        context.watch<MusicDownloadService>();
    final PlaybackService playback = context.read<PlaybackService>();
    final MusicDownloadJob? job = downloads.jobFor(song.id);
    final bool done = downloads.isDownloaded(song.id);
    final bool active = job != null &&
        (job.phase == MusicDownloadPhase.running ||
            job.phase == MusicDownloadPhase.idle);
    final double fraction = (job?.fraction ?? 0.0).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: () => _tap(downloads, playback, job, active, done),
      child: Container(
        height: 36,
        constraints: const BoxConstraints(minWidth: 44),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        child: done
            ? const Icon(Icons.check_rounded, size: 19, color: Colors.white)
            : active
                ? _DownloadRing(fraction: fraction)
                : Icon(
                    Icons.download_rounded,
                    size: 19,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
      ),
    );
  }
}

/// The live ring: 24px inside the 36px capsule, arc filling with the download
/// and the percentage counting up in the middle. While the stream is still
/// being resolved there are no bytes to count, so the ring spins instead of
/// sitting on a misleading 0%.
class _DownloadRing extends StatelessWidget {
  const _DownloadRing({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final bool measured = fraction > 0;
    // 100% belongs to the tick, not to the ring.
    final int pct = (fraction * 100).round().clamp(0, 99);
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: measured ? fraction : null,
              strokeWidth: 2.2,
              strokeCap: StrokeCap.round,
              color: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
            ),
          ),
          if (measured)
            SizedBox(
              width: 18,
              height: 18,
              // Scaled down rather than clipped: the number can never push the
              // ring wider, whatever the system font scale is.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '$pct%',
                  style: const TextStyle(
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The player's own slider: a thin white bar that thickens while touched,
/// like the web player's range inputs on artwork.
class _SidifySlider extends StatefulWidget {
  const _SidifySlider({required this.value, required this.onSeek, this.live = false});

  final double value;
  final ValueChanged<double> onSeek;
  final bool live;

  @override
  State<_SidifySlider> createState() => _SidifySliderState();
}

class _SidifySliderState extends State<_SidifySlider> {
  double? _drag;

  @override
  Widget build(BuildContext context) {
    final double v = (_drag ?? widget.value).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        void handle(double dx) {
          final double f = (dx / c.maxWidth).clamp(0.0, 1.0);
          setState(() => _drag = f);
          if (widget.live) widget.onSeek(f);
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              handle(d.localPosition.dx),
          onHorizontalDragEnd: (_) {
            if (_drag != null && !widget.live) widget.onSeek(_drag!);
            setState(() => _drag = null);
          },
          onTapDown: (TapDownDetails d) {
            handle(d.localPosition.dx);
            if (!widget.live) widget.onSeek(_drag!);
            setState(() => _drag = null);
          },
          child: Container(
            height: 22,
            alignment: Alignment.center,
            child: Stack(
              children: <Widget>[
                Container(
                  height: _drag != null ? 6 : 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: v,
                  child: Container(
                    height: _drag != null ? 6 : 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.86),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The queue inside the player: Now Playing, then Up next — drag to reorder,
/// swipe the × to remove, tap to jump.
class _PlayerQueue extends StatelessWidget {
  const _PlayerQueue();

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final List<Song> queue = playback.queue;
    final int index = playback.currentIndex;
    if (queue.isEmpty || index < 0) {
      return const Center(
        child: Text(
          'Nothing in the queue. Play something and it shows up here.',
          style: TextStyle(fontSize: 14, color: Colors.white60),
        ),
      );
    }
    final List<Song> upNext = queue.sublist(index + 1);
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 24),
      children: <Widget>[
        const _QueueHeading('Now Playing'),
        _QueueRow(song: queue[index], current: true),
        if (upNext.isNotEmpty) ...<Widget>[
          const _QueueHeading('Up next'),
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            buildDefaultDragHandles: false,
            itemCount: upNext.length,
            onReorder: (int from, int to) {
              final List<Song> next = List<Song>.of(queue);
              final Song moved = next.removeAt(index + 1 + from);
              final int insertAt = index + 1 + (to > from ? to - 1 : to);
              next.insert(insertAt, moved);
              playback.reorderQueue(next);
            },
            itemBuilder: (BuildContext context, int i) {
              final Song s = upNext[i];
              return ReorderableDragStartListener(
                key: ValueKey<String>('q-${s.id}-$i'),
                index: i,
                child: _QueueRow(
                  song: s,
                  absIndex: index + 1 + i,
                  onTap: () => playback.skipToIndex(index + 1 + i),
                  onRemove: () => playback.removeFromQueue(index + 1 + i),
                ),
              );
            },
          ),
        ] else
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Text(
              'AutoPlay lines up similar songs before the queue runs out.',
              style: TextStyle(fontSize: 13, color: Colors.white54),
            ),
          ),
      ],
    );
  }
}

class _QueueHeading extends StatelessWidget {
  const _QueueHeading(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: Colors.white.withValues(alpha: 0.75),
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.song,
    this.current = false,
    this.absIndex = -1,
    this.onTap,
    this.onRemove,
  });

  final Song song;
  final bool current;
  final int absIndex;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            children: <Widget>[
              Stack(
                children: <Widget>[
                  Artwork(url: song.thumbnailUrl, size: 44, radius: 6),
                  if (current)
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: PlayingBars(
                          paused: !playback.isPlaying,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        color: current
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.92),
                        fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    Text(
                      song.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
              if (song.duration != null)
                Text(
                  Fmt.duration(song.duration),
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.white.withValues(alpha: 0.5),
                  ),
                ),
              if (onRemove != null)
                IconButton(
                  icon: Icon(Icons.close_rounded,
                      size: 16, color: Colors.white.withValues(alpha: 0.6)),
                  onPressed: onRemove,
                ),
              if (!current)
                Icon(Icons.drag_handle_rounded,
                    size: 18, color: Colors.white.withValues(alpha: 0.35)),
            ],
          ),
        ),
      ),
    );
  }
}
