import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ifallmusic/core/services/jam_friends_service.dart';
import 'package:ifallmusic/core/services/listen_together_service.dart';
import 'package:ifallmusic/core/services/settings_service.dart';

import 'helpers/fake_party_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // The fake party server is a real localhost socket; undo the test
  // binding's blanket HTTP mock (which answers 400 to everything).
  HttpOverrides.global = null;

  group('room codes', () {
    test('normalisation mirrors the server', () {
      expect(normalizeJamCode('abc-def'), 'ABCDEF');
      expect(normalizeJamCode('o 1 l i'), '0111');
      expect(normalizeJamCode(' 123 456 '), '123456');
      expect(normalizeJamCode('TOOLONGCODE'), 'T0010N');
      expect(isValidJamCode(normalizeJamCode('abc-123')), isTrue);
      expect(isValidJamCode('ABC12'), isFalse);
      expect(isValidJamCode('ABC12I'), isFalse); // I is never issued
    });
  });

  group('JamService against the wire protocol', () {
    late FakePartyServer server;
    late JamService jam;

    setUp(() async {
      server = FakePartyServer();
      await server.start();
      SharedPreferences.setMockInitialValues(<String, Object>{
        SettingsService.kGapless: false,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      jam = JamService(
        settings: SettingsService(prefs),
        serverOverride: server.base,
      );
      jam.identify(
        userId: 'u-alice',
        deviceId: 'd-alice',
        displayName: 'Alice',
      );
    });

    tearDown(() async {
      jam.dispose();
      await server.stop();
    });

    /// A service with millisecond patience, so cold-start retry tests
    /// run in a blink instead of production timing. With no [budget]
    /// it matches production create/join: keep going until cancelled.
    Future<JamService> fastJam({
      Duration attemptTimeout = const Duration(seconds: 2),
      Duration? budget,
    }) async {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final JamService service = JamService(
        settings: SettingsService(prefs),
        serverOverride: server.base,
        openAttemptTimeout: attemptTimeout,
        createAttemptTimeout: attemptTimeout,
        openBudget: budget,
        rateLimitDelay: const Duration(milliseconds: 10),
        openRetryDelays: const <Duration>[Duration(milliseconds: 10)],
      );
      service.identify(
        userId: 'u-alice',
        deviceId: 'd-alice',
        displayName: 'Alice',
      );
      return service;
    }

    test('create parses the nested snapshot and playback extras', () async {
      final bool ok = await jam.create();
      expect(ok, isTrue, reason: jam.error ?? '');
      expect(jam.state, JamConnectionState.connected);
      expect(jam.code, 'ABC123');
      expect(jam.isHost, isTrue);
      expect(jam.members, hasLength(1));
      expect(jam.members.single.memberId, 'm1');
      expect(jam.queueItems, hasLength(2));
      expect(jam.currentTrack?.videoId, 'aaaaaaaaaaa');
      // queueSeq lives in the playback frame, not beside it.
      expect(jam.playback?.queueSeq, 1);
      expect(jam.autoplayEnabled, isTrue);
      await jam.leave();
      expect(jam.state, JamConnectionState.idle);
      expect(jam.inRoom, isFalse);
    });

    test('preview reads who is in a room without joining', () async {
      final (JamPreview? preview, String? error) = await jam.preview('abc123');
      expect(error, isNull);
      expect(preview?.hostName, 'Alice');
      expect(preview?.memberNames, <String>['Alice']);
      expect(preview?.isFull, isFalse);
    });

    test('create rides out a waking server (502s, then success)', () async {
      final JamService cold = await fastJam();
      try {
        server.failNextOpens = 2;
        final bool ok = await cold.create();
        expect(ok, isTrue, reason: cold.error ?? '');
        expect(server.openAttempts, 3, reason: 'two 502s, then the room');
        expect(cold.state, JamConnectionState.connected);
        expect(cold.code, 'ABC123');
        expect(cold.serverWaking, isFalse);
        await cold.leave();
      } finally {
        cold.dispose();
      }
    });

    test('create rides out a stalled first answer (timeout, then success)',
        () async {
      final JamService cold = await fastJam(
        attemptTimeout: const Duration(milliseconds: 80),
      );
      try {
        server.stallNextOpens = 1;
        server.openStall = const Duration(milliseconds: 300);
        final bool ok = await cold.create();
        expect(ok, isTrue, reason: cold.error ?? '');
        expect(server.openAttempts, 2,
            reason: 'first answer stalled past the attempt timeout');
        expect(cold.state, JamConnectionState.connected);
        // Let the stalled first answer land on the still-open client
        // (a timed-out Future does not cancel the request) instead of
        // racing teardown.
        await Future<void>.delayed(const Duration(milliseconds: 350));
        await cold.leave();
      } finally {
        cold.dispose();
      }
    });

    test('a server that never wakes gets the patient message, not one-shot',
        () async {
      final JamService cold = await fastJam(
        budget: const Duration(milliseconds: 150),
      );
      try {
        server.failNextOpens = 99;
        final bool ok = await cold.create();
        expect(ok, isFalse);
        expect(server.openAttempts, greaterThan(1),
            reason: 'it must keep asking until the budget is spent');
        expect(cold.error, contains('did not wake up'));
        expect(cold.serverWaking, isFalse);
      } finally {
        cold.dispose();
      }
    });

    test('testServer reports health and rides out booting answers', () async {
      final JamService cold = await fastJam();
      try {
        server.failNextHealths = 1;
        final (bool ok, String message) = await cold.testServer();
        expect(ok, isTrue);
        expect(message, contains('Server is up'));
        expect(server.healthAttempts, 2);
      } finally {
        cold.dispose();
      }
    });

    test('create waits out a 429 caused by its own held requests', () async {
      final JamService cold = await fastJam();
      try {
        // The router held earlier attempts during boot and delivered
        // them first, spending the two-creates-a-minute allowance.
        server.openFailStatus = HttpStatus.tooManyRequests;
        server.failNextOpens = 2;
        final bool ok = await cold.create();
        expect(ok, isTrue, reason: cold.error ?? '');
        expect(server.openAttempts, 3);
        expect(cold.state, JamConnectionState.connected);
        await cold.leave();
      } finally {
        cold.dispose();
      }
    });

    test('cancelOpen unblocks a create that would otherwise keep trying',
        () async {
      final JamService cold = await fastJam();
      try {
        server.failNextOpens = 99;
        final Future<bool> creating = cold.create();
        await untilTrue(() => server.openAttempts >= 3);
        cold.cancelOpen();
        final bool ok =
            await creating.timeout(const Duration(seconds: 5));
        expect(ok, isFalse);
        expect(cold.state, JamConnectionState.idle);
        expect(cold.error, isNull);
        expect(cold.inRoom, isFalse);
      } finally {
        cold.dispose();
      }
    });

    test('a refused first socket heals through the reconnect loop', () async {
      final JamService cold = await fastJam();
      try {
        server.failNextSockets = 1;
        final bool ok = await cold.create();
        // Holding the room + token already counts as opened; the socket
        // is earned back in the background instead of erroring out.
        expect(ok, isTrue, reason: cold.error ?? '');
        expect(cold.inRoom, isTrue);
        await untilTrue(
          () => cold.state == JamConnectionState.connected,
          timeout: const Duration(seconds: 10),
        );
        expect(server.socketAttempts, 2);
        await cold.leave();
      } finally {
        cold.dispose();
      }
    });

    test('chat settles the optimistic bubble on the server echo', () async {
      expect(await jam.create(), isTrue);
      expect(jam.sendChat('  hello   room  '), isTrue);
      expect(jam.chatMessages.single.pending, isTrue);
      await untilTrue(() => !jam.chatMessages.single.pending);
      expect(jam.chatMessages.single.text, 'hello room');
      expect(jam.chatMessages.single.by, 'Alice');
    });

    test('reportEnded is sent even when control is locked', () async {
      expect(await jam.create(), isTrue);
      // The server tells us the room is host-only and someone else hosts.
      server.socket!.add(
        '{"type":"members","members":['
        '{"memberId":"m2","userId":"u-bob","displayName":"Bob",'
        '"avatarUrl":null,"isHost":true,"joinedAtMs":1,"lastSeenMs":1,'
        '"connected":true},'
        '{"memberId":"m1","userId":"u-alice","displayName":"Alice",'
        '"avatarUrl":null,"isHost":false,"joinedAtMs":1,"lastSeenMs":1,'
        '"connected":true}],"maxMembers":5,"hostOnlyControl":true}',
      );
      await untilTrue(() => !jam.canControl);
      expect(jam.isHost, isFalse);
      jam.next();
      jam.reportEnded('aaaaaaaaaaa');
      await untilTrue(
        () => server.controlFrames
            .any((Map<String, dynamic> f) => f['action'] == 'ended'),
      );
      expect(
        server.controlFrames
            .any((Map<String, dynamic> f) => f['action'] == 'next'),
        isFalse,
        reason: 'a locked room must not take controls from a guest',
      );
    });
  });

  group('JamFriendsService', () {
    test('co-members are remembered, self is skipped, list survives reload',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final JamFriendsService friends =
          JamFriendsService(prefs, selfUserId: 'u-me');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      friends.recordMembers(const <JamMember>[
        JamMember(memberId: 'm1', userId: 'u-me', displayName: 'Me'),
        JamMember(memberId: 'm2', userId: 'u-bob', displayName: 'Bob'),
        JamMember(memberId: 'm3', userId: 'u-cid', displayName: 'Cid'),
      ]);
      // Recording again straight away is the same session, not a new one.
      friends.recordMembers(const <JamMember>[
        JamMember(memberId: 'm2', userId: 'u-bob', displayName: 'Bob'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final JamFriendsService reloaded =
          JamFriendsService(prefs, selfUserId: 'u-me');
      expect(reloaded.friends.map((JamFriend f) => f.userId),
          containsAll(<String>['u-bob', 'u-cid']));
      expect(reloaded.friends.map((JamFriend f) => f.userId),
          isNot(contains('u-me')));
      expect(reloaded.byId('u-bob')?.roomsTogether, 1);
      await reloaded.remove('u-bob');
      expect(reloaded.byId('u-bob'), isNull);
    });
  });
}
