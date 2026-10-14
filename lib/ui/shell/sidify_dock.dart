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
/// player and any sheet/dialog cover it; on a pushed page only the tab bar
/// steps aside (there is no tab bar under a pushed page).
class SidifyRouteObserver extends NavigatorObserver {
  final List<Route<dynamic>> _stack = <Route<dynamic>>[];
  final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);
  final ValueNotifier<bool> pageOnTop = ValueNotifier<bool>(false);

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _stack.add(route);
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
      if (pageOnTop.value) pageOnTop.value = false;
      return;
    }
    final Route<dynamic> top = _stack.last;
    final bool covering = top is PopupRoute ||
        (top is PageRoute<dynamic> &&
            top.settings.name == SidifyRoutes.fullPlayer);
    final bool pushed = _stack.length > 1;
    if (hidden.value != covering) hidden.value = covering;
    if (pageOnTop.value != pushed) pageOnTop.value = pushed;
  }
}

/// The floating chrome, painted above the navigator in `MaterialApp.builder`:
/// the glass pill mini player and the glass pill tab bar — the site's
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
    final SidifyShellController shell =
        context.watch<SidifyShellController>();
    final double safe = MediaQuery.paddingOf(context).bottom;

    return ValueListenableBuilder<bool>(
      valueListenable: observer.hidden,
      builder: (BuildContext context, bool hidden, Widget? _) {
        if (hidden) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: observer.pageOnTop,
          builder: (BuildContext context, bool pageOnTop, Widget? _) {
            final double tabBottom = safe > 0 ? safe + 6 : 10;
            final double miniBottom =
                pageOnTop ? tabBottom : tabBottom + 72;
            return Stack(
              children: <Widget>[
                if (playback.hasTrack)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: miniBottom,
                    child: Align(
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: _MiniPlayer(
                          onOpen: () {
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
                    ),
                  ),
                if (!pageOnTop)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: tabBottom,
                    child: Align(
                      alignment: Alignment.center,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: _TabBar(shell: shell),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// The pill mini player (58px, radius 18): artwork, title/artist, play and
/// next, and a 2px progress hairline along the bottom.
class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final JamService jam = context.watch<JamService>();
    final Song? track = playback.current;
    if (track == null) return const SizedBox.shrink();
    final SidifyTokens t = context.sidify;

    return GlassBox(
      bar: true,
      radius: 18,
      child: SizedBox(
        height: 58,
        child: Stack(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.only(left: 8, right: 6),
              child: Row(
                children: <Widget>[
                  GestureDetector(
                    onTap: onOpen,
                    child: Artwork(
                      url: track.thumbnailUrl,
                      size: 42,
                      radius: 9,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GestureDetector(
                      onTap: onOpen,
                      behavior: HitTestBehavior.opaque,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                              color: t.text,
                            ),
                          ),
                          Row(
                            children: <Widget>[
                              if (jam.isConnected) ...<Widget>[
                                Icon(Icons.people_rounded,
                                    size: 12, color: t.playing),
                                const SizedBox(width: 3),
                                Text(
                                  '${jam.members.length}',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600,
                                    color: t.playing,
                                  ),
                                ),
                                const SizedBox(width: 5),
                              ],
                              Flexible(
                                child: Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: t.text2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  _dockBtn(
                    context,
                    playback.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    24,
                    () => playback.togglePlayPause(),
                    loading: playback.isLoading,
                  ),
                  _dockBtn(
                    context,
                    Icons.skip_next_rounded,
                    22,
                    () => playback.next(),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 0,
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
                        child: Container(
                          decoration: BoxDecoration(
                            color: t.text.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ),
                  );
                },
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
          width: 40,
          height: 40,
          child: loading
              ? Center(
                  child: SizedBox(
                    width: 18,
                    height: 18,
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

/// The floating glass tab bar: five destinations, the selection carried by a
/// soft filled pill behind the icon + label.
class _TabBar extends StatelessWidget {
  const _TabBar({required this.shell});

  final SidifyShellController shell;

  static const List<(SidifyTab, String, IconData)> _tabs =
      <(SidifyTab, String, IconData)>[
    (SidifyTab.home, 'Home', Icons.home_rounded),
    (SidifyTab.explore, 'Explore', Icons.explore_rounded),
    (SidifyTab.search, 'Search', Icons.search_rounded),
    (SidifyTab.library, 'Library', Icons.library_music_rounded),
    (SidifyTab.together, 'Together', Icons.people_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final JamService jam = context.watch<JamService>();
    return GlassBox(
      bar: true,
      radius: 999,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: SizedBox(
        height: 50,
        child: Row(
          children: <Widget>[
            for (final (SidifyTab tab, String label, IconData icon) in _tabs)
              Expanded(
                child: GestureDetector(
                  onTap: () => shell.select(tab),
                  behavior: HitTestBehavior.opaque,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    height: 50,
                    decoration: BoxDecoration(
                      color: shell.tab == tab ? t.fill3 : Colors.transparent,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Stack(
                          clipBehavior: Clip.none,
                          children: <Widget>[
                            Icon(
                              icon,
                              size: 22,
                              color: shell.tab == tab
                                  ? t.text
                                  : t.text.withValues(alpha: 0.6),
                            ),
                            if (tab == SidifyTab.together && jam.isConnected)
                              Positioned(
                                top: -4,
                                right: -8,
                                child: Container(
                                  constraints:
                                      const BoxConstraints(minWidth: 15),
                                  height: 15,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: t.brand,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${jam.members.length}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            height: 1,
                            fontWeight: FontWeight.w600,
                            color: shell.tab == tab
                                ? t.text
                                : t.text.withValues(alpha: 0.6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
