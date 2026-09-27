import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/models/song.dart';
import 'package:ifallmusic/core/services/radio_queue.dart';

Song track(String id, String title, {String artist = 'Arijit Singh'}) =>
    Song(id: id, title: title, artist: artist, thumbnailUrl: '');
void main() {
  test('automatic queue rejects the seed recording in alternate forms', () {
    final seed = track('aaaaaaaaaaa', 'Kesariya');
    final result = radioCandidates(seed, [
      seed,
      track('bbbbbbbbbbb', 'Kesariya (Slowed + Reverb)'),
      track('ccccccccccc', 'Arijit Singh - Kesariya [Official Video]'),
      track('ddddddddddd', 'Kesariya | Brahmastra | Official Audio'),
      track('eeeeeeeeeee', 'Kesariya Arijit Singh Full Song'),
      track('fffffffffff', 'Channa Mereya'),
      track('ggggggggggg', 'Channa Mereya (Live)'),
      track('hhhhhhhhhhh', 'Agar Tum Saath Ho'),
    ]);
    expect(result.map((s) => s.title), ['Channa Mereya', 'Agar Tum Saath Ho']);
  });
  test('played recordings and failed IDs stay out; Unicode names survive', () {
    final seed = track('aaaaaaaaaaa', 'केसरिया');
    expect(
      sameRecording(seed, track('bbbbbbbbbbb', 'केसरिया (remix)')),
      isTrue,
    );
    final result = radioCandidates(
      seed,
      [track('ccccccccccc', 'Song Two'), track('ddddddddddd', 'Song Three')],
      history: [track('eeeeeeeeeee', 'Song Two')],
      excludedIds: {'ddddddddddd'},
    );
    expect(result, isEmpty);
  });
  test('completion/error claim once, loading and stale epochs ignored', () {
    final epoch = PlaybackEpoch();
    final first = epoch.begin();
    expect(epoch.complete(), isFalse);
    epoch.ready(first);
    expect(epoch.complete(), isTrue);
    expect(epoch.complete(), isFalse);
    final second = epoch.begin();
    expect(epoch.fail(first), isFalse);
    epoch.ready(second);
    expect(epoch.fail(second), isTrue);
    expect(epoch.fail(second), isFalse);
    expect(epoch.complete(), isFalse);
    final third = epoch.begin();
    epoch.ready(third);
    expect(epoch.complete(), isTrue);
  });
}
