import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../../services/lrc_parser.dart';
import '../../services/lyrics_clock.dart';
import '../../services/lyrics_service.dart';
import '../widgets/sidify_widgets.dart';

/// Synced lyrics, the way the site shows them: big type, the sung line lit,
/// the rest dimmed; tap a line to seek. Plain text falls back gracefully.
///
/// The words themselves come from the app's lyrics engine; the interface
/// only ever credits "Sidify" — provider names are an engine detail and are
/// never shown.
class LyricsPane extends StatefulWidget {
  const LyricsPane({
    super.key,
    required this.song,
    this.onArt = true,
  });

  final Song song;

  /// On the player's mesh backdrop (white text) vs on a plain page.
  final bool onArt;

  @override
  State<LyricsPane> createState() => _LyricsPaneState();
}

class _LyricsPaneState extends State<LyricsPane> {
  LyricsResult? _result;
  bool _loading = true;
  bool _failed = false;
  final ScrollController _scroll = ScrollController();
  List<GlobalKey> _keys = <GlobalKey>[];
  int _active = -1;
  DateTime _lastUserScroll = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LyricsPane old) {
    super.didUpdateWidget(old);
    if (old.song.id != widget.song.id) _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
      _result = null;
      _active = -1;
    });
    try {
      final LyricsResult r = await LyricsService.instance.find(
        title: widget.song.title,
        artist: widget.song.artist,
        durationSecs: widget.song.durationSecs,
        videoId: widget.song.id,
      );
      if (!mounted) return;
      setState(() {
        _result = r;
        _loading = false;
        _keys = List<GlobalKey>.generate(
          r.lines.length,
          (_) => GlobalKey(),
        );
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _follow(int active) {
    if (active == _active) return;
    _active = active;
    if (active < 0 || active >= _keys.length) return;
    if (DateTime.now().difference(_lastUserScroll) <
        const Duration(seconds: 4)) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final BuildContext? ctx = _keys[active].currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.38,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final LyricsResult? r = _result;
    final Color base = widget.onArt ? Colors.white : context.sidify.text;

    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(
              color: base.withValues(alpha: 0.7),
              strokeWidth: 2.5,
            ),
            const SizedBox(height: 14),
            Text(
              'Finding the words…',
              style: TextStyle(fontSize: 14, color: base.withValues(alpha: 0.6)),
            ),
          ],
        ),
      );
    }
    if (_failed || r == null || (r.lines.isEmpty && r.plain.trim().isEmpty)) {
      return EmptyState(
        icon: Icons.lyrics_rounded,
        title: 'No lyrics found',
        desc: 'Sidify could not find the words for this song yet.',
        action: SidifyButton(
          label: 'Try again',
          variant: SidifyButtonVariant.secondary,
          small: true,
          onTap: _load,
        ),
      );
    }

    if (r.lines.isEmpty) {
      // Plain, unsynced words.
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              r.plain,
              style: TextStyle(
                fontSize: 19,
                height: 1.5,
                fontWeight: FontWeight.w600,
                color: base.withValues(alpha: 0.9),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Lyrics · Sidify',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: base.withValues(alpha: 0.45),
              ),
            ),
          ],
        ),
      );
    }

    return StreamBuilder<Duration>(
      stream: playback.positionStream,
      initialData: playback.position,
      builder: (BuildContext context, AsyncSnapshot<Duration> snap) {
        final int posMs = (snap.data ?? playback.position).inMilliseconds;
        final int active = activeLineIndex(r.lines, posMs);
        _follow(active);
        return NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification n) {
            if (n is UserScrollNotification) {
              _lastUserScroll = DateTime.now();
            }
            return false;
          },
          child: ListView.builder(
            controller: _scroll,
            padding: EdgeInsets.symmetric(
              horizontal: 26,
              vertical: MediaQuery.sizeOf(context).height * 0.16,
            ),
            itemCount: r.lines.length + 1,
            itemBuilder: (BuildContext context, int i) {
              if (i == r.lines.length) {
                return Padding(
                  padding: const EdgeInsets.only(top: 28),
                  child: Text(
                    'Lyrics · Sidify',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: base.withValues(alpha: 0.45),
                    ),
                  ),
                );
              }
              final LyricLine line = r.lines[i];
              final bool isActive = i == active;
              final bool past = i < active;
              return GestureDetector(
                key: _keys[i],
                onTap: () =>
                    playback.seekTo(Duration(milliseconds: line.startMs)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(
                      fontSize: 24,
                      height: 1.22,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      color: base.withValues(
                        alpha: isActive ? 1 : (past ? 0.45 : 0.4),
                      ),
                      shadows: isActive
                          ? <Shadow>[
                              Shadow(
                                color: base.withValues(alpha: 0.28),
                                blurRadius: 18,
                              ),
                            ]
                          : null,
                    ),
                    child: AnimatedScale(
                      scale: isActive ? 1 : 0.98,
                      duration: const Duration(milliseconds: 300),
                      alignment: Alignment.centerLeft,
                      child: Text(line.text.isEmpty ? '♪' : line.text),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

/// The standalone lyrics page (from a song's menu): compact head + the pane.
class LyricsViewPage extends StatelessWidget {
  const LyricsViewPage({super.key, required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Lyrics', style: SidifyText.titleM(t.text)),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
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
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: t.text,
                        ),
                      ),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: t.text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: LyricsPane(song: song, onArt: false)),
        ],
      ),
    );
  }
}
