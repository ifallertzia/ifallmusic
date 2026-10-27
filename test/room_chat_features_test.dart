import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ifallmusic/core/services/listen_together_service.dart';
import 'package:ifallmusic/core/services/settings_service.dart';

import 'helpers/fake_party_server.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('chat message model', () {
    test('parses replies, reactions, sequence and edit stamp', () {
      final JamChatMessage m = JamChatMessage.fromJson(<String, dynamic>{
        'id': 'id-1',
        'memberId': 'm2',
        'userId': 'u-bob',
        'by': 'Bob',
        'text': 'hello',
        'atMs': 1234,
        'seq': 7,
        'replyTo': <String, dynamic>{
          'id': 'id-0',
          'by': 'Alice',
          'text': 'first',
        },
        'reactions': <String, dynamic>{
          '🔥': <String>['m1', 'm3'],
        },
        'editedAtMs': 5678,
      });
      expect(m.seq, 7);
      expect(m.replyTo?.by, 'Alice');
      expect(m.replyTo?.text, 'first');
      expect(m.reactions['🔥'], <String>['m1', 'm3']);
      expect(m.reactedBy('🔥', 'm1'), isTrue);
      expect(m.reactedBy('🔥', 'm9'), isFalse);
      expect(m.editedAtMs, 5678);
      expect(m.copyWith(text: 'edited').replyTo?.id, 'id-0');
      expect(JamReply.of(m).toJson()['text'], 'hello');
    });
  });

  group('room chat on the wire', () {
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
      expect(await jam.create(), isTrue, reason: jam.error ?? '');
      // Let the initial syncChat handshake finish before we push server
      // frames, so the real socket's startup traffic cannot race the test.
      await untilTrue(
        () => server.allFrames.any(
          (Map<String, dynamic> f) => f['type'] == 'syncChat',
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 60));
    });

    tearDown(() async {
      jam.dispose();
      await server.stop();
    });

    void push(Map<String, dynamic> frame) {
      server.socket!.add(jsonEncode(frame));
    }

    test('a reply travels with the message and survives the echo', () async {
      push(<String, dynamic>{
        'type': 'chat',
        'chatSeq': 1,
        'message': <String, dynamic>{
          'id': 'from-bob',
          'memberId': 'm2',
          'userId': 'u-bob',
          'by': 'Bob',
          'text': 'hello',
          'atMs': 1000,
          'seq': 1,
        },
      });
      await untilTrue(() => jam.chatMessages.isNotEmpty);
      final JamChatMessage bob = jam.chatMessages.first;
      expect(jam.sendChat('hi!', replyTo: bob), isTrue);
      await untilTrue(
        () => server.allFrames.any(
          (Map<String, dynamic> f) =>
              f['type'] == 'chat' && f['replyTo'] != null,
        ),
      );
      final Map<String, dynamic> sent = server.allFrames.firstWhere(
        (Map<String, dynamic> f) =>
            f['type'] == 'chat' && f['replyTo'] != null,
      );
      expect((sent['replyTo'] as Map)['by'], 'Bob');
      expect(jam.chatMessages.last.replyTo?.id, 'from-bob');
    });

    test('edit and reaction update one bubble without adding another', () async {
      push(<String, dynamic>{
        'type': 'chat',
        'chatSeq': 1,
        'message': <String, dynamic>{
          'id': 'own-1',
          'memberId': 'm1',
          'userId': 'u-alice',
          'by': 'Alice',
          'text': 'before',
          'atMs': 1000,
          'seq': 1,
        },
      });
      await untilTrue(() => jam.chatMessages.isNotEmpty);
      final JamChatMessage own = jam.chatMessages.first;

      expect(jam.editChat(own, '  after   edit  '), isTrue);
      expect(jam.chatMessages.single.text, 'after edit');
      expect(jam.chatMessages.single.editedAtMs, greaterThan(0));

      jam.toggleReaction(jam.chatMessages.single, '🔥');
      expect(jam.chatMessages.single.reactedBy('🔥', 'm1'), isTrue);
      await untilTrue(
        () => server.allFrames.any(
              (Map<String, dynamic> f) => f['type'] == 'chatEdit',
            ) &&
            server.allFrames.any(
              (Map<String, dynamic> f) => f['type'] == 'chatReact',
            ),
      );

      // The server's update frame replaces the same line in place.
      push(<String, dynamic>{
        'type': 'chat',
        'update': true,
        'chatSeq': 1,
        'message': <String, dynamic>{
          'id': 'own-1',
          'memberId': 'm1',
          'userId': 'u-alice',
          'by': 'Alice',
          'text': 'server truth',
          'atMs': 1000,
          'seq': 1,
          'reactions': <String, dynamic>{
            '🔥': <String>['m1', 'm2'],
          },
        },
      });
      await untilTrue(() => jam.chatMessages.single.text == 'server truth');
      expect(jam.chatMessages, hasLength(1));
      expect(jam.chatMessages.single.reactions['🔥'], hasLength(2));
    });

    test('single tick becomes two when another member reads', () async {
      push(<String, dynamic>{
        'type': 'chat',
        'chatSeq': 1,
        'message': <String, dynamic>{
          'id': 'own-1',
          'memberId': 'm1',
          'userId': 'u-alice',
          'by': 'Alice',
          'text': 'hello?',
          'atMs': 1000,
          'seq': 1,
        },
      });
      await untilTrue(() => jam.chatMessages.isNotEmpty);
      expect(jam.isReadByOthers(jam.chatMessages.single), isFalse);

      jam.markChatRead(1);
      await untilTrue(
        () => server.allFrames.any(
          (Map<String, dynamic> f) => f['type'] == 'chatRead',
        ),
      );

      // Bob's device read the line: the sender's tick turns green.
      push(<String, dynamic>{
        'type': 'chatRead',
        'chatSeq': 1,
        'reads': <String, dynamic>{'m1': 1, 'm2': 1},
      });
      await untilTrue(() => jam.maxOtherReadSeq == 1);
      expect(jam.isReadByOthers(jam.chatMessages.single), isTrue);
    });

    test('join and leave produce spoken announcements', () async {
      final List<JamPresenceEvent> events = <JamPresenceEvent>[];
      jam.onPresence = events.add;
      push(<String, dynamic>{
        'type': 'members',
        'members': <Map<String, dynamic>>[
          <String, dynamic>{
            'memberId': 'm1',
            'userId': 'u-alice',
            'displayName': 'Alice',
            'isHost': true,
            'connected': true,
          },
          <String, dynamic>{
            'memberId': 'm2',
            'userId': 'u-bob',
            'displayName': 'Bob',
            'isHost': false,
            'connected': true,
          },
        ],
        'maxMembers': 5,
      });
      await untilTrue(() => events.isNotEmpty);
      expect(events.single.name, 'Bob');
      expect(events.single.joined, isTrue);
      expect(jam.activities.any((JamActivity a) => a.action == 'join'), isTrue);

      push(<String, dynamic>{
        'type': 'members',
        'members': <Map<String, dynamic>>[
          <String, dynamic>{
            'memberId': 'm1',
            'userId': 'u-alice',
            'displayName': 'Alice',
            'isHost': true,
            'connected': true,
          },
        ],
        'maxMembers': 5,
      });
      await untilTrue(() => events.length == 2);
      expect(events.last.name, 'Bob');
      expect(events.last.joined, isFalse);
    });
  });
}
