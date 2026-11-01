import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/movies/models/movie_models.dart';
import 'package:ifallmusic/movies/models/movie_provider.dart';
import 'package:ifallmusic/movies/services/eon_movies_service.dart';
import 'package:ifallmusic/movies/services/hdhub4u_html_parser.dart';
import 'package:ifallmusic/movies/services/hdhub4u_service.dart';
import 'package:ifallmusic/movies/services/movie_http_client.dart';
import 'package:ifallmusic/movies/services/movie_quality_order.dart';
import 'package:ifallmusic/movies/services/movie_source.dart';
import 'package:ifallmusic/movies/services/movies_repository.dart';

const String _base = 'https://new10.hdhub4u.cl';

const String _listingHtml = '''
<html><body>
<div class="recent-movies">
  <div class="movie-card">
    <a href="$_base/obsession-2025-web-dl-1080p/">
      <figure><img src="https://cdn.hdhub4u.cl/p/obsession.jpg" alt="Download Obsession (2025) WEB-DL 1080p" /></figure>
    </a>
    <h3>Obsession (2025)</h3>
  </div>
  <div class="movie-card">
    <a href="$_base/visionquest-season-1-2026-hindi/">
      <figure><img data-src="https://cdn.hdhub4u.cl/p/vision.jpg" alt="Download VisionQuest Season 1 (2026)" /></figure>
    </a>
  </div>
</div>
</body></html>
''';

const String _movieHtml = '''
<html><head>
<meta property="og:image" content="https://cdn.hdhub4u.cl/p/obsession.jpg" />
<meta name="description" content="Obsession 2025 horror movie download" />
</head><body>
<div class="page-body">
  <h1 class="page-title"><span class="material-text">Download Obsession (2025) WEB-DL 1080p</span></h1>
  <p>Obsession is a 2025 horror film about a young woman and a cursed mirror that follows her everywhere she goes.</p>
  <h3>Download Obsession 1080p</h3>
  <p><strong>1080p HEVC 2.1GB</strong> <a href="https://hubcloud.cx/drive/abc1080">Download</a></p>
  <h3>Download Obsession 720p</h3>
  <p><strong>720p HEVC 1.2GB</strong> <a href="https://hubdrive.tools/file/def720">Download</a></p>
  <h3>Download Obsession 480p</h3>
  <p><strong>480p x264 700MB</strong> <a href="https://hubcloud.cx/drive/ghi480">Download</a></p>
</div>
</body></html>
''';

const String _seriesHtml = '''
<html><body>
<div class="page-body">
  <h1 class="page-title"><span class="material-text">Download VisionQuest Season 1 (2026) Hindi Web Series</span></h1>
  <h3>Season 1</h3>
  <h4>VisionQuest Season 1 1080p HEVC</h4>
  <p>Episode 1 : <a href="https://hubcloud.cx/drive/s1e1-1080">1080p</a></p>
  <p>Episode 2 : <a href="https://hubcloud.cx/drive/s1e2-1080">1080p</a></p>
  <h4>VisionQuest Season 1 720p</h4>
  <p>Episode 1 : <a href="https://hubcloud.cx/drive/s1e1-720">720p</a></p>
  <p>Episode 2 : <a href="https://hubcloud.cx/drive/s1e2-720">720p</a></p>
  <h3>Season 1 Complete Pack</h3>
  <p><a href="https://hubcloud.cx/drive/s1-pack-1080.zip">1080p</a></p>
</div>
</body></html>
''';

String _doubleAtob(String value) {
  final String once = base64Encode(utf8.encode(value));
  return base64Encode(utf8.encode(once));
}

class _FakeTransport implements MovieHttpTransport {
  final Map<String, MovieHttpResponse> getRoutes = <String, MovieHttpResponse>{};

  @override
  final Dio streamDio = Dio();

  @override
  Future<MovieHttpResponse> get(
    String url, {
    Map<String, String> headers = const <String, String>{},
    bool followRedirects = true,
  }) async {
    final MovieHttpResponse? hit = getRoutes[url];
    if (hit != null) return hit;
    return MovieHttpResponse(
      statusCode: 404,
      body: '',
      headers: const <String, String>{},
      effectiveUrl: url,
    );
  }

  @override
  Future<MovieHttpResponse> post(
    String url, {
    required String body,
    Map<String, String> headers = const <String, String>{},
  }) async {
    return MovieHttpResponse(
      statusCode: 404,
      body: '',
      headers: const <String, String>{},
      effectiveUrl: url,
    );
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
  group('HDHub4U catalog parsing', () {
    test('listing page yields premium posts', () {
      final List<MoviePost> posts =
          Hdhub4uHtmlParser.parsePosts(_listingHtml, _base);
      expect(posts, hasLength(2));
      expect(posts.first.provider, MovieProvider.hdhub4u);
      expect(posts.first.provider.premium, isTrue);
      expect(posts.first.title, 'Obsession (2025)');
      expect(posts.first.imageUrl, 'https://cdn.hdhub4u.cl/p/obsession.jpg');
      expect(posts.first.link, '$_base/obsession-2025-web-dl-1080p/');
      expect(posts[1].imageUrl, 'https://cdn.hdhub4u.cl/p/vision.jpg');
    });

    test('search endpoint JSON is mapped, not scraped', () {
      final String body = jsonEncode(<String, Object>{
        'hits': <Object>[
          <String, Object>{
            'document': <String, String>{
              'post_title': 'Download Obsession (2025) WEB-DL 1080p',
              'permalink': '/obsession-2025-web-dl-1080p/',
              'post_thumbnail': 'https://cdn.hdhub4u.cl/p/obsession.jpg',
            },
          },
        ],
      });
      final List<MoviePost> posts =
          Hdhub4uHtmlParser.parseSearchJson(body, _base);
      expect(posts, hasLength(1));
      expect(posts.single.title, 'Obsession (2025)');
      expect(posts.single.provider, MovieProvider.hdhub4u);
    });

    test('movie page exposes quality rows, highest first', () {
      final MovieDetail detail = Hdhub4uHtmlParser.parseDetail(
        html: _movieHtml,
        pageUrl: '$_base/obsession-2025-web-dl-1080p/',
        baseUrl: _base,
      );
      expect(detail.provider, MovieProvider.hdhub4u);
      expect(detail.isSeries, isFalse);
      expect(detail.year, '2025');
      expect(
        detail.directQualities
            .map((MovieQualityLink q) => q.resolution)
            .toList(),
        <String>['1080p', '720p', '480p'],
      );
      expect(detail.directQualities.first.codec, 'HEVC');
      expect(detail.directQualities.first.sizeLabel, '2.1 GB');
      expect(detail.directQualities.first.provider, MovieProvider.hdhub4u);
      expect(detail.directQualities.first.isZipPack, isFalse);
      expect(detail.directQualities[1].dlUrl, contains('hubdrive'));
    });

    test('series page builds season → episode groups and a pack group', () {
      final MovieDetail detail = Hdhub4uHtmlParser.parseDetail(
        html: _seriesHtml,
        pageUrl: '$_base/visionquest-season-1/',
        baseUrl: _base,
      );
      expect(detail.isSeries, isTrue);
      expect(detail.episodeGroups, hasLength(1));

      final MovieEpisodeGroup season = detail.episodeGroups.first;
      expect(season.seasonLabel, 'Season 1');
      final List<MovieEpisodeGroup> episodes = season.nestedGroups
          .where((MovieEpisodeGroup g) => !g.isCompletePack)
          .toList();
      expect(episodes, hasLength(2));
      expect(episodes.first.episodeLabel, 'Episode 1');
      expect(episodes.first.fullHeading, 'Season 1 • Episode 1');
      expect(
        episodes.first.qualities
            .map((MovieQualityLink q) => q.resolution)
            .toList(),
        <String>['1080p', '720p'],
      );
      expect(
        episodes.first.qualities.every(
          (MovieQualityLink q) => q.provider == MovieProvider.hdhub4u,
        ),
        isTrue,
      );

      MovieEpisodeGroup? pack;
      for (final MovieEpisodeGroup group in season.nestedGroups) {
        if (group.isCompletePack) pack = group;
      }
      expect(pack, isNotNull);
      expect(pack!.qualities.single.isZipPack, isTrue);
      expect(movieQualityCanStreamOnline(pack.qualities.single), isFalse);
    });
  });

  group('HDHub4U mirror resolution', () {
    test('hubcloud page → vcloud buttons become direct candidates', () async {
      final _FakeTransport transport = _FakeTransport();
      final String vcloudUrl = 'https://hubcloud.cx/vcloud/abc1080';
      transport.getRoutes['https://hubcloud.cx/drive/abc1080'] =
          MovieHttpResponse(
        statusCode: 200,
        body:
            '<html><body><script>var url = atob(atob("${_doubleAtob(vcloudUrl)}"));</script></body></html>',
        headers: const <String, String>{},
        effectiveUrl: 'https://hubcloud.cx/drive/abc1080',
      );
      transport.getRoutes[vcloudUrl] = const MovieHttpResponse(
        statusCode: 200,
        body: '''
<html><body>
<h5>Obsession.2025.1080p.WEB-DL.mkv</h5>
<span>2.1 GB</span>
<a class="btn btn-success btn-lg h6" href="https://pixeldrain.com/u/abc123">Pixeldrain</a>
<a class="btn btn-danger" href="https://r2.cloudflarestorage.com/bucket/obsession.mkv">CF Storage</a>
<a class="btn btn-secondary" href="https://fast-worker.workers.dev/token=abc">CF Worker</a>
</body></html>
''',
        headers: const <String, String>{},
        effectiveUrl: 'https://hubcloud.cx/vcloud/abc1080',
      );

      final Hdhub4uService service = Hdhub4uService(
        transport: transport,
        initialBaseUrl: _base,
      );
      addTearDown(service.dispose);
      final ResolvedMovieStream resolved = await service.resolveDownloadStream(
        const MovieQualityLink(
          id: 'hdh_test',
          rawLabel: '1080p',
          resolution: '1080p',
          dlUrl: 'https://hubcloud.cx/drive/abc1080',
          provider: MovieProvider.hdhub4u,
        ),
        fallbackTitle: 'Obsession',
      );
      final List<String> urls =
          resolved.candidates.map((MovieStreamCandidate c) => c.url).toList();
      expect(
        urls,
        contains('https://r2.cloudflarestorage.com/bucket/obsession.mkv'),
      );
      expect(urls, contains('https://pixeldrain.com/api/file/abc123?download'));
      expect(urls, contains('https://fast-worker.workers.dev/token=abc'));
      expect(resolved.candidates.first.server, 'Cloudflare Storage');
      expect(resolved.filename, contains('Obsession.2025.1080p.WEB-DL.mkv'));
      expect(resolved.sizeLabel, '2.1 GB');
    });

    test('a direct file link needs no extraction', () async {
      final Hdhub4uService service = Hdhub4uService(
        transport: _FakeTransport(),
        initialBaseUrl: _base,
      );
      addTearDown(service.dispose);
      final ResolvedMovieStream resolved = await service.resolveDownloadStream(
        const MovieQualityLink(
          id: 'hdh_direct',
          rawLabel: '720p',
          resolution: '720p',
          dlUrl: 'https://cdn.hubcdn.lat/movies/obsession-720p.mkv',
          provider: MovieProvider.hdhub4u,
        ),
        fallbackTitle: 'Obsession',
      );
      expect(
        resolved.candidates.single.url,
        'https://cdn.hubcdn.lat/movies/obsession-720p.mkv',
      );
      expect(resolved.mimeType, 'video/x-matroska');
    });
  });

  group('MoviesRepository', () {
    test('search keeps both catalogs and marks the premium one', () async {
      final _FakeTransport transport = _FakeTransport();
      transport.getRoutes[
              'https://new4.eonmovies.click/?action=search&page=1&name=obsession'] =
          const MovieHttpResponse(
        statusCode: 200,
        body: '''
<html><body>
<a href="https://new4.eonmovies.click/obsession-movie">
  <div class="image-container">
    <img src="https://new4.eonmovies.click/p/eon-obsession.jpg" alt="Obsession" />
    <span class="card-title">Obsession</span>
  </div>
</a>
</body></html>
''',
        headers: const <String, String>{},
        effectiveUrl: 'https://new4.eonmovies.click/',
      );
      transport.getRoutes['$_base/?s=obsession'] = MovieHttpResponse(
        statusCode: 200,
        body: _listingHtml,
        headers: const <String, String>{},
        effectiveUrl: '$_base/',
      );

      final MoviesRepository repository = MoviesRepository(
        eon: EonMoviesService(transport: transport),
        hdhub4u: Hdhub4uService(
          transport: transport,
          initialBaseUrl: _base,
        ),
        includePremiumProvider: true,
      );
      addTearDown(repository.dispose);

      final List<MoviePost> posts = await repository.search(query: 'obsession');
      expect(posts, hasLength(3));
      expect(
        posts.where((MoviePost p) => p.provider == MovieProvider.eonMovies),
        hasLength(1),
      );
      final List<MoviePost> premium =
          posts.where((MoviePost p) => p.provider.premium).toList();
      expect(premium, hasLength(2));
      expect(premium.every((MoviePost p) => p.provider.premium), isTrue);
      expect(
        premium.any((MoviePost p) => p.title == 'Obsession (2025)'),
        isTrue,
      );
      expect(
        premium.any((MoviePost p) => p.title.contains('VisionQuest')),
        isTrue,
      );
      // eon rows come first, premium rows are appended after them.
      expect(posts.first.provider, MovieProvider.eonMovies);
    });

    test('premium catalog is skipped when the repository is eon-only', () async {
      final MoviesRepository repository = MoviesRepository(
        eon: EonMoviesService(transport: _FakeTransport()),
        hdhub4u: Hdhub4uService(
          transport: _FakeTransport(),
          initialBaseUrl: _base,
        ),
        includePremiumProvider: false,
      );
      addTearDown(repository.dispose);
      expect(await repository.fetchPremiumPosts(), isEmpty);
      expect(await repository.search(query: 'obsession'), isEmpty);
    });

    test('repository routes each quality to its own catalog', () async {
      final MoviesRepository repository = MoviesRepository(
        eon: EonMoviesService(transport: _FakeTransport()),
        hdhub4u: Hdhub4uService(
          transport: _FakeTransport(),
          initialBaseUrl: _base,
        ),
        includePremiumProvider: false,
      );
      addTearDown(repository.dispose);
      expect(
        repository.sourceFor(MovieProvider.eonMovies).provider,
        MovieProvider.eonMovies,
      );
      expect(
        repository.sourceFor(MovieProvider.hdhub4u).provider,
        MovieProvider.hdhub4u,
      );
    });

    test('quality ordering walks from the lightest stream up', () {
      final List<MovieQualityLink> qualities = <MovieQualityLink>[
        const MovieQualityLink(
          id: 'a',
          rawLabel: '1080p',
          resolution: '1080p',
          dlUrl: 'https://x/1080.mkv',
        ),
        const MovieQualityLink(
          id: 'b',
          rawLabel: '480p',
          resolution: '480p',
          dlUrl: 'https://x/480.mkv',
          provider: MovieProvider.hdhub4u,
        ),
        const MovieQualityLink(
          id: 'c',
          rawLabel: '720p',
          resolution: '720p',
          dlUrl: 'https://x/720.mkv',
        ),
        const MovieQualityLink(
          id: 'zip',
          rawLabel: '1080p',
          resolution: '1080p',
          dlUrl: 'https://x/pack.zip',
          isZipPack: true,
        ),
      ];
      expect(
        playableQualitiesLowestFirst(qualities)
            .map((MovieQualityLink q) => q.id)
            .toList(),
        <String>['b', 'c', 'a'],
      );
      expect(lowestPlayableQuality(qualities)?.id, 'b');
      expect(highestPlayableQuality(qualities)?.id, 'a');
    });
  });
}
