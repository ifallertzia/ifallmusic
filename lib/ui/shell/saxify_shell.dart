import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/artwork_cache.dart';
import '../../core/services/native_bridge.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/playback_error_reporter.dart';
import '../../core/services/recommendation_service.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../home/home_page.dart';
import '../library/library_page.dart';
import '../search/search_page.dart';
import '../settings/settings_page.dart';
import '../settings/update_dialog.dart';
import 'mini_player.dart';
import 'shell_controller.dart';

/// The app shell: a frosted, floating tab bar over pure black, the persistent
/// mini player and the four sections.
class SaxifyShell extends StatefulWidget {
  const SaxifyShell({super.key});

  @override
  State<SaxifyShell> createState() => _SaxifyShellState();
}

class _SaxifyShellState extends State<SaxifyShell> {
  late final ShellController _shell = context.read<ShellController>();
  String? _shownNotice;
  String? _shownReport;
  late final PlaybackService _playback = context.read<PlaybackService>();
  late final RecommendationService _recommendations = context
      .read<RecommendationService>();
  bool _dbToastShown = false;

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
    final report = notice.startsWith('Failed') ? playback.lastError : null;
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
    final opened = await PlaybackErrorReporter.compose(report);
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
      } catch (_) {}
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
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (!_shell.back()) NativeBridge.backgroundApp();
      },
      child: Scaffold(
        backgroundColor: SaxifyColors.background,
        extendBody: true,
        body: Stack(
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
            // Now playing + navigation float above the content as one glass unit.
            Align(
              alignment: Alignment.bottomCenter,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  const _NextArtworkPrecache(),
                  const MiniPlayer(),
                  _GlassNavBar(
                    index: _shell.tab.index,
                    onSelect: (int i) => _shell.select(SaxifyTab.values[i]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Floating, frosted tab bar — Apple style: rounded, translucent, blurred.
class _GlassNavBar extends StatelessWidget {
  const _GlassNavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  static const List<(IconData, IconData, String)> _items =
      <(IconData, IconData, String)>[
        (Icons.home_outlined, Icons.home_rounded, 'Home'),
        (Icons.search_outlined, Icons.search_rounded, 'Search'),
        (Icons.library_music_outlined, Icons.library_music_rounded, 'Library'),
        (Icons.settings_outlined, Icons.settings_rounded, 'Settings'),
      ];

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final double bottomInset = MediaQuery.paddingOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        0,
        12,
        bottomInset > 0 ? bottomInset * 0.5 + 6 : 10,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SaxifyTheme.radiusLg),
        child: BackdropFilter(
          filter: GlassBlur.thickFilter,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFF07070A).withValues(alpha: 0.72),
              borderRadius: BorderRadius.circular(SaxifyTheme.radiusLg),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.6),
                  blurRadius: 30,
                  spreadRadius: -12,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              child: Row(
                children: <Widget>[
                  for (int i = 0; i < _items.length; i++)
                    Expanded(
                      child: _NavItem(
                        outlined: _items[i].$1,
                        filled: _items[i].$2,
                        label: _items[i].$3,
                        selected: index == i,
                        accent: accent,
                        onTap: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.outlined,
    required this.filled,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final IconData outlined;
  final IconData filled;
  final String label;
  final bool selected;
  final SaxifyAccent accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SaxifyTheme.radiusMd),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SaxifyTheme.radiusMd),
            color: selected
                ? accent.primary.withValues(alpha: 0.16)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? accent.primary.withValues(alpha: 0.35)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                selected ? filled : outlined,
                size: 23,
                color: selected ? accent.primary : SaxifyColors.textMuted,
              ),
              const SizedBox(height: 3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? accent.primary : SaxifyColors.textMuted,
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
      builder: (BuildContext context, AsyncSnapshot<Duration> snap) {
        final Song? next = playback.nextUp;
        final Duration left = playback.duration - (snap.data ?? Duration.zero);
        if (next != null &&
            left > Duration.zero &&
            left <= const Duration(seconds: 5) &&
            _warmed != next.id) {
          _warmed = next.id;
          ArtworkCache.precache(context, next.thumbnailUrl);
        }
        return const SizedBox.shrink();
      },
    );
  }
}
