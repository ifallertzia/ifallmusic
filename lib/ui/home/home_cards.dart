import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/branding.dart';
import '../../core/services/home_catalog.dart';
import '../../core/services/library_service.dart';
import '../../core/services/music_download_service.dart';
import '../../core/services/listen_together_service.dart';
import '../../core/theme/ifall_ui.dart';
import '../../core/theme/theme_controller.dart';
import '../../data/labels.dart';
import '../brands/brands_page.dart';
import '../rooms/listen_together_page.dart';
import '../shell/shell_controller.dart';
import '../../widgets/brand_logo.dart';

/// The frosted Home top bar: the mascot wordmark on the left, the listening
/// shortcuts on the right. It only paints its blur once content has scrolled
/// under it, so a fresh page is pure black.
class HomeTopBar extends StatelessWidget {
  const HomeTopBar({super.key, this.scrolled = false});

  final bool scrolled;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final bool glass = context.watch<ThemeController>().liquidGlass;
    final LibraryService library = context.watch<LibraryService>();
    final MusicDownloadService downloads = context.watch<MusicDownloadService>();
    final int activeDownloads = downloads.jobs
        .where(
          (MusicDownloadJob job) =>
              job.phase == MusicDownloadPhase.running ||
              job.phase == MusicDownloadPhase.idle,
        )
        .length;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: scrolled && glass ? 22 : 0,
          sigmaY: scrolled && glass ? 22 : 0,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: scrolled
                ? (c.isDark
                    ? Colors.black.withValues(alpha: 0.66)
                    : Colors.white.withValues(alpha: 0.80))
                : Colors.transparent,
            border: scrolled
                ? Border(
                    bottom: BorderSide(
                      color: c.outline.withValues(alpha: 0.6),
                      width: 0.5,
                    ),
                  )
                : null,
          ),
          child: SafeArea(
            bottom: false,
            child: SizedBox(
              height: 56,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: <Widget>[
                    Image.asset(
                      'assets/images/ifall_logo.png',
                      width: 30,
                      height: 30,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        IfallBranding.appName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: IfallText.title(c.onSurface),
                      ),
                    ),
                    _BarButton(
                      icon: Icons.favorite_border_rounded,
                      badge: library.likedSongs.length,
                      tooltip: 'Liked songs',
                      onTap: () => context.read<ShellController>().goLiked(),
                    ),
                    _BarButton(
                      icon: Icons.download_rounded,
                      badge: activeDownloads,
                      active: activeDownloads > 0,
                      tooltip: 'Downloads',
                      onTap: () => context.read<ShellController>().goDownloads(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BarButton extends StatelessWidget {
  const _BarButton({
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.badge = 0,
    this.active = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  final int badge;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: IconButton(
        onPressed: onTap,
        tooltip: tooltip,
        iconSize: 21,
        visualDensity: VisualDensity.compact,
        icon: Badge(
          isLabelVisible: badge > 0,
          label: Text('$badge'),
          backgroundColor: active ? c.accent : c.onSurfaceVariant,
          textColor: active
              ? (ThemeData.estimateBrightnessForColor(c.accent) ==
                      Brightness.dark
                  ? Colors.white
                  : Colors.black)
              : c.surface,
          child: Icon(icon, color: active ? c.accent : c.onSurface),
        ),
      ),
    );
  }
}

/// **Listen Together**, front and centre on Home.
///
/// One card: start a room, or jump straight back into the one that is live.
class HomeListenTogetherCard extends StatelessWidget {
  const HomeListenTogetherCard({super.key});

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final JamService jam = context.watch<JamService>();

    if (!jam.isConnected) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: IfallGlass(
          radius: IfallUI.rLg,
          blur: 0,
          onTap: () => openListenTogether(context),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.accent.withValues(alpha: 0.16),
                ),
                child: Icon(
                  Icons.surround_sound_rounded,
                  size: 20,
                  color: c.accent,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Listen Together',
                      style: IfallText.body(c.onSurface)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Open a room and play the same song, in sync, with friends.',
                      style: IfallText.caption(c.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: c.onSurfaceVariant),
            ],
          ),
        ),
      );
    }

    final int listeners = jam.members.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: IfallGlass(
        radius: IfallUI.rLg,
        blur: 0,
        color: c.accent.withValues(alpha: 0.12),
        border: c.accent.withValues(alpha: 0.45),
        onTap: () => openListenTogether(context),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            _LivePulse(color: c.accent),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    'In a room · ${jam.code ?? ''}',
                    style: IfallText.body(c.onSurface)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    jam.currentTrack != null
                        ? '${jam.currentTrack!.title} · $listeners listening'
                        : '$listeners listening',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: IfallText.caption(c.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, color: c.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _LivePulse extends StatefulWidget {
  const _LivePulse({required this.color});

  final Color color;

  @override
  State<_LivePulse> createState() => _LivePulseState();
}

class _LivePulseState extends State<_LivePulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? child) {
          return Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color.withValues(alpha: 0.18 + 0.12 * _c.value),
            ),
            child: Icon(
              Icons.surround_sound_rounded,
              size: 20,
              color: widget.color,
            ),
          );
        },
      ),
    );
  }
}

/// One-tap mood & genre stations, painted as coloured tiles.
class HomeMoodGrid extends StatelessWidget {
  const HomeMoodGrid({super.key});

  @override
  Widget build(BuildContext context) {
    final ShellController shell = context.read<ShellController>();
    final IfallPalette c = IfallPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: <Widget>[
          for (final (String label, String query) in HomeCatalog.moodGenres)
            _MoodTile(
              label: label,
              onTap: () => shell.goStation(label, query),
              accent: c.accent,
            ),
        ],
      ),
    );
  }
}

class _MoodTile extends StatelessWidget {
  const _MoodTile({
    required this.label,
    required this.onTap,
    required this.accent,
  });

  final String label;
  final VoidCallback onTap;
  final Color accent;

  /// A stable hue per label, so a tile keeps its colour between rebuilds.
  static const List<Color> _tones = <Color>[
    Color(0xFF7C3AED),
    Color(0xFFEC4899),
    Color(0xFF2563EB),
    Color(0xFF059669),
    Color(0xFFEA580C),
    Color(0xFF0891B2),
    Color(0xFFDB2777),
    Color(0xFF65A30D),
  ];

  @override
  Widget build(BuildContext context) {
    final int index = label.hashCode.abs() % _tones.length;
    final Color tone = _tones[index];
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(IfallUI.rMd),
        child: Container(
          width: (MediaQuery.sizeOf(context).width - 44) / 2,
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(IfallUI.rMd),
            gradient: LinearGradient(
              colors: <Color>[
                tone.withValues(alpha: 0.85),
                tone.withValues(alpha: 0.45),
              ],
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IfallText.body(Colors.white)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              const Icon(Icons.play_arrow_rounded, size: 18, color: Colors.white),
            ],
          ),
        ),
      ),
    );
  }
}

/// The official label channels.
class HomeBrandRow extends StatelessWidget {
  const HomeBrandRow({super.key});

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return SizedBox(
      height: 106,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: MusicBrands.all.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) {
          final MusicBrand brand = MusicBrands.all[i];
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(IfallUI.rMd),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (BuildContext c2) => BrandChannelPage(brand: brand),
                ),
              ),
              child: SizedBox(
                width: 104,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    BrandLogo(brand: brand, size: 48),
                    const SizedBox(height: 8),
                    Text(
                      brand.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: IfallText.caption(c.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
