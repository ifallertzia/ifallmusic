
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../../core/utils/format.dart';
import '../../widgets/quality_badge.dart';
import 'artwork.dart';
import 'song_download_button.dart';

/// Square card used by "Made for you" / "Recommended for you".
class SongCard extends StatelessWidget {
  const SongCard({
    super.key,
    required this.song,
    this.width = 162,
    this.onTap,
    this.subtitle,
  });

  final Song song;
  final double width;
  final VoidCallback? onTap;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final SaxifyAccent accent = context.accent;
    final bool isCurrent = playback.current?.id == song.id;

    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap ?? () => playback.playSong(song),
          borderRadius: BorderRadius.circular(SaxifyTheme.radiusMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Stack(
                children: <Widget>[
                  Artwork(
                    url: song.thumbnailUrl,
                    width: width,
                    height: width * 0.66,
                    radius: SaxifyTheme.radiusMd,
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: _PlayFab(accent: accent, active: isCurrent),
                  ),
                  Positioned(
                    right: 8,
                    top: 8,
                    child: SongDownloadButton(song: song, size: 34, floating: true),
                  ),
                  if (song.duration != null)
                    Positioned(
                      left: 8,
                      bottom: 8,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(7),
                        child: BackdropFilter(
                          filter: GlassBlur.thinFilter,
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                            color: Colors.black.withValues(alpha: 0.55),
                            child: Text(
                              Fmt.duration(song.duration),
                              style: const TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                song.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                  color: isCurrent ? accent.primary : SaxifyColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle ?? song.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: SaxifyColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square, poster-first recommendation card used by the Home grid.
/// Entire card is clickable — no overlay play button. Smaller thumbnail, cleaner look.
class RecommendationSongCard extends StatelessWidget {
  const RecommendationSongCard({
    super.key,
    required this.song,
    required this.onTap,
  });

  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final bool isCurrent = playback.current?.id == song.id;
    final SaxifyAccent accent = context.accent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SaxifyTheme.radiusMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1,
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  Artwork(
                    url: song.thumbnailUrl,
                    width: double.infinity,
                    height: double.infinity,
                    radius: SaxifyTheme.radiusMd,
                  ),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: QualityBadge(quality: song.quality, compact: true),
                  ),
                  // No play button overlay - entire card is clickable
                  if (isCurrent)
                    Positioned(
                      right: 6,
                      bottom: 6,
                      child: Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: accent.gradient,
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: accent.primary.withValues(alpha: 0.5),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                              spreadRadius: -1,
                            ),
                          ],
                        ),
                        child: Icon(
                          Icons.graphic_eq_rounded,
                          size: 10,
                          color: accent.onAccent,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                height: 1.14,
                fontWeight: FontWeight.w600,
                color: isCurrent ? accent.primary : SaxifyColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              song.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 9.5,
                height: 1.1,
                color: SaxifyColors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlayFab extends StatelessWidget {
  const _PlayFab({required this.accent, required this.active});

  final SaxifyAccent accent;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: accent.gradient,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.primary.withValues(alpha: 0.5),
            blurRadius: 16,
            offset: const Offset(0, 5),
            spreadRadius: -3,
          ),
        ],
      ),
      child: Icon(
        active ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
        size: 20,
        color: accent.onAccent,
      ),
    );
  }
}

/// Album sleeve card — the "New releases" shelf.
class AlbumTile extends StatelessWidget {
  const AlbumTile({
    super.key,
    required this.coverUrl,
    required this.title,
    required this.artist,
    required this.onTap,
    this.width = 152,
  });

  final String coverUrl;
  final String title;
  final String artist;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SaxifyTheme.radiusMd),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Artwork(
                url: coverUrl,
                width: width,
                height: width,
                radius: SaxifyTheme.radiusMd,
                fallbackIcon: Icons.album_rounded,
              ),
              const SizedBox(height: 10),
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: SaxifyTheme.appleFont(
                  size: 13.5,
                  weight: FontWeight.w700,
                  color: SaxifyColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5, color: SaxifyColors.textMuted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Artist avatar.
///
/// Shows the real face when one was resolved. When there is no photo it draws
/// the artist's initials on an accent gradient — **never** the app logo, which
/// is what used to make every artist on Home look like the same placeholder.
/// ---------------------------------------------------------------------------
class ArtistAvatar extends StatelessWidget {
  const ArtistAvatar({
    super.key,
    required this.name,
    this.imageUrl = '',
    this.size = 104,
    this.ring = true,
    this.icon,
  });

  final String name;
  final String imageUrl;
  final double size;
  final bool ring;
  final IconData? icon;

  static String _head(String value) {
    if (value.isEmpty) return '';
    return value.substring(0, 1).toUpperCase();
  }

  String get _initials {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return _head(parts.first);
    return _head(parts.first) + _head(parts[1]);
  }

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final Widget inner = imageUrl.isEmpty
        ? DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: <Color>[
                  accent.primary.withValues(alpha: 0.85),
                  accent.secondary.withValues(alpha: 0.65),
                ],
              ),
            ),
            child: Center(
              child: icon != null
                  ? Icon(icon, size: size * 0.32, color: accent.onAccent)
                  : Text(
                      _initials,
                      style: TextStyle(
                        fontSize: size * 0.3,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: accent.onAccent,
                      ),
                    ),
            ),
          )
        : Artwork(
            url: imageUrl,
            size: size,
            radius: size / 2,
            fallbackIcon: icon ?? Icons.person_rounded,
          );

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring ? Border.all(color: Colors.white.withValues(alpha: 0.14), width: 1.4) : null,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.primary.withValues(alpha: 0.18),
            blurRadius: 22,
            spreadRadius: -8,
          ),
        ],
      ),
      child: ClipOval(child: SizedBox(width: size, height: size, child: inner)),
    );
  }
}

/// Circular artist bubble — the "Top artists" rail.
class ArtistBubble extends StatelessWidget {
  const ArtistBubble({
    super.key,
    required this.name,
    required this.imageUrl,
    required this.onTap,
    this.size = 118,
    this.caption = 'Artist',
  });

  final String name;
  final String imageUrl;
  final VoidCallback onTap;
  final double size;
  final String caption;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(SaxifyTheme.radiusMd),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ArtistAvatar(name: name, imageUrl: imageUrl, size: size - 16),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: SaxifyTheme.appleFont(
                    size: 12.5,
                    weight: FontWeight.w600,
                    color: SaxifyColors.textPrimary,
                  ),
                ),
              ),
              Text(
                caption,
                style: const TextStyle(fontSize: 10.5, color: SaxifyColors.textFaint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Mood & genres.
///
/// Spotify-style **solid colour tiles** — every category owns its own deep
/// colour, completely independent from the app theme, exactly like the
/// reference site. Tiles are big, colourful and thumb-friendly on every phone:
/// the label wraps and scales instead of overflowing.
/// ---------------------------------------------------------------------------
class MoodGenreGrid extends StatelessWidget {
  const MoodGenreGrid({
    super.key,
    required this.items,
    required this.onSelected,
    this.horizontalPadding = 20,
    this.tileHeight = 92,
  });

  final List<(String, String)> items;
  final ValueChanged<String> onSelected;
  final double horizontalPadding;
  final double tileHeight;

  /// Deep, saturated pairs (start, end) — one per category, never the theme.
  static const List<(Color, Color)> _palette = <(Color, Color)>[
    (Color(0xFF7C3AED), Color(0xFF4C1D95)), // violet
    (Color(0xFFEC4899), Color(0xFF831843)), // pink
    (Color(0xFF2563EB), Color(0xFF1E3A8A)), // blue
    (Color(0xFF059669), Color(0xFF064E3B)), // emerald
    (Color(0xFFEA580C), Color(0xFF7C2D12)), // orange
    (Color(0xFF0891B2), Color(0xFF164E63)), // cyan
    (Color(0xFFD97706), Color(0xFF78350F)), // amber
    (Color(0xFFDC2626), Color(0xFF7F1D1D)), // red
    (Color(0xFF0D9488), Color(0xFF134E4A)), // teal
    (Color(0xFF9333EA), Color(0xFF581C87)), // purple
    (Color(0xFF4F46E5), Color(0xFF312E81)), // indigo
    (Color(0xFFDB2777), Color(0xFF9D174D)), // magenta-pink
    (Color(0xFF16A34A), Color(0xFF14532D)), // green
    (Color(0xFFC2410C), Color(0xFF9A3412)), // burnt orange
    (Color(0xFF0369A1), Color(0xFF0C4A6E)), // ocean
    (Color(0xFF6D28D9), Color(0xFF3B0764)), // deep violet
    (Color(0xFFB91C1C), Color(0xFF450A0A)), // blood red
    (Color(0xFF15803D), Color(0xFF052E16)), // forest
    (Color(0xFFA21CAF), Color(0xFF4A044E)), // fuchsia
    (Color(0xFF1D4ED8), Color(0xFF172554)), // royal
    (Color(0xFFCA8A04), Color(0xFF713F12)), // gold
    (Color(0xFF0F766E), Color(0xFF042F2E)), // pine
    (Color(0xFFBE123C), Color(0xFF4C0519)), // rose
    (Color(0xFF3F6212), Color(0xFF1A2E05)), // olive
  ];

  static const List<IconData> _icons = <IconData>[
    Icons.movie_creation_outlined,
    Icons.graphic_eq_rounded,
    Icons.album_outlined,
    Icons.headphones_rounded,
    Icons.auto_awesome_rounded,
    Icons.fitness_center_rounded,
    Icons.spa_rounded,
    Icons.nightlight_round,
    Icons.favorite_rounded,
    Icons.self_improvement_rounded,
    Icons.mic_rounded,
    Icons.record_voice_over_rounded,
    Icons.history_rounded,
    Icons.piano_rounded,
    Icons.celebration_rounded,
    Icons.psychology_rounded,
    Icons.directions_car_rounded,
    Icons.music_note_rounded,
    Icons.language_rounded,
    Icons.star_rounded,
    Icons.wb_twilight_rounded,
    Icons.cloud_rounded,
    Icons.bolt_rounded,
    Icons.terrain_rounded,
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 900
            ? 4
            : constraints.maxWidth >= 620
                ? 3
                : 2;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: tileHeight,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (BuildContext context, int index) {
            final (String, String) item = items[index];
            final (Color, Color) colours = _palette[index % _palette.length];
            final BorderRadius radius = BorderRadius.circular(SaxifyTheme.radiusMd);
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(item.$2),
                borderRadius: radius,
                child: Ink(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[colours.$1, colours.$2],
                    ),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: colours.$1.withValues(alpha: 0.35),
                        blurRadius: 20,
                        spreadRadius: -10,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: <Widget>[
                      Positioned(
                        right: -14,
                        bottom: -14,
                        child: Icon(
                          _icons[index % _icons.length],
                          size: tileHeight * 0.72,
                          color: Colors.black.withValues(alpha: 0.22),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            Icon(
                              _icons[index % _icons.length],
                              size: 20,
                              color: Colors.white.withValues(alpha: 0.9),
                            ),
                            Text(
                              item.$1,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.1,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                                color: Colors.white,
                                shadows: <Shadow>[
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    blurRadius: 8,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Compact colourful chip used in secondary shelves.
class MoodChip extends StatelessWidget {
  const MoodChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.color,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final Color base = color ?? accent.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(SaxifyTheme.radiusXl),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(SaxifyTheme.radiusXl),
            gradient: LinearGradient(
              colors: <Color>[base.withValues(alpha: 0.9), base.withValues(alpha: 0.55)],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 15, color: Colors.white),
                  const SizedBox(width: 7),
                ],
                Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal rail wrapper with the page's standard padding.
class HorizontalRail extends StatelessWidget {
  const HorizontalRail({
    super.key,
    required this.itemCount,
    required this.builder,
    this.height = 200,
    this.spacing = 14,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final int itemCount;
  final Widget Function(BuildContext, int) builder;
  final double height;
  final double spacing;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: padding,
        itemCount: itemCount,
        separatorBuilder: (BuildContext c, int i) => SizedBox(width: spacing),
        itemBuilder: builder,
      ),
    );
  }
}
