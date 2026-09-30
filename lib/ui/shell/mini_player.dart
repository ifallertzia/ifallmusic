
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/music_download_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../player/full_player_page.dart';
import '../widgets/artwork.dart';

/// The persistent mini player, floating above the tab bar.
///
/// It also mirrors **live download progress**, so a song that is saving shows
/// its percentage right here in the dock — on top of the one on the row and on
/// the download button.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final LibraryService library = context.watch<LibraryService>();
    final MusicDownloadService downloads = context.watch<MusicDownloadService>();
    final SaxifyAccent accent = context.accent;
    final Song? song = playback.current;

    if (song == null) return const SizedBox.shrink();

    final bool liked = library.isLiked(song.id);
    final MusicDownloadJob? job = downloads.active;
    final bool downloading = job != null &&
        job.phase == MusicDownloadPhase.running &&
        (job.fraction > 0 || job.size > 0);

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SaxifyTheme.radiusMd),
        child: BackdropFilter(
          filter: GlassBlur.thickFilter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(SaxifyTheme.radiusMd),
              color: const Color(0xFF0A0A0E).withValues(alpha: 0.78),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: accent.primary.withValues(alpha: 0.18),
                  blurRadius: 26,
                  spreadRadius: -10,
                  offset: const Offset(0, 10),
                ),
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.55),
                  blurRadius: 24,
                  spreadRadius: -12,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).push<void>(
                  PageRouteBuilder<void>(
                    opaque: false,
                    barrierDismissible: false,
                    transitionDuration: const Duration(milliseconds: 360),
                    reverseTransitionDuration: const Duration(milliseconds: 260),
                    pageBuilder: (BuildContext routeContext, Animation<double> animation,
                        Animation<double> secondaryAnimation) =>
                        const FullPlayerPage(),
                    transitionsBuilder: (
                      BuildContext routeContext,
                      Animation<double> animation,
                      Animation<double> secondaryAnimation,
                      Widget child,
                    ) {
                      final Animation<double> eased = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      );
                      return FadeTransition(
                        opacity: eased,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.12),
                            end: Offset.zero,
                          ).animate(eased),
                          child: child,
                        ),
                      );
                    },
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // ---- hairline playback progress ---------------------
                    ClipRRect(
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(SaxifyTheme.radiusMd),
                      ),
                      child: StreamBuilder<Duration>(
                        stream: playback.positionStream,
                        initialData: playback.position,
                        builder: (BuildContext c, AsyncSnapshot<Duration> snap) {
                          final Duration total = playback.duration == Duration.zero
                              ? (song.duration ?? Duration.zero)
                              : playback.duration;
                          final Duration pos = snap.data ?? Duration.zero;
                          final double fraction = total.inMilliseconds == 0
                              ? 0
                              : (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
                          return SizedBox(
                            height: 2.5,
                            child: Stack(
                              children: <Widget>[
                                Positioned.fill(
                                  child: ColoredBox(
                                    color: Colors.white.withValues(alpha: 0.08),
                                  ),
                                ),
                                FractionallySizedBox(
                                  widthFactor: fraction == 0 ? 0.001 : fraction,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: <Color>[accent.primary, accent.secondary],
                                      ),
                                    ),
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 9, 6, 9),
                      child: Row(
                        children: <Widget>[
                          Hero(
                            tag: 'player-artwork-${song.id}',
                            flightShuttleBuilder: (
                              BuildContext flightContext,
                              Animation<double> animation,
                              HeroFlightDirection flightDirection,
                              BuildContext fromHeroContext,
                              BuildContext toHeroContext,
                            ) =>
                                Artwork(url: song.thumbnailUrl, size: 46, radius: 10),
                            child: Artwork(url: song.thumbnailUrl, size: 46, radius: 10),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Text(
                                  song.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: SaxifyTheme.appleFont(
                                    size: 13.5,
                                    weight: FontWeight.w700,
                                    color: SaxifyColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                if (downloading)
                                  Row(
                                    children: <Widget>[
                                      Icon(Icons.download_rounded,
                                          size: 12, color: accent.primary),
                                      const SizedBox(width: 5),
                                      Flexible(
                                        child: Text(
                                          'Downloading ${(job.fraction * 100).round()}%',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: accent.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  )
                                else
                                  Text(
                                    song.artist,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 11.5,
                                      color: SaxifyColors.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: liked ? 'Remove from Liked' : 'Like',
                            icon: Icon(
                              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              size: 19,
                              color: liked ? accent.primary : SaxifyColors.textFaint,
                            ),
                            onPressed: () => library.toggleLike(song),
                          ),
                          playback.isLoading
                              ? const SizedBox(
                                  width: 36,
                                  height: 36,
                                  child: Padding(
                                    padding: EdgeInsets.all(9),
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : IconButton(
                                  visualDensity: VisualDensity.compact,
                                  tooltip: playback.isPlaying ? 'Pause' : 'Play',
                                  iconSize: 32,
                                  icon: Icon(
                                    playback.isPlaying
                                        ? Icons.pause_circle_filled_rounded
                                        : Icons.play_circle_filled_rounded,
                                    color: accent.primary,
                                  ),
                                  onPressed: playback.togglePlayPause,
                                ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Next',
                            icon: const Icon(
                              Icons.skip_next_rounded,
                              size: 25,
                              color: SaxifyColors.textSecondary,
                            ),
                            onPressed: playback.next,
                          ),
                        ],
                      ),
                    ),
                    if (downloading)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                        child: GlassProgress(fraction: job.fraction, height: 4),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
