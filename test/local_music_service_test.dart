import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/models/song.dart';
import 'package:ifallmusic/core/services/local_music_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('local device songs persist and restore from scan cache', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Song local = Song(
      id: 'local:42',
      title: 'Phone Song',
      artist: 'Device Artist',
      thumbnailUrl: 'content://media/external/audio/albumart/7',
      duration: const Duration(minutes: 3),
      album: 'Device Album',
      albumId: '7',
      artistId: '9',
      source: TrackSource.localDevice,
      localUri: 'content://media/external/audio/media/42',
    );
    await prefs.setString(
      'saxify.local_music.cache.v1',
      jsonEncode(<Map<String, dynamic>>[local.toJson()]),
    );

    final LocalMusicService restored = LocalMusicService(prefs);
    expect(restored.songs, hasLength(1));
    expect(restored.songs.single.source, TrackSource.localDevice);
    expect(restored.songs.single.localUri, 'content://media/external/audio/media/42');
    expect(restored.albums.single.title, 'Device Album');
    expect(restored.artists.single.name, 'Device Artist');
    expect(restored.search('phone').single.id, 'local:42');
  });
}
