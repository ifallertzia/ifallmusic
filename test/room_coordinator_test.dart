import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

import 'package:ifallmusic/core/models/song.dart';
import 'package:ifallmusic/core/services/library_service.dart';
import 'package:ifallmusic/core/services/listen_together_service.dart';
import 'package:ifallmusic/core/services/playback_service.dart';
import 'package:ifallmusic/core/services/room_playback_coordinator.dart';
import 'package:ifallmusic/core/services/settings_service.dart';
import 'package:ifallmusic/core/services/vibe_ranker.dart';
import 'package:ifallmusic/core/services/youtube_service.dart';

import 'helpers/fake_party_server.dart';

Song songOf(String id) => Song(
      id: id,
      title: 'Track $id',
      artist: 'Artist',
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
  Future<void> setLoopMode(LoopMode mode) async {}

  void complete() {
    position = duration!;
    processingState = ProcessingState.completed;
    states.add(PlayerState(true, ProcessingState.completed));
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
  Future<List<Song>> radioSongs(
    Song seed, {
    Iterable<Song> history = const [],
    Set<String> exclude = const {},
    VibeMemory? vibe,
    int limit = 12,
  }) async =>
      <Song>[];

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

  @override
  Future<String> resolvePlayableStreamUrl(VideoId id) async =>
      'https://stream.invalid/${id.value}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The fake party server is a real localhost socket; undo the test
  // binding's blanket HTTP mock (which answers 400 to everything).
  HttpOverrides.global = null;

  late FakePartyServer server;
  late FakePlayer player;
  late TestPlayback playback;
  late JamService jam;
  late RoomPlaybackCoordinator coordinator;

  setUp(() async {
    server = FakePartyServer();
    await server.start();
    SharedPreferences.setMockInitialValues(<String, Object>{
      SettingsService.kJamServer: server.base,
      SettingsService.kGapless: false,
    });
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final SettingsService settings = SettingsService(prefs);
    player = FakePlayer();
    playback = TestPlayback(
      youtube: FakeYoutube(),
      settings: settings,
      library: LibraryService(prefs),
      player: player,
    );
    jam = JamService(settings: settings);
    jam.identify(userId: 'u-alice', deviceId: 'd-alice', displayName: 'Alice');
    coordinator = RoomPlaybackCoordinator(jam: jam, playback: playback);
    coordinator.attach();
  });

  tearDown(() async {
    coordinator.dispose();
    jam.dispose();
    playback.dispose();
    await player.dispose();
    await server.stop();
  });

  test('joining a room puts the room track on this device', () async {
    expect(await jam.join('ABC123'), isTrue, reason: jam.error ?? '');
    await untilTrue(() => playback.current?.id == 'aaaaaaaaaaa');
    expect(playback.deferTrackCompletion, isTrue);
    await untilTrue(() => playback.isPlaying);
  });

  test('a local completion reports "ended" and waits for the room',
      () async {
    expect(await jam.join('ABC123'), isTrue);
    await untilTrue(() => playback.current?.id == 'aaaaaaaaaaa');
    await untilTrue(() => playback.isPlaying);
    player.complete();
    await untilTrue(
      () => server.controlFrames.any(
        (Map<String, dynamic> f) =>
            f['action'] == 'ended' && f['trackId'] == 'aaaaaaaaaaa',
      ),
    );
    // The local player must not have advanced on its own — it moves only
    // when the room says so.
    expect(playback.current?.id, 'aaaaaaaaaaa');
    server.advanceToB();
    await untilTrue(() => playback.current?.id == 'bbbbbbbbbbb');
  });

  test('playing something else locally is reported to the room', () async {
    expect(await jam.join('ABC123'), isTrue);
    await untilTrue(() => playback.current?.id == 'aaaaaaaaaaa');
    await playback.playQueue(<Song>[songOf('ccccccccccc')]);
    await untilTrue(
      () => server.controlFrames.any(
        (Map<String, dynamic> f) =>
            f['action'] == 'setTrack' &&
            (f['track'] as Map?)?['videoId'] == 'ccccccccccc',
      ),
      timeout: const Duration(seconds: 10),
    );
  });

  test('leaving restores local control of completion', () async {
    expect(await jam.join('ABC123'), isTrue);
    await untilTrue(() => playback.deferTrackCompletion);
    await jam.leave();
    await untilTrue(() => !playback.deferTrackCompletion);
  });
}
