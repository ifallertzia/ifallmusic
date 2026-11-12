import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/movies/services/movie_rating.dart';
import 'package:ifallmusic/movies/services/movie_resume_store.dart';
import 'package:ifallmusic/movies/services/movie_text_scrub.dart';
import 'package:ifallmusic/movies/ui/player/movie_player_sheets.dart';
import 'package:ifallmusic/movies/ui/player/movie_seek_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('source site name', () {
    test('is removed from titles and file names, extension kept', () {
      expect(
        scrubSourceNames('Movie.2025.1080p.x264-HDHub4u.Ms.mkv'),
        'Movie.2025.1080p.x264.mkv',
      );
      expect(scrubSourceNames('Movie-HDHub4u.mkv'), 'Movie.mkv');
      expect(
        scrubSourceNames('Obsession (2025) Hindi - HDHub4u'),
        'Obsession (2025) Hindi',
      );
      expect(scrubSourceNames('HDHub4u.com | Vision 2024'), 'Vision 2024');
      expect(scrubSourceNames('Vision [HDHub4u.Tv] 720p'), 'Vision 720p');
    });

    test('a string that was only the site name becomes empty', () {
      expect(scrubSourceNames('HDHub4u'), '');
      expect(scrubSourceNames('www.hdhub4u.cl'), '');
      expect(mentionsSourceName('HD Hub 4u'), isTrue);
    });

    test('other text is left exactly as written', () {
      expect(scrubSourceNames('Plain Title 2024'), 'Plain Title 2024');
      expect(mentionsSourceName('Plain Title 2024'), isFalse);
    });
  });

  group('rating', () {
    test('is read from a metadata pill', () {
      expect(extractMovieRatingFromLabel('⭐ 7.4'), '7.4');
      expect(extractMovieRatingFromLabel('7.4/10'), '7.4');
      expect(extractMovieRatingFromLabel('IMDb: 6.9/10'), '6.9');
    });

    test('other pills are not mistaken for a rating', () {
      for (final String pill in <String>[
        '3 Dec 2024',
        'Movie',
        'WEB-DL',
        'Hindi, Telugu',
        '1080p',
      ]) {
        expect(extractMovieRatingFromLabel(pill), '', reason: pill);
      }
    });

    test('in page text only a labelled score counts', () {
      expect(
        extractMovieRatingFromText(
          'Storyline here. IMDb Rating: 7.4/10 Genre: Action',
        ),
        '7.4',
      );
      expect(extractMovieRatingFromText('Size 1.4/10 GB'), '');
      expect(extractMovieRatingFromText('Rated 4 stars by 10 users'), '');
      expect(extractMovieRatingFromText(''), '');
    });
  });

  group('continue watching', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    test('a position part-way through is saved and loaded', () async {
      const String key = 'eon|/some-movie-2024';
      await MovieResumeStore.save(
        key,
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 100),
      );
      final MovieResumePoint? point = await MovieResumeStore.load(key);
      expect(point, isNotNull);
      expect(point!.position, const Duration(minutes: 10));
      expect(point.duration, const Duration(minutes: 100));
    });

    test('the first seconds and the end credits start over', () async {
      const String key = 'eon|/some-movie-2024';
      await MovieResumeStore.save(
        key,
        position: const Duration(minutes: 10),
        duration: const Duration(minutes: 100),
      );
      await MovieResumeStore.save(
        key,
        position: const Duration(seconds: 5),
        duration: const Duration(minutes: 100),
      );
      expect(await MovieResumeStore.load(key), isNull);

      await MovieResumeStore.save(
        key,
        position: const Duration(minutes: 99, seconds: 40),
        duration: const Duration(minutes: 100),
      );
      expect(await MovieResumeStore.load(key), isNull);
    });

    test('clear forgets a title, and an empty key is ignored', () async {
      const String key = 'local|mdl_1';
      await MovieResumeStore.save(
        key,
        position: const Duration(minutes: 3),
        duration: const Duration(minutes: 40),
      );
      expect(await MovieResumeStore.load(key), isNotNull);
      await MovieResumeStore.clear(key);
      expect(await MovieResumeStore.load(key), isNull);
      expect(await MovieResumeStore.load(''), isNull);
    });
  });

  group('player labels', () {
    test('clock', () {
      expect(
        movieClock(const Duration(hours: 1, minutes: 2, seconds: 3)),
        '1:02:03',
      );
      expect(movieClock(const Duration(minutes: 42, seconds: 10)), '42:10');
      expect(movieClock(const Duration(seconds: -4)), '0:00');
    });

    test('speed', () {
      expect(formatMovieSpeed(0.25), '0.25x');
      expect(formatMovieSpeed(0.5), '0.5x');
      expect(formatMovieSpeed(1.0), '1.0x');
      expect(formatMovieSpeed(1.25), '1.25x');
      expect(formatMovieSpeed(2.0), '2.0x');
    });
  });

  testWidgets('Playback Settings shows current values and real options',
      (WidgetTester tester) async {
    double speed = 1.0;
    MoviePlaybackSettings read() => MoviePlaybackSettings(
          speed: speed,
          speeds: const <double>[0.5, 1.0, 1.5],
          qualities: const <MovieSheetOption>[
            MovieSheetOption(id: 'q1080', title: '1080p', selected: true),
            MovieSheetOption(id: 'q720', title: '720p'),
          ],
          audioTracks: const <MovieSheetOption>[
            MovieSheetOption(id: 'auto', title: 'Auto', selected: true),
            MovieSheetOption(id: '2', title: 'Hindi'),
          ],
        );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: MoviePlaybackSettingsSheet(
            read: read,
            onSpeed: (double value) async => speed = value,
            onQuality: (_) {},
            onAudio: (_) async {},
          ),
        ),
      ),
    );

    // The three rows, each with its current value.
    expect(find.text('Playback Settings'), findsOneWidget);
    expect(find.text('Speed'), findsOneWidget);
    expect(find.text('Quality'), findsOneWidget);
    expect(find.text('Audio'), findsOneWidget);
    expect(find.text('Normal'), findsOneWidget);
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('Auto'), findsOneWidget);

    // Speed opens its own list; picking one applies it.
    await tester.tap(find.text('Speed'));
    await tester.pumpAndSettle();
    expect(find.text('0.5x'), findsOneWidget);
    expect(find.text('1.5x'), findsOneWidget);
    await tester.tap(find.text('1.5x'));
    await tester.pumpAndSettle();
    expect(speed, 1.5);

    // Back to the rows: the new value is shown.
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Playback Settings'), findsOneWidget);
    expect(find.text('1.5x'), findsOneWidget);

    // Quality lists what the source offers.
    await tester.tap(find.text('Quality'));
    await tester.pumpAndSettle();
    expect(find.text('1080p'), findsOneWidget);
    expect(find.text('720p'), findsOneWidget);
  });
}
