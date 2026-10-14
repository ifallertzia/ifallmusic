import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/home_catalog.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/youtube_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../shell/sidify_routes.dart';
import '../widgets/sidify_widgets.dart';

/// A mood or genre: a search seed with its own colour, ported from the
/// site's `explore.ts`.
class SidifyMood {
  const SidifyMood(this.title, this.color, this.query, {this.genre = false});

  final String title;
  final String color;
  final String query;
  final bool genre;
}

const List<SidifyMood> kSidifyMoods = <SidifyMood>[
  SidifyMood('Chill', '#7aaed0', 'chill songs'),
  SidifyMood('Feel Good', '#86b890', 'feel good songs'),
  SidifyMood('Energize', '#d0a060', 'energetic songs'),
  SidifyMood('Workout', '#cc6a55', 'workout music'),
  SidifyMood('Focus', '#8090c8', 'focus music for studying'),
  SidifyMood('Romance', '#c07a92', 'romantic songs'),
  SidifyMood('Sad', '#6a88b0', 'sad songs'),
  SidifyMood('Party', '#9c8ac0', 'party songs'),
  SidifyMood('Sleep', '#5a6e9a', 'calm sleep music'),
  SidifyMood('Commute', '#b0886a', 'road trip songs'),
];

const List<SidifyMood> kSidifyGenres = <SidifyMood>[
  SidifyMood('Bollywood', '#d08a4a', 'bollywood hits', genre: true),
  SidifyMood('Punjabi', '#9ab060', 'punjabi hits', genre: true),
  SidifyMood('Hip-Hop', '#8a8aa0', 'hip hop hits', genre: true),
  SidifyMood('Pop', '#d07aa8', 'pop hits', genre: true),
  SidifyMood('Indie', '#70a89a', 'indie pop songs', genre: true),
  SidifyMood('Rock', '#b05a5a', 'rock anthems', genre: true),
  SidifyMood('Dance & Electronic', '#5aa0c8', 'edm dance hits', genre: true),
  SidifyMood('K-Pop', '#b88ad0', 'kpop hits', genre: true),
  SidifyMood('Lo-Fi', '#8a9a7a', 'lofi beats', genre: true),
  SidifyMood('Jazz', '#c0a060', 'jazz classics', genre: true),
  SidifyMood('Classical', '#a09080', 'classical music', genre: true),
  SidifyMood('90s Throwback', '#c08aa0', '90s hits', genre: true),
  SidifyMood('Devotional', '#d0b070', 'devotional songs', genre: true),
  SidifyMood('Ghazals & Sufi', '#9a7a8a', 'ghazal sufi songs', genre: true),
];

/// Explore: New releases, Top songs (charts), Moods & moments, Genres —
/// the site's Explore, tile for tile.
class ExplorePage extends StatefulWidget {
  const ExplorePage({super.key});

  @override
  State<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends State<ExplorePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeCatalog>().load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final HomeCatalog catalog = context.watch<HomeCatalog>();
    final List<Song> trending = catalog.trending;
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 190),
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          const PageTitle('Explore'),
          if (catalog.freshReleases.isNotEmpty)
            ShelfSection(
              title: 'New releases',
              children: <Widget>[
                for (final item in catalog.freshReleases)
                  SquareCard(
                    title: item.title,
                    artwork: item.artwork,
                    onTap: () => openBrowse(context, item),
                  ),
              ],
            ),
          if (trending.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 36),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  const SectionHeader(title: 'Top songs', subtitle: 'Charts'),
                  QuickPicks(
                    tracks: trending.take(20).toList(),
                    label: 'Top songs',
                  ),
                ],
              ),
            ),
          _grid(context, 'Moods & moments', kSidifyMoods),
          _grid(context, 'Genres', kSidifyGenres),
        ],
      ),
    );
  }

  Widget _grid(BuildContext context, String title, List<SidifyMood> moods) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SectionHeader(title: title),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.72,
              ),
              itemCount: moods.length,
              itemBuilder: (BuildContext context, int i) {
                final SidifyMood m = moods[i];
                return MoodCard(
                  title: m.title,
                  colorHex: m.color,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => ExploreMoodPage(mood: m),
                      settings: const RouteSettings(name: 'sidify/mood'),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One mood / genre opened: its songs, from the catalogue, ready to play.
class ExploreMoodPage extends StatefulWidget {
  const ExploreMoodPage({super.key, required this.mood});

  final SidifyMood mood;

  @override
  State<ExploreMoodPage> createState() => _ExploreMoodPageState();
}

class _ExploreMoodPageState extends State<ExploreMoodPage> {
  late Future<List<Song>> _songs;

  @override
  void initState() {
    super.initState();
    _songs = context.read<YoutubeService>().searchSongs(widget.mood.query, limit: 30);
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final Color base = MoodCard.parse(widget.mood.color);
    return Scaffold(
      backgroundColor: t.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverAppBar(
            expandedHeight: 170,
            pinned: true,
            backgroundColor: Color.lerp(base, Colors.black, 0.25),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.mood.title,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: Colors.white,
                ),
              ),
              background: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[base, Color.lerp(base, Colors.black, 0.45)!],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FutureBuilder<List<Song>>(
              future: _songs,
              builder: (BuildContext context, AsyncSnapshot<List<Song>> snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 60),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                final List<Song> songs = snap.data ?? <Song>[];
                if (songs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.music_off_rounded,
                    title: 'Nothing here yet',
                    desc: 'This shelf could not be loaded. Try again in a moment.',
                  );
                }
                return Padding(
                  padding: const EdgeInsets.only(bottom: 190),
                  child: Column(
                    children: <Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                        child: Row(
                          children: <Widget>[
                            SidifyButton(
                              label: 'Play',
                              icon: Icons.play_arrow_rounded,
                              onTap: () => context
                                  .read<PlaybackService>()
                                  .playQueue(songs, startIndex: 0),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${songs.length} songs',
                              style: TextStyle(fontSize: 13, color: t.text2),
                            ),
                          ],
                        ),
                      ),
                      for (int i = 0; i < songs.length; i++)
                        TrackRow(tracks: songs, index: i),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
