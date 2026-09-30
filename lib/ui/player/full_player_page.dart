import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';

import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/playback_error_reporter.dart';
import '../../core/services/app_feedback.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../../core/utils/format.dart';
import '../../screens/lyrics_finder_screen.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/artwork.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_download_button.dart';
import '../widgets/song_tile.dart';
import 'equalizer_page.dart';

/// The full-screen player.
class FullPlayerPage extends StatefulWidget {
  const FullPlayerPage({super.key});

  @override
  State<FullPlayerPage> createState() => _FullPlayerPageState();
}

class _FullPlayerPageState extends State<FullPlayerPage> {
  bool _dragging = false;
  double _dragValue = 0;
  double _dismissDrag = 0;
  bool _lyricsRequested = false;
  final ScrollController _playerScrollController = ScrollController();
  final GlobalKey _lyricsSectionKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _playerScrollController.addListener(_maybeStartLyricsSearch);
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartLyricsSearch());
  }

  void _maybeStartLyricsSearch() {
    if (!mounted || _lyricsRequested) return;
    final BuildContext? sectionContext = _lyricsSectionKey.currentContext;
    final RenderObject? renderObject = sectionContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return;
    final double top = renderObject.localToGlobal(Offset.zero).dy;
    final double bottom = top + renderObject.size.height;
    final double viewportHeight = MediaQuery.sizeOf(context).height;
    if (top < viewportHeight && bottom > 0) {
      setState(() => _lyricsRequested = true);
    }
  }

  bool _handlePlayerScroll(ScrollNotification notification) {
    if (notification.depth != 0 ||
        notification.metrics.axis != Axis.vertical) return false;
    if (notification is OverscrollNotification &&
        notification.metrics.pixels <= notification.metrics.minScrollExtent &&
        notification.overscroll < 0) {
      final double next =
          (_dismissDrag - notification.overscroll * 0.62).clamp(0.0, 220.0);
      if (next != _dismissDrag) setState(() => _dismissDrag = next);
    } else if (notification is ScrollUpdateNotification &&
        notification.metrics.pixels > notification.metrics.minScrollExtent) {
      // Reading down the page: release any half-finished dismiss drag and let
      // the lyrics hint retire.
      if (_dismissDrag > 0) setState(() => _dismissDrag = 0);
    } else if (notification is ScrollEndNotification && _dismissDrag > 0) {
      if (_dismissDrag >= 85) {
        Navigator.of(context).maybePop();
      } else {
        setState(() => _dismissDrag = 0);
      }
    }
    return false;
  }

  @override
  void dispose() {
    _playerScrollController
      ..removeListener(_maybeStartLyricsSearch)
      ..dispose();
    super.dispose();
  }

  Future<void> _showQueueSheet() {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => const _QueueSheet(),
    );
  }

  Future<void> _showSleepSheet(PlaybackService playback) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => _SleepSheet(playback: playback),
    );
  }

  Future<void> _showSpeedSheet(PlaybackService playback) {
    const List<double> speeds = <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => GlassSheet(
        title: 'Playback speed',
        subtitle: 'Applied instantly to the current track',
        maxHeightFactor: 0.6,
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: 22),
          children: <Widget>[
            for (final double s in speeds)
              ListTile(
                onTap: () {
                  playback.setSpeed(s);
                  Navigator.of(sheetContext).pop();
                },
                title: Text('${s}x'),
                trailing: playback.speed == s
                    ? Icon(
                        Icons.check_rounded,
                        color: sheetContext.accent.primary,
                      )
                    : null,
              ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final LibraryService library = context.watch<LibraryService>();
    final SaxifyAccent accent = context.accent;
    final Song? song = playback.current;

    if (song == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(
                Icons.music_off_rounded,
                size: 46,
                color: SaxifyColors.textFaint,
              ),
              const SizedBox(height: 14),
              Text(
                'Nothing playing',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 18),
              TextButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('Back'),
              ),
            ],
          ),
        ),
      );
    }

    final bool liked = library.isLiked(song.id);
    final Duration total = playback.duration == Duration.zero
        ? (song.duration ?? Duration.zero)
        : playback.duration;
    final Size screenSize = MediaQuery.sizeOf(context);
    final double expandedHeight = math.min(
      math.min(screenSize.width, screenSize.height * 0.46),
      420.0,
    ).clamp(260.0, 420.0).toDouble();
    final double maxArtworkSize =
        (screenSize.width - 56).clamp(180.0, 360.0).toDouble();

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: NotificationListener<ScrollNotification>(
        onNotification: _handlePlayerScroll,
        child: AnimatedSlide(
          offset: Offset(
            0,
            screenSize.height == 0 ? 0 : _dismissDrag / screenSize.height,
          ),
          duration: _dismissDrag == 0
              ? const Duration(milliseconds: 180)
              : Duration.zero,
          curve: Curves.easeOutCubic,
          child: ColoredBox(
            color: SaxifyColors.background,
            child: CustomScrollView(
              controller: _playerScrollController,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: <Widget>[
                SliverAppBar(
                  primary: true,
                  pinned: true,
                  floating: false,
                  snap: false,
                  automaticallyImplyLeading: false,
                  expandedHeight: expandedHeight,
                  toolbarHeight: kToolbarHeight,
                  backgroundColor: SaxifyColors.background,
                  surfaceTintColor: Colors.transparent,
                  leadingWidth: 48,
                  leading: IconButton(
                    tooltip: 'Back to your music',
                    icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  title: Text(
                    'NOW PLAYING',
                    style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700,
                      color: accent.primary,
                    ),
                  ),
                  actions: <Widget>[
                    if (playback.lastError != null)
                      IconButton(
                        tooltip: 'Report playback issue',
                        icon: const Icon(Icons.bug_report_outlined),
                        onPressed: () async {
                          final bool opened = await PlaybackErrorReporter.compose(
                            playback.lastError!,
                          );
                          if (!opened) {
                            showAppNotice(
                              'No email app available. Use MAIL ERROR on the failure message to copy the report.',
                            );
                          }
                        },
                      ),
                    IconButton(
                      tooltip: 'Sleep timer',
                      icon: const Icon(Icons.bedtime_rounded),
                      onPressed: () => _showSleepSheet(playback),
                    ),
                    IconButton(
                      tooltip: 'More options',
                      icon: const Icon(Icons.more_horiz_rounded),
                      onPressed: () => showSongSheet(context, song),
                    ),
                  ],
                  flexibleSpace: LayoutBuilder(
                    builder: (BuildContext context, BoxConstraints constraints) {
                      final double availableHeight = constraints.biggest.height;
                      final double dismissProgress =
                          (_dismissDrag / 120).clamp(0.0, 1.0);
                      // The sleeve slides sideways, shrinks and fades as the
                      // player is dragged away, handing the stage to the mini
                      // player underneath.
                      final double artworkSize = (availableHeight - 84)
                          .clamp(0.0, maxArtworkSize)
                          .toDouble() *
                          (1 - dismissProgress * 0.22);
                      final double slide = dismissProgress *
                          math.min(screenSize.width * 0.18, 90);
                      return Stack(
                        fit: StackFit.expand,
                        children: <Widget>[
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: <Color>[
                                  accent.primary.withValues(alpha: 0.18),
                                  accent.secondary.withValues(alpha: 0.06),
                                  SaxifyColors.background,
                                ],
                              ),
                            ),
                          ),
                          if (artworkSize > 1)
                            Center(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  top: MediaQuery.paddingOf(context).top + 50,
                                  bottom: 12,
                                ),
                                child: Transform.translate(
                                  offset: Offset(slide, 18 * dismissProgress),
                                  child: Transform.scale(
                                    scale: 1 - dismissProgress * 0.16,
                                    child: Opacity(
                                      opacity: 1 - dismissProgress * 0.45,
                                      child: SizedBox.square(
                                        dimension: artworkSize,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              SaxifyTheme.radiusLg,
                                            ),
                                            boxShadow: <BoxShadow>[
                                              BoxShadow(
                                                color: accent.primary.withValues(
                                                  alpha: 0.22,
                                                ),
                                                blurRadius: 34,
                                                offset: const Offset(0, 13),
                                              ),
                                            ],
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              SaxifyTheme.radiusLg,
                                            ),
                                            child: Hero(
                                              tag: 'player-artwork-${song.id}',
                                              child: Artwork(
                                                url: song.thumbnailUrl,
                                                radius: SaxifyTheme.radiusLg,
                                                width: artworkSize,
                                                height: artworkSize,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),

                // Track title and quick actions.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 16, 12, 0),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                song.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                  height: 1.16,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                song.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: SaxifyColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SongDownloadButton(song: song, size: 40),
                        IconButton(
                          iconSize: 24,
                          tooltip: liked ? 'Remove from Liked' : 'Like',
                          icon: Icon(
                            liked
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            color: liked ? accent.primary : SaxifyColors.textMuted,
                          ),
                          onPressed: () => library.toggleLike(song),
                        ),
                      ],
                    ),
                  ),
                ),

                // Seek bar.
                SliverToBoxAdapter(
                  child: StreamBuilder<Duration>(
                    stream: playback.positionStream,
                    initialData: playback.position,
                    builder: (BuildContext context, AsyncSnapshot<Duration> snap) {
                      final Duration position = snap.data ?? Duration.zero;
                      final double fraction = total.inMilliseconds == 0
                          ? 0
                          : (position.inMilliseconds / total.inMilliseconds)
                                .clamp(0.0, 1.0);
                      final double value = _dragging ? _dragValue : fraction;
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(16, 5, 16, 0),
                        child: Column(
                          children: <Widget>[
                            Slider(
                              value: value,
                              onChanged: (double next) => setState(() {
                                _dragging = true;
                                _dragValue = next;
                              }),
                              onChangeEnd: (double next) async {
                                setState(() => _dragging = false);
                                await playback.seekFraction(next);
                              },
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: <Widget>[
                                  Text(
                                    Fmt.clock(
                                      _dragging
                                          ? Duration(
                                              milliseconds:
                                                  (total.inMilliseconds *
                                                          _dragValue)
                                                      .round(),
                                            )
                                          : position,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: SaxifyColors.textMuted,
                                      fontFeatures: <FontFeature>[
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                                  ),
                                  if (playback.isLoading)
                                    const SizedBox(
                                      width: 11,
                                      height: 11,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 1.6,
                                      ),
                                    )
                                  else
                                    Text(
                                      '-${Fmt.clock(total - position)}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: SaxifyColors.textMuted,
                                        fontFeatures: <FontFeature>[
                                          FontFeature.tabularFigures(),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),

                // Transport controls.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(18, 5, 18, 0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: <Widget>[
                        _TransportIcon(
                          icon: Icons.shuffle_rounded,
                          active: playback.shuffleEnabled,
                          onTap: playback.toggleShuffle,
                        ),
                        _TransportIcon(
                          icon: Icons.skip_previous_rounded,
                          size: 36,
                          onTap: playback.previous,
                        ),
                        _PlayButton(
                          playing: playback.isPlaying,
                          loading: playback.isLoading,
                          onTap: playback.togglePlayPause,
                        ),
                        _TransportIcon(
                          icon: Icons.skip_next_rounded,
                          size: 36,
                          onTap: playback.next,
                        ),
                        _TransportIcon(
                          icon: switch (playback.loopMode) {
                            LoopMode.one => Icons.repeat_one_rounded,
                            LoopMode.all => Icons.repeat_rounded,
                            LoopMode.off => Icons.repeat_rounded,
                          },
                          active: playback.loopMode != LoopMode.off,
                          onTap: playback.cycleLoopMode,
                        ),
                      ],
                    ),
                  ),
                ),

                // Secondary actions.
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: Row(
                      children: <Widget>[
                        _RoundAction(
                          icon: Icons.graphic_eq_rounded,
                          active: false,
                          onTap: () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const EqualizerPage(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: <Widget>[
                                _ChipButton(
                                  label: '${playback.speed}x',
                                  icon: Icons.speed_rounded,
                                  onTap: () => _showSpeedSheet(playback),
                                ),
                                const SizedBox(width: 7),
                                _ChipButton(
                                  label: 'Add Playlist',
                                  icon: Icons.playlist_add_rounded,
                                  active: library.playlists.any(
                                    (Playlist playlist) => playlist.songs.any(
                                      (Song item) => item.id == song.id,
                                    ),
                                  ),
                                  onTap: () =>
                                      showAddToPlaylistSheet(context, song),
                                ),
                                const SizedBox(width: 7),
                                _ChipButton(
                                  label: 'Queue',
                                  icon: Icons.queue_music_rounded,
                                  onTap: _showQueueSheet,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Reaching this section starts the lookup automatically. The
                // lookup itself stays lazy so opening the player makes no request.
                SliverToBoxAdapter(
                  child: Padding(
                    key: _lyricsSectionKey,
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(
                              Icons.lyrics_outlined,
                              size: 19,
                              color: accent.primary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Lyrics',
                              style: SaxifyTheme.appleFont(
                                size: 20,
                                weight: FontWeight.w700,
                                letterSpacing: -0.35,
                              ),
                            ),
                            const Spacer(),
                            if (_lyricsRequested)
                              TextButton.icon(
                                onPressed: () => showLyricsPanel(context, song),
                                icon: const Icon(Icons.open_in_full_rounded, size: 16),
                                label: const Text('Full'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_lyricsRequested)
                          SizedBox(
                            // Lyrics stay pinned to the bottom of the player and
                            // scroll on their own, so long tracks never fight
                            // the artwork above for gestures.
                            height: (screenSize.height * 0.52)
                                .clamp(300.0, 620.0)
                                .toDouble(),
                            child: LyricsFinderScreen(
                              key: ValueKey<String>('lyrics-${song.id}'),
                              song: song,
                              embedded: true,
                            ),
                          )
                        else
                          const _ScrollToLyricsHint(),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: SizedBox(height: MediaQuery.paddingOf(context).bottom + 36),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// First-run affordance: a looping arrow that tells you the lyrics live just
/// below, and that scrolling down opens them. The animation lives exactly as
/// long as the hint is on screen.
class _ScrollToLyricsHint extends StatefulWidget {
  const _ScrollToLyricsHint();

  @override
  State<_ScrollToLyricsHint> createState() => _ScrollToLyricsHintState();
}

class _ScrollToLyricsHintState extends State<_ScrollToLyricsHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final Animation<double> bounce = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOutSine,
    );
    return SizedBox(
      height: 128,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AnimatedBuilder(
              animation: bounce,
              builder: (BuildContext context, Widget? child) {
                final double wave = math.sin(bounce.value * math.pi);
                return Transform.translate(
                  offset: Offset(0, 10 * wave),
                  child: Opacity(
                    opacity: 0.55 + 0.45 * wave,
                    child: child,
                  ),
                );
              },
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: accent.gradient,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accent.primary.withValues(alpha: 0.45),
                      blurRadius: 22,
                      spreadRadius: -6,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  size: 26,
                  color: accent.onAccent,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Scroll to open lyrics',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.2,
                color: accent.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.onTap,
  });

  final bool playing;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: accent.gradient,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: accent.primary.withValues(alpha: 0.45),
              blurRadius: 30,
              offset: const Offset(0, 10),
              spreadRadius: -6,
            ),
          ],
        ),
        child: loading
            ? Padding(
                padding: const EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: accent.onAccent,
                ),
              )
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 38,
                color: accent.onAccent,
              ),
      ),
    );
  }
}

class _TransportIcon extends StatelessWidget {
  const _TransportIcon({
    required this.icon,
    required this.onTap,
    this.size = 24,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return IconButton(
      onPressed: onTap,
      iconSize: size,
      icon: Icon(
        icon,
        color: active ? accent.primary : SaxifyColors.textPrimary,
      ),
    );
  }
}

/// Round glass action button (the sound panel trigger).
class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active
                ? accent.primary.withValues(alpha: 0.22)
                : Colors.white.withValues(alpha: 0.07),
            border: Border.all(
              color: active
                  ? accent.primary.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.12),
            ),
          ),
          child: Icon(
            icon,
            size: 21,
            color: active ? accent.primary : SaxifyColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

class _ChipButton extends StatelessWidget {
  const _ChipButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.active = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SaxifyTheme.radiusXl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SaxifyTheme.radiusXl),
            color: active
                ? accent.primary.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: active
                  ? accent.primary.withValues(alpha: 0.6)
                  : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 14,
                color: active ? accent.primary : SaxifyColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: active ? accent.primary : SaxifyColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SleepSheet extends StatelessWidget {
  const _SleepSheet({required this.playback});

  final PlaybackService playback;

  @override
  Widget build(BuildContext context) {
    const List<int> minutes = <int>[15, 30, 45, 60, 90];
    return GlassSheet(
      title: 'Sleep timer',
      subtitle: 'Pause playback automatically',
      maxHeightFactor: 0.75,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final int m in minutes)
              ListTile(
                title: Text('$m minutes'),
                onTap: () {
                  playback.startSleepTimer(Duration(minutes: m));
                  Navigator.of(context).pop();
                },
              ),
            ListTile(
              title: const Text('Until the current track ends'),
              onTap: () {
                final Duration d = playback.duration - playback.position;
                if (d > Duration.zero) {
                  playback.startSleepTimer(d);
                }
                Navigator.of(context).pop();
              },
            ),
            if (playback.sleepRemaining != null)
              ListTile(
                title: const Text(
                  'Turn off timer',
                  style: TextStyle(color: SaxifyColors.danger),
                ),
                onTap: () {
                  playback.cancelSleepTimer();
                  Navigator.of(context).pop();
                },
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final SaxifyAccent accent = context.accent;
    final List<Song> queue = playback.queue;

    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.35,
      maxChildSize: 0.94,
      expand: false,
      builder: (BuildContext context, ScrollController controller) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(SaxifyTheme.radiusLg),
          ),
          child: BackdropFilter(
            filter: GlassBlur.thickFilter,
            child: ColoredBox(
              color: const Color(0xFF0B0B0F).withValues(alpha: 0.94),
              child: Column(
                children: <Widget>[
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 4.5,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                'Up next',
                                style: SaxifyTheme.appleFont(
                                  size: 17,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                '${queue.length} tracks in the queue',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: SaxifyColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: 'Shuffle queue',
                          icon: Icon(
                            Icons.shuffle_rounded,
                            color: playback.shuffleEnabled
                                ? accent.primary
                                : SaxifyColors.textMuted,
                          ),
                          onPressed: playback.toggleShuffle,
                        ),
                        IconButton(
                          tooltip: 'Clear queue',
                          icon: const Icon(
                            Icons.delete_sweep_rounded,
                            color: SaxifyColors.textMuted,
                          ),
                          onPressed: playback.clearQueue,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: queue.isEmpty
                        ? const Center(
                            child: Text(
                              'Queue is empty',
                              style: TextStyle(color: SaxifyColors.textMuted),
                            ),
                          )
                        : ListView.builder(
                            controller: controller,
                            padding: const EdgeInsets.only(bottom: 24),
                            itemCount: queue.length,
                            itemBuilder: (BuildContext c, int i) => QueueTile(
                              song: queue[i],
                              isPlaying: i == playback.currentIndex,
                              onTap: () => playback.skipToIndex(i),
                              onRemove: () => playback.removeFromQueue(i),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
