import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ifallmusic/core/services/innertube_resolver.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

void main() {
  test('Innertube rotates clients until an OK direct audio URL exists', () async {
    int calls = 0;
    final resolver = InnertubeResolver(
      client: MockClient((http.Request request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final client = (body['context'] as Map)['client'] as Map;
        if (calls == 1) {
          expect(client['clientName'], 'ANDROID_TESTSUITE');
          return http.Response(jsonEncode(<String, dynamic>{
            'playabilityStatus': <String, dynamic>{'status': 'LOGIN_REQUIRED'},
          }), 200);
        }
        expect(client['clientName'], 'ANDROID_VR');
        expect(request.headers['X-YouTube-Client-Name'], '28');
        return http.Response(jsonEncode(<String, dynamic>{
          'playabilityStatus': <String, dynamic>{'status': 'OK'},
          'streamingData': <String, dynamic>{
            'adaptiveFormats': <Map<String, dynamic>>[
              <String, dynamic>{
                'itag': 140,
                'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                'bitrate': 128000,
                'contentLength': '1234',
                'url': 'https://r1---sn.test.googlevideo.com/videoplayback?itag=140',
              },
            ],
          },
        }), 200);
      }),
    );

    final stream = await resolver.resolve(
      VideoId('abcdefghijk'),
      preferDownload: true,
      validate: false,
    );

    expect(calls, 2);
    expect(stream.itag, 140);
    expect(stream.contentLength, 1234);
    expect(stream.clientName, 'ANDROID_VR');
    resolver.close();
  });

  test('Innertube skips cipher-only responses and keeps rotating', () async {
    int calls = 0;
    final resolver = InnertubeResolver(
      client: MockClient((http.Request request) async {
        calls++;
        return http.Response(jsonEncode(<String, dynamic>{
          'playabilityStatus': <String, dynamic>{'status': 'OK'},
          'streamingData': <String, dynamic>{
            'adaptiveFormats': calls == 1
                ? <Map<String, dynamic>>[
                    <String, dynamic>{
                      'itag': 251,
                      'mimeType': 'audio/webm; codecs="opus"',
                      'bitrate': 160000,
                      'signatureCipher': 'url=https%3A%2F%2Fexample.invalid',
                    },
                  ]
                : <Map<String, dynamic>>[
                    <String, dynamic>{
                      'itag': 251,
                      'mimeType': 'audio/webm; codecs="opus"',
                      'bitrate': 160000,
                      'url': 'https://r1---sn.test.googlevideo.com/videoplayback?itag=251',
                    },
                  ],
          },
        }), 200);
      }),
    );

    final stream = await resolver.resolve(VideoId('abcdefghijk'), validate: false);

    expect(calls, 2);
    expect(stream.itag, 251);
    resolver.close();
  });
}
