import 'dart:math' as math;
import 'dart:ui';

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
import '../../services/lyrics_clock.dart';
import '../../services/lyrics_service.dart';
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

  final ScrollController _playerScrollController = ScrollController();
  final GlobalKey _lyricsSectionKey = GlobalKey();
  bool _lyricsRequested = false;

  @override
  void initState() {
    super.initState();
    _playerScrollController.addListener(_maybeStartLyricsSearch);
    // The section can already be on screen on a tall device.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStartLyricsSearch());
  }

  @override
  void dispose() {
    _playerScrollController
      ..removeListener(_maybeStartLyricsSearch)
      ..dispose();
    super.dispose();
  }

  /// Starts the lyrics lookup only once the section is (nearly) visible:
  /// opening the player must not fire a network request on its own.
  void _maybeStartLyricsSearch() {
    if (!mounted || _lyricsRequested) return;
    final BuildContext? sectionContext = _lyricsSectionKey.currentContext;
    if (sectionContext == null) return;
    final Object? object = sectionContext.findRenderObject();
    if (object is! RenderBox || !object.attached) return;
    final double screenHeight = MediaQuery.of(context).size.height;
    final double top = object.localToGlobal(Offset.zero).dy;
    if (top < screenHeight * 0.92) setState(() => _lyricsRequested = true);
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

    return Scaffold(
      backgroundColor: SaxifyColors.background,
      body: GestureDetector(
        onVerticalDragStart: (_) => _dismissDrag = 0,
        onVerticalDragUpdate: (details) => setState(
          () => _dismissDrag = (_dismissDrag + details.delta.dy).clamp(0, 400),
        ),
        onVerticalDragEnd: (details) {
          if (_dismissDrag > 110 ||
              (_dismissDrag > 25 && (details.primaryVelocity ?? 0) > 700)) {
            Navigator.of(context).maybePop();
          }
          setState(() => _dismissDrag = 0);
        },
        onVerticalDragCancel: () => setState(() => _dismissDrag = 0),
        child: Transform.translate(
          offset: Offset(0, _dismissDrag),
          child: Stack(
            children: <Widget>[
              // Ambient backdrop.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: <Color>[
                        accent.primary.withValues(alpha: 0.30),
                        accent.secondary.withValues(alpha: 0.10),
                        SaxifyColors.background,
                        SaxifyColors.background,
                      ],
                      stops: const <double>[0, 0.28, 0.62, 1],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 40, sigmaY: 40),
                  child: const SizedBox.shrink(),
                ),
              ),
              SafeArea(
                child: Column(
                  children: <Widget>[
                    // ---- top bar -------------------------------------------------
                    Padding(
                      padding: const EdgeInsets.fromLTRB(6, 4, 6, 0),
                      child: Row(
                        children: <Widget>[
                          IconButton(
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 30,
                            ),
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          Expanded(
                            child: Column(
                              children: <Widget>[
                                Text(
                                  'NOW PLAYING',
                                  style: TextStyle(
                                    fontSize: 10,
                                    letterSpacing: 1.8,
                                    fontWeight: FontWeight.w700,
                                    color: accent.primary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'From your queue',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: accent.primary.withValues(
                                      alpha: 0.75,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (playback.lastError != null)
                            IconButton(
                              tooltip:
                                  'Mail this error to ifallertzia so he can fix the bug',
                              icon: const Icon(Icons.bug_report_outlined),
                              onPressed: () async {
                                final opened =
                                    await PlaybackErrorReporter.compose(
                                      playback.lastError!,
                                    );
                                if (!opened)
                                  showAppNotice(
                                    'No email app available. Use MAIL ERROR on the failure message to copy the report.',
                                  );
                              },
                            ),
                          IconButton(
                            tooltip: 'Lyrics',
                            icon: const Icon(Icons.lyrics_outlined),
                            onPressed: () => showLyricsPanel(context, song),
                          ),
                          // ---- Sleep Timer (Top Right) ----
                          IconButton(
                            tooltip: 'Sleep Timer',
                            icon: const Icon(Icons.bedtime_rounded),
                            onPressed: () => _showSleepSheet(playback),
                          ),
                          IconButton(
                            icon: const Icon(Icons.more_horiz_rounded),
                            onPressed: () => showSongSheet(context, song),
                          ),
                        ],
                      ),
                    ),

                    // ---- artwork + controls + lyrics (one scroll) --------------
                    Expanded(
                      child: LayoutBuilder(
                        builder: (BuildContext layoutContext, BoxConstraints c) {
                          final double art = math.min(
                            c.maxWidth - 68,
                            c.maxHeight * 0.44,
                          );
                          return SingleChildScrollView(
                            controller: _playerScrollController,
                            padding: EdgeInsets.only(
                              bottom: MediaQuery.paddingOf(context).bottom + 28,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                // ---- artwork ---------------------------------
                                Center(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 34,
                                    ),
                                    child: SizedBox(
                                      height: art,
                                      width: art,
                                      child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(
                                  SaxifyTheme.radiusLg,
                                ),
                                boxShadow: <BoxShadow>[
                                  BoxShadow(
                                    color: accent.primary.withValues(
                                      alpha: 0.35,
                                    ),
                                    blurRadius: 60,
                                    offset: const Offset(0, 24),
                                    spreadRadius: -14,
                                  ),
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.6),
                                    blurRadius: 40,
                                    offset: const Offset(0, 18),
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
                                    size: double.infinity,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),

                    // ---- title row ----------------------------------------------
                    Padding(
                      padding: const EdgeInsets.fromLTRB(26, 22, 14, 0),
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
                                    height: 1.2,
                                  ),
                                ),
                                const SizedBox(height: 5),
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
                          SongDownloadButton(song: song, size: 42),
                          IconButton(
                            iconSize: 24,
                            icon: Icon(
                              liked
                                  ? Icons.favorite_rounded
                                  : Icons.favorite_border_rounded,
                              color: liked
                                  ? accent.primary
                                  : SaxifyColors.textMuted,
                            ),
                            onPressed: () => library.toggleLike(song),
                          ),
                        ],
                      ),
                    ),

                    // ---- seek ----------------------------------------------------
                    StreamBuilder<Duration>(
                      stream: playback.positionStream,
                      initialData: playback.position,
                      builder:
                          (BuildContext context, AsyncSnapshot<Duration> snap) {
                            final Duration position =
                                snap.data ?? Duration.zero;
                            final double fraction = total.inMilliseconds == 0
                                ? 0
                                : (position.inMilliseconds /
                                          total.inMilliseconds)
                                      .clamp(0.0, 1.0);
                            final double value = _dragging
                                ? _dragValue
                                : fraction;

                            return Padding(
                              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                              child: Column(
                                children: <Widget>[
                                  Slider(
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
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
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
                                            child: CircularProgressIndicator(
                                              strokeWidth: 1.6,
                                            ),
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
                    ),

                    // ---- transport ----------------------------------------------
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 8, 22, 0),
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

                    // ---- extras --------------------------------------------------
                    // Equalizer shortcut stays to the left of the playback controls.
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
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
                          const SizedBox(width: 10),
                          // Add to playlist: only the sign, no label and no
                          // extra dialog row — the circular + sits with the
                          // other round actions.
                          _RoundAction(
                            icon: Icons.add_rounded,
                            active: library.playlists.any(
                              (Playlist p) =>
                                  p.songs.any((Song s) => s.id == song.id),
                            ),
                            onTap: () => showAddToPlaylistSheet(context, song),
                          ),
                          const SizedBox(width: 10),
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
                                  const SizedBox(width: 8),
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
                    // ---- lyrics ---------------------------------------------
                    Padding(
                      key: _lyricsSectionKey,
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                      child: _lyricsRequested
                          ? _PlayerLyrics(
                              key: ValueKey<String>('lyrics-${song.id}'),
                              song: song,
                            )
                          : _LyricsHint(
                              onShow: () =>
                                  setState(() => _lyricsRequested = true),
                            ),
                    ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown until the listener scrolls to (or taps) the lyrics: a tiny affordance
/// that costs nothing and never fires a request on its own.
class _LyricsHint extends StatelessWidget {
  const _LyricsHint({required this.onShow});

  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton.icon(
        onPressed: onShow,
        icon: const Icon(Icons.lyrics_outlined, size: 17),
        label: const Text(
          'Lyrics',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

/// Lyrics pinned to the bottom of the player.
///
/// Deliberately quiet: only the words, a Static / Synced switch and a retry
/// affordance. No song title (it is already on screen above) and no
/// "wrong lyrics?" chatter — mismatch reporting stays in the lyrics finder.
class _PlayerLyrics extends StatefulWidget {
  const _PlayerLyrics({super.key, required this.song});

  final Song song;

  @override
  State<_PlayerLyrics> createState() => _PlayerLyricsState();
}

class _PlayerLyricsState extends State<_PlayerLyrics> {
  LyricsResult? _result;
  bool _loading = true;
  bool _synced = true;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _PlayerLyrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.song.id != widget.song.id) {
      _result = null;
      _synced = true;
      _load();
    }
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
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
        _missing =
            result.status == LyricsStatus.notFound ||
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

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final SaxifyAccent accent = context.accent;
    final LyricsResult? result = _result;
    final bool hasSynced = result?.synced ?? false;
    final bool synced = _synced && hasSynced;

    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 26),
        child: Row(
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
              'Lyrics dhoondh rahe hain…',
              style: TextStyle(fontSize: 12.5, color: SaxifyColors.textMuted),
            ),
          ],
        ),
      );
    }

    if (_missing || result == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(2, 8, 2, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'iska nahi dundh paya..sorry🥲',
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                fontWeight: FontWeight.w700,
                color: accent.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'shayad ye song playback kisi normal server se play ho raha,'
              'ya iska artist understand hai,,ya shayad ye song abhi '
              'underrated hai🥲..sorry again,,ifallertzia isko jaldi '
              'thik kr denge',
              style: TextStyle(
                fontSize: 11,
                height: 1.55,
                color: SaxifyColors.textMuted.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 10),
            TextButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded, size: 15),
              label: const Text('Try again', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Row(
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
              width: 30,
              height: 30,
              child: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 17,
                tooltip: 'Reload lyrics',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _load,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        if (synced)
          StreamBuilder<Duration>(
            stream: playback.positionStream,
            initialData: playback.position,
            builder: (
              BuildContext context,
              AsyncSnapshot<Duration> snap,
            ) {
              final int positionMs = (snap.data ?? Duration.zero).inMilliseconds;
              final int active = activeLineIndex(result.lines, positionMs);
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: EdgeInsets.zero,
                itemCount: result.lines.length,
                itemBuilder: (BuildContext context, int i) {
                  final bool isActive = i == active;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 7),
                    child: Text(
                      result.lines[i].text,
                      style: TextStyle(
                        fontSize: isActive ? 17 : 15.5,
                        height: 1.38,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? Colors.white : SaxifyColors.textMuted,
                      ),
                    ),
                  );
                },
              );
            },
          )
        else
          Text(
            result.plain,
            style: const TextStyle(
              fontSize: 15.5,
              height: 1.55,
              color: SaxifyColors.textSecondary,
            ),
          ),
      ],
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
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
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
              fontSize: 12,
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
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SaxifyTheme.radiusXl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SaxifyTheme.radiusXl),
            color: Colors.white.withValues(alpha: 0.06),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 14,
                color: SaxifyColors.textMuted,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: SaxifyColors.textSecondary,
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
