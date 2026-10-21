/// The floating dock, measured: the liquid-glass mini player and tab bar must
/// keep the geometry they have always had at rest, fold into one row on the way
/// down a page and unfold on the way back up, keep driving the real services,
/// and must not grow Flutter's yellow double underline under their labels.
///
/// The dock is painted by `MaterialApp.builder`, above the navigator and
/// outside any `Material` — which is exactly where a `Text` with no inherited
/// style falls back to Flutter's debug style: yellow monospace, double
/// underlined. This test reproduces that environment instead of a comfortable
/// `Scaffold`, so the yellow line cannot come back unnoticed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'package:ifallmusic/core/models/song.dart';
import 'package:ifallmusic/core/services/library_service.dart';
import 'package:ifallmusic/core/services/listen_together_service.dart';
import 'package:ifallmusic/core/services/music_download_service.dart';
import 'package:ifallmusic/core/services/playback_service.dart';
import 'package:ifallmusic/core/services/settings_service.dart';
import 'package:ifallmusic/core/services/youtube_service.dart';
import 'package:ifallmusic/core/theme/sidify_theme.dart';
import 'package:ifallmusic/ui/shell/sidify_dock.dart';
import 'package:ifallmusic/ui/shell/sidify_shell_controller.dart';
import 'package:ifallmusic/ui/widgets/sidify_widgets.dart';

Song _song(String id, String title) => Song(
      id: id,
      title: title,
      artist: 'Glass Artist',
      // An empty URL keeps the artwork on its placeholder: no network in tests.
      thumbnailUrl: '',
      duration: const Duration(minutes: 3),
    );

class FakePlayer implements AudioPlayer {
  final StreamController<PlayerState> states =
      StreamController<PlayerState>.broadcast(sync: true);
  final StreamController<Duration> positions =
      StreamController<Duration>.broadcast(sync: true);
  final StreamController<Duration?> durations =
      StreamController<Duration?>.broadcast(sync: true);
  final StreamController<PlaybackEvent> events =
      StreamController<PlaybackEvent>.broadcast(sync: true);
  final List<String> loaded = <String>[];
  final List<LoopMode> loops = <LoopMode>[];

  @override
  bool playing = false;
  @override
  ProcessingState processingState = ProcessingState.idle;
  @override
  double speed = 1;
  @override
  Duration position = Duration.zero;
  @override
  Duration? get duration => const Duration(minutes: 3);
  @override
  Stream<PlayerState> get playerStateStream => states.stream;
  @override
  Stream<Duration> get positionStream => positions.stream;
  @override
  Stream<Duration?> get durationStream => durations.stream;
  @override
  Stream<PlaybackEvent> get playbackEventStream => events.stream;

  @override
  Future<Duration?> setAudioSource(
    AudioSource source, {
    bool preload = true,
    int? initialIndex,
    Duration? initialPosition,
  }) async {
    loaded.add((source as UriAudioSource).uri.pathSegments.last);
    processingState = ProcessingState.ready;
    position = Duration.zero;
    states.add(PlayerState(playing, processingState));
    return duration;
  }

  @override
  Future<void> play() async {
    playing = true;
    states.add(PlayerState(true, processingState));
  }

  @override
  Future<void> pause() async {
    playing = false;
    states.add(PlayerState(false, processingState));
  }

  @override
  Future<void> stop() async {
    playing = false;
    processingState = ProcessingState.idle;
    states.add(PlayerState(false, processingState));
  }

  @override
  Future<void> seek(Duration? value, {int? index}) async {
    position = value ?? Duration.zero;
    positions.add(position);
  }

  @override
  Future<void> setSpeed(double value) async {
    speed = value;
  }

  @override
  Future<void> setLoopMode(LoopMode mode) async {
    loops.add(mode);
  }

  @override
  Future<void> dispose() async {
    await states.close();
    await positions.close();
    await durations.close();
    await events.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeYoutube implements YoutubeService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Playback with the stream resolver stubbed out, so the dock can be pumped
/// with a real current track and no network.
class TestPlayback extends PlaybackService {
  TestPlayback({
    required super.youtube,
    required super.settings,
    required super.library,
    required super.player,
  });

  @override
  Future<String> resolvePlayableStreamUrl(VideoId id) async =>
      'https://stream.invalid/${id.value}';
}

/// Everything the dock reads, kept together so a test can drive it.
class _Dock {
  _Dock({required this.playback, required this.shell});

  final TestPlayback playback;
  final SidifyShellController shell;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A mid-size Android phone in logical pixels: 392 x 850.
  const double screenW = 392;
  const double screenH = 850;

  /// Lets the dock's 280ms slides and 180ms selection fades finish, then runs
  /// the clock past the playback service's 2s queue-persist debounce so no
  /// timer is left pending when the test ends.
  Future<void> settle(WidgetTester tester) async {
    for (int i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    await tester.pump(const Duration(seconds: 3));
  }

  /// The nearest glass pane around [target].
  Finder glassAround(Finder target) =>
      find.ancestor(of: target, matching: find.byType(GlassBox)).first;

  /// Pumps the dock the way `main.dart` does — above the navigator, inside the
  /// builder, with the page behind it — and hands back the live services.
  Future<_Dock> pumpDock(WidgetTester tester) async {
    tester.view.physicalSize = const Size(screenW * 3, screenH * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsService.kDisplayName: 'Tester',
      SettingsService.kGapless: false,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsService settings = SettingsService(prefs);
    final LibraryService library = LibraryService(prefs);
    final TestPlayback playback = TestPlayback(
      youtube: FakeYoutube(),
      settings: settings,
      library: library,
      player: FakePlayer(),
    );
    addTearDown(playback.dispose);
    final SidifyShellController shell = SidifyShellController();
    addTearDown(shell.dispose);
    final SidifyRouteObserver observer = SidifyRouteObserver();
    final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

    await playback.playQueue(<Song>[
      _song('aaaaaaaaaaa', 'Glass Track'),
      _song('bbbbbbbbbbb', 'Second Track'),
    ]);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsService>.value(value: settings),
          ChangeNotifierProvider<LibraryService>.value(value: library),
          ChangeNotifierProvider<MusicDownloadService>(
            create: (_) => MusicDownloadService(prefs: prefs),
          ),
          ChangeNotifierProvider<PlaybackService>.value(value: playback),
          ChangeNotifierProvider<SidifyShellController>.value(value: shell),
          ChangeNotifierProvider<JamService>(
            create: (_) => JamService(settings: settings),
          ),
        ],
        child: MaterialApp(
          theme: SidifyTheme.dark,
          navigatorKey: navigatorKey,
          navigatorObservers: <NavigatorObserver>[observer],
          builder: (BuildContext context, Widget? child) => Stack(
            fit: StackFit.expand,
            children: <Widget>[
              child ?? const SizedBox.shrink(),
              SidifyDock(observer: observer, navigatorKey: navigatorKey),
            ],
          ),
          home: const Scaffold(body: ColoredBox(color: Colors.black)),
        ),
      ),
    );
    await settle(tester);
    return _Dock(playback: playback, shell: shell);
  }

  testWidgets('the dock keeps its exact geometry', (WidgetTester tester) async {
    await pumpDock(tester);
    expect(tester.takeException(), isNull);

    // -- mini player: 58px tall, 12px in from each side --------------------
    final Rect mini = tester.getRect(glassAround(find.text('Glass Track')));
    expect(mini.height, 58, reason: 'mini player height moved');
    expect(mini.width, screenW - 24, reason: 'mini player width moved');
    expect(mini.left, 12);
    // 10 (bar clearance) + 62 (bar slot) + 10 (gap) above the screen edge.
    expect(mini.bottom, screenH - 82, reason: 'mini player bottom moved');

    // -- tab pill: 50px of cells inside 6px of glass = 62px ----------------
    final Rect pill = tester.getRect(glassAround(find.text('Home')));
    expect(pill.height, 62, reason: 'tab bar height moved');
    expect(pill.width, screenW - 24 - 10 - 62, reason: 'tab pill width moved');
    expect(pill.left, 12);
    expect(pill.bottom, screenH - 10, reason: 'tab bar bottom moved');

    // -- the round Search button: 50px inside 6px of glass -----------------
    final Rect search =
        tester.getRect(glassAround(find.byIcon(Icons.search_rounded)));
    expect(search.size, const Size(62, 62));
    expect(search.right, screenW - 12);
    expect(search.bottom, screenH - 10);

    // -- the gap between the two components --------------------------------
    expect(pill.top - mini.bottom, 10, reason: 'dock spacing moved');

    // Each floating surface is still real glass: one frosted backdrop each.
    expect(find.byType(BackdropFilter), findsNWidgets(3));
  });

  testWidgets('a page scrolled down folds the bar into the mini player',
      (WidgetTester tester) async {
    await pumpDock(tester);

    // The row the page's scroll writes, driven directly — the dock reads this
    // notifier and nothing else.
    SidifyDockScroll.barHidden.value = true;
    await settle(tester);
    expect(tester.takeException(), isNull);

    // Home keeps its seat on the left, but the bar is now that seat alone:
    // one round 62px button, not a row of three cells.
    final Rect home = tester.getRect(glassAround(find.text('Home')));
    expect(home.size, const Size(62, 62), reason: 'the bar did not fold to Home');
    expect(home.left, 12);
    expect(home.bottom, screenH - 10);

    // The mini player came down into the row the bar vacated and slimmed to
    // match it — same pill, now sitting between Home and Search.
    final Rect mini = tester.getRect(glassAround(find.text('Glass Track')));
    expect(mini.height, 46, reason: 'the player did not slim down');
    expect(mini.left, 84, reason: '12 + 62 (Home) + 10 (gap)');
    expect(mini.right, screenW - 84, reason: 'Search keeps its own 72px');
    expect(mini.center.dy, closeTo(screenH - 41, 0.5),
        reason: 'the pill is centred in the 62px row');

    // Search never moved: it had the right-hand seat in both rows.
    final Rect search =
        tester.getRect(glassAround(find.byIcon(Icons.search_rounded)));
    expect(search.size, const Size(62, 62));
    expect(search.right, screenW - 12);
    expect(search.bottom, screenH - 10);

    // Explore and Library are only out of the way, not gone: their cells
    // closed, so the same three glass panes are all that is painted.
    expect(find.text('Explore'), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNWidgets(3));

    // Transport still works from the folded pill.
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await settle(tester);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    // And scrolling back up walks the same path in reverse.
    SidifyDockScroll.barHidden.value = false;
    await settle(tester);
    final Rect rest = tester.getRect(glassAround(find.text('Glass Track')));
    expect(rest.height, 58);
    expect(rest.left, 12);
    expect(rest.width, screenW - 24);
    expect(
      tester.getRect(glassAround(find.text('Explore'))).width,
      screenW - 24 - 10 - 62,
      reason: 'the bar unfolded back to a row of cells',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping the folded Home button brings the bar back',
      (WidgetTester tester) async {
    final _Dock dock = await pumpDock(tester);
    SidifyDockScroll.barHidden.value = true;
    await settle(tester);
    expect(SidifyDockScroll.barHidden.value, isTrue);

    // `select` is synchronous void — awaiting it is an analyzer error.
    dock.shell.select(SidifyTab.explore);
    await settle(tester);
    expect(SidifyDockScroll.barHidden.value, isTrue);

    // Tapping a tab is a deliberate act on the dock itself: the bar unfolds.
    // (Reachable only through Home, whose cell is the one that survived.)
    await tester.tap(find.byIcon(Icons.home_rounded));
    await settle(tester);
    expect(SidifyDockScroll.barHidden.value, isFalse);
    expect(dock.shell.tab, SidifyTab.home);
    expect(tester.takeException(), isNull);
  });

  testWidgets('no yellow underline survives under the dock labels',
      (WidgetTester tester) async {
    await pumpDock(tester);

    for (final String label in <String>[
      'Glass Track',
      'Glass Artist',
      'Home',
      'Explore',
      'Library',
    ]) {
      final Finder text = find.text(label);
      expect(text, findsOneWidget, reason: '$label is missing from the dock');

      // What the dock inherits. Flutter's fallback style is yellow monospace
      // 48/900 with a double underline, so any of these is the bug back again.
      // DefaultTextStyle.of hands back the inherited *widget*, and with no
      // ancestor at all it hands back Flutter's fallback — so this is the exact
      // lookup that used to return yellow monospace with a double underline.
      final TextStyle base = DefaultTextStyle.of(tester.element(text)).style;
      expect(base.decoration, TextDecoration.none, reason: '$label base style');
      expect(base.fontFamily, isNot('monospace'), reason: '$label base style');
      expect(base.fontSize, isNot(48), reason: '$label base style');
      expect(base.color, isNot(const Color(0xFFFFFF00)), reason: '$label base');

      // What is actually painted, after the widget's own style merges in.
      final RichText rich = tester.widget<RichText>(
        find.descendant(of: text, matching: find.byType(RichText)).first,
      );
      final TextStyle? painted = (rich.text as TextSpan).style;
      expect(
        painted?.decoration,
        isNot(TextDecoration.underline),
        reason: '$label is painted with an underline',
      );
      expect(
        painted?.decorationColor,
        isNot(const Color(0xFFFFFF00)),
        reason: '$label is painted with a yellow decoration',
      );
      // The typography itself is untouched: the dock still names its own size.
      expect(painted?.color, isNotNull, reason: '$label lost its colour');
    }

    // The playback progress hairline is still a real indicator inside the pill:
    // nothing functional was removed to get rid of the yellow line.
    expect(
      find.descendant(
        of: glassAround(find.text('Glass Track')),
        matching: find.byType(FractionallySizedBox),
      ),
      findsOneWidget,
    );
  });

  testWidgets('the dock stays away while a movie player route is open',
      (WidgetTester tester) async {
    await pumpDock(tester);
    final NavigatorState nav =
        tester.state<NavigatorState>(find.byType(Navigator).first);

    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: ColoredBox(color: Colors.black)),
        settings: const RouteSettings(name: 'sidify/movie-player-online'),
      ),
    );
    await settle(tester);
    expect(find.text('Home'), findsNothing);

    // media_kit enters fullscreen by pushing a second route with *no* name.
    // The dock must not mistake that for a normal page and pop back over the
    // video — the bug where the menu bar reappeared on the player.
    nav.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: ColoredBox(color: Colors.black)),
      ),
    );
    await settle(tester);
    expect(find.text('Home'), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsNothing);

    nav.pop();
    await settle(tester);
    expect(find.text('Home'), findsNothing);

    nav.pop();
    await settle(tester);
    expect(find.text('Home'), findsOneWidget);
  });

  testWidgets('in Movies the right-hand button is Music, not Search',
      (WidgetTester tester) async {
    final _Dock dock = await pumpDock(tester);
    await dock.shell.chooseMode(movies: true);
    await settle(tester);

    expect(find.byIcon(Icons.search_rounded), findsNothing);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.music_note_rounded));
    await settle(tester);

    expect(dock.shell.isMoviesMode, isFalse);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('in Movies the folded bar hands Home\'s seat to Search',
      (WidgetTester tester) async {
    final _Dock dock = await pumpDock(tester);
    await dock.shell.chooseMode(movies: true);
    await settle(tester);

    // At the top of the page: Home on the left, the way back to Music on the
    // right, and no search seat anywhere — Movies searches from its own header.
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsNothing);

    // Scrolling down folds the bar, and in Movies the button that survives on
    // the left is Search, not Home. The right-hand seat is left alone.
    SidifyDockScroll.barHidden.value = true;
    await settle(tester);
    expect(find.byIcon(Icons.home_rounded), findsNothing);
    expect(find.byIcon(Icons.search_rounded), findsOneWidget);
    expect(find.byIcon(Icons.music_note_rounded), findsOneWidget,
        reason: 'the right button keeps its job while folded');

    // Tapping it opens the search box and brings the bar back.
    await tester.tap(find.byIcon(Icons.search_rounded));
    await settle(tester);
    expect(dock.shell.tab, SidifyTab.search);
    expect(dock.shell.searchMode, SearchMode.movies);
    expect(SidifyDockScroll.barHidden.value, isFalse);

    // Scrolled back up, the seat is Home again — the swap belongs to the fold,
    // not to the page.
    expect(find.byIcon(Icons.home_rounded), findsOneWidget);
    expect(find.byIcon(Icons.search_rounded), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the dock still drives tabs and transport',
      (WidgetTester tester) async {
    final _Dock dock = await pumpDock(tester);

    // Navigation.
    await tester.tap(find.text('Explore'));
    await settle(tester);
    expect(dock.shell.tab, SidifyTab.explore);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byIcon(Icons.search_rounded));
    await settle(tester);
    expect(dock.shell.tab, SidifyTab.search);

    // Next track.
    await tester.tap(find.byIcon(Icons.skip_next_rounded));
    await settle(tester);
    expect(dock.playback.current?.id, 'bbbbbbbbbbb');
    expect(find.text('Second Track'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Pause, then play again.
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await settle(tester);
    expect(dock.playback.isPlaying, isFalse);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow_rounded));
    await settle(tester);
    expect(dock.playback.isPlaying, isTrue);
    expect(find.byIcon(Icons.pause_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
