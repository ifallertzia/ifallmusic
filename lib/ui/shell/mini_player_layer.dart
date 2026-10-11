import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/playback_service.dart';
import 'mini_player.dart';
import 'shell_controller.dart';

/// Watches the root navigator and tells the dock when the full player owns the
/// screen. Every other screen — album, playlist, artist, brand, downloads, on
/// device, settings — keeps the mini player docked at the bottom.
class MiniPlayerRouteObserver extends NavigatorObserver {
  MiniPlayerRouteObserver();

  final List<Route<dynamic>> _stack = <Route<dynamic>>[];

  /// True while something covers the dock (the full player, a sheet, a dialog).
  final ValueNotifier<bool> hidden = ValueNotifier<bool>(false);

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

  @override
  void didStartUserGesture(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _sync();
  }

  void _sync() {
    if (_stack.isEmpty) {
      hidden.value = false;
      return;
    }
    final Route<dynamic> top = _stack.last;
    final bool covering = top is PopupRoute ||
        (top is PageRoute<dynamic> &&
            top.settings.name == ShellRoutes.fullPlayer);
    if (hidden.value != covering) hidden.value = covering;
  }
}

/// The persistent mini player, painted **above the navigator**.
///
/// It used to live inside the shell, which is why it disappeared the moment a
/// page was pushed (a playlist, Downloads, On device, an artist, a brand …) and
/// only came back after pressing Back. Sitting above the navigator — right on
/// top of the tab bar — it is now present on every screen of the app, collapsing
/// to the player and sliding away while the full player is open.
class MiniPlayerLayer extends StatelessWidget {
  const MiniPlayerLayer({
    super.key,
    required this.observer,
    required this.navigatorKey,
  });

  final MiniPlayerRouteObserver observer;

  /// The app's root navigator. This layer is painted *above* it (it lives in
  /// `MaterialApp.builder`), so opening the full player goes through this key
  /// instead of `Navigator.of(context)`.
  final GlobalKey<NavigatorState> navigatorKey;

  static const double _navHeight = 66;
  static const double _navHeightCompact = 46;

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final ShellController shell = context.watch<ShellController>();

    // Nothing playing → nothing docked (and nothing in the way of touches).
    if (!playback.hasTrack) return const SizedBox.shrink();

    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final double navPadding = bottomInset > 0 ? bottomInset * 0.5 + 6 : 10;

    return ValueListenableBuilder<bool>(
      valueListenable: observer.hidden,
      builder: (BuildContext context, bool hidden, Widget? _) =>
          ValueListenableBuilder<bool>(
            valueListenable: shell.navCompact,
            builder: (BuildContext context, bool compact, Widget? _) => Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.only(
                  bottom:
                      navPadding + (compact ? _navHeightCompact : _navHeight),
                ),
                child: IgnorePointer(
                  ignoring: hidden,
                  child: AnimatedSlide(
                    duration: const Duration(milliseconds: 260),
                    curve: Curves.easeOutCubic,
                    offset: hidden ? const Offset(0, 0.55) : Offset.zero,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      opacity: hidden ? 0 : 1,
                      child: AnimatedScale(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        scale: hidden ? 0.94 : 1,
                        child: MiniPlayer(
                          compact: compact,
                          navigator: navigatorKey,
                        ),
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
