import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/artist.dart';
import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../widgets/collection_header.dart';
import '../widgets/sidify_widgets.dart';

/// One ranked thing in Replay: a song (grouped by id) with its play count.
class ReplayTally {
  const ReplayTally(this.song, this.count);

  final Song song;
  final int count;

  String get artist => song.artist;
  String get title => song.title;
  String get thumbnailUrl => song.thumbnailUrl;
}

/// Replay, computed on the device from the local history — the site's
/// Replay page: minutes listened, top songs, top artists, active days.
/// Nothing leaves the phone.
class ReplayStats {
  const ReplayStats({
    required this.minutes,
    required this.plays,
    required this.activeDays,
    required this.topSong,
    required this.topArtist,
    required this.songs,
    required this.artists,
  });

  final int minutes;
  final int plays;
  final int activeDays;
  final ReplayTally? topSong;
  final ReplayTally? topArtist;
  final List<ReplayTally> songs;
  final List<ReplayTally> artists;

  factory ReplayStats.fromHistory(List<HistoryEntry> history) {
    final Map<String, ReplayTally> bySong = <String, ReplayTally>{};
    final Map<String, ReplayTally> byArtist = <String, ReplayTally>{};
    final Set<String> days = <String>{};
    int totalMs = 0;
    for (final HistoryEntry e in history) {
      totalMs += (e.song.duration?.inMilliseconds ?? 210000);
      days.add('${e.playedAt.year}-${e.playedAt.month}-${e.playedAt.day}');
      final ReplayTally? cur = bySong[e.song.id];
      bySong[e.song.id] = ReplayTally(e.song, (cur?.count ?? 0) + 1);
      final String key = e.song.artist.toLowerCase();
      final ReplayTally? curA = byArtist[key];
      byArtist[key] = ReplayTally(e.song, (curA?.count ?? 0) + 1);
    }
    List<ReplayTally> rank(Map<String, ReplayTally> m) =>
        m.values.toList()..sort((a, b) => b.count.compareTo(a.count));
    final List<ReplayTally> songs = rank(bySong);
    final List<ReplayTally> artists = rank(byArtist);
    return ReplayStats(
      minutes: totalMs ~/ 60000,
      plays: history.length,
      activeDays: days.length,
      topSong: songs.isEmpty ? null : songs.first,
      topArtist: artists.isEmpty ? null : artists.first,
      songs: songs,
      artists: artists,
    );
  }
}

class ReplayPage extends StatelessWidget {
  const ReplayPage({super.key});

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final SidifyTokens t = context.sidify;
    final List<HistoryEntry> history = library.history;
    final int year = DateTime.now().year;

    if (history.isEmpty) {
      return Scaffold(
        backgroundColor: t.bg,
        appBar: _bar(context, 'Replay $year'),
        body: const EmptyState(
          icon: Icons.bar_chart_rounded,
          title: 'Nothing to replay yet',
          desc: 'Play some songs and your minutes, top songs and top '
              'artists will show up here — counted on this device only.',
        ),
      );
    }

    final ReplayStats stats = ReplayStats.fromHistory(history);
    final List<Song> topSongs =
        stats.songs.take(10).map((ReplayTally e) => e.song).toList();

    return Scaffold(
      backgroundColor: t.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverToBoxAdapter(
            child: CollectionHeader(
              artwork: stats.topSong?.thumbnailUrl ?? '',
              eyebrow: 'Sidify Replay',
              title: 'Replay $year',
              subtitle: stats.minutes >= 60
                  ? '${(stats.minutes / 60).toStringAsFixed(1)} hours listened'
                  : '${stats.minutes} minutes listened',
              meta: '${stats.plays} plays · ${stats.activeDays} active days',
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.only(bottom: 190),
            sliver: SliverList.list(
              children: <Widget>[
                const SectionHeader(title: 'Top songs'),
                for (int i = 0; i < topSongs.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TrackRow(
                      tracks: topSongs,
                      index: i,
                      numbered: true,
                      subtitle:
                          '${topSongs[i].artist} · ${stats.songs[i].count} plays',
                    ),
                  ),
                const SizedBox(height: 28),
                const SectionHeader(title: 'Top artists'),
                for (int i = 0; i < stats.artists.length && i < 10; i++)
                  _artistRow(context, stats.artists[i], i),
              ],
            ),
          ),
        ],
      ),
    );
  }

  AppBar _bar(BuildContext context, String title) {
    final SidifyTokens t = context.sidify;
    return AppBar(
      backgroundColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: Icon(Icons.arrow_back_rounded, color: t.text),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Text(title, style: SidifyText.titleM(t.text)),
    );
  }

  Widget _artistRow(BuildContext context, ReplayTally tally, int rank) {
    final SidifyTokens t = context.sidify;
    final List<Song> mine = context
        .read<LibraryService>()
        .history
        .where((HistoryEntry e) => e.song.artist == tally.artist)
        .map((HistoryEntry e) => e.song)
        .toList();
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: mine.isEmpty
            ? null
            : () => context
                .read<PlaybackService>()
                .playQueue(mine, startIndex: 0),
        child: Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 28,
                child: Text(
                  '${rank + 1}',
                  style: TextStyle(fontSize: 15, color: t.text2),
                ),
              ),
              Artwork(url: tally.thumbnailUrl, size: 52, radius: 999, round: true),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      tally.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, color: t.text),
                    ),
                    Text(
                      '${tally.count} plays',
                      style: TextStyle(fontSize: 13, color: t.text2),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
