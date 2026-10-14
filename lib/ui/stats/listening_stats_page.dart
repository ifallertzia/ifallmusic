import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/branding.dart';
import '../../core/models/artist.dart';
import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/ifall_ui.dart';
import '../../core/utils/format.dart';
import '../widgets/artwork.dart';

/// **Replay** — the listener's own year, computed on the device.
///
/// Nothing leaves the phone: the counts come from the local history store, the
/// same one that feeds the recommendation engine.
class ListeningStatsPage extends StatelessWidget {
  const ListeningStatsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final PlaybackService playback = context.watch<PlaybackService>();
    final SettingsService settings = context.watch<SettingsService>();
    final IfallPalette c = IfallPalette.of(context);

    final List<HistoryEntry> history = library.history;
    final int plays = history.length;
    final int liked = library.likedSongs.length;
    final int playlists = library.playlists.length;

    final Map<String, _Tally> artists = <String, _Tally>{};
    final Map<String, _Tally> songs = <String, _Tally>{};
    int totalMs = 0;
    for (final HistoryEntry entry in history) {
      final Song song = entry.song;
      final int ms = song.duration?.inMilliseconds ?? 0;
      totalMs += ms;
      artists
          .putIfAbsent(song.artist, () => _Tally(song.artist, song.thumbnailUrl))
          .add(ms);
      songs
          .putIfAbsent(song.id, () => _Tally(song.title, song.thumbnailUrl))
          .add(ms, song: song);
    }

    final List<_Tally> topArtists = _ranked(artists.values);
    final List<_Tally> topSongs = _ranked(songs.values);

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 40),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 12, 2),
              child: Row(
                children: <Widget>[
                  const BackButton(),
                  Expanded(
                    child: Text(
                      'Listening stats',
                      style: IfallText.title(c.onSurface),
                    ),
                  ),
                ],
              ),
            ),
            _HeroCard(
              plays: plays,
              minutes: totalMs ~/ 60000,
              liked: liked,
              playlists: playlists,
            ),
            if (!settings.statsOptIn)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: IfallGlass(
                  radius: IfallUI.rMd,
                  blur: 0,
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'Stats are switched off in Settings ▸ Privacy, so new plays '
                    'are not being recorded. What you see here is history kept '
                    'before that.',
                    style: IfallText.body(c.onSurfaceVariant),
                  ),
                ),
              ),
            if (topArtists.isEmpty)
              const IfallEmpty(
                icon: Icons.auto_graph_rounded,
                message:
                    'Nothing to replay yet. Play a few songs and your numbers appear here.',
              )
            else ...<Widget>[
              IfallSectionHeader(
                title: 'Top artists',
                subtitle: 'From ${history.length} plays on this device',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: IfallGlass(
                  radius: IfallUI.rLg,
                  blur: 0,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < topArtists.length; i++)
                        _RankRow(
                          rank: i + 1,
                          tally: topArtists[i],
                          caption: '${topArtists[i].count} plays',
                          onTap: () => playback.playQueue(
                            history
                                .where((HistoryEntry e) =>
                                    e.song.artist == topArtists[i].name)
                                .map((HistoryEntry e) => e.song)
                                .toList(growable: false),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const IfallSectionHeader(
                title: 'Top songs',
                subtitle: 'Your most played tracks',
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: IfallGlass(
                  radius: IfallUI.rLg,
                  blur: 0,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    children: <Widget>[
                      for (int i = 0; i < topSongs.length; i++)
                        _RankRow(
                          rank: i + 1,
                          tally: topSongs[i],
                          caption: '${topSongs[i].count} plays',
                          onTap: topSongs[i].song == null
                              ? null
                              : () => playback.playSong(topSongs[i].song!),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),
            Center(
              child: Text(
                'Everything here is counted on this phone. '
                '${IfallBranding.appName} uploads nothing.',
                textAlign: TextAlign.center,
                style: IfallText.caption(c.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_Tally> _ranked(Iterable<_Tally> values) {
    final List<_Tally> list = values.toList()
      ..sort((_Tally a, _Tally b) {
        final int byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : b.ms.compareTo(a.ms);
      });
    return list.take(10).toList();
  }
}

class _Tally {
  _Tally(this.name, this.artwork) : ids = HashSet<String>();

  final String name;
  final String artwork;
  final Set<String> ids;
  int ms = 0;
  Song? song;

  int get count => ids.length;

  void add(int milliseconds, {Song? song}) {
    ms += milliseconds;
    this.song ??= song;
    if (song != null) ids.add(song.id);
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.plays,
    required this.minutes,
    required this.liked,
    required this.playlists,
  });

  final int plays;
  final int minutes;
  final int liked;
  final int playlists;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
      child: IfallGlass(
        radius: IfallUI.rXl,
        blur: 0,
        color: c.accent.withValues(alpha: 0.12),
        border: c.accent.withValues(alpha: 0.4),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('YOUR REPLAY', style: IfallText.label(c.accent)),
            const SizedBox(height: 10),
            Text(
              minutes >= 60
                  ? '${(minutes / 60).toStringAsFixed(1)} hours'
                  : '$minutes minutes',
              style: IfallText.style(
                32,
                weight: FontWeight.w800,
                letterSpacing: -0.9,
                color: c.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'of music on this device',
              style: IfallText.body(c.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Row(
              children: <Widget>[
                Expanded(
                  child: _Metric(
                    value: Fmt.count(plays),
                    label: 'plays',
                  ),
                ),
                Expanded(
                  child: _Metric(value: Fmt.count(liked), label: 'liked'),
                ),
                Expanded(
                  child: _Metric(
                    value: Fmt.count(playlists),
                    label: 'playlists',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          value,
          style: IfallText.style(
            21,
            weight: FontWeight.w800,
            letterSpacing: -0.5,
            color: c.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(label, style: IfallText.caption(c.onSurfaceVariant)),
      ],
    );
  }
}

class _RankRow extends StatelessWidget {
  const _RankRow({
    required this.rank,
    required this.tally,
    required this.caption,
    this.onTap,
  });

  final int rank;
  final _Tally tally;
  final String caption;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        leading: SizedBox(
          width: 34,
          child: Text(
            '#$rank',
            style: IfallText.body(
              rank <= 3 ? c.accent : c.onSurfaceVariant,
            ).copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        title: Text(
          tally.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: IfallText.body(c.onSurface),
        ),
        subtitle: Text(caption, style: IfallText.caption(c.onSurfaceVariant)),
        trailing: Artwork(url: tally.artwork, size: 44, radius: 8),
      ),
    );
  }
}
