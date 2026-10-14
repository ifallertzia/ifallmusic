import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/music_download_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../../core/utils/format.dart';
import '../widgets/sidify_widgets.dart';

/// Downloads: songs saved for offline listening, with live progress for the
/// ones still coming down. Tapping a saved song plays it from the device.
class DownloadsPage extends StatelessWidget {
  const DownloadsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final MusicDownloadService downloads =
        context.watch<MusicDownloadService>();
    final PlaybackService playback = context.read<PlaybackService>();
    final SidifyTokens t = context.sidify;
    final List<MusicDownloadJob> saved = downloads.downloaded;
    final List<MusicDownloadJob> active = downloads.jobs
        .where((MusicDownloadJob j) =>
            j.phase == MusicDownloadPhase.running ||
            j.phase == MusicDownloadPhase.idle)
        .toList();
    final List<Song> savedSongs =
        saved.map((MusicDownloadJob j) => j.song).toList();
    final Map<String, String> sources = <String, String>{
      for (final MusicDownloadJob j in saved)
        if (j.offlinePath != null) j.song.id: j.offlinePath!,
    };

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Downloads', style: SidifyText.titleM(t.text)),
        actions: <Widget>[
          if (saved.isNotEmpty)
            TextButton(
              onPressed: () => playback.playOfflineQueue(
                savedSongs,
                sources,
                startIndex: 0,
              ),
              child: Text('Play all', style: TextStyle(color: t.text)),
            ),
        ],
      ),
      body: saved.isEmpty && active.isEmpty
          ? const EmptyState(
              icon: Icons.download_rounded,
              title: 'No downloads yet',
              desc: 'Download a song from its "…" menu and it will be here, '
                  'ready to play offline.',
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 190),
              physics: const BouncingScrollPhysics(),
              children: <Widget>[
                for (final MusicDownloadJob job in active) _activeRow(context, job),
                if (active.isNotEmpty && saved.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                    child: SectionHeader(title: 'On this device'),
                  ),
                for (int i = 0; i < saved.length; i++)
                  _savedRow(context, saved[i], savedSongs, i, sources),
              ],
            ),
    );
  }

  Widget _activeRow(BuildContext context, MusicDownloadJob job) {
    final SidifyTokens t = context.sidify;
    final MusicDownloadService downloads =
        context.read<MusicDownloadService>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          Artwork(url: job.song.thumbnailUrl, size: 52, radius: 6),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  job.song.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: t.text),
                ),
                Text(
                  job.phase == MusicDownloadPhase.idle
                      ? 'Waiting…'
                      : '${(job.fraction * 100).round()}% · ${Fmt.bytes(job.received)}',
                  style: TextStyle(fontSize: 12.5, color: t.text2),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: job.fraction > 0 ? job.fraction : null,
                    minHeight: 3,
                    backgroundColor: t.fill2,
                    color: t.text,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 18, color: t.text2),
            onPressed: () => downloads.cancel(job),
          ),
        ],
      ),
    );
  }

  Widget _savedRow(
    BuildContext context,
    MusicDownloadJob job,
    List<Song> songs,
    int index,
    Map<String, String> sources,
  ) {
    final SidifyTokens t = context.sidify;
    final PlaybackService playback = context.read<PlaybackService>();
    final MusicDownloadService downloads =
        context.read<MusicDownloadService>();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: job.offlinePath == null
            ? null
            : () => playback.playOfflineQueue(songs, sources, startIndex: index),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              Artwork(url: job.song.thumbnailUrl, size: 52, radius: 6),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      job.song.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: t.text),
                    ),
                    Text(
                      '${job.song.artist} · ${Fmt.bytes(job.size)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: t.text2),
                    ),
                  ],
                ),
              ),
              Icon(Icons.download_done_rounded, size: 18, color: t.text2),
              IconButton(
                icon: Icon(Icons.delete_outline_rounded, size: 19, color: t.text2),
                onPressed: () async {
                  final bool? sure = await showDialog<bool>(
                    context: context,
                    builder: (BuildContext d) => AlertDialog(
                      backgroundColor: t.raised,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18)),
                      title: Text('Delete download?',
                          style: SidifyText.title(t.text)),
                      content: Text(
                        '“${job.song.title}” will be removed from this device.',
                        style: TextStyle(color: t.text2),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () => Navigator.of(d).pop(false),
                          child: Text('Keep', style: TextStyle(color: t.text2)),
                        ),
                        TextButton(
                          onPressed: () => Navigator.of(d).pop(true),
                          child: Text('Delete',
                              style: TextStyle(color: t.danger)),
                        ),
                      ],
                    ),
                  );
                  if (sure == true) {
                    await downloads.delete(job, playback: playback);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
