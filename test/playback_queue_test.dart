import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:ifallmusic/core/models/song.dart';
import 'package:ifallmusic/core/services/library_service.dart';
import 'package:ifallmusic/core/services/playback_service.dart';
import 'package:ifallmusic/core/services/settings_service.dart';
import 'package:ifallmusic/core/services/youtube_service.dart';

Song song(String id) => Song(
  id: id,
  title: 'Track $id',
  artist: 'Artist',
  thumbnailUrl: '',
  duration: const Duration(minutes: 3),
);
final a = song('aaaaaaaaaaa'), b = song('bbbbbbbbbbb'), c = song('ccccccccccc');

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

  void complete({int times = 1}) {
    position = duration!;
    processingState = ProcessingState.completed;
    for (int i = 0; i < times; i++) {
      states.add(PlayerState(true, ProcessingState.completed));
    }
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
  List<Song> recommendations = [];
  Completer<List<Song>>? pending;
  @override
  Future<List<Song>> radioSongs(
    Song seed, {
    Iterable<Song> history = const [],
    Set<String> exclude = const {},
  }) async => pending?.future ?? recommendations;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class TestPlayback extends PlaybackService {
  TestPlayback({
    required super.youtube,
    required super.settings,
    required super.library,
    required super.player,
  });
  final resolved = <String>[];
  Completer<String>? pendingResolve;
  @override
  Future<String> resolvePlayableStreamUrl(VideoId id) async {
    resolved.add(id.value);
    return pendingResolve?.future ?? 'https://stream.invalid/${id.value}';
  }
}

Future<void> drain() async {
  for (int i = 0; i < 30; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePlayer player;
  late FakeYoutube youtube;
  late TestPlayback playback;
  setUp(() async {
    SharedPreferences.setMockInitialValues({SettingsService.kGapless: false});
    final prefs = await SharedPreferences.getInstance();
    player = FakePlayer();
    youtube = FakeYoutube();
    playback = TestPlayback(
      youtube: youtube,
      settings: SettingsService(prefs),
      library: LibraryService(prefs),
      player: player,
    );
  });
  tearDown(() async {
    playback.dispose();
    await drain();
  });
  test(
    'first, second, third track complete without duplicate next transitions',
    () async {
      await playback.playQueue([a, b, c]);
      player.complete(times: 3);
      await drain();
      expect(playback.current, b);
      player.complete(times: 3);
      await drain();
      expect(playback.current, c);
      expect(player.loaded, [a.id, b.id, c.id]);
      expect(player.loops.every((mode) => mode == LoopMode.off), isTrue);
    },
  );
  test('fresh-source retry succeeds before skipping', () async {
    player.failures[a.id] = 1;
    await playback.playQueue([a, b]);
    expect(playback.current, a);
    expect(playback.isPlaying, isTrue);
    expect(playback.resolved.where((id) => id == a.id).length, 2);
    expect(playback.lastError, isNull);
  });
  test('unloadable middle track is reported and third plays', () async {
    player.failures[b.id] = 2;
    await playback.playQueue([a, b, c]);
    player.complete();
    await drain();
    expect(playback.current, c);
    expect(playback.isPlaying, isTrue);
    expect(playback.isLoading, isFalse);
    expect(playback.lastError?.body, contains('403 source error'));
    expect(playback.lastError?.body, contains(b.id));
  });
  test(
    'radio excludes seed variants and does not use a search-results queue',
    () async {
      youtube.recommendations = [
        a,
        Song(
          id: 'ddddddddddd',
          title: '${a.title} (slowed reverb)',
          artist: 'Artist',
          thumbnailUrl: '',
        ),
        b,
        c,
      ];
      await playback.playRadio(a);
      await drain();
      expect(playback.queue, [a, b, c]);
      player.complete();
      await drain();
      expect(playback.current, b);
    },
  );
  test('stop invalidates an in-flight radio refill', () async {
    youtube.pending = Completer<List<Song>>();
    await playback.playRadio(a);
    await playback.stop();
    youtube.pending!.complete([b, c]);
    await drain();
    expect(playback.queue, [a]);
    expect(playback.isPlaying, isFalse);
  });
  test('new selection invalidates an older pending load', () async {
    final pending = Completer<String>();
    playback.pendingResolve = pending;
    final first = playback.playQueue([a]);
    await drain();
    playback.pendingResolve = null;
    await playback.playQueue([b]);
    pending.complete('https://stream.invalid/${a.id}');
    await first;
    await drain();
    expect(playback.current, b);
    expect(player.loaded, [b.id]);
  });
  test('pausing a pending source load keeps the loaded song paused', () async {
    final pending = Completer<String>();
    playback.pendingResolve = pending;
    final load = playback.playQueue([a]);
    await drain();
    await playback.pause();
    pending.complete('https://stream.invalid/${a.id}');
    await load;
    await drain();
    expect(playback.isLoading, isFalse);
    expect(player.playing, isFalse);
    await playback.resume();
    expect(player.playing, isTrue);
  });
  test(
    'mid-stream error retries once then advances; does not spin on same track',
    () async {
      await playback.playQueue([a, b, c]);
      player.events.addError(
        StateError('403 stream expired'),
        StackTrace.empty,
      );
      await drain();
      expect(playback.current, a);
      expect(player.loaded, [a.id, a.id]);
      player.events.addError(StateError('403 again'), StackTrace.empty);
      await drain();
      expect(playback.current, b);
      expect(playback.lastError, isNotNull);
    },
  );
  test(
    'offline failure storm has a finite budget and exits loading state',
    () async {
      final tracks = [
        a,
        b,
        c,
        song('ddddddddddd'),
        song('eeeeeeeeeee'),
        song('fffffffffff'),
        song('ggggggggggg'),
      ];
      for (final s in tracks) {
        player.failures[s.id] = 2;
      }
      await playback.playQueue(tracks);
      await drain();
      expect(player.loaded.length, 12);
      expect(playback.isLoading, isFalse);
      expect(playback.notice, contains('Check your connection'));
      expect(playback.current, tracks[5]);
    },
  );
}
