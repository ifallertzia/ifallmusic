import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/services/lyrics_query.dart';

void main() {
  test('clean title in prescribed order', () {
    expect(
      cleanTitle('Kesariya (Official Video) | Brahmastra'),
      'Kesariya | Brahmastra',
    );
    expect(cleanTitle('Song [Official HD Audio] (remaster version) -'), 'Song');
    expect(cleanTitle('Song (Live at Wembley)'), 'Song (Live at Wembley)');
  });
  test('film, pipe, dash variants capped at four', () {
    final pipe = queryVariants(
      title: 'Kesariya (Official Video) | Brahmastra',
      artist: 'Arijit Singh - Topic',
    );
    expect(pipe, contains((title: 'Kesariya', artist: 'Arijit Singh')));
    final dash = queryVariants(
      title: 'Singer - Song (from Film) | OST',
      artist: 'LabelVEVO',
    );
    expect(dash.length, lessThanOrEqualTo(4));
    expect(dash, contains((title: 'Song (from Film)', artist: 'Singer')));
    expect(dash, contains((title: 'Singer', artist: 'Label')));
    expect(cleanArtist('Unknown Artist'), '');
    expect(cleanArtist('Various Artists'), '');
    expect(normalize('Ｆｕｌｌ Width!'), 'full width');
  });
}
