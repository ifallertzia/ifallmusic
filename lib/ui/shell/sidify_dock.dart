import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/listen_together_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../player/full_player_page.dart';
import '../widgets/sidify_widgets.dart';
import 'sidify_routes.dart';
import 'sidify_shell_controller.dart';

/// Watches the root navigator so the dock knows when to step aside: the full
/// player and any sheet/dialog cover it.
class SidifyRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];
  final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);

  /// True while any page is pushed over the shell (album, artist, settings…).
  final ValueNotifier<bool> pushed = ValueNotifier<bool>(false);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
    // A fresh page starts scrolled to the top — its chrome starts unfolded.
    SidifyDockScroll.barHidden.value = false;
    _sync();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _sync();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.remove(route);
    _sync();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    if (oldRoute != null) _stack.remove(oldRoute);
    if (newRoute != null) _stack.add(newRoute);
    _sync();
  }

  void _sync() {
    if (_stack.isEmpty) {
      if (hidden.value) hidden.value = false;
      if (pushed.value) pushed.value = false;
      return;
    }
    final Route<dynamic> top = _stack.last;
    final String routeName = top.settings.name ?? '';
    final bool covering = top is PopupRoute ||
        (top is PageRoute<dynamic> &&
            (routeName == SidifyRoutes.fullPlayer ||
                routeName.startsWith('sidify/movie-player-')));
    final bool over = _stack.length > 1;
    if (hidden.value != covering) hidden.value = covering;
    if (pushed.value != over) pushed.value = over;
  }
}

/// Scroll-driven chrome: scrolling down folds the tab bar into a single row —
/// Home staying as a small round button, the mini player sliding in beside it,
/// Search keeping its seat on the right. The smallest upward nudge unfolds it
/// back through the same path, so the pieces look like they are coming out of
/// each other rather than being swapped for different widgets.
class SidifyDockScroll {
  SidifyDockScroll._();

  /// True while the tab bar is folded into the mini player's row.
  static final ValueNotifier<bool> barHidden = ValueNotifier<bool>(false);

  /// Wired to the root [NotificationListener]; never consumes notifications.
  static bool handle(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is ScrollUpdateNotification) {
      final double delta = notification.scrollDelta ?? 0;
      if (notification.metrics.pixels <=
          notification.metrics.minScrollExtent + 2) {
        // At (or bouncing at) the very top the bar is always present.
        if (barHidden.value) barHidden.value = false;
      } else if (delta >= 1) {
        if (!barHidden.value) barHidden.value = true;
      } else if (delta <= -1) {
        if (barHidden.value) barHidden.value = false;
      }
    } else if (notification is ScrollEndNotification) {
      if (notification.metrics.pixels <=
              notification.metrics.minScrollExtent + 2 &&
          barHidden.value) {
        barHidden.value = false;
      }
    }
    return false;
  }
}

/// The base text style for everything the dock paints. The dock lives above
/// the navigator, outside any `Material`, so it has to name its own style —
/// otherwise `Text` falls back to Flutter's debug style (yellow monospace,
/// double-underlined) and every label grows a yellow line under it.
TextStyle _dockTextStyle(BuildContext context) {
  final SidifyTokens t = context.sidify;
  return (Theme.of(context).textTheme.bodyMedium ?? SidifyText.bodyS(t.text))
      .copyWith(decoration: TextDecoration.none);
}

// ---------------------------------------------------------------------------
// The dock's single source of truth for size. Everything the morph lerps
// between is expressed with these, so the folded row and the resting rows are
// two states of one layout instead of two layouts.
// ---------------------------------------------------------------------------

/// Height of a tab cell inside the bar.
const double _cell = 50;

/// Glass padding the bar and the round buttons wear.
const double _glassPad = 6;

/// The bar's whole slot: a 50px row of cells inside 6px of glass.
const double _slot = _cell + _glassPad * 2;

/// Air between the dock's separate surfaces.
const double _gap = 10;

/// Mini player height at rest / folded into the bar.
const double _miniH = 58;
const double _miniHFold = 46;

/// The dock stops growing past this width (tablets stay pocket-sized).
const double _maxWidth = 440;

double _lerp(double a, double b, double t) => a + (b - a) * t;

/// The floating chrome, painted above the navigator in `MaterialApp.builder`:
/// the liquid-glass tab bar and the pill mini player — the site's
/// `MobileChrome`, in Flutter. Present on every screen; only the full player
/// (and sheets) cover it.
class SidifyDock extends StatelessWidget {
  const SidifyDock({
    super.key,
    required this.observer,
    required this.navigatorKey,
  });

  final SidifyRouteObserver observer;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    // Before the profile exists there is no shell to dock onto.
    final SettingsService settings = context.watch<SettingsService>();
    if (settings.displayName.isEmpty) return const SizedBox.shrink();

    final PlaybackService playback = context.watch<PlaybackService>();
    final SidifyShellController shell = context.watch<SidifyShellController>();
    final double safe = MediaQuery.paddingOf(context).bottom;
    final bool hasTrack = playback.hasTrack && !shell.isMoviesMode;

    return ValueListenableBuilder<bool>(
      valueListenable: observer.hidden,
      builder: (BuildContext context, bool hidden, Widget? _) {
        if (hidden) return const SizedBox.shrink();
        final double tabBottom = safe > 0 ? safe + _glassPad : 10;
        return ValueListenableBuilder<bool>(
          valueListenable: SidifyDockScroll.barHidden,
          builder: (BuildContext context, bool barHidden, Widget? _) {
            return LayoutBuilder(
              builder: (BuildContext context, BoxConstraints box) {
                return _DockMorph(
                  folded: barHidden,
                  duration: settings.reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 460),
                  builder: (BuildContext context, double fold) {
                    // The raw 0→1 drive, split into two beats that share one
                    // controller: the bar folds and the player slims (first
                    // 62%), then the player drops into the seat the bar opened
                    // (the rest). Scrolling back up plays the same two beats in
                    // reverse, so the button looks like it came out of the bar
                    // and goes back into it — and the two panes never have to
                    // pass through each other to get there.
                    final double raw = fold.clamp(0.0, 1.0);
                    final double ease = Curves.easeOutCubic
                        .transform((raw / 0.62).clamp(0.0, 1.0));
                    final double drop = Curves.easeOutCubic.transform(
                        ((raw - 0.62) / 0.38).clamp(0.0, 1.0));
                    // `wobble` is the little overshoot the glass gets mid-flight
                    // so a pane stretches before it settles.
                    final double wobble = math.sin(raw * math.pi) * 0.045;

                    final double availW =
                        box.maxWidth.isFinite ? box.maxWidth : _maxWidth;
                    final double rowW =
                        math.max(math.min(availW - 24, _maxWidth), 0.0);
                    final double x0 = (availW - rowW) / 2;

                    // Three surfaces in one row need room for the two round
                    // buttons plus a readable pill. A window narrower than
                    // that — a shrunk desktop one — keeps the bar unfolded
                    // instead of crushing the player to nothing.
                    final double room = rowW - 2 * (_slot + _gap);
                    final bool canFold = room >= 120;
                    final double barT = canFold ? ease : 0.0;
                    final double dropT = canFold ? drop : 0.0;

                    // The bar: full row → just the Home button.
                    final double barW = math.max(rowW - _gap - _slot, _slot);
                    final double pillW = _lerp(barW, _slot, barT);

                    // The player: its own row above → the seat the bar just
                    // gave up, between Home and Search.
                    final double miniH =
                        (_lerp(_miniH, _miniHFold, barT) + _slot * wobble)
                            .clamp(40.0, _slot);
                    final double miniLeft = x0 + _lerp(0, _slot + _gap, barT);
                    final double miniW = math.max(
                        rowW - _lerp(0, 2 * (_slot + _gap), barT), 0.0);
                    final double miniBottom = tabBottom +
                        _lerp(_slot + _gap, (_slot - miniH) / 2, dropT);

                    // The liquid highlight travels across a pane as it folds.
                    final double sheen = Curves.easeInOutSine.transform(raw);

                    // The dock is painted above the navigator
                    // (MaterialApp.builder), so it has no Material ancestor.
                    // Without one, every Text here inherits Flutter's
                    // *fallback* text style — yellow monospace with a double
                    // yellow underline — which is exactly what used to draw
                    // yellow lines under the song title, the artist name and
                    // the tab labels. Supplying the app's own body style
                    // removes them at the source.
                    return DefaultTextStyle(
                      style: _dockTextStyle(context),
                      child: Stack(
                        children: <Widget>[
                          // The bar pill — Home · Explore · Library, folding
                          // down to Home alone on the left.
                          Positioned(
                            left: x0,
                            bottom: tabBottom,
                            width: pillW,
                            height: _slot,
                            child: _TabPill(
                              shell: shell,
                              observer: observer,
                              navigatorKey: navigatorKey,
                              fold: barT,
                              width: pillW,
                              sheen: sheen,
                            ),
                          ),
                          // Search: it never moves sideways, it just keeps its
                          // seat at the right end of whatever row is showing.
                          Positioned(
                            left: x0 + rowW - _slot,
                            bottom: tabBottom,
                            width: _slot,
                            height: _slot,
                            child: _SearchButton(
                              shell: shell,
                              observer: observer,
                              navigatorKey: navigatorKey,
                              sheen: sheen,
                            ),
                          ),
                          if (hasTrack)
                            Positioned(
                              left: miniLeft,
                              bottom: miniBottom,
                              width: miniW,
                              height: miniH,
                              child: _MiniPlayer(
                                fold: barT,
                                height: miniH,
                                width: miniW,
                                sheen: sheen,
                                onOpen: () {
                                  SidifyDockScroll.barHidden.value = false;
                                  final NavigatorState? nav =
                                      navigatorKey.currentState;
                                  if (nav == null) return;
                                  nav.push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => const FullPlayerPage(),
                                      settings: const RouteSettings(
                                        name: SidifyRoutes.fullPlayer,
                                      ),
                                      fullscreenDialog: true,
                                    ),
                                  );
                                },
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }
}

/// One driven number for the whole dock. A single `AnimationController` (rather than
/// `AnimatedPositioned` per piece) is what keeps the fold in lock-step: the
/// bar, the player and the highlight are three views of the same animation,
/// and an interrupted fold reverses from wherever it currently is instead of
/// restarting.
class _DockMorph extends StatefulWidget {
  const _DockMorph({
    required this.folded,
    required this.duration,
    required this.builder,
  });

  final bool folded;
  final Duration duration;
  final Widget Function(BuildContext context, double fold) builder;

  @override
  State<_DockMorph> createState() => _DockMorphState();
}

class _DockMorphState extends State<_DockMorph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.folded ? 1 : 0,
    );
  }

  @override
  void didUpdateWidget(_DockMorph old) {
    super.didUpdateWidget(old);
    if (old.duration != widget.duration && widget.duration != Duration.zero) {
      _controller.duration = widget.duration;
    }
    if (old.folded != widget.folded) _run();
  }

  void _run() {
    final double target = widget.folded ? 1 : 0;
    if (widget.duration == Duration.zero) {
      if (_controller.value != target) _controller.value = target;
      return;
    }
    _controller.animateTo(
      target,
      duration: widget.duration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: const SizedBox.shrink(),
      builder: (BuildContext context, Widget? _) =>
          widget.builder(context, _controller.value),
    );
  }
}

/// The pill mini player — liquid glass, 58px tall at rest and 46px once it has
/// folded into the bar's row: artwork, title/artist, play and next, and a 2px
/// progress hairline along the bottom edge. Every measurement is lerped
/// between the two seats, so the pill reads as the same object shrinking into
/// the bar instead of a second widget appearing.
class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({
    required this.onOpen,
    required this.fold,
    required this.height,
    required this.width,
    required this.sheen,
  });

  final VoidCallback onOpen;

  /// 0 = its own row above the tab bar, 1 = folded in beside Home.
  final double fold;
  final double height;
  final double width;
  final double sheen;

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final JamService jam = context.watch<JamService>();
    final Song? track = playback.current;
    if (track == null) return const SizedBox.shrink();
    final SidifyTokens t = context.sidify;
    final double f = fold;

    final double art = _lerp(42, 32, f);
    final double radius = _lerp(18, 999, f);
    final double btn = _lerp(40, 30, f);
    final double titleSize = _lerp(14.5, 12.5, f);
    final double artistSize = _lerp(12.5, 10.5, f);
    // Folded into a narrow row the pill gives up its least essential pieces
    // first — the artist, then the skip — rather than crushing the title.
    final bool narrow = f > 0.5 && width < 208;
    final bool tight = f > 0.5 && width < 176;

    return GlassBox(
      bar: true,
      radius: radius,
      sheen: sheen,
      child: SizedBox(
        height: height,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: EdgeInsets.only(
                left: _lerp(8, 5, f),
                right: _lerp(6, 4, f),
              ),
              child: Row(
                children: <Widget>[
                  GestureDetector(
                    onTap: onOpen,
                    child: Artwork(
                      url: track.thumbnailUrl,
                      size: art,
                      radius: _lerp(9, 7, f),
                    ),
                  ),
                  SizedBox(width: _lerp(10, 7, f)),
                  Expanded(
                    child: GestureDetector(
                      onTap: onOpen,
                      behavior: HitTestBehavior.opaque,
                      // Clamped scaling keeps the two text lines inside the
                      // pill on every font scale — no overflow stripes.
                      child: MediaQuery.withClampedTextScaling(
                        maxScaleFactor: 1.15,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              track.title,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: titleSize,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                                color: t.text,
                              ),
                            ),
                            if (!narrow) ...<Widget>[
                              SizedBox(height: _lerp(1, 0.5, f)),
                              Row(
                                children: <Widget>[
                                  if (jam.isConnected) ...<Widget>[
                                    Icon(
                                        Icons.people_rounded,
                                        size: _lerp(12, 10, f),
                                        color: t.playing),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${jam.members.length}',
                                      style: TextStyle(
                                        fontSize: artistSize,
                                        fontWeight: FontWeight.w600,
                                        color: t.playing,
                                      ),
                                    ),
                                    SizedBox(width: _lerp(5, 4, f)),
                                  ],
                                  Flexible(
                                    child: Text(
                                      track.artist,
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: artistSize,
                                        height: 1.1,
                                        color: t.text2,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: _lerp(4, 2, f)),
                  _dockBtn(
                    context,
                    playback.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    _lerp(24, 19, f),
                    btn,
                    () => playback.togglePlayPause(),
                    loading: playback.isLoading,
                  ),
                  if (!tight)
                    _dockBtn(
                      context,
                      Icons.skip_next_rounded,
                      _lerp(22, 17, f),
                      btn,
                      () => playback.next(),
                    ),
                ],
              ),
            ),
            // Its own layer: the hairline ticks with playback, and this keeps
            // those repaints off the glass underneath.
            Positioned(
              left: _lerp(16, 10, f),
              right: _lerp(16, 10, f),
              bottom: 0,
              child: RepaintBoundary(
                child: StreamBuilder<Duration>(
                  stream: playback.positionStream,
                  initialData: playback.position,
                  builder: (BuildContext context, AsyncSnapshot<Duration> s) {
                    final Duration pos = s.data ?? playback.position;
                    final int durMs = playback.duration.inMilliseconds;
                    final double pct = durMs > 0
                        ? (pos.inMilliseconds / durMs).clamp(0.0, 1.0)
                        : 0;
                    return Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color: t.fill2,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: pct,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              gradient: LinearGradient(
                                colors: <Color>[
                                  t.text.withValues(alpha: 0.55),
                                  t.text.withValues(alpha: 0.78),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dockBtn(
    BuildContext context,
    IconData icon,
    double size,
    double box,
    VoidCallback onTap, {
    bool loading = false,
  }) {
    return Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: box,
          height: box,
          child: loading
              ? Center(
                  child: SizedBox(
                    width: box * 0.45,
                    height: box * 0.45,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: context.sidify.text,
                    ),
                  ),
                )
              : Icon(icon, size: size, color: context.sidify.text),
        ),
      ),
    );
  }
}

/// The bar's cells in one glass pill: Home · Explore · Library, the selection
/// carried by a soft translucent pane. Folding the bar does not hide this
/// widget — the two outer cells shrink to nothing and Home takes the whole
/// pill, which is why the small button looks like it grew out of the bar.
class _TabPill extends StatelessWidget {
  const _TabPill({
    required this.shell,
    required this.observer,
    required this.navigatorKey,
    required this.fold,
    required this.width,
    required this.sheen,
  });

  final SidifyShellController shell;
  final SidifyRouteObserver observer;
  final GlobalKey<NavigatorState> navigatorKey;

  /// 0 = three cells side by side, 1 = Home alone as a round button.
  final double fold;
  final double width;
  final double sheen;

  List<(SidifyTab, String, IconData)> get _tabs => <(SidifyTab, String, IconData)>[
        (SidifyTab.home, 'Home', Icons.home_rounded),
        (SidifyTab.explore, 'Explore', Icons.explore_rounded),
        (SidifyTab.library, 'Library', shell.isMoviesMode ? Icons.video_library_rounded : Icons.library_music_rounded),
      ];

  /// The selected destination: a soft translucent pane, a shade brighter
  /// along the top so it reads as glass resting on glass. Legible for the icon
  /// and the label on top of it, and quiet enough that the unselected cells
  /// stay clear against the pane.
  static LinearGradient _selection(SidifyTokens t) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          t.text.withValues(alpha: t.isDark ? 0.18 : 0.12),
          t.text.withValues(alpha: t.isDark ? 0.09 : 0.06),
        ],
      );

  void _go(SidifyTab tab) {
    // Tapping a tab from a pushed page lands on that tab's root.
    if (observer.pushed.value) {
      navigatorKey.currentState?.popUntil((Route<dynamic> r) => r.isFirst);
    }
    // And it brings the full bar back — a fold the user did not ask for should
    // never outlive the tap that ended the scroll.
    if (SidifyDockScroll.barHidden.value) {
      SidifyDockScroll.barHidden.value = false;
    }
    shell.select(tab);
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    // The two outer cells hand their width to Home as the bar folds. Home is
    // what is left over, so the three cells always add up to exactly the pill —
    // no rounding drift, no overflow stripe down the middle of the dock.
    final double inner = width - _glassPad * 2;
    final double sideW = math.max(inner / 3 * (1 - fold), 0.0);
    final double homeW = inner - sideW * 2;

    return GlassBox(
      bar: true,
      radius: 999,
      sheen: sheen,
      padding: const EdgeInsets.symmetric(horizontal: _glassPad, vertical: _glassPad),
      child: SizedBox(
        height: _cell,
        child: Row(
          children: <Widget>[
            _cellWidget(t, 0, homeW),
            _cellWidget(t, 1, sideW),
            _cellWidget(t, 2, sideW),
          ],
        ),
      ),
    );
  }

  Widget _cellWidget(SidifyTokens t, int index, double w) {
    final (SidifyTab tab, String label, IconData icon) = _tabs[index];
    final bool selected = shell.tab == tab;
    // The cell's *window* shrinks; its content keeps its own size and is
    // clipped, which is what makes the row fold instead of squelching.
    final double contentW = math.max(w, _cell);
    return SizedBox(
      width: w,
      height: _cell,
      child: GestureDetector(
        onTap: () => _go(tab),
        behavior: HitTestBehavior.opaque,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.center,
            minWidth: contentW,
            maxWidth: contentW,
            child: Container(
              width: contentW,
              height: _cell,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient: selected ? _selection(t) : null,
              ),
              child: MediaQuery.withClampedTextScaling(
                maxScaleFactor: 1.1,
                // The content keeps its natural size; the cell's window is what
                // changes. Nudging it down by half a label as the bar folds is
                // what centres the icon again in the button Home becomes.
                child: Transform.translate(
                  offset: Offset(0, 8 * fold),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        icon,
                        size: 22,
                        color: selected
                            ? t.text
                            : t.text.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 3),
                      Opacity(
                        opacity: (1 - fold).clamp(0.0, 1.0),
                        // Scale-down fit: a long label shrinks inside its cell
                        // instead of overflowing the pill.
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            label,
                            maxLines: 1,
                            softWrap: false,
                            overflow: TextOverflow.clip,
                            style: TextStyle(
                              fontSize: 10,
                              height: 1,
                              fontWeight: FontWeight.w600,
                              color: selected
                                  ? t.text
                                  : t.text.withValues(alpha: 0.6),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The round glass Search button. It sits at the right end of the row in both
/// states, so folding the bar costs it nothing but a seat change.
class _SearchButton extends StatelessWidget {
  const _SearchButton({
    required this.shell,
    required this.observer,
    required this.navigatorKey,
    required this.sheen,
  });

  final SidifyShellController shell;
  final SidifyRouteObserver observer;
  final GlobalKey<NavigatorState> navigatorKey;
  final double sheen;

  void _goSearch() {
    if (observer.pushed.value) {
      navigatorKey.currentState?.popUntil((Route<dynamic> r) => r.isFirst);
    }
    if (SidifyDockScroll.barHidden.value) {
      SidifyDockScroll.barHidden.value = false;
    }
    shell.goSearch();
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return GlassBox(
      bar: true,
      radius: 999,
      sheen: sheen,
      padding: const EdgeInsets.all(_glassPad),
      child: GestureDetector(
        onTap: _goSearch,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: _cell,
          height: _cell,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: shell.tab == SidifyTab.search ? _TabPill._selection(t) : null,
          ),
          child: Icon(
            Icons.search_rounded,
            size: 22,
            color: shell.tab == SidifyTab.search
                ? t.text
                : t.text.withValues(alpha: 0.72),
          ),
        ),
      ),
    );
  }
}
