import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A minimal in-process stand-in for the Go party server, speaking the
/// exact wire shapes the real one does (nested `party` snapshots,
/// `queueSeq` inside playback, chat broadcasts). Records what the client
/// sends so tests can assert on it.
class FakePartyServer {
  HttpServer? _server;
  WebSocket? socket;

  final List<Map<String, dynamic>> controlFrames =
      <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> chatLog = <Map<String, dynamic>>[];
  int chatSeq = 0;
  int playbackSeq = 1;
  Map<String, dynamic>? trackNow;

  /// Cold-start simulation knobs: make the next N create/join calls fail
  /// the way a booting free host does — 502s, or answers so slowly the
  /// client's per-attempt timeout fires first. [openAttempts] counts
  /// how many times the client kept asking.
  int failNextOpens = 0;
  int openFailStatus = HttpStatus.badGateway;
  int stallNextOpens = 0;
  Duration openStall = const Duration(milliseconds: 300);
  int openAttempts = 0;
  int failNextHealths = 0;
  int healthAttempts = 0;

  /// Refuse the next N WebSocket upgrades outright (500, no upgrade) —
  /// the way a just-booted process or a flaky edge sometimes does.
  int failNextSockets = 0;
  int socketAttempts = 0;

  static const Map<String, dynamic> trackA = <String, dynamic>{
    'videoId': 'aaaaaaaaaaa',
    'title': 'Track A',
    'artist': 'Artist',
    'thumbnailUrl': '',
    'durationMs': 180000,
    'fromAutoplay': false,
  };
  static const Map<String, dynamic> trackB = <String, dynamic>{
    'videoId': 'bbbbbbbbbbb',
    'title': 'Track B',
    'artist': 'Artist',
    'thumbnailUrl': '',
    'durationMs': 180000,
    'fromAutoplay': false,
  };

  String get base => 'http://127.0.0.1:${_server!.port}';

  int _now() => DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> _you() => <String, dynamic>{
        'memberId': 'm1',
        'userId': 'u-alice',
        'displayName': 'Alice',
        'avatarUrl': null,
        'isHost': true,
        'joinedAtMs': _now(),
        'lastSeenMs': _now(),
        'connected': true,
      };

  Map<String, dynamic> _playback() => <String, dynamic>{
        'track': trackNow,
        'positionMs': 0,
        'anchorMs': _now(),
        'isPlaying': trackNow != null,
        'seq': playbackSeq,
        'queueSeq': 1,
        'queueIndex': trackNow == trackB ? 1 : 0,
        'queueLength': 2,
        'autoplayEnabled': true,
        'startedBy': null,
        'startedByName': null,
        'updatedBy': null,
      };

  Map<String, dynamic> _queue() => <String, dynamic>{
        'items': <Map<String, dynamic>>[trackA, trackB],
        'index': trackNow == trackB ? 1 : 0,
        'seq': 1,
      };

  Map<String, dynamic> _party() => <String, dynamic>{
        'code': 'ABC123',
        'hostOnlyControl': false,
        'maxMembers': 5,
        'createdAtMs': _now(),
        'lastActiveMs': _now(),
        'members': <Map<String, dynamic>>[_you()],
        'playback': _playback(),
        'queue': _queue(),
        'chat': chatLog,
        'chatSeq': chatSeq,
        'serverMs': _now(),
      };

  Map<String, dynamic> _snapshot() => <String, dynamic>{
        'ok': true,
        'code': 'ABC123',
        'token': 'tok-1',
        'you': _you(),
        'party': _party(),
        'serverMs': _now(),
      };

  Future<void> start({bool withTrack = true}) async {
    trackNow = withTrack ? trackA : null;
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server!.listen((HttpRequest request) async {
      final String path = request.uri.path;
      if (path.startsWith('/ws/')) {
        socketAttempts++;
        if (failNextSockets > 0) {
          failNextSockets--;
          request.response.statusCode = HttpStatus.internalServerError;
          await request.response.close();
          return;
        }
        final WebSocket ws = await WebSocketTransformer.upgrade(request);
        socket = ws;
        ws.add(jsonEncode(<String, dynamic>{
          'type': 'welcome',
          'you': _you(),
          'party': _party(),
          'serverMs': _now(),
        }));
        ws.listen((dynamic raw) {
          if (raw is! String) return;
          final Object? decoded = jsonDecode(raw);
          if (decoded is! Map) return;
          final Map<String, dynamic> frame =
              decoded.cast<String, dynamic>();
          switch (frame['type']) {
            case 'ping':
              ws.add(jsonEncode(<String, dynamic>{
                'type': 'pong',
                'clientMs': frame['clientMs'],
                'serverMs': _now(),
              }));
            case 'sync':
              sendState();
            case 'syncQueue':
              ws.add(jsonEncode(<String, dynamic>{
                'type': 'queue',
                'queue': _queue(),
                'serverMs': _now(),
              }));
            case 'syncChat':
              ws.add(jsonEncode(<String, dynamic>{
                'type': 'chat',
                'snapshot': true,
                'chatSeq': chatSeq,
                'messages': chatLog,
                'serverMs': _now(),
              }));
            case 'chat':
              chatSeq++;
              final Map<String, dynamic> message = <String, dynamic>{
                'id': frame['id'],
                'memberId': 'm1',
                'userId': 'u-alice',
                'by': 'Alice',
                'text': frame['text'],
                'atMs': _now(),
              };
              chatLog.add(message);
              ws.add(jsonEncode(<String, dynamic>{
                'type': 'chat',
                'chatSeq': chatSeq,
                'message': message,
                'serverMs': _now(),
              }));
            case 'control':
              controlFrames.add(frame);
          }
        });
        return;
      }
      final bool isOpen = request.method == 'POST' &&
          (path == '/api/parties' || path.endsWith('/join'));
      if (isOpen) {
        openAttempts++;
        if (stallNextOpens > 0) {
          stallNextOpens--;
          await Future<void>.delayed(openStall);
        }
        if (failNextOpens > 0) {
          failNextOpens--;
          request.response.statusCode = openFailStatus;
          request.response.write('{"error":"booting"}');
          await request.response.close();
          return;
        }
      }
      if (request.method == 'GET' && path == '/healthz') {
        healthAttempts++;
        if (failNextHealths > 0) {
          failNextHealths--;
          request.response.statusCode = HttpStatus.badGateway;
          request.response.write('{"error":"booting"}');
        } else {
          request.response.write(jsonEncode(<String, dynamic>{
            'ok': true,
            'serverMs': _now(),
          }));
        }
      } else if (request.method == 'POST' && path == '/api/parties') {
        request.response.statusCode = HttpStatus.created;
        request.response.write(jsonEncode(_snapshot()));
      } else if (request.method == 'POST' && path.endsWith('/join')) {
        request.response.write(jsonEncode(_snapshot()));
      } else if (request.method == 'POST' && path.endsWith('/leave')) {
        request.response.write('{"ok":true}');
      } else if (request.method == 'GET' && path.endsWith('/preview')) {
        request.response.write(jsonEncode(<String, dynamic>{
          'code': 'ABC123',
          'exists': true,
          'hostName': 'Alice',
          'memberCount': 1,
          'maxMembers': 5,
          'isFull': false,
          'members': <Map<String, dynamic>>[
            <String, dynamic>{
              'displayName': 'Alice',
              'avatarUrl': null,
              'isHost': true,
            },
          ],
          'serverMs': _now(),
        }));
      } else {
        request.response.statusCode = HttpStatus.notFound;
        request.response.write('{"error":"no_such_party"}');
      }
      await request.response.close();
    });
  }

  /// Pushes the current playback state as the server would after a control.
  void sendState() {
    socket?.add(jsonEncode(<String, dynamic>{
      'type': 'state',
      'playback': _playback(),
      'serverMs': _now(),
    }));
  }

  /// Advances the room to track B, the way an accepted "ended"/"next"
  /// would come back to every client.
  void advanceToB() {
    trackNow = trackB;
    playbackSeq++;
    sendState();
    socket?.add(jsonEncode(<String, dynamic>{
      'type': 'queue',
      'queue': _queue(),
      'serverMs': _now(),
    }));
  }

  Future<void> stop() async {
    try {
      await socket?.close();
    } catch (_) {}
    await _server?.close(force: true);
  }
}

/// Polls until [condition] holds or the timeout runs out.
Future<void> untilTrue(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 6),
}) async {
  final DateTime deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
