import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../core/theme/saxify_accents.dart';
import '../services/lrc_parser.dart';
import '../services/lyrics_clock.dart';

enum LyricsMode { staticText, synced }

class LyricsView extends StatefulWidget {
  const LyricsView({
    super.key,
    required this.plain,
    required this.lines,
    required this.mode,
    this.positionMs = 0,
    required this.source,
    this.onSeek,
  });
  final String plain, source;
  final List<LyricLine> lines;
  final LyricsMode mode;
  final int positionMs;
  final ValueChanged<int>? onSeek;
  @override
  State<LyricsView> createState() => _LyricsViewState();
}

class _LyricsViewState extends State<LyricsView> {
  final _scroll = ScrollController();
  Timer? _pause;
  bool _following = true;
  double _height = 300;
  int get _active => activeLineIndex(widget.lines, widget.positionMs);
  @override
  void didUpdateWidget(LyricsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (activeLineIndex(oldWidget.lines, oldWidget.positionMs) != _active ||
        oldWidget.mode != widget.mode) {
      if (_following)
        WidgetsBinding.instance.addPostFrameCallback((_) => _center());
    }
  }

  void _center() {
    if (!mounted ||
        !_scroll.hasClients ||
        _active < 0 ||
        widget.mode != LyricsMode.synced)
      return;
    final offset = (_height * .34 + _active * 112 + 56 - _height / 2).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    if ((offset - _scroll.offset).abs() > 600 ||
        MediaQuery.disableAnimationsOf(context)) {
      _scroll.jumpTo(offset);
    } else {
      _scroll.animateTo(
        offset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _resume() {
    _pause?.cancel();
    if (mounted) setState(() => _following = true);
    _center();
  }

  void _userScroll() {
    _pause?.cancel();
    if (_following) setState(() => _following = false);
    _pause = Timer(const Duration(seconds: 5), _resume);
  }

  @override
  void dispose() {
    _pause?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode != LyricsMode.synced || !usableSync(widget.lines)) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: SelectableText(
          widget.plain,
          style: const TextStyle(fontSize: 15, height: 1.9),
        ),
      );
    }
    final active = _active;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _height = constraints.maxHeight;
        return Stack(
          children: [
            NotificationListener<ScrollNotification>(
              onNotification: (notice) {
                if (notice is ScrollStartNotification &&
                        notice.dragDetails != null ||
                    notice is UserScrollNotification &&
                        notice.direction != ScrollDirection.idle)
                  _userScroll();
                return false;
              },
              child: ListView.builder(
                controller: _scroll,
                itemExtent: 112,
                padding: EdgeInsets.only(
                  top: _height * .34,
                  bottom: _height * .46,
                ),
                itemCount: widget.lines.length,
                itemBuilder: (context, i) => Semantics(
                  label: 'Play from this line',
                  button: widget.onSeek != null,
                  child: InkWell(
                    onTap: widget.onSeek == null
                        ? null
                        : () {
                            widget.onSeek!(widget.lines[i].startMs);
                            _resume();
                          },
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        child: AnimatedOpacity(
                          opacity: i == active
                              ? 1
                              : i < active
                              ? .20
                              : .34,
                          duration: const Duration(milliseconds: 350),
                          child: AnimatedScale(
                            scale: i == active && !reduced ? 1.035 : 1,
                            duration: Duration(milliseconds: reduced ? 0 : 350),
                            child: AnimatedDefaultTextStyle(
                              duration: Duration(
                                milliseconds: reduced ? 0 : 350,
                              ),
                              style: TextStyle(
                                fontSize: 19,
                                height: 1.35,
                                fontWeight: i == active
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: i == active
                                    ? context.accent.primary
                                    : Colors.white,
                                shadows: i == active && !reduced
                                    ? [
                                        Shadow(
                                          color: context.accent.primary
                                              .withValues(alpha: .35),
                                          blurRadius: 12,
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Text(
                                widget.lines[i].text,
                                textAlign: TextAlign.center,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
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
            if (!_following)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: FilledButton.tonalIcon(
                    onPressed: _resume,
                    icon: const Icon(Icons.my_location, size: 16),
                    label: const Text('Current line'),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
