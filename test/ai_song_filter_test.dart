import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/models/song.dart';
import 'package:ifallmusic/core/services/ai_song_filter.dart';
import 'package:ifallmusic/core/services/radio_queue.dart';

Song track(String title, {String artist = 'Singer'}) => Song(
  id: title, title: title, artist: artist, thumbnailUrl: '',
);

void main() {
  test('explicit AI uploads are removed without excluding ordinary titles', () {
    expect(isLikelyAiSong(track('AI generated cover')), isTrue);
    expect(isLikelyAiSong(track('My song', artist: 'AI Voice Channel')), isTrue);
    expect(isLikelyAiSong(track('Aisa Kya')), isFalse);
  });
  test('radio never appends labelled AI candidates', () {
    expect(radioCandidates(track('Seed'), [
      track('AI cover'), track('Normal Song'),
    ]).map((s) => s.title), ['Normal Song']);
  });
}
