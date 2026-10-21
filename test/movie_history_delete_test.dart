/// Recently watched, row by row: each title carries its own delete, and using
/// it drops that title alone.
///
/// The list is history only — a watchlist entry, a download or anything saved
/// on the device is none of this button's business, and the suite says so.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ifallmusic/core/theme/sidify_theme.dart';
import 'package:ifallmusic/movies/models/movie_models.dart';
import 'package:ifallmusic/movies/services/movie_library_service.dart';
import 'package:ifallmusic/movies/ui/movie_library_page.dart';

const MoviePost _pushpa = MoviePost(
  title: 'Pushpa 2 - The Rule',
  link: '/pushpa-2-the-rule-2024-3617',
  imageUrl: '',
  badge: 'Movie',
  subtitle: '2024',
);

const MoviePost _vision = MoviePost(
  title: 'VisionQuest - Season 1',
  link: '/visionquest-season-1-episode-4-added-2026-3553',
  imageUrl: '',
  badge: 'Series',
  subtitle: '2026',
);

Future<MovieLibraryService> _libraryWith({
  List<MoviePost> history = const <MoviePost>[_pushpa, _vision],
  List<MoviePost> watchlist = const <MoviePost>[],
}) async {
  SharedPreferences.setMockInitialValues(<String, Object>{});
  final SharedPreferences prefs = await SharedPreferences.getInstance();
  final MovieLibraryService library = MovieLibraryService(prefs);
  // recordOpened puts the newest first, so the list is fed backwards to come
  // out on screen in the order it was given.
  for (final MoviePost post in history.reversed) {
    await library.recordOpened(post);
  }
  for (final MoviePost post in watchlist) {
    await library.toggleWatchlist(post);
  }
  return library;
}

Future<void> _pump(WidgetTester tester, MovieLibraryService library) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ChangeNotifierProvider<MovieLibraryService>.value(
      value: library,
      child: MaterialApp(
        theme: SidifyTheme.dark,
        home: const Scaffold(body: MovieLibraryPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every history row has its own delete', (WidgetTester tester) async {
    final MovieLibraryService library = await _libraryWith();
    await _pump(tester, library);

    expect(find.text('Recently watched'), findsOneWidget);
    expect(
      find.byTooltip('Remove from recently watched'),
      findsNWidgets(2),
      reason: 'one delete per name',
    );

    // Deleting one leaves the other exactly where it was.
    await tester.tap(find.byTooltip('Remove from recently watched').first);
    await tester.pumpAndSettle();
    expect(find.text('Pushpa 2 - The Rule'), findsNothing);
    expect(find.text('VisionQuest - Season 1'), findsOneWidget);
    expect(library.history.single.link, _vision.link);

    // Let the "Removed …" notice timer drain before the widget tree goes.
    await tester.pump(const Duration(seconds: 4));
    library.dispose();
  });

  testWidgets('deleting from history touches nothing else', (WidgetTester tester) async {
    final MovieLibraryService library =
        await _libraryWith(history: <MoviePost>[_pushpa], watchlist: <MoviePost>[_pushpa]);
    await _pump(tester, library);

    expect(library.watchlist, hasLength(1));
    await tester.tap(find.byTooltip('Remove from recently watched'));
    await tester.pumpAndSettle();

    expect(library.history, isEmpty);
    expect(library.watchlist, hasLength(1), reason: 'the watchlist is not history');
    expect(library.contains(_pushpa), isTrue);

    await tester.pump(const Duration(seconds: 4));
    library.dispose();
  });

  testWidgets('clear all empties the list in one tap', (WidgetTester tester) async {
    final MovieLibraryService library = await _libraryWith();
    await _pump(tester, library);

    expect(find.text('Clear all'), findsOneWidget);
    await tester.tap(find.text('Clear all'));
    await tester.pumpAndSettle();
    expect(library.history, isEmpty);
    expect(find.text('Pushpa 2 - The Rule'), findsNothing);
    expect(find.text('Your viewing history will appear here.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    library.dispose();
  });

  test('a removal survives the service being rebuilt', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final MovieLibraryService first = MovieLibraryService(prefs);
    await first.recordOpened(_pushpa);
    await first.recordOpened(_vision);
    // recordOpened puts the newest first, so this drops the newest.
    expect(await first.removeFromHistory(_vision), isTrue);
    expect(await first.removeFromHistory(_vision), isFalse, reason: 'already gone');
    first.dispose();

    final MovieLibraryService second = MovieLibraryService(prefs);
    expect(second.history.map((MoviePost p) => p.link), <String>[_pushpa.link]);
    await second.clearHistory();
    expect(second.history, isEmpty);
    second.dispose();

    final MovieLibraryService third = MovieLibraryService(prefs);
    expect(third.history, isEmpty, reason: 'the empty list was persisted too');
    third.dispose();
  });
}
