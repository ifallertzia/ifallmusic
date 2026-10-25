import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ifallmusic/core/services/jam_friends_service.dart';
import 'package:ifallmusic/core/services/listen_together_service.dart';
import 'package:ifallmusic/core/services/settings_service.dart';

import 'helpers/fake_party_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        SettingsService.kJamServer: server.base,
        SettingsService.kGapless: false,
      });
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      jam = JamService(settings: SettingsService(prefs));
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
