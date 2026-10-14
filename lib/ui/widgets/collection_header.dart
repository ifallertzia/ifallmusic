import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/settings_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../player/player_palette.dart';
import 'sidify_widgets.dart';

/// The top of an album / playlist / artist page (the site's
/// CollectionHeader): the artwork bleeding edge to edge and fading into its
/// own dominant colour, a centred bold title, a small meta line, and round
/// shuffle · Play pill · round action.
class CollectionHeader extends StatefulWidget {
  const CollectionHeader({
    super.key,
    this.artwork = '',
    this.arts,
    this.cover,
    this.eyebrow,
    required this.title,
    this.subtitle,
    this.meta,
    this.onPlay,
    this.onShuffle,
    this.action,
    this.round = false,
  });

  final String artwork;
  final List<String>? arts;
  final Widget? cover;
  final String? eyebrow;
  final String title;
  final String? subtitle;
  final String? meta;
  final VoidCallback? onPlay;
  final VoidCallback? onShuffle;
  final Widget? action;
  final bool round;

  @override
  State<CollectionHeader> createState() => _CollectionHeaderState();
}

class _CollectionHeaderState extends State<CollectionHeader> {
  MeshPalette _palette = MeshPalette.fallback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(CollectionHeader old) {
    super.didUpdateWidget(old);
    if (old.artwork != widget.artwork || old.arts?.first != widget.arts?.first) {
      _load();
    }
  }

  void _load() {
    final String url =
        widget.artwork.isNotEmpty ? widget.artwork : (widget.arts?.first ?? '');
    if (url.isEmpty || widget.cover != null) return;
    MeshPaletteService.extract(url).then((MeshPalette p) {
      if (mounted) setState(() => _palette = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final Color base = widget.cover != null
        ? const Color(0xFF3A0D16)
        : settings.dynamicColor
            ? Color.lerp(_palette.base, Colors.black, 0.15)!
            : context.sidify.raised;
    final List<String>? arts =
        (widget.arts != null && widget.arts!.length >= 4)
            ? widget.arts!.take(4).toList()
            : null;

    final Widget squareArt = widget.cover ??
        (arts != null
            ? GridView.count(
                crossAxisCount: 2,
                physics: const NeverScrollableScrollPhysics(),
                children: <Widget>[
                  for (final String a in arts)
                    Artwork(url: a, radius: 0, fit: BoxFit.cover, width: 200, height: 200),
                ],
              )
            : Artwork(
                url: widget.artwork.isNotEmpty
                    ? widget.artwork
                    : (widget.arts?.first ?? ''),
                radius: 0,
                fit: BoxFit.cover,
                width: 800,
                height: 800,
              ));

    return Column(
      children: <Widget>[
        Stack(
          children: <Widget>[
            // Full-bleed artwork fading into its own colour.
            AspectRatio(
              aspectRatio: widget.round ? 1.35 : 1,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  if (widget.round)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: Artwork(
                          url: widget.artwork,
                          size: 210,
                          radius: 999,
                          round: true,
                        ),
                      ),
                    )
                  else ...<Widget>[
                    squareArt,
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Colors.transparent,
                            base,
                          ],
                          stops: const <double>[0.45, 1],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 4,
              child: SafeArea(
                child: IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),
          ],
        ),
        Container(
          width: double.infinity,
          color: widget.round ? Colors.transparent : base,
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Column(
            children: <Widget>[
              if (widget.eyebrow != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    widget.eyebrow!.toUpperCase(),
                    style: SidifyText.eyebrow(
                      Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              Text(
                widget.title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  height: 1.12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: Colors.white,
                ),
              ),
              if (widget.subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    widget.subtitle!,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              if (widget.meta != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    widget.meta!.toUpperCase(),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.06,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                  ),
                ),
              if (widget.onPlay != null || widget.onShuffle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      if (widget.onShuffle != null)
                        _headerRound(
                          Icons.shuffle_rounded,
                          'Shuffle',
                          widget.onShuffle!,
                        ),
                      if (widget.onShuffle != null && widget.onPlay != null)
                        const SizedBox(width: 12),
                      if (widget.onPlay != null)
                        Material(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(999),
                          child: InkWell(
                            onTap: widget.onPlay,
                            borderRadius: BorderRadius.circular(999),
                            child: Container(
                              height: 44,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 28),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.1),
                                  width: 0.5,
                                ),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Icon(Icons.play_arrow_rounded,
                                      size: 18, color: Colors.white),
                                  SizedBox(width: 6),
                                  Text(
                                    'Play',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      if (widget.action != null) ...<Widget>[
                        const SizedBox(width: 12),
                        widget.action!,
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        // The colour bleeds out into the page.
        Container(
          height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                widget.round ? Colors.transparent : base,
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _headerRound(IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 18, color: Colors.white),
      ),
    );
  }
}

/// Round secondary action beside the Play pill.
class HeaderAction extends StatelessWidget {
  const HeaderAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: active
                ? Colors.white
                : Colors.white.withValues(alpha: 0.14),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 18,
            color: active ? Colors.black : Colors.white,
          ),
        ),
      ),
    );
  }
}
