import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/artwork_cache.dart';
import '../../core/services/native_bridge.dart';
import '../../core/services/playback_error_reporter.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/recommendation_service.dart';
import '../../core/theme/ifall_ui.dart';
import '../../core/theme/theme_controller.dart';
import '../home/home_page.dart';
import '../library/library_page.dart';
import '../player/player_palette.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';
import '../settings/update_dialog.dart';
import 'shell_controller.dart';

/// Space the floating bars occupy at the bottom of every page.
///
/// Pages pad their scrollables with this so the last row is never hidden behind
/// the tab bar or the mini player.
class IfallInsets {
  const IfallInsets._();

  /// The floating tab bar, including its own side padding.
  static const double tabBar = 74;

  /// The mini player docked above the tab bar.
  static const double miniPlayer = 72;

  /// Everything that can be docked at once.
  static const double bottom = tabBar + miniPlayer + 12;
}

/// The app shell.
///
/// Four sections sit on true black behind a floating, frosted tab bar whose
/// selection is a **sliding glass pill** — tap a tab or drag the pill sideways.
/// Scrolling a page down shrinks the bar to icons; scrolling back up brings the
/// labels back.
///
/// The mini player is painted above the navigator (see `MiniPlayerLayer`), so
/// it stays docked on every pushed page too.
class IfallShell extends StatefulWidget {
  const IfallShell({super.key});

  @override
  State<IfallShell> createState() => _IfallShellState();
}

class _IfallShellState extends State<IfallShell> {
  late final ShellController _shell = context.read<ShellController>();
  late final PlaybackService _playback = context.read<PlaybackService>();
  late final RecommendationService _recommendations =
      context.read<RecommendationService>();

  String? _shownNotice;
  String? _shownReport;
  bool _dbToastShown = false;

  /// The bars shrink when a page is scrolled down and STAY compact while the
  /// listener remains down the page. The slightest upward scroll brings them
  /// back. Idle keeps whatever state we are in instead of popping back.
  bool _navCompact = false;

  bool _onScroll(UserScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    final ScrollDirection direction = notification.direction;
    if (direction == ScrollDirection.idle) return false;
    final bool compact = direction == ScrollDirection.reverse;
    if (compact == _navCompact) return false;
    if (!mounted) return false;
    _shell.navCompact.value = compact;
    setState(() => _navCompact = compact);
    return false;
  }

  @override
  void initState() {
    super.initState();
    _shell.addListener(_onShellChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<PlaybackService>().addListener(_onPlaybackChanged);
      context.read<RecommendationService>().addListener(_onRecommendations);
      _onRecommendations();
    });

    // Quietly check GitHub Releases once the UI is up. Only shows a dialog when
    // a newer version actually exists.
    Future<void>.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      checkAndPromptUpdate(context, silent: true);
    });
  }

  void _onShellChanged() {
    if (mounted) setState(() {});
  }

  /// Surfaces playback notices ("skipped to something similar") once each.
  void _onPlaybackChanged() {
    if (!mounted) return;
    final PlaybackService playback = context.read<PlaybackService>();
    final String? notice = playback.notice;
    if (notice == null) {
      _shownNotice = null;
      return;
    }
    final PlaybackErrorReport? report =
        notice.startsWith('Failed') ? playback.lastError : null;
    if (notice == _shownNotice && report?.id == _shownReport) return;
    _shownNotice = notice;
    _shownReport = report?.id;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(notice),
          duration: const Duration(seconds: 10),
          behavior: SnackBarBehavior.floating,
          action: SnackBarAction(
            label: report == null ? 'DISMISS' : 'MAIL ERROR',
            onPressed: report == null
                ? playback.dismissNotice
                : () => _mailReport(report),
          ),
        ),
      );
  }

  Future<void> _mailReport(PlaybackErrorReport report) async {
    final bool opened = await PlaybackErrorReporter.compose(report);
    if (!opened && mounted) {
      try {
        await Clipboard.setData(ClipboardData(text: report.body));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No email app available. Diagnostic report copied — paste it in an email to ifallertzia.',
            ),
          ),
        );
      } catch (_) {
        // Clipboard access can be denied; the message above is best-effort.
      }
    }
  }

  void _onRecommendations() {
    if (!mounted || _dbToastShown) return;
    if (!context.read<RecommendationService>().store.recovered) return;
    _dbToastShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Local cache was rebuilt. Your library is untouched.'),
      ),
    );
  }

  @override
  void dispose() {
    _shell.removeListener(_onShellChanged);
    _playback.removeListener(_onPlaybackChanged);
    _recommendations.removeListener(_onRecommendations);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? result) {
        if (didPop) return;
        if (!_shell.back()) NativeBridge.backgroundApp();
      },
      child: Scaffold(
        backgroundColor: IfallPalette.of(context).background,
        extendBody: true,
        body: NotificationListener<UserScrollNotification>(
          onNotification: _onScroll,
          child: Stack(
            children: <Widget>[
              IndexedStack(
                index: _shell.tab.index,
                children: const <Widget>[
                  HomePage(),
                  SearchPage(),
                  LibraryPage(),
                  SettingsPage(),
                ],
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const _NextArtworkPrecache(),
                    IfallTabBar(
                      index: _shell.tab.index,
                      compact: _navCompact,
                      onSelect: (int i) => _shell.select(SaxifyTab.values[i]),
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

/// The floating, frosted tab bar with its sliding glass selection pill.
class IfallTabBar extends StatefulWidget {
  const IfallTabBar({
    super.key,
    required this.index,
    required this.onSelect,
    this.compact = false,
  });

  final int index;
  final ValueChanged<int> onSelect;
  final bool compact;

  @override
  State<IfallTabBar> createState() => _IfallTabBarState();
}

class _IfallTabBarState extends State<IfallTabBar> {
  static const List<(IconData, IconData, String)> _items =
      <(IconData, IconData, String)>[
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.search_rounded, Icons.search_rounded, 'Search'),
    (Icons.library_music_outlined, Icons.library_music_rounded, 'Library'),
    (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
  ];

  double _drag = 0;
  bool _dragging = false;
  double _slotWidth = 0;

  void _onDragStart(DragStartDetails details) => setState(() => _dragging = true);

  void _onDragUpdate(DragUpdateDetails details) {
    if (_slotWidth <= 0) return;
    final double max = (_items.length - 1 - widget.index) * _slotWidth;
    final double min = -widget.index * _slotWidth;
    setState(() => _drag = (_drag + details.delta.dx).clamp(min, max));
  }

  void _onDragEnd(DragEndDetails details) {
    _dragging = false;
    if (_slotWidth > 0) {
      final int moved = (_drag / _slotWidth).round();
      final int target = (widget.index + moved).clamp(0, _items.length - 1);
      if (target != widget.index) widget.onSelect(target);
    }
    setState(() => _drag = 0);
  }

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final bool glass = context.watch<ThemeController>().liquidGlass;
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    final bool compact = widget.compact;

    final double fullWidth =
        math.max(0.0, math.min(MediaQuery.sizeOf(context).width - 24, IfallUI.maxBarWidth));
    final double barWidth = compact ? math.min(fullWidth, 232.0) : fullWidth;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        bottomInset > 0 ? bottomInset * 0.5 + 6 : 10,
      ),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: barWidth,
        height: compact ? 48 : 66,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.isDark
              ? const Color(0xF20D0D0F)
              : const Color(0xF7FFFFFF),
          borderRadius: BorderRadius.circular(IfallUI.rXl),
          border: Border.all(color: c.outline.withValues(alpha: 0.8)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: c.isDark ? 0.6 : 0.12),
              blurRadius: 30,
              spreadRadius: -12,
              offset: const Offset(0, 14),
            ),
          ],
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: glass ? 26 : 0,
            sigmaY: glass ? 26 : 0,
          ),
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double slot = constraints.maxWidth / _items.length;
              _slotWidth = slot;
              final double pillWidth = slot * 0.86;
              final double left =
                  widget.index * slot + (slot - pillWidth) / 2 + _drag;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                child: SizedBox.expand(
                  child: Stack(
                    children: <Widget>[
                      AnimatedPositioned(
                        duration: _dragging
                            ? Duration.zero
                            : const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        left: left,
                        top: 0,
                        bottom: 0,
                        width: pillWidth,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(IfallUI.rLg),
                            gradient: LinearGradient(
                              colors: <Color>[
                                c.accent.withValues(alpha: 0.32),
                                c.accent.withValues(alpha: 0.14),
                              ],
                            ),
                            border: Border.all(
                              color: c.accent.withValues(alpha: 0.55),
                            ),
                          ),
                        ),
                      ),
                      Row(
                        children: <Widget>[
                          for (int i = 0; i < _items.length; i++)
                            Expanded(
                              child: _TabItem(
                                outlined: _items[i].$1,
                                filled: _items[i].$2,
                                label: _items[i].$3,
                                selected: widget.index == i,
                                compact: compact,
                                onTap: () => widget.onSelect(i),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({
    required this.outlined,
    required this.filled,
    required this.label,
    required this.selected,
    required this.compact,
    required this.onTap,
  });

  final IconData outlined;
  final IconData filled;
  final String label;
  final bool selected;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(IfallUI.rLg),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              selected ? filled : outlined,
              size: compact ? 22 : 23,
              color: selected ? c.onSurface : c.onSurfaceVariant,
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: SizedBox(
                height: compact ? 0 : 15,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: IfallText.label(
                      selected ? c.onSurface : c.onSurfaceVariant,
                    ),
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

/// Warms the next sleeve about 5 seconds before the current track ends.
class _NextArtworkPrecache extends StatefulWidget {
  const _NextArtworkPrecache();

  @override
  State<_NextArtworkPrecache> createState() => _NextArtworkPrecacheState();
}

class _NextArtworkPrecacheState extends State<_NextArtworkPrecache> {
  String? _warmed;

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    return StreamBuilder<Duration>(
      stream: playback.positionStream,
      builder: (BuildContext context, AsyncSnapshot<Duration> snapshot) {
        final Song? next = playback.nextUp;
        final Duration left =
            playback.duration - (snapshot.data ?? Duration.zero);
        if (next != null &&
            left > Duration.zero &&
            left <= const Duration(seconds: 5) &&
            _warmed != next.id) {
          _warmed = next.id;
          ArtworkCache.precache(context, next.thumbnailUrl);
          // The player's backdrop belongs to the sleeve: extract the next
          // track's palette now so it switches the moment the song does.
          PlayerPaletteService.warm(next.thumbnailUrl);
        }
        return const SizedBox.shrink();
      },
    );
  }
}
