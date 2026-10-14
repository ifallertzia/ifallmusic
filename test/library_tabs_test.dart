import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/models/artist.dart';
import 'package:ifallmusic/core/models/playlist.dart';
import 'package:ifallmusic/core/models/song.dart';
import 'package:ifallmusic/core/services/library_service.dart';
import 'package:ifallmusic/core/services/music_download_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Song _song(String id) => Song(
  id: id,
  title: 'Title $id',
  artist: 'Artist',
  thumbnailUrl: 'https://i.example/$id.jpg',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The Library page is a hub now (Replay, Liked Songs, History, Downloads,
  // Lyrics finder, playlists…), so the counts that used to feed the old tab
  // bar are asserted against the services they are read from.
  test('library hub counts come straight from the services', () async {
    final File offlineFile = File(
      '${Directory.systemTemp.path}/sidify_library_hub_test.mp3',
    )..writeAsBytesSync(<int>[1, 2, 3]);
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

    expect(library.likedSongs, hasLength(1));
    expect(library.playlists, hasLength(1));
    expect(library.artists, hasLength(1));
    expect(library.history, hasLength(1));
    expect(library.likedSongs.first.id, 'liked1');
    expect(downloads.downloaded, hasLength(1));
    expect(downloads.isDownloaded('dl1'), isTrue);

    await offlineFile.delete();
  });

  test('liked toggling survives a restart through the same prefs', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final LibraryService library = LibraryService(prefs);
    await library.toggleLike(_song('a'));
    expect(library.isLiked('a'), isTrue);

    final LibraryService restarted = LibraryService(prefs);
    expect(restarted.isLiked('a'), isTrue);
    await restarted.toggleLike(_song('a'));
    expect(restarted.isLiked('a'), isFalse);
  });
}
