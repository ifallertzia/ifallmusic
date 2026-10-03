import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
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
import '../../services/lyrics_clock.dart';
import '../../services/lyrics_service.dart';
import '../widgets/add_to_playlist_sheet.dart';
import '../widgets/artwork.dart';
import '../widgets/song_menu.dart';
import '../widgets/song_download_button.dart';
import '../widgets/song_tile.dart';
import 'equalizer_page.dart';
import 'player_palette.dart';

/// The full-screen player.
///
/// Layout, top to bottom: lightweight header, square artwork (the visual
/// focus), song info, seek bar, transport controls and a bottom-anchored
/// utility row (Equalizer | Add to Playlist | Speed | Queue). Lyrics live in
/// their own pull-up sheet at the very bottom, and the whole player can be
/// dragged downwards to collapse back into the mini player — revealing the
/// real Home screen underneath (the route below is kept alive because this
/// page is pushed as a non-opaque route).
class FullPlayerPage extends StatefulWidget {
  const FullPlayerPage({super.key});

  @override
  State<FullPlayerPage> createState() => _FullPlayerPageState();
}

class _FullPlayerPageState extends State<FullPlayerPage>
    with SingleTickerProviderStateMixin {
  // ---- seek bar drag ------------------------------------------------------
  bool _dragging = false;
  double _dragValue = 0;

  // ---- swipe-down collapse ------------------------------------------------
  double _dismissDrag = 0;
  double _snapFrom = 0;
  late final AnimationController _snapBack = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 280),
  );

  // ---- lyrics sheet -------------------------------------------------------
  final DraggableScrollableController _lyricsCtrl =
      DraggableScrollableController();
  final ValueNotifier<double> _lyricsExtent = ValueNotifier<double>(0);
  double _lyricsMinExtent = 0.08;
  static const double _lyricsMaxExtent = 0.88;

  // ---- dynamic artwork palette -------------------------------------------
  String? _paletteUrl;
  PlayerPalette _palette = PlayerPalette.fallback;

  @override
  void initState() {
    super.initState();
    _snapBack.addListener(_onSnapBackTick);
    _lyricsCtrl.addListener(_onLyricsExtentChanged);
  }

  @override
  void dispose() {
    _snapBack
      ..removeListener(_onSnapBackTick)
      ..dispose();
    _lyricsCtrl
      ..removeListener(_onLyricsExtentChanged)
      ..dispose();
    _lyricsExtent.dispose();
    super.dispose();
  }

  void _onSnapBackTick() {
    if (!mounted) return;
    setState(() {
      _dismissDrag =
          _snapFrom * (1 - Curves.easeOutCubic.transform(_snapBack.value));
    });
  }

  void _onLyricsExtentChanged() {
    if (!_lyricsCtrl.isAttached) return;
    final double size = _lyricsCtrl.size;
    // The controller can notify during layout; defer the notification in that
    // case so dependent widgets never call setState mid-build.
    final SchedulerPhase phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _lyricsExtent.value = size;
      });
    } else {
      _lyricsExtent.value = size;
    }
  }

  // -------------------------------------------------------------------------
  // Dynamic backdrop palette
  // -------------------------------------------------------------------------

  /// Keeps [_palette] in sync with the sleeve of the current song. Cached
  /// palettes apply instantly; new sleeves are analysed off the hot path and
  /// the backdrop cross-fades once the colours are ready.
  void _syncPalette(Song song) {
    final String url = song.thumbnailUrl;
    if (url == _paletteUrl) return;
    _paletteUrl = url;
    final PlayerPalette? hit = PlayerPaletteService.cached(url);
    if (hit != null) {
      _palette = hit;
      return;
    }
    PlayerPaletteService.extract(url).then((PlayerPalette palette) {
      if (!mounted || _paletteUrl != url) return;
      setState(() => _palette = palette);
    });
  }

  // -------------------------------------------------------------------------
  // Swipe-down collapse
  // -------------------------------------------------------------------------

  void _onDismissStart(DragStartDetails details) => _snapBack.stop();

  void _onDismissUpdate(DragUpdateDetails details) {
    final double max = MediaQuery.sizeOf(context).height * 0.7;
    setState(
      () => _dismissDrag = (_dismissDrag + details.delta.dy).clamp(0.0, max),
    );
  }

  void _onDismissEnd(DragEndDetails details) {
    final double height = MediaQuery.sizeOf(context).height;
    final double velocity = details.primaryVelocity ?? 0;
    final bool shouldClose = _dismissDrag > height * 0.22 ||
        (_dismissDrag > 60 && velocity > 650);
    if (shouldClose) {
      // Playback continues untouched — only the route goes away, revealing
      // the Home shell (and its mini player) that is still alive below.
      Navigator.of(context).maybePop();
      return;
    }
    _springBack();
  }

  void _springBack() {
    if (_dismissDrag <= 0) return;
    _snapFrom = _dismissDrag;
    _snapBack.forward(from: 0);
  }

  // -------------------------------------------------------------------------
  // Sheets (existing functionality, unchanged wiring)
  // -------------------------------------------------------------------------

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

  void _toggleLyricsSheet() {
    if (!_lyricsCtrl.isAttached) return;
    final bool expanded = _lyricsCtrl.size > _lyricsMinExtent + 0.05;
    _lyricsCtrl.animateTo(
      expanded ? _lyricsMinExtent : _lyricsMaxExtent,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

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

    _syncPalette(song);

    final bool liked = library.isLiked(song.id);
    final Duration total = playback.duration == Duration.zero
        ? (song.duration ?? Duration.zero)
        : playback.duration;

    final Size screen = MediaQuery.sizeOf(context);
    final EdgeInsets insets = MediaQuery.paddingOf(context);

    // Collapsed "Lyrics" bar height, expressed as a sheet fraction.
    final double peekPx = 56 + insets.bottom;
    _lyricsMinExtent = screen.height > 0
        ? (peekPx / screen.height).clamp(0.055, 0.18)
        : 0.08;

    // 0 → fully expanded, 1 → dragged far enough to collapse.
    final double dismissP = screen.height > 0
        ? (_dismissDrag / (screen.height * 0.42)).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      // Transparent so the Home shell below the (non-opaque) route shows
      // through while the player is being dragged down.
      backgroundColor: Colors.transparent,
      body: Transform.translate(
        offset: Offset(0, _dismissDrag),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30 * dismissP),
          child: Stack(
            fit: StackFit.expand,
            children: <Widget>[
              // ---- dynamic, artwork-driven backdrop ----------------------
              Opacity(
                opacity: (1 - dismissP * 1.05).clamp(0.0, 1.0),
                child: _PlayerBackdrop(palette: _palette),
              ),

              // ---- main content (drag down anywhere here to collapse) ----
              GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragStart: _onDismissStart,
                onVerticalDragUpdate: _onDismissUpdate,
                onVerticalDragEnd: _onDismissEnd,
                onVerticalDragCancel: _springBack,
                child: Opacity(
                  opacity: (1 - dismissP * 0.35).clamp(0.0, 1.0),
                  child: SafeArea(
                    bottom: false,
                    child: Column(
                      children: <Widget>[
                        _buildTopBar(playback, song),
                        Expanded(
                          child: Column(
                            children: <Widget>[
                              // ---- artwork: the visual focus -------------
                              Expanded(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 10),
                                  child: Center(
                                    child: _buildArtwork(song, dismissP),
                                  ),
                                ),
                              ),
                              _buildTitleRow(song, library, liked, accent),
                              _buildSeekBar(playback, total),
                              _buildTransport(playback),
                              const SizedBox(height: 10),
                              _buildUtilityRow(playback, library, song),
                              // Room for the collapsed lyrics bar + system
                              // navigation / gesture inset.
                              SizedBox(height: peekPx + 12),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ---- lyrics: a dedicated pull-up experience ----------------
              _LyricsSheet(
                song: song,
                controller: _lyricsCtrl,
                extentListenable: _lyricsExtent,
                minExtent: _lyricsMinExtent,
                maxExtent: _lyricsMaxExtent,
                palette: _palette,
                onHeaderTap: _toggleLyricsSheet,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- top bar -------------------------------------------------------------

  Widget _buildTopBar(PlaybackService playback, Song song) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            tooltip: 'Minimize',
            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 30),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              children: <Widget>[
                const Text(
                  'NOW PLAYING',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.8,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'From your queue',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
          if (playback.lastError != null)
            IconButton(
              tooltip: 'Mail this error to ifallertzia so he can fix the bug',
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
            tooltip: 'Lyrics',
            icon: const Icon(Icons.lyrics_outlined),
            onPressed: _toggleLyricsSheet,
          ),
          IconButton(
            tooltip: 'Sleep Timer',
            icon: const Icon(Icons.bedtime_rounded),
            onPressed: () => _showSleepSheet(playback),
          ),
          IconButton(
            tooltip: 'More',
            icon: const Icon(Icons.more_horiz_rounded),
            onPressed: () => showSongSheet(context, song),
          ),
        ],
      ),
    );
  }

  // ---- artwork --------------------------------------------------------------

  Widget _buildArtwork(Song song, double dismissP) {
    return ValueListenableBuilder<double>(
      valueListenable: _lyricsExtent,
      builder: (BuildContext context, double extent, Widget? _) {
        // Shrink the sleeve as the lyrics sheet rises and as the player is
        // dragged down towards the mini player.
        final double lyricsRange = 0.60 - _lyricsMinExtent;
        final double lyricsP = lyricsRange <= 0
            ? 0
            : ((extent - _lyricsMinExtent) / lyricsRange).clamp(0.0, 1.0);
        final double scale = (1 - 0.34 * lyricsP) * (1 - 0.18 * dismissP);

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints c) {
            double side = math.min(
              c.maxWidth.isFinite ? c.maxWidth - 56 : 320.0,
              c.maxHeight.isFinite ? c.maxHeight - 12 : 320.0,
            );
            side = side.clamp(0.0, 420.0) * scale;
            if (side <= 10) return const SizedBox.shrink();

            return Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: _palette.glow.withValues(alpha: 0.35),
                    blurRadius: 80,
                    spreadRadius: -18,
                    offset: const Offset(0, 26),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.55),
                    blurRadius: 40,
                    spreadRadius: -8,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Hero(
                  tag: 'player-artwork-${song.id}',
                  child: Artwork(
                    url: song.thumbnailUrl,
                    radius: 8,
                    size: double.infinity,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---- song information ------------------------------------------------------

  Widget _buildTitleRow(
    Song song,
    LibraryService library,
    bool liked,
    SaxifyAccent accent,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 6, 12, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    color: SaxifyColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SongDownloadButton(song: song, size: 40),
          IconButton(
            iconSize: 24,
            tooltip: liked ? 'Remove from Liked' : 'Like',
            icon: Icon(
              liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              color: liked ? accent.primary : SaxifyColors.textMuted,
            ),
            onPressed: () => library.toggleLike(song),
          ),
        ],
      ),
    );
  }

  // ---- seek bar ----------------------------------------------------------------

  Widget _buildSeekBar(PlaybackService playback, Duration total) {
    return StreamBuilder<Duration>(
      stream: playback.positionStream,
      initialData: playback.position,
      builder: (BuildContext context, AsyncSnapshot<Duration> snap) {
        final Duration position = snap.data ?? Duration.zero;
        final double fraction = total.inMilliseconds == 0
            ? 0
            : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
        final double value = _dragging ? _dragValue : fraction;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Column(
            children: <Widget>[
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3.4,
                  activeTrackColor: Colors.white,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.22),
                  thumbColor: Colors.white,
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                    pressedElevation: 3,
                  ),
                  overlayShape: const RoundSliderOverlayShape(
                    overlayRadius: 15,
                  ),
                  overlayColor: Colors.white.withValues(alpha: 0.12),
                ),
                child: Slider(
                  value: value,
                  onChanged: (double v) => setState(() {
                    _dragging = true;
                    _dragValue = v;
                  }),
                  onChangeEnd: (double v) async {
                    setState(() => _dragging = false);
                    await playback.seekFraction(v);
                  },
                ),
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
                                    (total.inMilliseconds * _dragValue)
                                        .round(),
                              )
                            : position,
                      ),
                      style: const TextStyle(
                        fontSize: 11.5,
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
                        child: CircularProgressIndicator(strokeWidth: 1.6),
                      )
                    else
                      Text(
                        '-${Fmt.clock(total - position)}',
                        style: const TextStyle(
                          fontSize: 11.5,
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
    );
  }

  // ---- transport -----------------------------------------------------------------

  Widget _buildTransport(PlaybackService playback) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 2, 26, 0),
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
            size: 38,
            onTap: playback.previous,
          ),
          _PlayButton(
            playing: playback.isPlaying,
            loading: playback.isLoading,
            glow: _palette.glow,
            onTap: playback.togglePlayPause,
          ),
          _TransportIcon(
            icon: Icons.skip_next_rounded,
            size: 38,
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
    );
  }

  // ---- bottom utility controls ------------------------------------------------------
  //
  // Mandatory order: Equalizer | Add to Playlist | Speed | Queue — anchored to
  // the bottom of the expanded player, above the collapsed lyrics bar.

  Widget _buildUtilityRow(
    PlaybackService playback,
    LibraryService library,
    Song song,
  ) {
    final bool inPlaylist = library.playlists.any(
      (Playlist p) => p.songs.any((Song s) => s.id == song.id),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _UtilityButton(
              icon: Icons.graphic_eq_rounded,
              label: 'Equalizer',
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EqualizerPage(),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _UtilityButton(
              // Playlist-plus glyph: stacked playlist lines + a plus sign.
              icon: Icons.playlist_add_rounded,
              label: 'Playlist',
              active: inPlaylist,
              onTap: () => showAddToPlaylistSheet(context, song),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _UtilityButton(
              icon: Icons.speed_rounded,
              label: '${playback.speed}x',
              active: playback.speed != 1.0,
              onTap: () => _showSpeedSheet(playback),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _UtilityButton(
              icon: Icons.queue_music_rounded,
              label: 'Queue',
              onTap: _showQueueSheet,
            ),
          ),
        ],
      ),
    );
  }
}

/// Deep gradient derived from the current sleeve. The [AnimatedContainer]s
/// cross-fade the colours (~750 ms) whenever a new palette arrives, so the
/// backdrop feels tied to the artwork instead of a hard theme switch.
class _PlayerBackdrop extends StatelessWidget {
  const _PlayerBackdrop({required this.palette});

  final PlayerPalette palette;

  static const Duration _fade = Duration(milliseconds: 750);

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: _fade,
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            palette.primary,
            palette.secondary,
            SaxifyColors.background,
          ],
          stops: const <double>[0.0, 0.55, 1.0],
        ),
      ),
      // A very subtle ambient colour wash behind the artwork area — not a
      // blurred copy of the sleeve, just its light.
      child: AnimatedContainer(
        duration: _fade,
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.45),
            radius: 1.15,
            colors: <Color>[
              palette.glow.withValues(alpha: 0.20),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }
}

/// One of the four bottom utility controls.
class _UtilityButton extends StatelessWidget {
  const _UtilityButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final Color fg = active ? accent.primary : SaxifyColors.textSecondary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: active
                ? accent.primary.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: active
                  ? accent.primary.withValues(alpha: 0.55)
                  : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 20, color: fg),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Lyrics sheet
// ---------------------------------------------------------------------------

/// The dedicated lyrics experience: a pull-up sheet anchored below the bottom
/// utility controls. Collapsed it is just a slim "Lyrics" bar; dragged (or
/// tapped) upwards it takes over most of the screen while the artwork above
/// shrinks. Fetching only starts once the listener actually opens it, so the
/// player never fires a lyrics request on its own.
class _LyricsSheet extends StatefulWidget {
  const _LyricsSheet({
    required this.song,
    required this.controller,
    required this.extentListenable,
    required this.minExtent,
    required this.maxExtent,
    required this.palette,
    required this.onHeaderTap,
  });

  final Song song;
  final DraggableScrollableController controller;
  final ValueListenable<double> extentListenable;
  final double minExtent;
  final double maxExtent;
  final PlayerPalette palette;
  final VoidCallback onHeaderTap;

  @override
  State<_LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<_LyricsSheet> {
  LyricsResult? _result;
  bool _requested = false;
  bool _loading = false;
  bool _missing = false;
  bool _synced = true;

  // Auto-centering of the active synced line.
  final GlobalKey _activeLineKey = GlobalKey();
  ScrollController? _listController;
  int _lastActive = -1;
  DateTime? _holdUntil;

  @override
  void initState() {
    super.initState();
    widget.extentListenable.addListener(_onExtentChanged);
  }

  @override
  void dispose() {
    widget.extentListenable.removeListener(_onExtentChanged);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _LyricsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.extentListenable != widget.extentListenable) {
      oldWidget.extentListenable.removeListener(_onExtentChanged);
      widget.extentListenable.addListener(_onExtentChanged);
    }
    if (oldWidget.song.id != widget.song.id) {
      _result = null;
      _missing = false;
      _synced = true;
      _lastActive = -1;
      if (_requested) _load();
    }
  }

  bool get _expanded =>
      widget.extentListenable.value > widget.minExtent + 0.05;

  void _onExtentChanged() {
    if (!mounted) return;
    // First expansion triggers the lookup.
    if (!_requested && _expanded) {
      _requested = true;
      _load();
    }
    // Header chevron + secondary controls depend on the expansion state.
    setState(() {});
  }

  Future<void> _load() async {
    final Song song = widget.song;
    if (!mounted) return;
    setState(() {
      _loading = true;
      _missing = false;
    });
    try {
      final LyricsResult result = await LyricsService.instance.find(
        title: song.title,
        artist: song.artist,
        durationSecs: song.duration?.inSeconds ?? 0,
        videoId: song.id,
      );
      if (!mounted || song.id != widget.song.id) return;
      setState(() {
        _result = result;
        _loading = false;
        _missing = result.status == LyricsStatus.notFound ||
            (result.plain.trim().isEmpty && result.lines.isEmpty);
        _synced = result.synced;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _missing = true;
      });
    }
  }

  // ---- header drag: let the collapsed bar be swiped up/down ----------------

  void _onHeaderDragUpdate(DragUpdateDetails details) {
    if (!widget.controller.isAttached) return;
    final double height = MediaQuery.sizeOf(context).height;
    if (height <= 0) return;
    final double size = (widget.controller.size - details.delta.dy / height)
        .clamp(widget.minExtent, widget.maxExtent);
    widget.controller.jumpTo(size);
  }

  void _onHeaderDragEnd(DragEndDetails details) {
    if (!widget.controller.isAttached) return;
    final double velocity = details.primaryVelocity ?? 0;
    double target;
    if (velocity < -350) {
      target = widget.maxExtent;
    } else if (velocity > 350) {
      target = widget.minExtent;
    } else {
      final double size = widget.controller.size;
      final double mid = (widget.minExtent + widget.maxExtent) / 2;
      target = size >= mid ? widget.maxExtent : widget.minExtent;
    }
    widget.controller.animateTo(
      target,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  // ---- synced-line centering ------------------------------------------------

  void _scheduleCenter(int active, int total) {
    if (active < 0 || active == _lastActive) return;
    _lastActive = active;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _centerActive(active, total),
    );
  }

  void _centerActive(int active, int total) {
    if (!mounted || !_expanded || !_synced) return;
    final DateTime? hold = _holdUntil;
    if (hold != null && DateTime.now().isBefore(hold)) return;
    final BuildContext? lineContext = _activeLineKey.currentContext;
    if (lineContext != null) {
      Scrollable.ensureVisible(
        lineContext,
        alignment: 0.35,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    // The active line is far outside the viewport: approximate, then the next
    // tick will fine-tune via ensureVisible.
    final ScrollController? sc = _listController;
    if (sc == null || !sc.hasClients || total <= 0) return;
    final double max = sc.position.maxScrollExtent;
    sc.animateTo(
      (max * active / total).clamp(0.0, max),
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  bool _onScrollNotification(ScrollNotification notification) {
    final bool userDriven =
        (notification is ScrollStartNotification &&
            notification.dragDetails != null) ||
        (notification is ScrollUpdateNotification &&
            notification.dragDetails != null);
    if (userDriven) {
      _holdUntil = DateTime.now().add(const Duration(seconds: 3));
    }
    return false;
  }

  // ---- build ------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      controller: widget.controller,
      minChildSize: widget.minExtent,
      initialChildSize: widget.minExtent,
      maxChildSize: widget.maxExtent,
      snap: true,
      snapSizes: const <double>[0.55],
      builder: (BuildContext context, ScrollController scrollController) {
        _listController = scrollController;
        final bool expanded = _expanded;
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          child: BackdropFilter(
            filter: GlassBlur.thickFilter,
            child: Container(
              decoration: BoxDecoration(
                color: Color.alphaBlend(
                  widget.palette.primary.withValues(alpha: 0.18),
                  const Color(0xFF0A0B10),
                ).withValues(alpha: 0.93),
                border: Border(
                  top: BorderSide(
                    color: Colors.white.withValues(alpha: 0.10),
                  ),
                ),
              ),
              child: Column(
                children: <Widget>[
                  _buildHeader(expanded),
                  if (expanded && _result != null && !_loading && !_missing)
                    _buildModeRow(),
                  Expanded(
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: _buildBody(scrollController),
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

  Widget _buildHeader(bool expanded) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onHeaderTap,
      onVerticalDragUpdate: _onHeaderDragUpdate,
      onVerticalDragEnd: _onHeaderDragEnd,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 7),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 7, 14, 8),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.lyrics_outlined,
                  size: 16,
                  color: SaxifyColors.textMuted,
                ),
                const SizedBox(width: 8),
                const Text(
                  'Lyrics',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: SaxifyColors.textPrimary,
                  ),
                ),
                const Spacer(),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 240),
                  child: const Icon(
                    Icons.keyboard_arrow_up_rounded,
                    size: 22,
                    color: SaxifyColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Static / Synced toggle + reload + "find lyrics" — technical options that
  /// live inside the lyrics area instead of the main player.
  Widget _buildModeRow() {
    final LyricsResult? result = _result;
    final bool hasSynced = result?.synced ?? false;
    final bool synced = _synced && hasSynced;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 10, 6),
      child: Row(
        children: <Widget>[
          _LyricsModeChip(
            label: 'Static',
            selected: !synced,
            onTap: () => setState(() => _synced = false),
          ),
          const SizedBox(width: 8),
          _LyricsModeChip(
            label: 'Synced',
            selected: synced,
            enabled: hasSynced,
            onTap: () => setState(() => _synced = true),
          ),
          const Spacer(),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 17,
              tooltip: 'Reload lyrics',
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _load,
            ),
          ),
          SizedBox(
            width: 32,
            height: 32,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 17,
              tooltip: 'Find or fix lyrics',
              icon: const Icon(Icons.manage_search_rounded),
              onPressed: () => showLyricsPanel(context, widget.song),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ScrollController scrollController) {
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final SaxifyAccent accent = context.accent;

    if (!_requested || _loading) {
      return ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(24, 10, 24, bottomInset + 30),
        children: <Widget>[
          if (_loading)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.6,
                    color: accent.primary,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Looking for lyrics…',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: SaxifyColors.textMuted,
                  ),
                ),
              ],
            )
          else
            const Center(
              child: Text(
                'Swipe up to read along',
                style: TextStyle(
                  fontSize: 12.5,
                  color: SaxifyColors.textMuted,
                ),
              ),
            ),
        ],
      );
    }

    final LyricsResult? result = _result;
    if (_missing || result == null) {
      return ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(28, 26, 28, bottomInset + 30),
        children: <Widget>[
          Icon(
            Icons.lyrics_outlined,
            size: 38,
            color: Colors.white.withValues(alpha: 0.28),
          ),
          const SizedBox(height: 14),
          const Text(
            'No lyrics for this one yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15.5,
              fontWeight: FontWeight.w700,
              color: SaxifyColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'This track may be too new or too underrated for the lyrics '
            'providers. ifallertzia is on it — try again in a bit.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.55,
              color: SaxifyColors.textMuted.withValues(alpha: 0.9),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Try again', style: TextStyle(fontSize: 12)),
            ),
          ),
        ],
      );
    }

    final bool hasSynced = result.synced && result.lines.isNotEmpty;
    final bool synced = _synced && hasSynced;

    if (!synced) {
      return ListView(
        controller: scrollController,
        padding: EdgeInsets.fromLTRB(24, 6, 24, bottomInset + 40),
        children: <Widget>[
          Text(
            result.plain,
            style: const TextStyle(
              fontSize: 16,
              height: 1.6,
              fontWeight: FontWeight.w500,
              color: SaxifyColors.textSecondary,
            ),
          ),
        ],
      );
    }

    final PlaybackService playback = context.watch<PlaybackService>();
    return StreamBuilder<Duration>(
      stream: playback.positionStream,
      initialData: playback.position,
      builder: (BuildContext context, AsyncSnapshot<Duration> snap) {
        final int positionMs = (snap.data ?? Duration.zero).inMilliseconds;
        final int active = activeLineIndex(result.lines, positionMs);
        _scheduleCenter(active, result.lines.length);

        return ListView.builder(
          controller: scrollController,
          padding: EdgeInsets.fromLTRB(24, 6, 24, bottomInset + 120),
          itemCount: result.lines.length,
          itemBuilder: (BuildContext context, int i) {
            final bool isActive = i == active;
            final Widget line = Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                style: TextStyle(
                  fontSize: isActive ? 19 : 16.5,
                  height: 1.35,
                  fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                  color: isActive
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.38),
                ),
                child: Text(result.lines[i].text),
              ),
            );
            return isActive
                ? KeyedSubtree(key: _activeLineKey, child: line)
                : line;
          },
        );
      },
    );
  }
}

/// Static / Synced selector. Kept small so it never competes with the words.
class _LyricsModeChip extends StatelessWidget {
  const _LyricsModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final Color border = selected
        ? accent.primary.withValues(alpha: 0.75)
        : Colors.white.withValues(alpha: 0.10);
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: border),
            color: selected
                ? accent.primary.withValues(alpha: 0.14)
                : Colors.white.withValues(alpha: 0.03),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : SaxifyColors.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton({
    required this.playing,
    required this.loading,
    required this.glow,
    required this.onTap,
  });

  final bool playing;
  final bool loading;
  final Color glow;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 750),
        curve: Curves.easeOutCubic,
        width: 68,
        height: 68,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: glow.withValues(alpha: 0.55),
              blurRadius: 34,
              offset: const Offset(0, 10),
              spreadRadius: -6,
            ),
          ],
        ),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.black,
                ),
              )
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 38,
                color: Colors.black,
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
