import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ifallmusic/core/services/module_source_resolver.dart';

void main() {
  group('ModuleSourceResolver.extractStreamUrl', () {
    test('accepts the documented JSON shapes', () {
      expect(
        ModuleSourceResolver.extractStreamUrl('{"url": "https://a.b/c.flac"}'),
        'https://a.b/c.flac',
      );
      expect(
        ModuleSourceResolver.extractStreamUrl(
          '{"data": {"streamUrl": "https://a.b/d.m4a"}}',
        ),
        'https://a.b/d.m4a',
      );
      expect(
        ModuleSourceResolver.extractStreamUrl(
          '[{"audio_url": "https://a.b/e.opus"}]',
        ),
        'https://a.b/e.opus',
      );
    });

    test('accepts a plain-text URL and rejects everything else', () {
      expect(
        ModuleSourceResolver.extractStreamUrl('  https://a.b/f.flac \n'),
        'https://a.b/f.flac',
      );
      expect(ModuleSourceResolver.extractStreamUrl('{"url": 42}'), isNull);
      expect(ModuleSourceResolver.extractStreamUrl('not json'), isNull);
      expect(ModuleSourceResolver.extractStreamUrl(''), isNull);
      expect(
        ModuleSourceResolver.extractStreamUrl('{"url": "file:///etc/passwd"}'),
        isNull,
      );
    });
  });

  group('ModuleSourceResolver.resolve', () {
    test('asks enabled sources in order with the video id', () async {
      final List<Uri> asked = <Uri>[];
      final ModuleSourceResolver resolver = ModuleSourceResolver(
        client: MockClient((http.Request request) async {
          asked.add(request.url);
          if (request.url.host == 'dead.example.com') {
            return http.Response('nope', 500);
          }
          return http.Response('{"streamUrl": "https://cdn.example.com/x.flac"}', 200);
        }),
      );
      final String? url = await resolver.resolve(
        videoId: 'abc123',
        title: 'Song',
        artist: 'Singer',
        sources: <Map<String, dynamic>>[
          <String, dynamic>{'name': 'off', 'url': 'https://off.example.com', 'enabled': false},
          <String, dynamic>{'name': 'dead', 'url': 'https://dead.example.com/api'},
          <String, dynamic>{'name': 'live', 'url': 'https://live.example.com/api'},
        ],
      );
      expect(url, 'https://cdn.example.com/x.flac');
      expect(asked.length, 2); // disabled source never asked
      expect(asked.first.queryParameters['videoId'], 'abc123');
      expect(asked.first.queryParameters['q'], 'Singer Song');
    });

    test('a dead or silent source set resolves to null, never throws', () async {
      final ModuleSourceResolver resolver = ModuleSourceResolver(
        client: MockClient((http.Request request) async {
          throw Exception('offline');
        }),
      );
      expect(
        await resolver.resolve(
          videoId: 'abc123',
          sources: <Map<String, dynamic>>[
            <String, dynamic>{'url': 'https://dead.example.com'},
          ],
        ),
        isNull,
      );
      expect(
        await resolver.resolve(videoId: 'abc123', sources: const <Map<String, dynamic>>[]),
        isNull,
      );
    });

    test('{id} placeholders are substituted instead of queried', () async {
      Uri? asked;
      final ModuleSourceResolver resolver = ModuleSourceResolver(
        client: MockClient((http.Request request) async {
          asked = request.url;
          return http.Response('https://cdn.example.com/y.flac', 200);
        }),
      );
      final String? url = await resolver.resolve(
        videoId: 'xyz',
        sources: <Map<String, dynamic>>[
          <String, dynamic>{'url': 'https://m.example.com/track/{id}'},
        ],
      );
      expect(url, 'https://cdn.example.com/y.flac');
      expect(asked.toString(), 'https://m.example.com/track/xyz');
    });
  });
}
