import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/artist_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/youtube_service.dart';
import '../../core/theme/ifall_ui.dart';
import '../../core/utils/format.dart';
import '../widgets/artwork.dart';
import '../widgets/search_fab.dart';
import '../widgets/song_tile.dart';

/// Profile opened only after a confident name match. Songs still come from
/// the existing YouTube search.
class ArtistProfilePage extends StatefulWidget {
  const ArtistProfilePage({
    super.key,
    required this.queryName,
    required this.profile,
  });

  final String queryName;
  final ArtistProfile profile;

  @override
  State<ArtistProfilePage> createState() => _ArtistProfilePageState();
}

class _ArtistProfilePageState extends State<ArtistProfilePage> {
  late final Future<List<Song>> _songs = _load();

  Future<List<Song>> _load() {
    final String name = widget.profile.name;
    return context.read<YoutubeService>().searchSongs('$name songs', limit: 20);
  }

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final ArtistProfile profile = widget.profile;

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        title: Text(
          profile.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: IfallText.title(c.onSurface),
        ),
        actions: const <Widget>[SaxifySearchButton()],
      ),
      body: FutureBuilder<List<Song>>(
        future: _songs,
        builder: (BuildContext context, AsyncSnapshot<List<Song>> snap) {
          final List<Song> songs = snap.data ?? <Song>[];
          return ListView(
            padding: const EdgeInsets.only(bottom: 140),
            children: <Widget>[
              const SizedBox(height: 18),
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: c.accent, width: 2),
                  ),
                  child: ClipOval(
                    child: Artwork(
                      url: profile.imageUrl,
                      size: 120,
                      radius: 60,
                      fallbackIcon: Icons.person_rounded,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Center(
                child: Text(
                  profile.name,
                  textAlign: TextAlign.center,
                  style: IfallText.style(
                    24,
                    weight: FontWeight.w800,
                    letterSpacing: -0.7,
                    color: c.onSurface,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Center(
                child: Text(
                  profile.fanCount == null
                      ? 'Photo via ${profile.source}'
                      : '${Fmt.count(profile.fanCount)} fans · ${profile.source}',
                  style: IfallText.caption(c.onSurfaceVariant),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: _PlayTopButton(songs: songs),
              ),
              if (snap.connectionState != ConnectionState.done)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Center(
                    child: CircularProgressIndicator(color: c.accent),
                  ),
                )
              else if (songs.isEmpty)
                IfallEmpty(
                  icon: Icons.music_off_rounded,
                  message: 'Try again in a moment, or search the name again.',
                )
              else
                for (int i = 0; i < songs.length; i++)
                  SongTile(
                    song: songs[i],
                    rank: i + 1,
                    onTap: () => context.read<PlaybackService>().playQueue(
                      songs,
                      startIndex: i,
                    ),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _PlayTopButton extends StatelessWidget {
  const _PlayTopButton({required this.songs});

  final List<Song> songs;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final Color onAccent =
        ThemeData.estimateBrightnessForColor(c.accent) == Brightness.dark
            ? Colors.white
            : Colors.black;
    return Opacity(
      opacity: songs.isEmpty ? 0.4 : 1,
      child: SizedBox(
        width: double.infinity,
        height: 46,
        child: FilledButton.icon(
          onPressed: songs.isEmpty
              ? null
              : () => context.read<PlaybackService>().playQueue(songs),
          style: FilledButton.styleFrom(
            backgroundColor: c.accent,
            foregroundColor: onAccent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(IfallUI.rPill),
            ),
          ),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(
            'Play top songs',
            style: IfallText.body(onAccent).copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}
