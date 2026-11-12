import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// `0.25x`, `0.5x`, `1.0x`, `1.25x`, `2.0x`.
String formatMovieSpeed(double speed) {
  final String two = speed.toStringAsFixed(2);
  final String text = two.endsWith('0') ? speed.toStringAsFixed(1) : two;
  return '${text}x';
}

/// One selectable line in a player sheet.
class MovieSheetOption {
  const MovieSheetOption({
    required this.id,
    required this.title,
    this.subtitle = '',
    this.selected = false,
    this.icon,
  });

  final String id;
  final String title;
  final String subtitle;
  final bool selected;
  final IconData? icon;
}

/// Everything the "Playback Settings" sheet shows, read fresh from the player
/// each time the sheet rebuilds. Nothing in here is a placeholder: the
/// qualities are the ones the current source really offers and the audio
/// tracks are the ones the playing file really carries.
class MoviePlaybackSettings {
  const MoviePlaybackSettings({
    required this.speed,
    required this.speeds,
    required this.qualities,
    required this.audioTracks,
    this.qualityNote = '',
    this.audioNote = '',
  });

  final double speed;
  final List<double> speeds;
  final List<MovieSheetOption> qualities;
  final List<MovieSheetOption> audioTracks;

  /// Shown under the quality list (or instead of it when it is empty).
  final String qualityNote;

  /// Shown under the audio list (or instead of it when it is empty).
  final String audioNote;

  String get speedLabel =>
      (speed - 1.0).abs() < 0.001 ? 'Normal' : formatMovieSpeed(speed);

  static String _selectedTitle(List<MovieSheetOption> options) {
    for (final MovieSheetOption option in options) {
      if (option.selected) return option.title;
    }
    return options.isEmpty ? 'Not available' : options.first.title;
  }

  String get qualityLabel => _selectedTitle(qualities);
  String get audioLabel => _selectedTitle(audioTracks);
}

/// Opens the player's glass bottom sheet: a large rounded, dark translucent
/// panel that blurs the (dimmed, still playing) video behind it, with a drag
/// indicator and the standard slide-up animation. Drag it down, tap outside
/// it or press back to dismiss.
Future<T?> showMovieGlassSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.38),
    elevation: 0,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (BuildContext sheetContext) {
      return MovieGlassSheet(child: builder(sheetContext));
    },
  );
}

/// The glass panel itself.
class MovieGlassSheet extends StatelessWidget {
  const MovieGlassSheet({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData mq = MediaQuery.of(context);
    final bool landscape = mq.orientation == Orientation.landscape;
    final double maxHeight = mq.size.height * (landscape ? 0.9 : 0.7);
    const BorderRadius radius = BorderRadius.all(Radius.circular(28));

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: ClipRRect(
            borderRadius: radius,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFF0E0E12).withValues(alpha: 0.68),
                  borderRadius: radius,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                  ),
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const SizedBox(height: 10),
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.32),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Flexible(child: child),
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

enum _SettingsView { root, speed, quality, audio }

/// "Playback Settings": three rows — Speed, Quality, Audio — each showing its
/// current value and opening its own list of real options.
class MoviePlaybackSettingsSheet extends StatefulWidget {
  const MoviePlaybackSettingsSheet({
    super.key,
    required this.read,
    required this.onSpeed,
    required this.onQuality,
    required this.onAudio,
    this.refresh,
  });

  /// Reads the current values from the player.
  final MoviePlaybackSettings Function() read;

  /// Fires whenever something the sheet shows may have changed (a track list
  /// arrived, the quality was switched, …).
  final Listenable? refresh;

  final Future<void> Function(double speed) onSpeed;

  /// Switching quality reloads the stream, so the sheet closes first.
  final void Function(String id) onQuality;
  final Future<void> Function(String id) onAudio;

  @override
  State<MoviePlaybackSettingsSheet> createState() =>
      _MoviePlaybackSettingsSheetState();
}

class _MoviePlaybackSettingsSheetState
    extends State<MoviePlaybackSettingsSheet> {
  _SettingsView _view = _SettingsView.root;

  @override
  void initState() {
    super.initState();
    widget.refresh?.addListener(_onRefresh);
  }

  @override
  void didUpdateWidget(covariant MoviePlaybackSettingsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refresh != widget.refresh) {
      oldWidget.refresh?.removeListener(_onRefresh);
      widget.refresh?.addListener(_onRefresh);
    }
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    if (mounted) setState(() {});
  }

  void _open(_SettingsView view) => setState(() => _view = view);

  @override
  Widget build(BuildContext context) {
    final MoviePlaybackSettings data = widget.read();

    final Widget body;
    switch (_view) {
      case _SettingsView.root:
        body = _buildRoot(data);
      case _SettingsView.speed:
        body = _SheetOptionList(
          key: const ValueKey<String>('speed'),
          title: 'Speed',
          onBack: () => _open(_SettingsView.root),
          options: <MovieSheetOption>[
            for (final double speed in data.speeds)
              MovieSheetOption(
                id: speed.toString(),
                title: formatMovieSpeed(speed),
                subtitle: (speed - 1.0).abs() < 0.001 ? 'Normal' : '',
                selected: (speed - data.speed).abs() < 0.001,
              ),
          ],
          onSelected: (MovieSheetOption option) async {
            final double? speed = double.tryParse(option.id);
            if (speed == null) return;
            await widget.onSpeed(speed);
            if (mounted) setState(() {});
          },
        );
      case _SettingsView.quality:
        body = _SheetOptionList(
          key: const ValueKey<String>('quality'),
          title: 'Quality',
          onBack: () => _open(_SettingsView.root),
          options: data.qualities,
          note: data.qualityNote,
          onSelected: (MovieSheetOption option) async {
            if (option.selected) return;
            Navigator.of(context).pop();
            widget.onQuality(option.id);
          },
        );
      case _SettingsView.audio:
        body = _SheetOptionList(
          key: const ValueKey<String>('audio'),
          title: 'Audio',
          onBack: () => _open(_SettingsView.root),
          options: data.audioTracks,
          note: data.audioNote,
          onSelected: (MovieSheetOption option) async {
            await widget.onAudio(option.id);
            if (mounted) setState(() {});
          },
        );
    }

    return PopScope(
      // Back inside a list returns to the three rows before closing the sheet.
      canPop: _view == _SettingsView.root,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && _view != _SettingsView.root) {
          _open(_SettingsView.root);
        }
      },
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (Widget? current, List<Widget> previous) {
            // Only the incoming view takes part in layout: the sheet is sized
            // by what it is showing, never by the view it is leaving.
            return current ?? const SizedBox.shrink();
          },
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.06, 0),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: body,
        ),
      ),
    );
  }

  Widget _buildRoot(MoviePlaybackSettings data) {
    return SingleChildScrollView(
      key: const ValueKey<String>('root'),
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 6, 12, 10),
            child: Text(
              'Playback Settings',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
          ),
          _SettingsRow(
            icon: Icons.speed_rounded,
            label: 'Speed',
            value: data.speedLabel,
            onTap: () => _open(_SettingsView.speed),
          ),
          _SettingsRow(
            icon: Icons.high_quality_outlined,
            label: 'Quality',
            value: data.qualityLabel,
            onTap: () => _open(_SettingsView.quality),
          ),
          _SettingsRow(
            icon: Icons.graphic_eq_rounded,
            label: 'Audio',
            value: data.audioLabel,
            onTap: () => _open(_SettingsView.audio),
          ),
        ],
      ),
    );
  }
}

/// A single-list glass sheet: a title and its options. Used for subtitles
/// (stays open and moves the highlight) and for "Report" (closes with the
/// chosen option).
class MovieOptionsSheet extends StatefulWidget {
  const MovieOptionsSheet({
    super.key,
    required this.title,
    required this.read,
    required this.onSelected,
    this.note,
    this.refresh,
    this.closeOnSelect = false,
    this.showSelection = true,
  });

  final String title;
  final List<MovieSheetOption> Function() read;

  /// Explanatory line under the list; read fresh on every rebuild.
  final String Function()? note;
  final Listenable? refresh;
  final Future<void> Function(MovieSheetOption option) onSelected;

  /// Close the sheet, returning the chosen option's id, instead of staying
  /// open.
  final bool closeOnSelect;

  /// Draw the check mark / highlight on the selected option.
  final bool showSelection;

  @override
  State<MovieOptionsSheet> createState() => _MovieOptionsSheetState();
}

class _MovieOptionsSheetState extends State<MovieOptionsSheet> {
  @override
  void initState() {
    super.initState();
    widget.refresh?.addListener(_onRefresh);
  }

  @override
  void didUpdateWidget(covariant MovieOptionsSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refresh != widget.refresh) {
      oldWidget.refresh?.removeListener(_onRefresh);
      widget.refresh?.addListener(_onRefresh);
    }
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_onRefresh);
    super.dispose();
  }

  void _onRefresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return _SheetOptionList(
      title: widget.title,
      options: widget.read(),
      note: widget.note?.call() ?? '',
      showSelection: widget.showSelection,
      onSelected: (MovieSheetOption option) async {
        if (widget.closeOnSelect) {
          Navigator.of(context).pop(option.id);
          return;
        }
        await widget.onSelected(option);
        if (mounted) setState(() {});
      },
    );
  }
}

/// A row of the settings root: icon, label, current value, right arrow.
class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '$label, $value',
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
          child: Row(
            children: <Widget>[
              Icon(icon, color: Colors.white, size: 23),
              const SizedBox(width: 16),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.white.withValues(alpha: 0.62),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled, scrollable list of options with the selected one highlighted.
class _SheetOptionList extends StatelessWidget {
  const _SheetOptionList({
    super.key,
    required this.title,
    required this.options,
    required this.onSelected,
    this.onBack,
    this.note = '',
    this.showSelection = true,
  });

  final String title;
  final List<MovieSheetOption> options;
  final Future<void> Function(MovieSheetOption option) onSelected;
  final VoidCallback? onBack;
  final String note;
  final bool showSelection;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.fromLTRB(onBack == null ? 22 : 8, 2, 16, 6),
          child: Row(
            children: <Widget>[
              if (onBack != null)
                IconButton(
                  tooltip: 'Back',
                  onPressed: onBack,
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 19,
                  ),
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: onBack == null ? 8 : 0,
                  ),
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
            children: <Widget>[
              for (final MovieSheetOption option in options)
                _OptionRow(
                  option: option,
                  showSelection: showSelection,
                  onTap: () => unawaited(onSelected(option)),
                ),
              if (note.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                  child: Text(
                    note,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.58),
                      fontSize: 12.5,
                      height: 1.35,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  const _OptionRow({
    required this.option,
    required this.onTap,
    required this.showSelection,
  });

  final MovieSheetOption option;
  final VoidCallback onTap;
  final bool showSelection;

  @override
  Widget build(BuildContext context) {
    final bool selected = showSelection && option.selected;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        button: true,
        selected: selected,
        child: Material(
          color: selected
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: <Widget>[
                  if (option.icon != null) ...<Widget>[
                    Icon(option.icon, color: Colors.white, size: 21),
                    const SizedBox(width: 14),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          option.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.86),
                            fontSize: 15,
                            fontWeight:
                                selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        if (option.subtitle.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            option.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.56),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (selected) ...<Widget>[
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
