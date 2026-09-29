import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ifallmusic/core/services/innertube_resolver.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

const Map<String, dynamic> _okFormats = <String, dynamic>{
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
};

void main() {
  test('Innertube leads with VISIONOS and rotates with numeric client ids',
      () async {
    int calls = 0;
    final resolver = InnertubeResolver(
      client: MockClient((http.Request request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final client = (body['context'] as Map)['client'] as Map;
        final String headerId = request.headers['X-YouTube-Client-Name']!;
        // A non-numeric client id is treated as malformed by YouTube.
        expect(int.tryParse(headerId), isNotNull,
            reason: 'X-YouTube-Client-Name must be numeric, got $headerId');
        if (calls == 1) {
          expect(client['clientName'], 'VISIONOS');
          expect(client['clientVersion'], '1.02');
          expect(headerId, '101');
          expect(client['deviceMake'], 'Apple');
          expect(client['osName'], 'visionOS');
          expect(client['gl'], isNotEmpty);
          expect(client['hl'], isNotEmpty);
          expect(
            request.headers['User-Agent'],
            contains('Version/26.0 Safari/605.1.15'),
          );
          return http.Response(
            jsonEncode(<String, dynamic>{
              'playabilityStatus':
                  <String, dynamic>{'status': 'LOGIN_REQUIRED'},
            }),
            200,
          );
        }
        expect(client['clientName'], 'TVHTML5');
        expect(headerId, '7');
        return http.Response(jsonEncode(_okFormats), 200);
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
    expect(stream.clientName, 'TVHTML5');
    resolver.close();
  });

  test('LOGIN_REQUIRED retries the same client with visitorData once',
      () async {
    int calls = 0;
    final resolver = InnertubeResolver(
      client: MockClient((http.Request request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final client = (body['context'] as Map)['client'] as Map;
        if (calls == 1) {
          expect(client['clientName'], 'VISIONOS');
          expect(client.containsKey('visitorData'), isFalse);
          return http.Response(
            jsonEncode(<String, dynamic>{
              'playabilityStatus':
                  <String, dynamic>{'status': 'LOGIN_REQUIRED'},
              'responseContext': <String, dynamic>{
                'visitorData': 'VD-CHALLENGE-1',
              },
            }),
            200,
          );
        }
        // Same client, challenge echoed back on both header and body.
        expect(client['clientName'], 'VISIONOS');
        expect(client['visitorData'], 'VD-CHALLENGE-1');
        expect(request.headers['X-Goog-Visitor-Id'], 'VD-CHALLENGE-1');
        return http.Response(jsonEncode(_okFormats), 200);
      }),
    );

    final stream = await resolver.resolve(VideoId('abcdefghijk'));

    expect(calls, 2);
    expect(stream.clientName, 'VISIONOS');
    expect(stream.itag, 140);
    resolver.close();
  });

  test('Innertube skips cipher-only responses and keeps rotating', () async {
    int calls = 0;
    final resolver = InnertubeResolver(
      client: MockClient((http.Request request) async {
        calls++;
        return http.Response(
          jsonEncode(<String, dynamic>{
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
                        'url':
                            'https://r1---sn.test.googlevideo.com/videoplayback?itag=251',
                      },
                    ],
            },
          }),
          200,
        );
      }),
    );

    final stream = await resolver.resolve(VideoId('abcdefghijk'), validate: false);

    expect(calls, 2);
    expect(stream.itag, 251);
    resolver.close();
  });

  test('every client failure is reported with its playability status',
      () async {
    int calls = 0;
    final resolver = InnertubeResolver(
      client: MockClient((http.Request request) async {
        calls++;
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final client = (body['context'] as Map)['client'] as Map;
        if (client['clientName'] == 'VISIONOS') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'playabilityStatus': <String, dynamic>{
                'status': 'ERROR',
                'reason': 'The video you are trying to watch is not available',
              },
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'playabilityStatus': <String, dynamic>{'status': 'LOGIN_REQUIRED'},
          }),
          200,
        );
      }),
    );

    await expectLater(
      resolver.resolve(VideoId('abcdefghijk'), validate: false),
      throwsA(
        isA<StateError>().having(
          (StateError e) => e.message,
          'message',
          allOf(
            contains('Innertube could not resolve a playable stream'),
            contains('VISIONOS=ERROR'),
            contains('The video you are trying to watch is not available'),
            contains('TVHTML5=LOGIN_REQUIRED'),
            contains('TVHTML5_SIMPLY_EMBEDDED_PLAYER=LOGIN_REQUIRED'),
          ),
        ),
      ),
    );
    // No visitorData in these responses, so no client is retried.
    expect(calls, 6);
    resolver.close();
  });

  test('HEAD probe rejection rotates, network failure keeps the URL',
      () async {
    // First candidate answers 403 (dead); second answers 405 to HEAD
    // (not proof of death) — the resolver must return it instead of
    // burning the budget or blacklisting unrelated itags.
    int probe = 0;
    final resolver = InnertubeResolver(
      client: MockClient((http.Request request) async {
        if (request.method == 'HEAD') {
          probe++;
          if (probe == 1) return http.Response('', 403);
          return http.Response('', 405);
        }
        return http.Response(
          jsonEncode(<String, dynamic>{
            'playabilityStatus': <String, dynamic>{'status': 'OK'},
            'streamingData': <String, dynamic>{
              // Sorted by bitrate desc, so itag 140 is probed first.
              'adaptiveFormats': <Map<String, dynamic>>[
                <String, dynamic>{
                  'itag': 140,
                  'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                  'bitrate': 256000,
                  'url':
                      'https://r1---sn.test.googlevideo.com/videoplayback?itag=140',
                },
                <String, dynamic>{
                  'itag': 141,
                  'mimeType': 'audio/mp4; codecs="mp4a.40.2"',
                  'bitrate': 128000,
                  'url':
                      'https://r2---sn.test.googlevideo.com/videoplayback?itag=141',
                },
              ],
            },
          }),
          200,
        );
      }),
    );

    final stream = await resolver.resolve(VideoId('abcdefghijk'));

    expect(stream.itag, 141);
    expect(probe, 2);
    resolver.close();
  });
}
