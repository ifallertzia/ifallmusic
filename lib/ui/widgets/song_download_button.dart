import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/music_download_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../downloads/storage_permission.dart';

/// Per-song download control with live progress. Tapping a completed download
/// starts its local copy; tapping an active download cancels it.
class SongDownloadButton extends StatelessWidget {
  const SongDownloadButton({
    super.key,
    required this.song,
    this.size = 40,
    this.floating = false,
  });

  final Song song;
  final double size;
  final bool floating;

  @override
  Widget build(BuildContext context) {
    final MusicDownloadService downloads = context.watch<MusicDownloadService>();
    final MusicDownloadJob? job = downloads.jobFor(song.id);
    final bool isRunning = job?.phase == MusicDownloadPhase.running;
    final bool isQueued = job?.phase == MusicDownloadPhase.idle;
    final bool isDone = job?.phase == MusicDownloadPhase.done &&
        job?.offlinePath != null;
    final SaxifyAccent accent = context.accent;

    Widget icon;
    if (isRunning) {
      icon = SizedBox(
        width: size * 0.72,
        height: size * 0.72,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            CircularProgressIndicator(
              value: job!.fraction <= 0 ? null : job.fraction,
              strokeWidth: 2.5,
              color: accent.primary,
              backgroundColor: accent.primary.withValues(alpha: 0.18),
            ),
            Text(
              job.fraction <= 0 ? '…' : '${(job.fraction * 100).round()}%',
              style: TextStyle(
                fontSize: size * 0.17,
                fontWeight: FontWeight.w800,
                color: floating ? Colors.white : accent.primary,
              ),
            ),
          ],
        ),
      );
    } else if (isDone) {
      icon = Icon(Icons.offline_pin_rounded, size: size * 0.57, color: accent.primary);
    } else if (isQueued) {
      icon = Icon(Icons.schedule_rounded, size: size * 0.52, color: accent.primary);
    } else {
      icon = Icon(
        job?.phase == MusicDownloadPhase.failed
            ? Icons.downloading_rounded
            : Icons.download_rounded,
        size: size * 0.52,
        color: job?.phase == MusicDownloadPhase.failed
            ? SaxifyColors.danger
            : (floating ? Colors.white : SaxifyColors.textSecondary),
      );
    }

    return IconButton(
      tooltip: isRunning
          ? 'Cancel download'
          : isDone
              ? 'Play offline'
              : isQueued
                  ? 'Waiting to download'
                  : 'Download song',
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: BoxConstraints.tightFor(width: size, height: size),
      style: IconButton.styleFrom(
        backgroundColor: floating ? Colors.black.withValues(alpha: 0.72) : null,
        foregroundColor: floating ? Colors.white : accent.primary,
        shape: const CircleBorder(),
      ),
      onPressed: () => _activate(context, downloads, job),
      icon: icon,
    );
  }

  Future<void> _activate(
    BuildContext context,
    MusicDownloadService downloads,
    MusicDownloadJob? job,
  ) async {
    if (job?.phase == MusicDownloadPhase.running ||
        job?.phase == MusicDownloadPhase.idle) {
      downloads.cancel(job);
      return;
    }

    final PlaybackService playback = context.read<PlaybackService>();
    if (job?.phase == MusicDownloadPhase.done && job?.offlinePath != null) {
      await playback.playOfflineSong(song, job!.offlinePath!);
      return;
    }

    final bool allowed = await StoragePermission.ensure(context);
    if (!allowed || !context.mounted) return;
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Song download started')));

    final MusicDownloadJob result = await downloads.enqueue(song, playback);
    if (!context.mounted) return;
    final String message = switch (result.phase) {
      MusicDownloadPhase.done => 'Saved for offline listening',
      MusicDownloadPhase.failed => result.error ?? 'Could not download this song',
      MusicDownloadPhase.cancelled => 'Download cancelled',
      _ => 'Downloading · progress is shown on this button',
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
