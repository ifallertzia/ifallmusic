import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/music_download_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../../core/utils/format.dart';
import '../../widgets/quality_badge.dart';
import 'artwork.dart';
import 'song_download_button.dart';
import 'song_menu.dart';

/// One row in any track list. Matches the site's result rows: square artwork,
/// title, artist, duration, heart, overflow menu.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.onTap,
    this.rank,
    this.subtitle,
    this.dense = false,
    this.showArtwork = true,
    this.showMenu = true,
    this.startRadio = false,
    this.onLongPress,
  });

  final Song song;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// When set, the row is a chart row and shows `#1`, `#2`, …
  final int? rank;
  final String? subtitle;
  final bool dense;
  final bool showArtwork;
  final bool showMenu;
  final bool startRadio;

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final LibraryService library = context.watch<LibraryService>();
    final MusicDownloadService downloads = context
        .watch<MusicDownloadService>();
    final SaxifyAccent accent = context.accent;

    final bool isCurrent = playback.current?.id == song.id;
    final MusicDownloadJob? job = downloads.jobFor(song.id);
    final bool isDownloading = job?.phase == MusicDownloadPhase.running;
    final bool liked = library.isLiked(song.id);

    final String secondLine = <String>[
      subtitle ?? song.artist,
      if (song.album != null) song.album!,
      if (song.duration != null) Fmt.duration(song.duration),
    ].join(' · ');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap ?? () => playback.playSong(song),
        onLongPress:
            onLongPress ??
            (showMenu
                ? () => showSongSheet(context, song, radio: startRadio)
                : null),
        borderRadius: BorderRadius.circular(SaxifyTheme.radiusMd),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: dense ? 10 : 12,
            vertical: dense ? 5 : 7,
          ),
          child: Row(
            children: <Widget>[
              if (rank != null)
                SizedBox(
                  width: 26,
                  child: Text(
                    '#$rank',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: isCurrent
                          ? accent.primary
                          : SaxifyColors.textFaint,
                    ),
                  ),
                ),
              if (showArtwork) ...<Widget>[
                Stack(
                  children: <Widget>[
                    Artwork(
                      url: song.thumbnailUrl,
                      size: dense ? 44 : 52,
                      radius: 8,
                    ),
                    if (isCurrent)
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: 0.55),
                            child: Icon(
                              playback.isPlaying
                                  ? Icons.graphic_eq_rounded
                                  : Icons.pause_rounded,
                              size: 18,
                              color: accent.primary,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: dense ? 13.5 : 14.5,
                        fontWeight: isCurrent
                            ? FontWeight.w700
                            : FontWeight.w600,
                        color: isCurrent
                            ? accent.primary
                            : SaxifyColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (isDownloading)
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.download_rounded,
                            size: 12,
                            color: accent.primary,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              'Downloading ${(job!.fraction * 100).round()}%',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: accent.primary,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      Text(
                        secondLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: SaxifyColors.textMuted,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  QualityBadge(quality: song.quality),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SongDownloadButton(song: song, size: dense ? 36 : 38),
                      IconButton(
                        tooltip: liked ? 'Remove from Liked Songs' : 'Like',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(
                          width: 38,
                          height: 38,
                        ),
                        icon: Icon(
                          liked
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 19,
                          color: liked
                              ? accent.primary
                              : SaxifyColors.textFaint,
                        ),
                        onPressed: () => library.toggleLike(song),
                      ),
                      if (showMenu)
                        IconButton(
                          tooltip: 'More',
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 38,
                            height: 38,
                          ),
                          icon: const Icon(
                            Icons.more_horiz_rounded,
                            size: 20,
                            color: SaxifyColors.textFaint,
                          ),
                          onPressed: () =>
                              showSongSheet(context, song, radio: startRadio),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact row used inside the queue sheet and the mini player's "up next".
class QueueTile extends StatelessWidget {
  const QueueTile({
    super.key,
    required this.song,
    required this.onTap,
    required this.onRemove,
    this.isPlaying = false,
  });

  final Song song;
  final VoidCallback onTap;
  final VoidCallback onRemove;
  final bool isPlaying;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Artwork(url: song.thumbnailUrl, size: 44, radius: 8),
      title: Text(
        song.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 13.5,
          fontWeight: FontWeight.w600,
          color: isPlaying ? accent.primary : SaxifyColors.textPrimary,
        ),
      ),
      subtitle: Text(
        song.artist,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 11.5, color: SaxifyColors.textMuted),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SongDownloadButton(song: song, size: 36),
          if (isPlaying)
            Icon(Icons.graphic_eq_rounded, size: 18, color: accent.primary),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 18,
              color: SaxifyColors.textFaint,
            ),
            onPressed: onRemove,
          ),
        ],
      ),
    );
  }
}
