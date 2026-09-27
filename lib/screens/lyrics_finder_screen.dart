import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:provider/provider.dart';

import '../core/models/song.dart';
import '../core/services/playback_service.dart';
import '../services/lyrics_clock.dart';
import '../services/lyrics_service.dart';
import '../widgets/copy_lyrics_button.dart';
import '../widgets/lyrics_view.dart';

Future<void> showLyricsPanel(BuildContext context, Song song) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (_) => FractionallySizedBox(
        heightFactor: .94,
        child: LyricsFinderScreen(song: song, panel: true),
      ),
    );

class LyricsFinderScreen extends StatefulWidget {
  const LyricsFinderScreen({
    super.key,
    this.song,
    this.panel = false,
    this.embedded = false,
  });
  final Song? song;
  final bool panel, embedded;
  @override
  State<LyricsFinderScreen> createState() => _LyricsFinderScreenState();
}

class _LyricsFinderScreenState extends State<LyricsFinderScreen>
    with SingleTickerProviderStateMixin {
  final _title = TextEditingController(), _artist = TextEditingController();
  LyricsResult? _result;
  LyricsMode _mode = LyricsMode.staticText;
  bool _loading = false;
  bool _live = false;
  Song? _bound;
  late PlaybackService _playback;
  late Ticker _ticker;
  StreamSubscription<Duration>? _positionSub;
  CancelToken? _cancel;
  int _generation = 0,
      _clock = 0,
      _lastFrame = 0,
      _bucket = -1,
      _displayClock = 0;

  @override
  void initState() {
    super.initState();
    _playback = context.read<PlaybackService>();
    _ticker = createTicker(_tick)..start();
    _playback.addListener(_trackChanged);
    _positionSub = _playback.positionStream.listen((position) {
      if (needsResync(_clock, position.inMilliseconds, _playback.isPlaying)) {
        _clock = position.inMilliseconds;
        if (mounted && _canSync && _mode == LyricsMode.synced)
          setState(() => _displayClock = _clock);
      }
    });
    if (widget.song != null) {
      _bound = widget.song;
      _live = _playback.current?.id == widget.song!.id;
      _fill(widget.song!);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _find(bound: widget.song);
      });
    }
  }

  void _fill(Song s) {
    _title.text = cleanTitle(s.title);
    _artist.text = cleanArtist(s.artist);
  }

  void _trackChanged() {
    final song = _playback.current;
    if (!_live || song == null || song.id == _bound?.id) return;
    _bound = song;
    _fill(song);
    _mode = LyricsMode.staticText;
    _find(bound: song);
  }

  bool get _canSync => _bound != null && _playback.current?.id == _bound!.id;
  void _tick(Duration elapsed) {
    final delta = elapsed.inMilliseconds - _lastFrame;
    _lastFrame = elapsed.inMilliseconds;
    if (!_canSync || !_playback.isPlaying) return;
    _clock = advance(
      _clock,
      delta,
      _playback.speed,
      _playback.duration.inMilliseconds,
    );
    final bucket = _clock ~/ 80;
    if (bucket == _bucket) return;
    _bucket = bucket;
    final lines = _result?.lines ?? <LyricLine>[];
    if (_mode == LyricsMode.synced &&
        activeLineIndex(lines, _displayClock) !=
            activeLineIndex(lines, _clock)) {
      setState(() => _displayClock = _clock);
    }
  }

  Future<void> _find({Song? bound, bool refresh = false}) async {
    if (_title.text.trim().isEmpty) return;
    _cancel?.cancel();
    _cancel = CancelToken();
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _result = null;
      _bound = bound;
      _mode = LyricsMode.staticText;
    });
    LyricsResult result;
    try {
      result = await LyricsService.instance.find(
        title: _title.text,
        artist: _artist.text,
        durationSecs:
            bound != null &&
                _playback.current?.id == bound.id &&
                _playback.duration.inSeconds > 0
            ? _playback.duration.inSeconds
            : bound?.durationSecs ?? 0,
        videoId: bound?.id,
        refresh: refresh,
        cancelToken: _cancel,
      );
    } catch (_) {
      result = const LyricsResult(status: LyricsStatus.unavailable);
    }
    if (!mounted || generation != _generation) return;
    setState(() {
      _result = result;
      _loading = false;
      _clock = _playback.position.inMilliseconds;
      _displayClock = _clock;
    });
  }

  void _seek(int ms) {
    _playback.seekTo(Duration(milliseconds: ms));
    setState(() {
      _clock = ms;
      _displayClock = ms;
    });
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _ticker.dispose();
    _positionSub?.cancel();
    _playback.removeListener(_trackChanged);
    _title.dispose();
    _artist.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = _result ?? const LyricsResult(status: LyricsStatus.notFound);
    final found =
        _result != null && r.status == LyricsStatus.found && !r.instrumental;
    final content = Column(
      children: [
        if (!widget.embedded)
          ListTile(
            title: Text(
              widget.panel ? 'Lyrics' : 'Lyrics Finder',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              widget.panel
                  ? 'NOW PLAYING · ${_bound?.title ?? ''} · ${_bound?.artist ?? ''}'
                  : 'Song ka naam likho — lyrics yahin aa jayenge.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close),
            ),
          ),
        ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.viewInsetsOf(context).bottom > 0 ? 150 : 260,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ExpansionTile(
                key: ValueKey(widget.panel),
                initiallyExpanded: !widget.panel,
                title: Text(
                  widget.panel
                      ? 'Wrong match or missing lyrics?'
                      : 'Search by song and singer',
                ),
                subtitle: widget.panel
                    ? const Text('Search by song and singer')
                    : null,
                children: [
                  TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Song title (required)',
                    ),
                    onSubmitted: (_) {
                      _live = widget.panel && _playback.current != null;
                      _find(
                        bound: widget.panel ? _playback.current : null,
                        refresh: true,
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _artist,
                    decoration: const InputDecoration(
                      labelText: 'Singer (optional)',
                    ),
                  ),
                  Wrap(
                    spacing: 8,
                    children: [
                      FilledButton(
                        onPressed: _loading
                            ? null
                            : () {
                                _live =
                                    widget.panel && _playback.current != null;
                                _find(
                                  bound: widget.panel
                                      ? _playback.current
                                      : null,
                                  refresh: true,
                                );
                              },
                        child: const Text('Find lyrics'),
                      ),
                      TextButton(
                        onPressed: () {
                          final song = _playback.current;
                          if (song != null) {
                            _live = true;
                            _fill(song);
                            _find(bound: song);
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Play a song first'),
                              ),
                            );
                          }
                        },
                        child: const Text('Use the playing song'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (found)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Wrap(
              spacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('Static'),
                  selected: _mode == LyricsMode.staticText,
                  onSelected: (_) =>
                      setState(() => _mode = LyricsMode.staticText),
                ),
                Tooltip(
                  message: r.synced
                      ? '${r.lines.length} timed lines'
                      : 'Timed lyrics are not available for this song',
                  child: ChoiceChip(
                    label: const Text('Synced'),
                    selected: _mode == LyricsMode.synced,
                    onSelected: r.synced
                        ? (_) => setState(() {
                            _mode = LyricsMode.synced;
                            _displayClock = _clock;
                          })
                        : null,
                  ),
                ),
                if (r.synced)
                  Text(
                    '${r.lines.length} timed lines',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 14),
                      Text('Finding lyrics…'),
                    ],
                  ),
                )
              : found
              ? LyricsView(
                  key: ValueKey('${_bound?.id}|${r.plain.hashCode}'),
                  plain: r.plain,
                  lines: r.lines,
                  mode: _mode,
                  positionMs: _canSync ? _displayClock : 0,
                  source: r.source,
                  onSeek: _canSync ? _seek : null,
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _result == null
                              ? 'Find lyrics, then read or copy them here.'
                              : r.instrumental
                              ? 'Instrumental track — no lyrics'
                              : r.status == LyricsStatus.unavailable
                              ? 'Lyrics services are temporarily unavailable. Please retry.'
                              : 'Lyrics not found',
                          textAlign: TextAlign.center,
                        ),
                        if (_result != null && !r.instrumental)
                          TextButton(
                            onPressed: () =>
                                _find(bound: _bound, refresh: true),
                            child: const Text('Retry'),
                          ),
                      ],
                    ),
                  ),
                ),
        ),
        if (found && _mode == LyricsMode.synced && _canSync)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                tooltip: 'Previous line',
                onPressed: () {
                  final i = activeLineIndex(r.lines, _clock);
                  _seek(r.lines[(i - 1).clamp(0, r.lines.length - 1)].startMs);
                },
                icon: const Icon(Icons.skip_previous),
              ),
              const Text('Tap a line to seek'),
              IconButton(
                tooltip: 'Next line',
                onPressed: () {
                  final i = activeLineIndex(r.lines, _clock);
                  _seek(r.lines[(i + 1).clamp(0, r.lines.length - 1)].startMs);
                },
                icon: const Icon(Icons.skip_next),
              ),
            ],
          ),
        if (found)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '${_mode == LyricsMode.synced ? 'Synced' : 'Static'} · via ${r.source}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
                CopyLyricsButton(plain: r.plain),
              ],
            ),
          ),
        SizedBox(height: widget.embedded ? 145 : 0),
      ],
    );
    return widget.panel
        ? Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: content,
          )
        : widget.embedded
        ? content
        : Scaffold(body: SafeArea(child: content));
  }
}
