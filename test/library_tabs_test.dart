import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/models/artist.dart';
import 'package:ifallmusic/core/models/playlist.dart';
import 'package:ifallmusic/core/models/song.dart';
import 'package:ifallmusic/core/services/library_service.dart';
import 'package:ifallmusic/core/services/music_download_service.dart';
import 'package:ifallmusic/ui/library/library_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song _song(String id) => Song(
  id: id,
  title: 'Title $id',
  artist: 'Artist',
  thumbnailUrl: 'https://i.example/$id.jpg',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('library tab counters cover every tab, in tab order', () async {
    final File offlineFile = File(
      '${Directory.systemTemp.path}/saxify_library_tabs_test.mp3',
    );
    await offlineFile.writeAsString('x');

    final MusicDownloadJob job = MusicDownloadJob(song: _song('dl1'))
      ..phase = MusicDownloadPhase.done
      ..offlinePath = offlineFile.path;

    SharedPreferences.setMockInitialValues(<String, Object>{
      LibraryService.kLiked: jsonEncode(<Map<String, dynamic>>[
        _song('liked1').toJson(),
      ]),
      LibraryService.kSongs: jsonEncode(<Map<String, dynamic>>[
        _song('song1').toJson(),
        _song('song2').toJson(),
      ]),
      LibraryService.kPlaylists: jsonEncode(<Map<String, dynamic>>[
        Playlist(id: 'p1', name: 'Mix').toJson(),
      ]),
      LibraryService.kArtists: jsonEncode(<Map<String, dynamic>>[
        ArtistRef(channelId: 'c1', name: 'Arijit', imageUrl: '').toJson(),
      ]),
      LibraryService.kHistory: jsonEncode(<Map<String, dynamic>>[
        HistoryEntry(
          song: _song('h1'),
          playedAt: DateTime(2026, 9, 28),
        ).toJson(),
      ]),
      'saxify.music_downloads.v1': jsonEncode(<Map<String, dynamic>>[
        job.toJson(),
      ]),
    });

    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final LibraryService library = LibraryService(prefs);
    final MusicDownloadService downloads = MusicDownloadService(prefs: prefs);

    final List<int> counts = buildLibraryTabCounts(
      library: library,
      downloads: downloads,
      onDeviceCount: 5,
    );

    // One entry per tab: Your Space · Liked · Playlists · Songs · Artists ·
    // On device · Downloads · History · Lyrics Finder.
    expect(counts, hasLength(libraryTabCount));
    expect(libraryTabCount, 9);
    expect(
      counts,
      <int>[0, 1, 1, 2, 1, 5, 1, 1, 0],
      reason: 'counts must stay aligned with the tab order',
    );

    await offlineFile.delete();
  });
}
