import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/ifall_ui.dart';
import '../../core/utils/format.dart';
import '../widgets/artwork.dart';
import '../../core/models/nerd_stats.dart';

// ------------------------------------------------------------------- queue

/// The up-next sheet: the live queue, draggable and removable.
void showQueueSheet(BuildContext context) {
  showIfallSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => const _QueueSheet(),
  );
}

class _QueueSheet extends StatelessWidget {
  const _QueueSheet();

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final List<Song> queue = playback.queue;
    final int current = playback.currentIndex;

    return IfallSheet(
      title: 'Up next',
      subtitle: '${queue.length} tracks',
      actions: <Widget>[
        TextButton(
          onPressed: queue.isEmpty ? null : playback.clearQueue,
          child: Text(
            'Clear',
            style: IfallText.caption(IfallPalette.of(context).accent)
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
      child: queue.isEmpty
          ? const IfallEmpty(
              icon: Icons.queue_music_rounded,
              message: 'Nothing is queued. Play something and it lands here.',
            )
          : ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: queue.length,
              onReorder: (int from, int to) =>
                  _move(context, from: from, to: to),
              itemBuilder: (BuildContext context, int i) {
                final Song song = queue[i];
                final bool active = i == current;
                return _QueueRow(
                  key: ValueKey<String>('q-${song.id}-$i'),
                  song: song,
                  index: i,
                  active: active,
                  onTap: () => playback.skipToIndex(i),
                  onRemove: () => playback.removeFromQueue(i),
                );
              },
            ),
    );
  }

  /// ReorderableListView reports the index the item *would* land in after the
  /// move, which is one further down when an item travels downwards.
  void _move(BuildContext context, {required int from, required int to}) {
    final PlaybackService playback = context.read<PlaybackService>();
    final List<Song> queue = List<Song>.from(playback.queue);
    if (from < 0 || from >= queue.length) return;
    if (to > from) to -= 1;
    if (to < 0 || to >= queue.length) return;
    final Song song = queue.removeAt(from);
    queue.insert(to, song);
    playback.reorderQueue(queue, keepCurrentIndex: playback.currentIndex);
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    super.key,
    required this.song,
    required this.index,
    required this.active,
    required this.onTap,
    required this.onRemove,
  });

  final Song song;
  final int index;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: ListTile(
        key: ValueKey<String>('row-${song.id}-$index'),
        contentPadding: const EdgeInsets.symmetric(horizontal: 6),
        leading: ReorderableDragStartListener(
          index: index,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Icon(
              Icons.drag_handle_rounded,
              size: 18,
              color: c.onSurfaceVariant,
            ),
          ),
        ),
        title: Text(
          song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: IfallText.body(active ? c.accent : c.onSurface),
        ),
        subtitle: Text(
          song.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: IfallText.caption(c.onSurfaceVariant),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (song.duration != null)
              Text(
                Fmt.duration(song.duration),
                style: IfallText.caption(c.onSurfaceVariant),
              ),
            IconButton(
              onPressed: onRemove,
              icon: const Icon(Icons.close_rounded),
              iconSize: 18,
              color: c.onSurfaceVariant,
            ),
          ],
        ),
        onTap: onTap,
      ),
    );
  }
}

// -------------------------------------------------------------- sleep timer

/// Fixed presets, or "stop after this track".
void showSleepTimerSheet(BuildContext context) {
  showIfallSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => const _SleepTimerSheet(),
  );
}

class _SleepTimerSheet extends StatelessWidget {
  const _SleepTimerSheet();

  static const List<int> presets = <int>[5, 10, 15, 30, 45, 60, 90, 120];

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final SettingsService settings = context.watch<SettingsService>();
    final IfallPalette c = IfallPalette.of(context);
    final Duration? remaining = playback.sleepRemaining;

    return IfallSheet(
      title: 'Sleep timer',
      subtitle: remaining == null
          ? 'Playback pauses when the timer ends'
          : 'Pausing in ${Fmt.clock(remaining)}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (remaining != null) ...<Widget>[
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: playback.cancelSleepTimer,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel sleep timer'),
                style: FilledButton.styleFrom(
                  backgroundColor: c.accent,
                  foregroundColor:
                      ThemeData.estimateBrightnessForColor(c.accent) ==
                              Brightness.dark
                          ? Colors.white
                          : Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(IfallUI.rPill),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final int minutes in presets)
                IfallChip(
                  label: '$minutes min',
                  selected: remaining != null &&
                      remaining.inMinutes <= minutes &&
                      remaining.inMinutes > minutes - 2,
                  onTap: () {
                    settings.setSleepMinutes(minutes);
                    settings.setSleepEndOfTrack(false);
                    playback.startSleepTimer(Duration(minutes: minutes));
                    Navigator.of(context).pop();
                  },
                ),
            ],
          ),
          const SizedBox(height: 18),
          IfallSwitchRow(
            icon: Icons.skip_next_rounded,
            title: 'Stop after this track',
            subtitle: 'Instead of counting down',
            value: settings.sleepEndOfTrack,
            onChanged: (bool v) async {
              await settings.setSleepEndOfTrack(v);
              if (v) {
                playback.startSleepTimer(
                  const Duration(hours: 12),
                  endOfTrack: true,
                );
              } else {
                playback.cancelSleepTimer();
              }
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------- stats for nerds

/// Codec, container, bitrate and everything else the engine is doing.
void showNerdStatsSheet(BuildContext context) {
  showIfallSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => const _NerdStatsSheet(),
  );
}

class _NerdStatsSheet extends StatelessWidget {
  const _NerdStatsSheet();

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final IfallPalette c = IfallPalette.of(context);
    final NerdStats stats = playback.nerdStats;

    return IfallSheet(
      title: 'Stats for nerds',
      subtitle: stats.title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _Stat('Video ID', stats.videoId),
          _Stat('Source', stats.source),
          _Stat('Container', stats.bufferLine),
          _Stat('Format', stats.formatLine),
          _Stat('Progress', stats.progressLine),
          _Stat('Resolver', stats.resolver),
          _Stat('Speed', '${stats.speed}x'),
          _Stat('Volume', '${(stats.volume * 100).round()}%'),
          _Stat('Normalized', stats.normalized ? 'On' : 'Off'),
          _Stat(
            'Crossfade',
            stats.crossfadeSeconds == 0
                ? 'Off'
                : '${stats.crossfadeSeconds}s',
          ),
          _Stat('Automix', stats.automix ? 'On' : 'Off'),
          _Stat('Skip silence', stats.skipSilence ? 'On' : 'Off'),
          _Stat('Platform', stats.platformLine),
          if (stats.sessionId != null)
            _Stat('Audio session', '${stats.sessionId}'),
          const SizedBox(height: 10),
          Text(
            'Values are read back from the player and the resolver, so a track '
            'that fell over to the legacy resolver says so here.',
            style: IfallText.caption(c.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 120,
            child: Text(label, style: IfallText.caption(c.onSurfaceVariant)),
          ),
          Expanded(
            child: Text(
              value,
              style: IfallText.body(c.onSurface)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------- sound

/// Volume, speed and the quick-jump into the equalizer.
void showSoundSheet(BuildContext context) {
  showIfallSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => const _SoundSheet(),
  );
}

class _SoundSheet extends StatelessWidget {
  const _SoundSheet();

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final SettingsService settings = context.watch<SettingsService>();
    final IfallPalette c = IfallPalette.of(context);

    return IfallSheet(
      title: 'Sound',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IfallSliderRow(
            icon: Icons.volume_up_rounded,
            title: 'Volume',
            value: playback.volume,
            min: 0,
            max: 1,
            format: (double v) => '${(v * 100).round()}%',
            onChanged: playback.setVolume,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Text(
              'Speed',
              style: IfallText.body(c.onSurface),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: IfallSegmented<double>(
              value: settings.playbackSpeed,
              options: const <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
              labelBuilder: (double v) => v == 1.0 ? '1x' : '${v}x',
              onChanged: playback.setSpeed,
            ),
          ),
          IfallSliderRow(
            icon: Icons.compare_arrows_rounded,
            title: 'Crossfade',
            value: settings.crossfadeSeconds.toDouble(),
            min: 0,
            max: 12,
            divisions: 12,
            format: (double v) => v == 0 ? 'Off' : '${v.round()}s',
            onChanged: (double v) => playback.setCrossfadeSeconds(v.round()),
          ),
          IfallSwitchRow(
            icon: Icons.volume_down_rounded,
            title: 'Normalize volume',
            value: settings.normalizeVolume,
            onChanged: playback.setNormalizeVolume,
          ),
          IfallSwitchRow(
            icon: Icons.content_cut_rounded,
            title: 'Skip silence',
            value: settings.skipSilence,
            onChanged: playback.setSkipSilence,
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- track details

/// The "about this track" sheet: artwork, artist, and where it came from.
void showTrackDetailsSheet(BuildContext context, Song song) {
  showIfallSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => _TrackDetailsSheet(song: song),
  );
}

class _TrackDetailsSheet extends StatelessWidget {
  const _TrackDetailsSheet({required this.song});

  final Song song;

  @override
  Widget build(BuildContext context) {
    final NerdStats stats = context.read<PlaybackService>().nerdStats;
    return IfallSheet(
      title: song.title,
      subtitle: song.artist,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(
            child: Artwork(url: song.thumbnailUrl, size: 180, radius: 14),
          ),
          const SizedBox(height: 18),
          if (song.album != null) _Stat('Album', song.album!),
          if (song.duration != null) _Stat('Length', Fmt.duration(song.duration)),
          _Stat('Source', song.source.name),
          if (song.id == stats.videoId) _Stat('Container', stats.bufferLine),
          _Stat('Video ID', song.id),
        ],
      ),
    );
  }
}
