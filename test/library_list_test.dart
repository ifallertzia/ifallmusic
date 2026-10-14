import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ifallmusic/core/services/library_service.dart';
import 'package:ifallmusic/core/services/local_music_service.dart';
import 'package:ifallmusic/core/services/music_download_service.dart';
import 'package:ifallmusic/core/services/playback_service.dart';
import 'package:ifallmusic/core/services/settings_service.dart';
import 'package:ifallmusic/core/services/youtube_service.dart';
import 'package:ifallmusic/ui/library/library_page.dart';
import 'package:ifallmusic/ui/shell/sidify_shell_controller.dart';

class FakePlayer implements AudioPlayer {
  final states = StreamController<PlayerState>.broadcast(sync: true);
  final positions = StreamController<Duration>.broadcast(sync: true);
  final durations = StreamController<Duration?>.broadcast(sync: true);
  final events = StreamController<PlaybackEvent>.broadcast(sync: true);
  final List<String> loaded = [];
  final Map<String, int> failures = {};
  final List<LoopMode> loops = [];
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
    final id = (source as UriAudioSource).uri.pathSegments.last;
    loaded.add(id);
    if ((failures[id] ?? 0) > 0) {
      failures[id] = failures[id]! - 1;
      throw StateError('403 source error');
    }
    processingState = ProcessingState.ready;
    position = Duration.zero;
    states.add(PlayerState(playing, processingState));
    return duration;
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

/// The framework's own complaint, minus the widget tree and stack trace Flutter
/// appends to it. That tail is 50+ lines long and is exactly what hides the
/// cause when a CI log gets tailed, so only the head is kept.
String frameworkErrorHead(Object error) {
  final String text = error is FlutterErrorDetails
      ? error.exceptionAsString()
      : error.toString();
  const List<String> markers = <String>[
    'The relevant error-causing widget',
    'When the exception was thrown',
    'package:flutter/',
    'package:ifallmusic/',
    'dart:',
  ];
  int cut = text.length;
  for (final String marker in markers) {
    final int at = text.indexOf(marker);
    if (at > 0 && at < cut) cut = at;
  }
  final String head = text.substring(0, cut).trim();
  return head.isEmpty ? text.split('\n').take(3).join('\n') : head;
}

/// Fails with the framework's OWN complaint (overflow, failed assertion, …).
void expectCleanPump(WidgetTester tester, String step) {
  final Object? error = tester.takeException();
  if (error == null) return;
  fail('$step threw a framework error: ${frameworkErrorHead(error)}');
}

/// The Library is a hub now: every collection is its own pushed page, so the
/// system Back button returns to the list instead of dropping the listener
/// on Home — and there is no horizontal tab strip anywhere.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// Boots the Library inside every provider it reads, and tears the player
  /// down after the test.
  Widget libraryUnderTest(SharedPreferences prefs) {
    final SettingsService settings = SettingsService(prefs);
    final LibraryService library = LibraryService(prefs);
    final PlaybackService playback = PlaybackService(
      youtube: YoutubeService(),
      settings: settings,
      library: library,
      player: FakePlayer(),
    );
    addTearDown(playback.dispose);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsService>.value(value: settings),
        ChangeNotifierProvider<SidifyShellController>(
          create: (_) => SidifyShellController(),
        ),
        ChangeNotifierProvider<LibraryService>.value(value: library),
        ChangeNotifierProvider<MusicDownloadService>.value(
          value: MusicDownloadService(prefs: prefs),
        ),
        ChangeNotifierProvider<LocalMusicService>.value(
          value: LocalMusicService(prefs),
        ),
        ChangeNotifierProvider<PlaybackService>.value(value: playback),
        Provider<YoutubeService>.value(value: YoutubeService()),
      ],
      child: const MaterialApp(home: Scaffold(body: LibraryPage())),
    );
  }

  testWidgets('library hub lists every section and shows no tab strip', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(libraryUnderTest(prefs));
    expectCleanPump(tester, 'pumpWidget');
    await tester.pumpAndSettle();
    expectCleanPump(tester, 'pumpAndSettle');

    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Liked Songs'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Downloads'), findsOneWidget);
    expect(find.text('Lyrics finder'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
    // The horizontal tab strip is gone for good.
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(TabBarView), findsNothing);
  });

  testWidgets('opening a section and going Back returns to the list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(libraryUnderTest(prefs));
    expectCleanPump(tester, 'pumpWidget');
    await tester.pumpAndSettle();
    expectCleanPump(tester, 'pumpAndSettle');

    await tester.tap(find.text('Liked Songs'));
    await tester.pumpAndSettle();
    expectCleanPump(tester, 'after tapping Liked Songs');

    // The section is a real route with its own header.
    expect(find.text('Liked Songs'), findsWidgets);
    expect(find.byIcon(Icons.arrow_back_rounded), findsOneWidget);

    // Liked Songs has its own glass back button in the header.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expectCleanPump(tester, 'after tapping back');

    // Back lands on the library hub again, never on Home.
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Playlists'), findsOneWidget);
  });
}
