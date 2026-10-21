import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ifallmusic/core/services/library_service.dart';
import 'package:ifallmusic/core/services/music_download_service.dart';
import 'package:ifallmusic/core/services/settings_service.dart';
import 'package:ifallmusic/core/theme/sidify_theme.dart';
import 'package:ifallmusic/movies/models/movie_models.dart';
import 'package:ifallmusic/movies/services/eon_html_parser.dart';
import 'package:ifallmusic/movies/services/eon_movies_service.dart';
import 'package:ifallmusic/movies/services/movie_download_service.dart';
import 'package:ifallmusic/movies/services/movie_http_client.dart';
import 'package:ifallmusic/movies/ui/search_hub_page.dart';
import 'package:ifallmusic/ui/shell/sidify_shell_controller.dart';

class _FakeMovieTransport implements MovieHttpTransport {
  final Map<String, MovieHttpResponse> getRoutes = <String, MovieHttpResponse>{};
  final Map<String, MovieHttpResponse Function(String body, Map<String, String> headers)>
      postRoutes =
      <String, MovieHttpResponse Function(String body, Map<String, String> headers)>{};
  final List<String> requestedUrls = <String>[];

  @override
  final Dio streamDio = Dio();

  @override
  Future<MovieHttpResponse> get(
    String url, {
    Map<String, String> headers = const <String, String>{},
    bool followRedirects = true,
  }) async {
    requestedUrls.add(url);
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
    final MovieHttpResponse Function(String, Map<String, String>)? handler =
        postRoutes[url];
    if (handler != null) {
      return handler(body, headers);
    }
    return MovieHttpResponse(
      statusCode: 404,
      body: '',
      headers: const <String, String>{},
      effectiveUrl: url,
    );
  }

  @override
  void close() {}
}

const String _baseUrl = 'https://new4.eonmovies.click';

const String _sampleCatalogHtml = '''
<!doctype html>
<html><body>
  <a href="/visionquest-season-1-episode-4-added-2026-3553">
    <div class="image-container">
      <span class="badge">Series</span>
      <img alt="VisionQuest - Season 1" src="" />
    </div>
    <div class="card-title">VisionQuest - Season 1</div>
    <div class="card-meta">2026 • S01 E04</div>
  </a>
  <a href="/pushpa-2-the-rule-2024-3617">
    <div class="image-container">
      <span class="badge">Movie</span>
      <img alt="Pushpa 2 - The Rule" src="" />
    </div>
    <div class="card-title">Pushpa 2 - The Rule</div>
    <div class="card-meta">2024</div>
  </a>
</body></html>
''';

const String _sampleMovieDetailHtml = '''
<!doctype html>
<html>
<head>
  <title>Download Pushpa 2 - The Rule (2024) WEB-DL [Hindi,Telugu] 540p 720p &amp; 1080p Movie</title>
  <meta property="og:title" content="Pushpa 2 - The Rule (2024) - Download in HD | EonMovies" />
</head>
<body>
  <div id="heroBackdrop" style="background-image:url('https://image.tmdb.org/t/p/w780/backdrop.jpg')"></div>
  <h1>Pushpa 2 - The Rule (2024)</h1>
  <div class="meta-pills">
    <span class="meta-pill">3 Dec 2024</span>
    <span class="meta-pill">Movie</span>
    <span class="meta-pill">WEB-DL</span>
    <span class="meta-pill">Hindi, Telugu</span>
  </div>
  <div id="movieGenresBox">
    <span class="genre-pill">Drama</span>
    <span class="genre-pill">Action</span>
  </div>
  <p class="overview-text">Pushpa expands his rule across borders.</p>
  <h2>Download Pushpa 2 - The Rule (2024) WEB-DL in Hindi, Telugu</h2>
  <div class="dl-row" data-dlname="540p">
    <span class="dl-row-name">540p</span>
    <span>1.11 GB</span>
    <a href="/dl/35620">Download</a>
  </div>
  <div class="dl-row" data-dlname="1080p HEVC">
    <span class="dl-row-name">1080p HEVC</span>
    <span>3.52 GB</span>
    <a href="/dl/35624">Download</a>
  </div>
</body>
</html>
''';

const String _sampleSeriesDetailHtml = '''
<!doctype html>
<html>
<head>
  <title>Download VisionQuest - Season 1 [Episode 4 Added] (2026) WEB-DL [Hindi,English] Series</title>
  <meta property="og:title" content="VisionQuest - Season 1 (2026) - Download in HD | EonMovies" />
</head>
<body>
  <h1>VisionQuest - Season 1 [Episode 4 Added] (2026)</h1>
  <div class="meta-pills">
    <span class="meta-pill">12 Oct 2026</span>
    <span class="meta-pill">Series</span>
    <span class="meta-pill">Hindi, English</span>
  </div>
  <div id="movieGenresBox">
    <span class="genre-pill">Sci-Fi</span>
  </div>
  <p class="overview-text">Vision quests for identity and memory.</p>
  <div class="dl-row" data-dlname="Episode 1">
    <span class="dl-row-name">Episode 1</span>
    <a href="/dl/34936">Download</a>
  </div>
  <div class="dl-row" data-dlname="Episode 2">
    <span class="dl-row-name">Episode 2</span>
    <a href="/dl/34937">Download</a>
  </div>
</body>
</html>
''';

const String _sampleEp1SubPageHtml = '''
<!doctype html>
<html>
<head><title>VisionQuest - Season 1 (2026) [Hindi, English] - Episode 1 - EonMovies</title></head>
<body>
  <h1>VisionQuest - Season 1 - Episode 1</h1>
  <div class="dl-row" data-dlname="480p HEVC">
    <span class="dl-row-name">480p HEVC</span>
    <span>204.3 MB</span>
    <a href="/dl/34938">Download</a>
  </div>
  <div class="dl-row" data-dlname="720p HEVC">
    <span class="dl-row-name">720p HEVC</span>
    <span>419.94 MB</span>
    <a href="/dl/34939">Download</a>
  </div>
</body>
</html>
''';

const String _sampleEp2SubPageHtml = '''
<!doctype html>
<html>
<head><title>VisionQuest - Season 1 (2026) [Hindi, English] - Episode 2 - EonMovies</title></head>
<body>
  <h1>VisionQuest - Season 1 - Episode 2</h1>
  <div class="dl-row" data-dlname="720p HEVC">
    <span class="dl-row-name">720p HEVC</span>
    <span>410.0 MB</span>
    <a href="/dl/34940">Download</a>
  </div>
</body>
</html>
''';

const String _sampleLinksBoxHtml = '''
<!doctype html>
<html><body>
  <h2>VisionQuest.S01E01.480p.WEB-DL.Hindi.AAC2.0-English.AAC2.0.H.265-EonMovies.Com.mkv</h2>
  <p>Size: 204.3 MB | Type: video/x-matroska</p>
  <a href="/dl/99001">TMBCLOUD</a>
  <a href="/dl/99002">DOTFLIX</a>
</body></html>
''';

void main() {
  group('EonMovies HTML & Dotflix parser + stream resolver', () {
    test('parses catalog posts and rewrites blocked TMDB image URLs', () {
      const String htmlWithBothImages = '''
      <a href="/pushpa-2-the-rule-2024-3617">
        <div class="image-container">
          <span>Movie</span>
          <img alt="Pushpa 2 - The Rule" data-src="https://image.tmdb.org/t/p/w500/poster.jpg" />
        </div>
        <div class="card-title">Pushpa 2 - The Rule</div>
        <div>2024</div>
      </a>
      ''';

      final List<MoviePost> posts =
          EonHtmlParser.parsePostList(htmlWithBothImages, _baseUrl);
      expect(posts, hasLength(1));
      expect(posts.first.title, 'Pushpa 2 - The Rule');
      expect(
        posts.first.imageUrl,
        'https://new4.eonmovies.click/img/t/p/w500/poster.jpg',
      );
      expect(
        posts.first.fallbackImageUrl,
        'https://image.tmdb.org/t/p/w500/poster.jpg',
      );
    });

    test('parses movie detail languages and quality-wise download links', () {
      final MovieDetail movie = EonHtmlParser.parseDetail(
        _sampleMovieDetailHtml,
        pageUrl: '$_baseUrl/pushpa-2-the-rule-2024-3617',
        baseUrl: _baseUrl,
      );

      expect(movie.isSeries, isFalse);
      expect(movie.languages, 'Hindi, Telugu');
      expect(movie.genres, <String>['Drama', 'Action']);
      expect(movie.directQualities, hasLength(2));
      expect(movie.directQualities.first.displayQuality, '540p');
      expect(movie.directQualities.first.sizeLabel, '1.11 GB');
      expect(movie.directQualities.last.displayQuality, '1080p HEVC');
      expect(movie.directQualities.last.languages, 'Hindi, Telugu');
    });

    test('expands series seasons & episodes and extracts multi-mirror CDN links',
        () async {
      final _FakeMovieTransport transport = _FakeMovieTransport();
      transport.getRoutes['$_baseUrl/visionquest-season-1-episode-4-added-2026-3553'] =
          const MovieHttpResponse(
        statusCode: 200,
        body: _sampleSeriesDetailHtml,
        headers: <String, String>{},
        effectiveUrl:
            '$_baseUrl/visionquest-season-1-episode-4-added-2026-3553',
      );
      transport.getRoutes['$_baseUrl/dl/34936'] = const MovieHttpResponse(
        statusCode: 302,
        body: '',
        headers: <String, String>{'location': '/page/1990'},
        effectiveUrl: '$_baseUrl/dl/34936',
      );
      transport.getRoutes['$_baseUrl/page/1990'] = const MovieHttpResponse(
        statusCode: 200,
        body: _sampleEp1SubPageHtml,
        headers: <String, String>{},
        effectiveUrl: '$_baseUrl/page/1990',
      );
      transport.getRoutes['$_baseUrl/dl/34937'] = const MovieHttpResponse(
        statusCode: 302,
        body: '',
        headers: <String, String>{'location': '/page/1991'},
        effectiveUrl: '$_baseUrl/dl/34937',
      );
      transport.getRoutes['$_baseUrl/page/1991'] = const MovieHttpResponse(
        statusCode: 200,
        body: _sampleEp2SubPageHtml,
        headers: <String, String>{},
        effectiveUrl: '$_baseUrl/page/1991',
      );

      // Link box -> DOTFLIX mirror -> Dotflix Cloudflare R2 + Pixeldrain
      transport.getRoutes['$_baseUrl/dl/34938'] = const MovieHttpResponse(
        statusCode: 302,
        body: '',
        headers: <String, String>{'location': '/links/AbcFrDGzpp'},
        effectiveUrl: '$_baseUrl/dl/34938',
      );
      transport.getRoutes['$_baseUrl/links/AbcFrDGzpp'] = const MovieHttpResponse(
        statusCode: 200,
        body: _sampleLinksBoxHtml,
        headers: <String, String>{},
        effectiveUrl: '$_baseUrl/links/AbcFrDGzpp',
      );
      transport.getRoutes['$_baseUrl/dl/99002'] = const MovieHttpResponse(
        statusCode: 302,
        body: '',
        headers: <String, String>{
          'location': 'https://dotflix.fit/share/9E24F352',
        },
        effectiveUrl: '$_baseUrl/dl/99002',
      );
      transport.getRoutes['https://dotflix.fit/api/secure-cloudflare-url/9E24F352'] =
          MovieHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object>{
          'success': true,
          'data': <String, String>{
            'cloudflare_url':
                'https://pub-cdn.r2.dev/VisionQuest.S01E01.480p.mkv',
          },
        }),
        headers: const <String, String>{},
        effectiveUrl: 'https://dotflix.fit/api/secure-cloudflare-url/9E24F352',
      );
      final String escapedRsc = jsonEncode(
        '1:{"initialShareData":{"filename":"VisionQuest.S01E01.480p.mkv","formattedFileSize":"204.3 MB","pixeldrainLink":"https://pixeldrain.com/u/XYZ123"}}',
      );
      transport.getRoutes['https://dotflix.fit/share/9E24F352'] =
          MovieHttpResponse(
        statusCode: 200,
        body: '<script>self.__next_f.push([1,$escapedRsc])</script>',
        headers: const <String, String>{},
        effectiveUrl: 'https://dotflix.fit/share/9E24F352',
      );

      final EonMoviesService svc = EonMoviesService(transport: transport);
      final MovieDetail series = await svc.fetchDetail(
        '/visionquest-season-1-episode-4-added-2026-3553',
      );

      expect(series.isSeries, isTrue);
      expect(series.languages, 'Hindi, English');
      expect(series.episodeGroups, hasLength(2));
      expect(series.episodeGroups.first.fullHeading, 'Season 1 • Episode 1');
      expect(series.episodeGroups.first.qualities, hasLength(2));
      expect(
        series.episodeGroups.first.qualities.first.displayQuality,
        '480p HEVC',
      );

      final ResolvedMovieStream stream = await svc.resolveDownloadStream(
        series.episodeGroups.first.qualities.first,
        fallbackTitle: series.cleanTitle,
      );
      expect(stream.filename, 'VisionQuest.S01E01.480p.mkv');
      expect(
        stream.candidates.map((MovieStreamCandidate c) => c.url),
        containsAll(<String>[
          'https://pub-cdn.r2.dev/VisionQuest.S01E01.480p.mkv',
          'https://pixeldrain.com/api/file/XYZ123?download',
        ]),
      );
    });
  });

  group('MovieDownloadService failover + UI end-to-end flow', () {
    test('fails over cleanly when mirror 1 returns HTML and saves binary file',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Directory tempDir = await Directory.systemTemp.createTemp('movie_dl_');
      addTearDown(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });

      final _FakeMovieTransport transport = _FakeMovieTransport();
      transport.getRoutes['$_baseUrl/dl/35620'] = const MovieHttpResponse(
        statusCode: 302,
        body: '',
        headers: <String, String>{
          'location': 'https://dotflix.fit/share/ABCDEF12',
        },
        effectiveUrl: '$_baseUrl/dl/35620',
      );
      transport.getRoutes['https://dotflix.fit/api/secure-cloudflare-url/ABCDEF12'] =
          MovieHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object>{
          'success': true,
          'data': <String, String>{
            'cloudflare_url': 'https://mirror1.invalid/broken',
          },
        }),
        headers: const <String, String>{},
        effectiveUrl: 'https://dotflix.fit/api/secure-cloudflare-url/ABCDEF12',
      );
      final String escaped = jsonEncode(
        '1:{"initialShareData":{"filename":"Pushpa.2.540p.mkv","formattedFileSize":"1.11 GB","pixeldrainLink":"https://pixeldrain.com/u/GOOD999"}}',
      );
      transport.getRoutes['https://dotflix.fit/share/ABCDEF12'] =
          MovieHttpResponse(
        statusCode: 200,
        body: '<script>self.__next_f.push([1,$escaped])</script>',
        headers: const <String, String>{},
        effectiveUrl: 'https://dotflix.fit/share/ABCDEF12',
      );

      final EonMoviesService svc = EonMoviesService(transport: transport);
      final List<int> payload = List<int>.filled(4096, 0x42);

      final MovieDownloadService downloader =
          await MovieDownloadService.create(
        prefs,
        moviesService: svc,
        customDirectory: tempDir,
        streamOpener: ({
          required String url,
          required Map<String, String> headers,
          required CancelToken cancelToken,
        }) async {
          if (url.contains('mirror1.invalid')) {
            return OpenedByteStream(
              statusCode: 200,
              contentType: 'text/html; charset=utf-8',
              contentLength: 20,
              stream: Stream<List<int>>.value('<html>error</html>'.codeUnits),
            );
          }
          return OpenedByteStream(
            statusCode: 200,
            contentType: 'application/octet-stream',
            contentLength: payload.length,
            stream: Stream<List<int>>.value(payload),
          );
        },
      );

      final MovieDetail detail = EonHtmlParser.parseDetail(
        _sampleMovieDetailHtml,
        pageUrl: '$_baseUrl/pushpa-2-the-rule-2024-3617',
        baseUrl: _baseUrl,
      );

      await downloader.enqueueDownload(
        detail: detail,
        quality: detail.directQualities.first,
      );

      for (int i = 0; i < 40; i++) {
        if (downloader.items.first.status == MovieDownloadStatus.completed) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      final MovieDownloadItem finished = downloader.items.first;
      expect(finished.status, MovieDownloadStatus.completed);
      expect(finished.activeServer, 'Pixeldrain High-Speed');
      expect(File(finished.savedPath).lengthSync(), 4096);
      downloader.dispose();
    });

    testWidgets(
        'SearchHubPage shows Music vs Movies chooser, browse/search, series seasons & episodes, languages, and downloads page',
        (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1170, 2532);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Directory tempDir = await tester.runAsync(
        () => Directory.systemTemp.createTemp('movie_ui_test_'),
      ) as Directory;
      addTearDown(() async {
        await tester.runAsync(() async {
          if (tempDir.existsSync()) {
            await tempDir.delete(recursive: true);
          }
        });
      });

      final _FakeMovieTransport transport = _FakeMovieTransport();
      transport.getRoutes['$_baseUrl/?action=&page=1&name=&category='] =
          const MovieHttpResponse(
        statusCode: 200,
        body: _sampleCatalogHtml,
        headers: <String, String>{},
        effectiveUrl: '$_baseUrl/',
      );
      transport.getRoutes['$_baseUrl/?action=search&page=1&name=vision'] =
          const MovieHttpResponse(
        statusCode: 200,
        body: _sampleCatalogHtml,
        headers: <String, String>{},
        effectiveUrl: '$_baseUrl/?action=search&page=1&name=vision',
      );
      transport.getRoutes[
              '$_baseUrl/visionquest-season-1-episode-4-added-2026-3553'] =
          const MovieHttpResponse(
        statusCode: 200,
        body: _sampleSeriesDetailHtml,
        headers: <String, String>{},
        effectiveUrl:
            '$_baseUrl/visionquest-season-1-episode-4-added-2026-3553',
      );
      transport.getRoutes['$_baseUrl/dl/34936'] = const MovieHttpResponse(
        statusCode: 302,
        body: '',
        headers: <String, String>{'location': '/page/1990'},
        effectiveUrl: '$_baseUrl/dl/34936',
      );
      transport.getRoutes['$_baseUrl/page/1990'] = const MovieHttpResponse(
        statusCode: 200,
        body: _sampleEp1SubPageHtml,
        headers: <String, String>{},
        effectiveUrl: '$_baseUrl/page/1990',
      );
      transport.getRoutes['$_baseUrl/dl/34937'] = const MovieHttpResponse(
        statusCode: 302,
        body: '',
        headers: <String, String>{'location': '/page/1991'},
        effectiveUrl: '$_baseUrl/dl/34937',
      );
      transport.getRoutes['$_baseUrl/page/1991'] = const MovieHttpResponse(
        statusCode: 200,
        body: _sampleEp2SubPageHtml,
        headers: <String, String>{},
        effectiveUrl: '$_baseUrl/page/1991',
      );
      transport.getRoutes['$_baseUrl/dl/34938'] = const MovieHttpResponse(
        statusCode: 302,
        body: '',
        headers: <String, String>{
          'location': 'https://dotflix.fit/share/9E24F352',
        },
        effectiveUrl: '$_baseUrl/dl/34938',
      );
      transport.getRoutes[
              'https://dotflix.fit/api/secure-cloudflare-url/9E24F352'] =
          MovieHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object>{
          'success': true,
          'data': <String, String>{
            'cloudflare_url': 'https://pub-cdn.r2.dev/ep1.mkv',
          },
        }),
        headers: const <String, String>{},
        effectiveUrl: 'https://dotflix.fit/api/secure-cloudflare-url/9E24F352',
      );

      final EonMoviesService moviesService =
          EonMoviesService(transport: transport);
      final MovieDownloadService movieDownloads =
          await MovieDownloadService.create(
        prefs,
        moviesService: moviesService,
        customDirectory: tempDir,
        streamOpener: ({
          required String url,
          required Map<String, String> headers,
          required CancelToken cancelToken,
        }) async {
          return OpenedByteStream(
            statusCode: 200,
            contentType: 'video/x-matroska',
            contentLength: 2048,
            stream: Stream<List<int>>.value(List<int>.filled(2048, 0x1A)),
          );
        },
      );
      final SidifyShellController shell = SidifyShellController()..goSearch();

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SettingsService>(
              create: (_) => SettingsService(prefs),
            ),
            ChangeNotifierProvider<LibraryService>(
              create: (_) => LibraryService(prefs),
            ),
            ChangeNotifierProvider<MusicDownloadService>(
              create: (_) => MusicDownloadService(prefs: prefs),
            ),
            ChangeNotifierProvider<MovieDownloadService>.value(
              value: movieDownloads,
            ),
            Provider<EonMoviesService>.value(value: moviesService),
            ChangeNotifierProvider<SidifyShellController>.value(value: shell),
          ],
          child: MaterialApp(
            theme: SidifyTheme.dark,
            home: const Scaffold(body: SearchHubPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 1. Search chooser displays Music and Movies & Series options
      expect(find.byKey(const ValueKey<String>('search-choice-music')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('search-choice-movies')), findsOneWidget);

      // 2. Tap Movies & Series -> opens Movies hub with Search bar + Recommended grid
      await tester.tap(find.byKey(const ValueKey<String>('search-choice-movies')));
      await tester.pumpAndSettle();

      expect(find.text('Recommended Movies & Series'), findsOneWidget);
      expect(find.text('VisionQuest - Season 1'), findsOneWidget);

      // 3. Test live search input
      await tester.enterText(find.byType(TextField), 'vision');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();
      expect(find.text('Search Results for "vision"'), findsOneWidget);

      // 4. Open Series detail -> shows Languages, Season & Episode names, and Qualities
      await tester.tap(find.text('VisionQuest - Season 1'));
      await tester.pumpAndSettle();

      expect(find.text('Hindi, English'), findsWidgets);
      expect(find.text('Season 1 • Episode 1'), findsOneWidget);
      expect(find.text('480p HEVC'), findsOneWidget);

      // 5. Start quality download & open Movie Downloads page
      await tester.ensureVisible(find.text('Download').first);
      await tester.tap(find.text('Download').first);
      for (int i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump();
        if (movieDownloads.items.isNotEmpty &&
            movieDownloads.items.first.status ==
                MovieDownloadStatus.completed) {
          break;
        }
      }
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.text('Downloads').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Movie Downloads'), findsOneWidget);
      expect(find.text('Play Video'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      movieDownloads.dispose();
      shell.dispose();
    });
  });
}
