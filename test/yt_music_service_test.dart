import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/services/yt_music_service.dart';

void main() {
  test('WEB_REMIX contract, raw query, cache and in-flight sharing', () async {
    int calls = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          calls++;
          expect(options.uri.host, 'music.youtube.com');
          expect(options.headers['X-YouTube-Client-Name'], '67');
          expect(options.data['context']['client']['clientName'], 'WEB_REMIX');
          expect(options.data['context']['client']['gl'], 'IN');
          expect(options.data['query'], 'Kesariya');
          expect(options.data['params'], YtMusicService.songsFilter);
          await Future<void>.delayed(const Duration(milliseconds: 5));
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: jsonDecode(
                File('test/fixtures/yt_music_songs.json').readAsStringSync(),
              ),
            ),
          );
        },
      ),
    );
    final service = YtMusicService(dio: dio);
    final results = await Future.wait([
      service.search('Kesariya', filter: YtMusicService.songsFilter),
      service.search('Kesariya', filter: YtMusicService.songsFilter),
    ]);
    expect(calls, 1);
    expect(results.first.tracks.single.id, 'abcdefghijk');
    await service.search('Kesariya', filter: YtMusicService.songsFilter);
    expect(calls, 1);
    service.close();
  });
  test('request errors are not cached', () async {
    int calls = 0;
    final dio = Dio();
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          calls++;
          handler.reject(
            DioException(
              requestOptions: options,
              type: DioExceptionType.connectionError,
            ),
          );
        },
      ),
    );
    final service = YtMusicService(dio: dio);
    await expectLater(service.search('Song'), throwsA(isA<DioException>()));
    await expectLater(service.search('Song'), throwsA(isA<DioException>()));
    expect(calls, 2);
    service.close();
  });
}
