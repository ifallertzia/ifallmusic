import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ifallmusic/core/services/native_bridge.dart';
import 'package:ifallmusic/core/services/settings_service.dart';
import 'package:ifallmusic/core/theme/sidify_theme.dart';
import 'package:ifallmusic/movies/models/movie_models.dart';
import 'package:ifallmusic/movies/services/eon_movies_service.dart';
import 'package:ifallmusic/movies/services/movie_catalog_filters.dart';
import 'package:ifallmusic/movies/services/movie_download_service.dart';
import 'package:ifallmusic/movies/services/movie_http_client.dart';
import 'package:ifallmusic/movies/services/movie_library_service.dart';
import 'package:ifallmusic/movies/ui/movie_settings_page.dart';
import 'package:ifallmusic/movies/ui/movie_ui_widgets.dart';
import 'package:ifallmusic/movies/ui/movies_explore_page.dart';
import 'package:ifallmusic/ui/shell/sidify_shell_controller.dart';

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
      statusCode: 404,
      bytes: Uint8List(0),
      headers: const <String, String>{},
      effectiveUrl: url,
    );
  }

  @override
  void close() {}
}

const String _baseUrl = 'https://new4.eonmovies.click';

const String _catalogHtml = '''
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

MovieQualityLink _quality(
  String id,
  String resolution, {
  bool zip = false,
  String zipEntry = '',
  String size = '1 GB',
}) {
  return MovieQualityLink(
    id: id,
    rawLabel: resolution,
    resolution: resolution,
    dlUrl: '$_baseUrl/dl/$id',
    sizeLabel: size,
    isZipPack: zip,
    zipEntryName: zipEntry,
  );
}

void main() {
  group('Explore catalog filters', () {
    const MoviePost movie = MoviePost(
      title: 'Pushpa 2 - The Rule',
      link: '/pushpa-2-the-rule-2024-3617',
      imageUrl: '',
      badge: 'Movie',
      subtitle: '2024',
    );
    const MoviePost series = MoviePost(
      title: 'VisionQuest - Season 1',
      link: '/visionquest-season-1-episode-4-added-2026-3553',
      imageUrl: '',
      badge: 'Series',
      subtitle: '2026 • S01 E04',
    );

    test('year comes from catalog subtitle/title data', () {
      expect(moviePostYear(movie), 2024);
      expect(moviePostYear(series), 2026);
      expect(moviePostYears(<MoviePost>[movie, series]), <int>[2026, 2024]);
    });

    test('type and year filters actually narrow the catalog', () {
      const List<MoviePost> posts = <MoviePost>[movie, series];
      expect(
        filterMoviePosts(posts, type: MovieExploreType.series),
        <MoviePost>[series],
      );
      expect(
        filterMoviePosts(posts, type: MovieExploreType.movies),
        <MoviePost>[movie],
      );
      expect(filterMoviePosts(posts, year: 2024), <MoviePost>[movie]);
      expect(filterMoviePosts(posts, year: 1999), isEmpty);
    });

    test('language and genre match real detail metadata only', () {
      const MovieDetail detail = MovieDetail(
        title: 'Pushpa 2 - The Rule',
        cleanTitle: 'Pushpa 2 - The Rule',
        type: MovieMediaType.movie,
        webUrl: '/pushpa-2-the-rule-2024-3617',
        languages: 'Hindi, Telugu',
        languageList: <String>['Hindi', 'Telugu'],
        genres: <String>['Action', 'Drama'],
      );
      expect(movieDetailMatchesExplore(detail, language: 'Telugu'), isTrue);
      expect(movieDetailMatchesExplore(detail, language: 'Tamil'), isFalse);
      expect(movieDetailMatchesExplore(detail, genre: 'Action'), isTrue);
      expect(movieDetailMatchesExplore(detail, genre: 'Horror'), isFalse);
      expect(
        movieDetailMatchesExplore(detail, language: 'Hindi', genre: 'Drama'),
        isTrue,
      );
    });
  });

  group('Playback quality helpers', () {
    test('lowest playable quality skips ZIP packs and ZIP entries', () {
      final List<MovieQualityLink> qualities = <MovieQualityLink>[
        _quality('a', '1080p'),
        _quality('b', '480p', zip: true),
        _quality('c', '720p', zipEntry: 'S01E01.mkv'),
        _quality('d', '540p'),
      ];
      expect(lowestPlayableQuality(qualities)?.id, 'd');
      expect(
        lowestPlayableQuality(<MovieQualityLink>[_quality('z', '480p', zip: true)]),
        isNull,
      );
      expect(movieQualityRank(_quality('x', '720p HEVC')), 720);
    });
  });

  group('Movie library persistence', () {
    test('watchlist and history survive a service restart', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      const MoviePost post = MoviePost(
        title: 'Pushpa 2 - The Rule',
        link: '/pushpa-2-the-rule-2024-3617',
        imageUrl: 'https://img/poster.jpg',
        badge: 'Movie',
        subtitle: '2024',
      );
      final MovieLibraryService first = MovieLibraryService(prefs);
      await first.toggleWatchlist(post);
      await first.recordOpened(post);
      first.dispose();

      final MovieLibraryService second = MovieLibraryService(prefs);
      expect(second.contains(post), isTrue);
      expect(second.watchlist.single.link, post.link);
      expect(second.history.single.link, post.link);
      await second.toggleWatchlist(post);
      expect(second.contains(post), isFalse);
      second.dispose();
    });
  });

  group('Shell navigation for movies mode', () {
    test('downloads tab appended without shifting existing indices', () {
      expect(SidifyTab.home.index, 0);
      expect(SidifyTab.together.index, 4);
      expect(SidifyTab.downloads.index, 5);
    });

    test('movies mode search is direct and mode choice persists', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final SidifyShellController shell = SidifyShellController(prefs);
      await shell.chooseMode(movies: true);
      shell.goSearch('pushpa');
      expect(shell.tab, SidifyTab.search);
      expect(shell.searchMode, SearchMode.movies);
      shell.goDownloads();
      expect(shell.tab, SidifyTab.downloads);
      shell.dispose();

      final SidifyShellController restored = SidifyShellController(prefs);
      expect(restored.hasModeChoice, isTrue);
      expect(restored.isMoviesMode, isTrue);
      restored.dispose();
    });
  });

  test('LocalVideoFile parses MediaStore bridge maps', () {
    final LocalVideoFile file = LocalVideoFile.fromMap(<Object?, Object?>{
      'id': 42,
      'title': 'Clip',
      'path': '/storage/emulated/0/Movies/clip.mp4',
      'durationMs': 95000,
      'size': 2048000,
      'dateAdded': 1700000000,
      'mimeType': 'video/mp4',
      'width': 1920,
      'height': 1080,
    });
    expect(file.id, 42);
    expect(file.path, '/storage/emulated/0/Movies/clip.mp4');
    expect(file.durationMs, 95000);
    expect(file.height, 1080);
  });

  testWidgets('MovieSettingsPage offers theme and update check', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SidifyShellController shell = SidifyShellController(prefs);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>(
            create: (_) => SettingsService(prefs),
          ),
          ChangeNotifierProvider<SidifyShellController>.value(value: shell),
        ],
        child: MaterialApp(
          theme: SidifyTheme.dark,
          home: const MovieSettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Settings'), findsWidgets);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('Accent colour'), findsOneWidget);
    expect(find.text('Check for update'), findsOneWidget);
    shell.dispose();
  });

  testWidgets('Explore filters the catalog by type', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Directory tempDir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('explore_test_'),
    ) as Directory;
    addTearDown(() async {
      await tester.runAsync(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });
    });

    final _FakeTransport transport = _FakeTransport();
    transport.getRoutes['$_baseUrl/?action=&page=1&name=&category='] =
        const MovieHttpResponse(
      statusCode: 200,
      body: _catalogHtml,
      headers: <String, String>{},
      effectiveUrl: '$_baseUrl/',
    );
    final EonMoviesService moviesService = EonMoviesService(transport: transport);
    final MovieDownloadService downloads = await MovieDownloadService.create(
      prefs,
      moviesService: moviesService,
      customDirectory: tempDir,
    );
    final SidifyShellController shell = SidifyShellController(prefs);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<EonMoviesService>.value(value: moviesService),
          ChangeNotifierProvider<MovieDownloadService>.value(value: downloads),
          ChangeNotifierProvider<SidifyShellController>.value(value: shell),
        ],
        child: MaterialApp(
          theme: SidifyTheme.dark,
          home: const Scaffold(body: MoviesExplorePage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pushpa 2 - The Rule'), findsOneWidget);
    expect(find.text('VisionQuest - Season 1'), findsOneWidget);

    await tester.tap(find.text('Series').last);
    await tester.pumpAndSettle();
    expect(find.text('Pushpa 2 - The Rule'), findsNothing);
    expect(find.text('VisionQuest - Season 1'), findsOneWidget);

    downloads.dispose();
    shell.dispose();
  });

  testWidgets('Series ZIP dialog lists pack qualities and starts download',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1170, 2532);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final Directory tempDir = await tester.runAsync(
      () => Directory.systemTemp.createTemp('series_dialog_test_'),
    ) as Directory;
    addTearDown(() async {
      await tester.runAsync(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });
    });

    final EonMoviesService moviesService =
        EonMoviesService(transport: _FakeTransport());
    final MovieDownloadService downloads = await MovieDownloadService.create(
      prefs,
      moviesService: moviesService,
      customDirectory: tempDir,
    );

    const MovieDetail detail = MovieDetail(
      title: 'VisionQuest - Season 1',
      cleanTitle: 'VisionQuest',
      type: MovieMediaType.series,
      webUrl: '/visionquest',
      languages: 'Hindi, English',
    );
    final List<MovieQualityLink> packs = <MovieQualityLink>[
      _quality('480', '480p', zip: true, size: '1.2 GB'),
      _quality('720', '720p', zip: true, size: '2.4 GB'),
    ];

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<EonMoviesService>.value(value: moviesService),
          ChangeNotifierProvider<MovieDownloadService>.value(value: downloads),
        ],
        child: MaterialApp(
          theme: SidifyTheme.dark,
          home: Scaffold(
            body: Builder(
              builder: (BuildContext context) => Center(
                child: ElevatedButton(
                  onPressed: () => showSeriesDownloadDialog(
                    context,
                    detail: detail,
                    packQualities: packs,
                  ),
                  child: const Text('Open dialog'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
    expect(find.text('Download all episodes as ZIP'), findsOneWidget);
    expect(find.text('Download episodes individually'), findsOneWidget);

    await tester.tap(find.text('Download all episodes as ZIP'));
    await tester.pumpAndSettle();
    expect(find.text('480p'), findsOneWidget);
    expect(find.text('2.4 GB'), findsOneWidget);

    await tester.tap(find.text('480p'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
    expect(downloads.items, hasLength(1));
    expect(downloads.items.first.qualityLabel, '480p');

    // Let the (failing) resolve + notice timers drain before disposing.
    for (int i = 0; i < 20; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(seconds: 3));
    downloads.dispose();
  });
}
