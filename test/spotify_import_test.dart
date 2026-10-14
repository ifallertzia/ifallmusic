import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/services/spotify_import_service.dart';

void main() {
  group('SpotifyImportService.playlistId', () {
    test('reads every link shape Spotify hands out', () {
      expect(
        SpotifyImportService.playlistId(
          'https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M?si=abc',
        ),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
      expect(
        SpotifyImportService.playlistId('spotify:playlist/37i9dQZF1DXcBWIGoYBM5M'),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
      expect(
        SpotifyImportService.playlistId(
          'https://open.spotify.com/embed/playlist/37i9dQZF1DXcBWIGoYBM5M',
        ),
        '37i9dQZF1DXcBWIGoYBM5M',
      );
      expect(SpotifyImportService.playlistId('https://example.com/nope'), isNull);
      expect(SpotifyImportService.playlistId(''), isNull);
    });
  });

  group('SpotifyImportService.parseEmbedPage', () {
    test('extracts the playlist name and its tracks in order', () {
      const String html = '''
<html><head><title>Midnight Drive - playlist by someone | Spotify</title></head>
<body><script>{"props":{"trackList":[
 {"uri":"spotify:track:1","title":"Kesariya","subtitle":"Pritam, Arijit Singh","duration":268000},
 {"uri":"spotify:track:2","title":"Say \\"Hi\\"","subtitle":"Dua Lipa","duration":180000}
]}}</script></body></html>''';
      final parsed = SpotifyImportService.parseEmbedPage(html);
      expect(parsed, isNotNull);
      expect(parsed!.name, 'Midnight Drive');
      expect(parsed.tracks.length, 2);
      expect(parsed.tracks.first.title, 'Kesariya');
      expect(parsed.tracks.first.artist, 'Pritam, Arijit Singh');
      expect(parsed.tracks.last.title, 'Say "Hi"');
    });

    test('a page without a track list is not a playlist', () {
      expect(
        SpotifyImportService.parseEmbedPage('<html><title>404</title></html>'),
        isNull,
      );
    });
  });
}
