import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/movies/models/movie_models.dart';
import 'package:ifallmusic/movies/models/movie_provider.dart';
import 'package:ifallmusic/movies/services/ifallhub_service.dart';
import 'package:ifallmusic/movies/services/movie_http_client.dart';

const String _base = 'https://ifallhub.test';

MovieHttpResponse _json(int status, Object? body) {
  return MovieHttpResponse(
    statusCode: status,
    body: body == null ? '' : jsonEncode(body),
    headers: const <String, String>{},
    effectiveUrl: _base,
  );
}

class _FakeHubTransport implements MovieHttpTransport {
  final Map<String, MovieHttpResponse Function(Uri uri)> getRoutes =
      <String, MovieHttpResponse Function(Uri uri)>{};
  final Map<String, MovieHttpResponse Function(String body)> postRoutes =
      <String, MovieHttpResponse Function(String body)>{};
  final List<Uri> gets = <Uri>[];
  final List<String> posts = <String>[];

  @override
  final Dio streamDio = Dio();

  @override
  Future<MovieHttpResponse> get(
    String url, {
    Map<String, String> headers = const <String, String>{},
    bool followRedirects = true,
  }) async {
    final Uri uri = Uri.parse(url);
    gets.add(uri);
    final MovieHttpResponse Function(Uri uri)? handler = getRoutes[uri.path];
    if (handler != null) return handler(uri);
    return _json(404, <String, String>{'error': 'no route for ${uri.path}'});
  }

  @override
  Future<MovieHttpResponse> post(
    String url, {
    required String body,
    Map<String, String> headers = const <String, String>{},
  }) async {
    posts.add(body);
    final MovieHttpResponse Function(String body)? handler =
        postRoutes[Uri.parse(url).path];
    if (handler != null) return handler(body);
    return _json(404, <String, String>{'error': 'no route'});
  }

  @override
  Future<MovieRangeResponse> getRange(
    String url, {
    Map<String, String> headers = const <String, String>{},
    required int start,
    int? end,
  }) async {
    return MovieRangeResponse(
      statusCode: 416,
      bytes: Uint8List(0),
      headers: const <String, String>{},
      effectiveUrl: url,
    );
  }

  @override
  void close() {}
}

void main() {
  group('Ifallhub catalog', () {
    test('search maps the server items to ifallhub posts', () async {
      final _FakeHubTransport transport = _FakeHubTransport();
      transport.getRoutes['/api/search'] = (Uri uri) => _json(200, <Object>[
            <String, Object>{
              'id': <String, String>{'provider': 'moviebox', 'value': '42'},
              'media_type': 'movie',
              'poster_url': 'https://img.test/avatar.jpg',
              'title': 'Avatar [Hindi]',
              'year': '2009',
            },
            <String, Object>{
              'id': <String, String>{'provider': 'moviebox', 'value': '43'},
              'media_type': 'series',
              'poster_url': null,
              'title': 'Avatar: The Last Airbender',
              'year': '2024',
            },
          ]);

      final IfallhubService service =
          IfallhubService(transport: transport, baseUrl: _base);
      addTearDown(service.dispose);

      final List<MoviePost> posts = await service.searchPosts(query: 'avatar');
      expect(posts, hasLength(2));
      expect(posts.every((MoviePost p) => p.provider == MovieProvider.ifallhub),
          isTrue);
      expect(posts.first.provider.badgeLabel, 'ifallhub');
      expect(posts.first.title, 'Avatar [Hindi]');
      expect(posts.first.imageUrl, 'https://img.test/avatar.jpg');
      expect(posts.first.link, startsWith('$_base/api/details?'));
      final Uri link = Uri.parse(posts.first.link);
      expect(link.queryParameters['provider'], 'moviebox');
      expect(link.queryParameters['id'], '42');
      expect(posts[1].isSeries, isTrue);
      expect(posts[1].badge, 'Series');
      expect(transport.gets.single.path, '/api/search');
      expect(transport.gets.single.queryParameters['q'], 'avatar');
    });

    test('a movie title page lists releases as playable ifallhub qualities',
        () async {
      final _FakeHubTransport transport = _FakeHubTransport();
      transport.getRoutes['/api/details'] = (Uri uri) => _json(200,
          <String, Object>{
            'id': <String, String>{'provider': 'moviebox', 'value': '42'},
            'title': 'Avatar [Hindi]',
            'media_type': 'movie',
            'year': '2009',
            'poster_url': 'https://img.test/avatar.jpg',
            'description': 'A marine on Pandora.',
            'imdb_rating': '7.9',
            'duration': '2h 42m',
            'genres': <String>['Action', 'Sci-Fi'],
            'dubs': <Object>[
              <String, String>{'label': 'Original Audio', 'language': 'en'},
              <String, String>{'label': 'Hindi dub', 'language': 'hi'},
            ],
            'seasons': <Object>[],
          });
      // The title's own catalogue has nothing (the deployment cannot reach
      // its upstream); the server's other catalogue has the film.
      transport.getRoutes['/api/streams'] = (Uri uri) {
        if (uri.queryParameters['provider'] == 'dramachi') {
          return _json(200, <String, Object>{
            'stream_set_id': 'set-1',
            'blocked_addons': <Object>[],
            'releases': <Object>[
              <String, Object>{
                'provider': 'dramachi',
                'filename': 'Avatar_2009_Full.mkv',
                'quality': '720p',
                'codec': null,
                'language': null,
                'size_bytes': 1043500892,
                'season': null,
                'episode': null,
                'mirrors': <Object>[
                  <String, Object>{
                    'label': 'Dramachi CDN',
                    'resolver_url': '',
                    'headers': <Object>[],
                    'direct_file': true,
                  },
                ],
                'resource_id': '533584',
              },
            ],
          });
        }
        return _json(502, <String, String>{'error': 'No playable streams'});
      };
      transport.getRoutes['/api/search'] = (Uri uri) {
        if (uri.queryParameters['provider'] == 'dramachi') {
          return _json(200, <Object>[
            <String, Object>{
              'id': <String, String>{'provider': 'dramachi', 'value': '77'},
              'media_type': 'movie',
              'poster_url': 'https://img.test/a2.jpg',
              'title': 'Avatar 2009',
              'year': '2009',
            },
          ]);
        }
        return _json(200, <Object>[]);
      };

      final IfallhubService service =
          IfallhubService(transport: transport, baseUrl: _base);
      addTearDown(service.dispose);

      final String link = Uri.parse('$_base/api/details').replace(
        queryParameters: <String, String>{
          'provider': 'moviebox',
          'id': '42',
          'title': 'Avatar [Hindi]',
          'year': '2009',
        },
      ).toString();
      final MovieDetail detail = await service.fetchDetail(link);

      expect(detail.provider, MovieProvider.ifallhub);
      expect(detail.isSeries, isFalse);
      expect(detail.title, 'Avatar [Hindi]');
      expect(detail.cleanTitle, 'Avatar');
      expect(detail.year, '2009');
      expect(detail.rating, '7.9');
      expect(detail.genres, contains('Action'));
      expect(detail.languageList, contains('Hindi dub'));
      expect(detail.directQualities, hasLength(1));
      final MovieQualityLink quality = detail.directQualities.single;
      expect(quality.provider, MovieProvider.ifallhub);
      expect(quality.displayQuality, '720p');
      expect(quality.sizeLabel, isNotEmpty);
      expect(quality.dlUrl, startsWith('ifallhub://play?'));
      final Uri play = Uri.parse(quality.dlUrl);
      expect(play.queryParameters['provider'], 'dramachi');
      expect(play.queryParameters['id'], '77');
      expect(play.queryParameters['set'], 'set-1');
      expect(play.queryParameters['name'], 'Avatar_2009_Full.mkv');
    });

    test('series title page builds seasons and expands one episode', () async {
      final _FakeHubTransport transport = _FakeHubTransport();
      transport.getRoutes['/api/details'] = (Uri uri) => _json(200,
          <String, Object>{
            'id': <String, String>{'provider': 'moviebox', 'value': '9'},
            'title': 'Avatar: The Last Airbender S1-S2',
            'media_type': 'series',
            'year': '2024',
            'poster_url': 'https://img.test/tla.jpg',
            'description': 'The Avatar returns.',
            'genres': <String>[],
            'dubs': <Object>[],
            'seasons': <Object>[
              <String, Object>{
                'number': 1,
                'episodes': <Object>[
                  <String, Object>{'number': 1, 'season': 1},
                  <String, Object>{'number': 2, 'season': 1},
                ],
              },
              <String, Object>{
                'number': 2,
                'episodes': <Object>[
                  <String, Object>{'number': 1, 'season': 2},
                ],
              },
            ],
          });
      transport.getRoutes['/api/streams'] = (Uri uri) => _json(200,
          <String, Object>{
            'stream_set_id': 'set-2',
            'releases': <Object>[
              <String, Object>{
                'provider': 'moviebox',
                'filename': 'TLA.S02E01.1080p.mkv',
                'quality': '1080p',
                'codec': 'H.265',
                'language': null,
                'size_bytes': 500000000,
                'season': 2,
                'episode': 1,
                'mirrors': <Object>[
                  <String, Object>{'label': 'Direct', 'resolver_url': ''},
                ],
                'resource_id': null,
              },
            ],
          });

      final IfallhubService service =
          IfallhubService(transport: transport, baseUrl: _base);
      addTearDown(service.dispose);

      final String link = Uri.parse('$_base/api/details').replace(
        queryParameters: <String, String>{
          'provider': 'moviebox',
          'id': '9',
          'title': 'Avatar: The Last Airbender S1-S2',
          'year': '2024',
        },
      ).toString();
      final MovieDetail detail = await service.fetchDetail(link);

      expect(detail.isSeries, isTrue);
      expect(detail.episodeGroups, hasLength(2));
      final MovieEpisodeGroup season = detail.episodeGroups.first;
      expect(season.seasonLabel, 'Season 1');
      expect(season.isLoaded, isTrue);
      expect(season.nestedGroups, hasLength(2));
      expect(season.nestedGroups.first.isLoaded, isFalse);
      expect(season.nestedGroups.first.episodeLabel, 'Episode 1');
      expect(detail.episodeGroups[1].nestedGroups, hasLength(1));

      final MovieEpisodeGroup loaded =
          await service.expandEpisodeGroup(season.nestedGroups.first);
      expect(loaded.isLoaded, isTrue);
      expect(loaded.qualities, hasLength(1));
      expect(loaded.qualities.single.resolution, '1080p');
      expect(loaded.qualities.single.seasonLabel, 'Season 1');
      expect(loaded.qualities.single.episodeLabel, 'Episode 1');
    });

    test('play answers a same-origin media URL and posts the stream set',
        () async {
      final _FakeHubTransport transport = _FakeHubTransport();
      transport.postRoutes['/api/play'] = (String body) {
        final Map<String, dynamic> sent =
            jsonDecode(body) as Map<String, dynamic>;
        expect(sent['stream_set_id'], 'set-1');
        expect(sent['release_index'], 0);
        expect(sent['mirror_index'], 0);
        return _json(200, <String, Object>{
          'playback_url': '/api/media/tok/https/cdn.test/movie.mp4',
          'stream_type': 'file',
          'source_label': 'Direct',
          'quality': '1080p',
          'title': 'movie.mp4',
          'provider': 'dramachi',
        });
      };

      final IfallhubService service =
          IfallhubService(transport: transport, baseUrl: _base);
      addTearDown(service.dispose);

      const MovieQualityLink quality = MovieQualityLink(
        id: 'ifallhub_dramachi_77_0_0_0',
        rawLabel: '1080p',
        resolution: '1080p',
        dlUrl:
            'ifallhub://play?provider=dramachi&id=77&set=set-1&release=0&mirror=0&name=movie.mp4&quality=1080p',
        provider: MovieProvider.ifallhub,
      );

      final ResolvedMovieStream resolved = await service.resolvePlaybackStream(
        quality,
        fallbackTitle: 'Avatar',
      );

      expect(resolved.candidates, hasLength(1));
      expect(
        resolved.candidates.single.url,
        '$_base/api/media/tok/https/cdn.test/movie.mp4',
      );
      expect(resolved.filename, 'movie.mp4');
      expect(resolved.mimeType, 'video/mp4');
      expect(transport.posts, hasLength(1));
    });

    test('an expired stream list is refreshed before playing', () async {
      final _FakeHubTransport transport = _FakeHubTransport();
      transport.getRoutes['/api/streams'] = (Uri uri) => _json(200,
          <String, Object>{
            'stream_set_id': 'set-fresh',
            'releases': <Object>[
              <String, Object>{
                'provider': 'dramachi',
                'filename': 'movie.mp4',
                'quality': '1080p',
                'codec': null,
                'language': null,
                'size_bytes': 100,
                'season': null,
                'episode': null,
                'mirrors': <Object>[
                  <String, Object>{'label': 'Direct', 'resolver_url': ''},
                ],
                'resource_id': null,
              },
            ],
          });
      var calls = 0;
      transport.postRoutes['/api/play'] = (String body) {
        calls++;
        final Map<String, dynamic> sent =
            jsonDecode(body) as Map<String, dynamic>;
        if (sent['stream_set_id'] == 'set-old') {
          return _json(410, <String, String>{'error': 'Stream list expired.'});
        }
        return _json(200, <String, Object>{
          'playback_url': '/api/media/new/https/cdn.test/movie.mp4',
          'stream_type': 'file',
        });
      };

      final IfallhubService service =
          IfallhubService(transport: transport, baseUrl: _base);
      addTearDown(service.dispose);

      const MovieQualityLink quality = MovieQualityLink(
        id: 'ifallhub_dramachi_77_0_0_0',
        rawLabel: '1080p',
        resolution: '1080p',
        dlUrl:
            'ifallhub://play?provider=dramachi&id=77&set=set-old&release=0&mirror=0&name=movie.mp4&quality=1080p',
        provider: MovieProvider.ifallhub,
      );

      final ResolvedMovieStream resolved = await service.resolvePlaybackStream(
        quality,
        fallbackTitle: 'movie',
      );

      expect(calls, 2);
      expect(
        resolved.candidates.single.url,
        '$_base/api/media/new/https/cdn.test/movie.mp4',
      );
    });

    test('download resolution uses the same media URL', () async {
      final _FakeHubTransport transport = _FakeHubTransport();
      transport.postRoutes['/api/play'] = (String body) => _json(200,
          <String, Object>{
            'playback_url': '/api/media/tok/https/cdn.test/movie.mkv',
            'stream_type': 'file',
          });

      final IfallhubService service =
          IfallhubService(transport: transport, baseUrl: _base);
      addTearDown(service.dispose);

      const MovieQualityLink quality = MovieQualityLink(
        id: 'ifallhub_dramachi_77_0_0_0',
        rawLabel: '720p',
        resolution: '720p',
        dlUrl:
            'ifallhub://play?provider=dramachi&id=77&set=set-1&release=0&mirror=0&name=movie.mkv&quality=720p',
        provider: MovieProvider.ifallhub,
      );

      final ResolvedMovieStream resolved = await service.resolveDownloadStream(
        quality,
        fallbackTitle: 'movie',
      );

      expect(resolved.filename, 'movie.mkv');
      expect(resolved.mimeType, 'video/x-matroska');
      expect(
        resolved.candidates.single.url,
        '$_base/api/media/tok/https/cdn.test/movie.mkv',
      );
      expect(resolved.sharePageUrl, '$_base/title/dramachi/77');
    });

    test('ZIP helpers refuse politely — ifallhub has no season archives',
        () async {
      final IfallhubService service = IfallhubService(
        transport: _FakeHubTransport(),
        baseUrl: _base,
      );
      addTearDown(service.dispose);

      const MovieQualityLink pack = MovieQualityLink(
        id: 'ifallhub_pack',
        rawLabel: '1080p',
        resolution: '1080p',
        dlUrl: 'ifallhub://play?provider=moviebox&id=1',
        isZipPack: true,
        provider: MovieProvider.ifallhub,
      );

      await expectLater(
        service.listZipPackEpisodes(pack, fallbackTitle: 'x'),
        throwsStateError,
      );
      await expectLater(
        service.prepareZipEpisodeDownload(pack, fallbackTitle: 'x'),
        throwsStateError,
      );
    });
  });
}
