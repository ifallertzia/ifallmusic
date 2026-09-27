import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/services/lyrics_service.dart';

Dio mock(dynamic Function(RequestOptions) respond) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final result = respond(options);
        if (result is int) {
          handler.reject(
            DioException(
              requestOptions: options,
              response: Response(requestOptions: options, statusCode: result),
              type: DioExceptionType.badResponse,
            ),
          );
        } else {
          handler.resolve(
            Response(requestOptions: options, data: result, statusCode: 200),
          );
        }
      },
    ),
  );
  return dio;
}

Map<String, dynamic> record(String artist, {int duration = 200}) => {
  'trackName': 'Song',
  'artistName': artist,
  'duration': duration,
  'plainLyrics': 'One\nTwo',
  'syncedLyrics': '[00:01]One\n[00:02]Two',
};
void main() {
  test('exact hit short circuits other tiers', () async {
    int calls = 0;
    final service = LyricsService(
      persist: false,
      dio: mock((o) {
        calls++;
        expect(o.path, endsWith('/get'));
        return record('Singer');
      }),
    );
    final result = await service.find(
      title: 'Song',
      artist: 'Singer',
      durationSecs: 200,
    );
    expect(result.synced, isTrue);
    expect(result.source, 'LRCLIB');
    expect(calls, 1);
    await service.find(title: 'Song', artist: 'Singer', durationSecs: 200);
    expect(calls, 1);
  });
  test('title-only search then artist +4 and duration +2 ranking', () async {
    final service = LyricsService(
      persist: false,
      dio: mock((o) {
        if (o.path.endsWith('/get')) return 404;
        expect(o.queryParameters.keys, ['track_name']);
        return [record('Other'), record('Singer', duration: 500)];
      }),
    );
    final result = await service.find(
      title: 'Song',
      artist: 'Singer',
      durationSecs: 200,
    );
    expect(result.status, LyricsStatus.found);
    expect(
      rankLyrics(
        [record('Other'), record('Singer', duration: 500)],
        [(title: 'Song', artist: 'Singer')],
        200,
      )!['artistName'],
      'Singer',
    );
  });
  test('ambiguous zero-score matches rejected, unique artist allowed', () {
    const variants = [(title: 'Song', artist: 'Label')];
    expect(rankLyrics([record('One'), record('Two')], variants, 0), isNull);
    expect(rankLyrics([record('One'), record('One')], variants, 0), isNotNull);
  });
  test(
    'plain fallback, 404 miss and 503 outage are distinct; outage not cached',
    () async {
      final plain = LyricsService(
        persist: false,
        dio: mock(
          (o) => o.path.contains('lyrics.ovh') ? {'lyrics': 'Full text'} : 404,
        ),
      );
      final hit = await plain.find(title: 'Song', artist: 'Singer');
      expect(hit.source, 'lyrics.ovh');
      expect(hit.lines, isEmpty);
      int misses = 0, outages = 0;
      final missing = LyricsService(
        persist: false,
        dio: mock((_) {
          misses++;
          return 404;
        }),
      );
      expect((await missing.find(title: 'Song')).status, LyricsStatus.notFound);
      await missing.find(title: 'Song');
      expect(misses, 2);
      final unavailable = LyricsService(
        persist: false,
        dio: mock((_) {
          outages++;
          return 503;
        }),
      );
      expect(
        (await unavailable.find(title: 'Song')).status,
        LyricsStatus.unavailable,
      );
      await unavailable.find(title: 'Song');
      expect(outages, 4);
    },
  );
  test('instrumental and synced-only payloads', () async {
    expect(
      LyricsResult.fromRecord({'instrumental': true}).instrumental,
      isTrue,
    );
    final result = LyricsResult.fromRecord({
      'syncedLyrics': '[00:01]One\n[00:02]Two',
    });
    expect(result.plain, 'One\nTwo');
    expect(result.synced, isTrue);
  });
}
