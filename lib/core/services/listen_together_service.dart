import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/song.dart';
import 'settings_service.dart';

/// What the socket is doing right now.
enum JamConnectionState {
  /// Nothing is connected. The steady state before a room is opened.
  idle,

  /// The room is being created or joined over REST.
  joining,

  /// The WebSocket is up and the room is live.
  connected,

  /// The socket dropped (or never came up). [JamService.error] explains why.
  error,
}

/// Why the server sent us away.
enum JamByeReason { left, kicked, unknown }

/// One song in the shared queue.
///
/// Deliberately thin: enough to identify a track and to *show* it, and nothing
/// more. Stream URLs, sources, quality and download state stay each device's
/// own business, so two people in a room can be on different sources at
/// different bitrates and still be in the same place.
class JamTrack {
  const JamTrack({
    required this.videoId,
    required this.title,
    required this.artist,
    this.thumbnailUrl = '',
    this.durationMs = 0,
    this.fromAutoplay = false,
  });

  final String videoId;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final int durationMs;
  final bool fromAutoplay;

  factory JamTrack.fromJson(Map<String, dynamic> json) => JamTrack(
        videoId: json['videoId']?.toString() ?? '',
        title: json['title']?.toString() ?? 'Unknown title',
        artist: json['artist']?.toString() ?? 'Unknown artist',
        thumbnailUrl: json['thumbnailUrl']?.toString() ?? '',
        durationMs: (json['durationMs'] as num?)?.round() ?? 0,
        fromAutoplay: json['fromAutoplay'] == true,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'videoId': videoId,
        'title': title,
        'artist': artist,
        'thumbnailUrl': thumbnailUrl,
        'durationMs': durationMs,
        'fromAutoplay': fromAutoplay,
      };

  factory JamTrack.fromSong(Song song) => JamTrack(
        videoId: song.id,
        title: song.title,
        artist: song.artist,
        thumbnailUrl: song.thumbnailUrl,
        durationMs: song.duration?.inMilliseconds ?? 0,
      );

  Song toSong() => Song(
        id: videoId,
        title: title,
        artist: artist,
        thumbnailUrl: thumbnailUrl,
        duration: durationMs > 0 ? Duration(milliseconds: durationMs) : null,
      );

  @override
  bool operator ==(Object other) =>
      other is JamTrack && other.videoId == videoId;

  @override
  int get hashCode => videoId.hashCode;

  @override
  String toString() => 'JamTrack($videoId · $title)';
}

/// Someone in the room.
class JamMember {
  const JamMember({
    required this.userId,
    required this.deviceId,
    required this.displayName,
    this.avatarUrl,
    this.isHost = false,
    this.connected = true,
  });

  final String userId;
  final String deviceId;
  final String displayName;
  final String? avatarUrl;
  final bool isHost;
  final bool connected;

  factory JamMember.fromJson(Map<String, dynamic> json) => JamMember(
        userId: json['userId']?.toString() ?? '',
        deviceId: json['deviceId']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? 'Listener',
        avatarUrl: json['avatarUrl']?.toString(),
        isHost: json['isHost'] == true,
        connected: json['connected'] != false,
      );

  /// Two letters for the avatar bubble when there is no picture.
  String get initials {
    final List<String> parts = displayName
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return parts.first.substring(0, math.min(2, parts.first.length)).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}

/// The server's truth: a position, the instant it was true, and whether the
/// room is playing.
class JamPlayback {
  const JamPlayback({
    this.track,
    this.positionMs = 0,
    this.anchorMs = 0,
    this.isPlaying = false,
    this.seq = 0,
    this.startedBy,
    this.startedByName,
    this.updatedBy,
  });

  final JamTrack? track;
  final int positionMs;
  final int anchorMs;
  final bool isPlaying;

  /// Monotonic version. **A state whose `seq` is not greater than the last one
  /// applied must be ignored** — that is what makes two people hitting pause at
  /// the same moment settle instead of oscillate.
  final int seq;

  final String? startedBy;
  final String? startedByName;
  final String? updatedBy;

  factory JamPlayback.fromJson(Map<String, dynamic> json) => JamPlayback(
        track: json['track'] is Map
            ? JamTrack.fromJson((json['track'] as Map).cast<String, dynamic>())
            : null,
        positionMs: (json['positionMs'] as num?)?.round() ?? 0,
        anchorMs: (json['anchorMs'] as num?)?.round() ?? 0,
        isPlaying: json['isPlaying'] == true,
        seq: (json['seq'] as num?)?.round() ?? 0,
        startedBy: json['startedBy']?.toString(),
        startedByName: json['startedByName']?.toString(),
        updatedBy: json['updatedBy']?.toString(),
      );
}

/// The room itself.
class JamParty {
  const JamParty({
    required this.code,
    required this.maxMembers,
    this.hostOnlyControl = false,
  });

  final String code;
  final int maxMembers;
  final bool hostOnlyControl;

  factory JamParty.fromJson(Map<String, dynamic> json) => JamParty(
        code: json['code']?.toString() ?? '',
        maxMembers: (json['maxMembers'] as num?)?.round() ?? 5,
        hostOnlyControl: json['hostOnlyControl'] == true,
      );
}

/// Shared-queue snapshot.
class JamQueue {
  const JamQueue({
    this.items = const <JamTrack>[],
    this.index = 0,
    this.seq = 0,
  });

  final List<JamTrack> items;
  final int index;
  final int seq;

  factory JamQueue.fromJson(Map<String, dynamic> json) => JamQueue(
        items: (json['items'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map m) => JamTrack.fromJson(m.cast<String, dynamic>()))
            .toList(),
        index: (json['index'] as num?)?.round() ?? 0,
        seq: (json['seq'] as num?)?.round() ?? 0,
      );
}

/// The **Listen Together** client.
///
/// Create a room, share its six-character code, and everybody in it hears the
/// same thing at the same time. Anyone can control the music unless the host
/// has locked it down.
///
/// ### How devices stay in time
///
/// Nothing is synchronised by broadcasting "play now" — a frame that arrives
/// 40 ms late on one phone and 300 ms late on another would start them a
/// quarter of a second apart, and re-sending it more often would only
/// re-spread it.
///
/// Instead the server holds **a position and the server time that position was
/// true at**. Each device knows its own offset from that clock (measured with a
/// ping/pong exchange, keeping the sample with the smallest round trip — the
/// NTP trick), so it can answer "where should I be *right now*" locally:
///
/// ```
/// serverNow = deviceNow + clockOffset
/// playhead  = positionMs + max(0, serverNow - anchorMs)   // while playing
/// playhead  = positionMs                                   // while paused
/// ```
///
/// A delayed frame carries an anchor that is correspondingly further in the
/// past, so it still lands the device in exactly the right place.
///
/// The server's state is the truth. Devices *report* their real playhead
/// through [reportPosition], but that is only logged — a room is never
/// averaged towards a straggler on a bad connection.
class JamService extends ChangeNotifier {
  JamService({
    required SettingsService settings,
    http.Client? client,
  })  : _settings = settings,
        _client = client ?? http.Client();

  final SettingsService _settings;
  final http.Client _client;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _pingTimer;

  JamConnectionState _state = JamConnectionState.idle;
  String? _error;
  String? _token;
  JamParty? _party;
  JamMember? _you;
  List<JamMember> _members = const <JamMember>[];
  JamPlayback? _playback;
  JamQueue _queue = const JamQueue();
  int _appliedSeq = -1;
  int _appliedQueueSeq = -1;

  /// Server clock minus device clock, in milliseconds.
  ///
  /// Estimated from ping/pong; `null` until the first round trip completes,
  /// at which point [positionNow] can be trusted.
  int? _clockOffsetMs;
  int? _bestRoundTripMs;

  /// The identity handed to the server when a room is created or joined.
  String _userId = '';
  String _deviceId = '';
  String _displayName = '';
  String? _avatarUrl;

  // ------------------------------------------------------------------ getters
  JamConnectionState get state => _state;
  String? get error => _error;
  bool get isConnected => _state == JamConnectionState.connected;
  JamParty? get party => _party;
  JamMember? get you => _you;
  List<JamMember> get members => _members;
  JamPlayback? get playback => _playback;
  JamQueue get queue => _queue;
  List<JamTrack> get queueItems => _queue.items;
  int get queueIndex => _queue.index;
  JamTrack? get currentTrack => _playback?.track;
  String? get code => _party?.code;
  bool get isHost => _you?.isHost ?? false;
  bool get hostOnlyControl => _party?.hostOnlyControl ?? false;
  bool get isPaused => !(_playback?.isPlaying ?? false);

  /// True when this device is allowed to drive playback.
  bool get canControl => isConnected && (!hostOnlyControl || isHost);

  /// How far the device clock is from the server's, once measured.
  int? get clockOffsetMs => _clockOffsetMs;

  /// The room's playhead *right now*, derived locally from the last anchor.
  Duration get positionNow => positionAt(DateTime.now());

  Duration positionAt(DateTime deviceNow) {
    final JamPlayback? p = _playback;
    if (p == null) return Duration.zero;
    if (!p.isPlaying) return Duration(milliseconds: p.positionMs);
    final int serverNow =
        deviceNow.millisecondsSinceEpoch + (_clockOffsetMs ?? 0);
    final int elapsed = math.max(0, serverNow - p.anchorMs);
    return Duration(milliseconds: p.positionMs + elapsed);
  }

  /// The base address with any trailing slash removed.
  String get serverBase =>
      _settings.jamServer.trim().replaceAll(RegExp(r'/+$'), '');

  bool get hasServer => serverBase.isNotEmpty;

  /// The address shown in the UI while no server is configured.
  static const String placeholderServer = 'https://party.example.com';

  // ------------------------------------------------------------------- setup

  /// Registers who this device is. Called once at startup from the profile.
  void identify({
    required String userId,
    required String deviceId,
    required String displayName,
    String? avatarUrl,
  }) {
    _userId = userId;
    _deviceId = deviceId;
    _displayName = displayName;
    _avatarUrl = avatarUrl;
  }

  Map<String, dynamic> get _identity => <String, dynamic>{
        'userId': _userId,
        'deviceId': _deviceId,
        'displayName': _settings.jamDisplayName.isNotEmpty
            ? _settings.jamDisplayName
            : _displayName,
        if (_avatarUrl != null && _avatarUrl!.isNotEmpty) 'avatarUrl': _avatarUrl,
      };

  Map<String, String> get _authHeaders => <String, String>{
        'Authorization': 'Bearer ${_token ?? ''}',
        'Content-Type': 'application/json',
      };

  // ------------------------------------------------------------- create / join

  /// Opens a new room and joins it as the host.
  Future<bool> create() => _open(create: true);

  /// Joins an existing room from its six-character code.
  Future<bool> join(String code) => _open(create: false, code: code);

  Future<bool> _open({required bool create, String? code}) async {
    if (!hasServer) {
      _fail('No Listen Together server is set. Add one in Settings.');
      return false;
    }
    final String normalised = (code ?? '').trim().toUpperCase();
    _setState(JamConnectionState.joining);
    _error = null;
    try {
      final Uri uri = create
          ? Uri.parse('$serverBase/api/parties')
          : Uri.parse(
              '$serverBase/api/parties/${Uri.encodeComponent(normalised)}/join',
            );
      final http.Response response = await _client
          .post(
            uri,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(_identity),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200 && response.statusCode != 201) {
        _fail(_explainStatus(response.statusCode, response.body));
        return false;
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        _fail('The server sent something we could not read.');
        return false;
      }
      _absorbSnapshot(decoded.cast<String, dynamic>());
      if (_token == null || _token!.isEmpty) {
        _fail('The server did not hand back a token.');
        return false;
      }
      await _settings.setJamLastCode(_party?.code);
      await _connectSocket();
      return _state == JamConnectionState.connected;
    } on TimeoutException {
      _fail('The Listen Together server did not answer in time.');
      return false;
    } catch (e) {
      _fail('Could not reach the Listen Together server: $e');
      return false;
    }
  }

  /// Reads the fields that both the REST snapshot and `welcome` carry.
  void _absorbSnapshot(Map<String, dynamic> payload) {
    _token = payload['token']?.toString() ?? _token;
    if (payload['you'] is Map) {
      _you = JamMember.fromJson((payload['you'] as Map).cast<String, dynamic>());
    }
    if (payload['party'] is Map) {
      _party = JamParty.fromJson((payload['party'] as Map).cast<String, dynamic>());
    }
    if (payload['queue'] is Map) {
      _applyQueue((payload['queue'] as Map).cast<String, dynamic>());
    }
    if (payload['playback'] is Map) {
      _applyPlayback((payload['playback'] as Map).cast<String, dynamic>());
    }
    if (payload['members'] is List) {
      _members = (payload['members'] as List)
          .whereType<Map>()
          .map((Map m) => JamMember.fromJson(m.cast<String, dynamic>()))
          .toList();
    }
    final Object? serverMs = payload['serverMs'];
    if (serverMs is num && _clockOffsetMs == null) {
      _clockOffsetMs =
          serverMs.round() - DateTime.now().millisecondsSinceEpoch;
    }
  }

  String _explainStatus(int status, String body) {
    String server = '';
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map) {
        server = (decoded['error'] ?? decoded['message'])?.toString() ?? '';
      }
    } catch (_) {
      // A plain-text body is fine; fall through to the generic message.
    }
    return switch (status) {
      404 => 'No room with that code.',
      409 => server.isNotEmpty ? server : 'That room is full.',
      422 => 'The server needs a name before you can join.',
      429 => 'Too many rooms too quickly. Try again in a minute.',
      _ => server.isNotEmpty
          ? server
          : 'The server refused the request ($status).',
    };
  }

  Future<void> _connectSocket() async {
    final String? code = _party?.code;
    if (code == null || !hasServer) return;
    final Uri ws = Uri.parse(serverBase.replaceFirst(RegExp(r'^http'), 'ws'))
        .replace(path: '/ws/parties/${Uri.encodeComponent(code)}');
    try {
      // The token rides in a header, not the URL: a token in a path lands in
      // ordinary HTTP access logs.
      _socket = await WebSocket.connect(
        ws.toString(),
        headers: <String, String>{'Authorization': 'Bearer ${_token ?? ''}'},
      ).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      _fail('The room did not answer in time.');
      return;
    } catch (e) {
      _fail('Could not open the room connection: $e');
      return;
    }
    await _sub?.cancel();
    _sub = _socket!.listen(
      _onFrame,
      onError: (Object error) => _fail('The room connection dropped: $error'),
      onDone: () {
        if (_state == JamConnectionState.connected) {
          _state = JamConnectionState.error;
          _error = 'The room connection closed.';
          notifyListeners();
        }
      },
      cancelOnError: false,
    );
    _setState(JamConnectionState.connected);
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _ping());
    _ping();
    _send(<String, dynamic>{'type': 'sync'});
  }

  /// Sends a frame. Silently drops it when nothing is connected.
  void _send(Map<String, dynamic> frame) {
    final WebSocket? socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) return;
    try {
      socket.add(jsonEncode(frame));
    } catch (_) {
      // A closed socket during teardown is expected; nothing to recover from.
    }
  }

  void _ping() {
    _send(<String, dynamic>{
      'type': 'ping',
      'clientMs': DateTime.now().millisecondsSinceEpoch,
    });
  }

  void _noteClockSample(int sentAt, int serverMs) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    final int roundTrip = now - sentAt;
    // Keeping the sample with the *smallest* round trip is what makes this
    // accurate over mobile data: the error is bounded by half the round trip.
    if (_bestRoundTripMs != null && roundTrip >= _bestRoundTripMs!) return;
    _bestRoundTripMs = roundTrip;
    _clockOffsetMs = serverMs - ((sentAt + now) ~/ 2);
  }

  // ------------------------------------------------------------ frame handling

  void _onFrame(dynamic raw) {
    if (raw is! String) return;
    Map<String, dynamic> frame;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      frame = decoded.cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (frame['type']) {
      case 'welcome':
        _absorbSnapshot(frame);
        notifyListeners();
      case 'pong':
        final int? clientMs = (frame['clientMs'] as num?)?.round();
        final int? serverMs = (frame['serverMs'] as num?)?.round();
        if (clientMs != null && serverMs != null) {
          _noteClockSample(clientMs, serverMs);
        }
      case 'state':
        if (frame['playback'] is Map) {
          _applyPlayback((frame['playback'] as Map).cast<String, dynamic>());
        }
        final int? queueSeq = (frame['queueSeq'] as num?)?.round();
        if (queueSeq != null && queueSeq != _appliedQueueSeq) {
          // Self-healing half: a missed queue broadcast is noticed on the very
          // next heartbeat rather than lived with.
          _send(<String, dynamic>{'type': 'syncQueue'});
        }
        notifyListeners();
      case 'queue':
        if (frame['queue'] is Map) {
          _applyQueue((frame['queue'] as Map).cast<String, dynamic>());
          notifyListeners();
        }
      case 'members':
        if (frame['members'] is List) {
          _members = (frame['members'] as List)
              .whereType<Map>()
              .map((Map m) => JamMember.fromJson(m.cast<String, dynamic>()))
              .toList();
        }
        if (frame['maxMembers'] is num) {
          _party = JamParty(
            code: _party?.code ?? '',
            maxMembers: (frame['maxMembers'] as num).round(),
            hostOnlyControl: _party?.hostOnlyControl ?? false,
          );
        }
        if (frame['hostOnlyControl'] != null) {
          _party = JamParty(
            code: _party?.code ?? '',
            maxMembers: _party?.maxMembers ?? 5,
            hostOnlyControl: frame['hostOnlyControl'] == true,
          );
        }
        notifyListeners();
      case 'error':
        _error = (frame['message'] ?? frame['error'])?.toString() ??
            'The room refused that.';
        notifyListeners();
      case 'bye':
        final JamByeReason reason = switch (frame['reason']) {
          'left' => JamByeReason.left,
          'kicked' => JamByeReason.kicked,
          _ => JamByeReason.unknown,
        };
        _teardown();
        _state = JamConnectionState.idle;
        _error = reason == JamByeReason.kicked
            ? 'The host removed you from the room.'
            : null;
        notifyListeners();
    }
  }

  /// Applies a state frame — **unless its `seq` has gone backwards**, which is
  /// what stops two devices from fighting over the same pause.
  void _applyPlayback(Map<String, dynamic> json) {
    final JamPlayback incoming = JamPlayback.fromJson(json);
    if (incoming.seq <= _appliedSeq) return;
    _appliedSeq = incoming.seq;
    _playback = incoming;
  }

  void _applyQueue(Map<String, dynamic> json) {
    final JamQueue incoming = JamQueue.fromJson(json);
    if (incoming.seq < _appliedQueueSeq) return;
    _appliedQueueSeq = incoming.seq;
    _queue = incoming;
  }

  // ------------------------------------------------------------------ controls

  /// Plays, resuming from [positionMs] when given.
  void play({int? positionMs}) => _control('play', <String, dynamic>{
        if (positionMs != null) 'positionMs': positionMs,
      });

  void pause({int? positionMs}) => _control('pause', <String, dynamic>{
        if (positionMs != null) 'positionMs': positionMs,
      });

  void seek(Duration position) => _control(
        'seek',
        <String, dynamic>{'positionMs': position.inMilliseconds},
      );

  void next() => _control('next', const <String, dynamic>{});

  void previous() => _control('previous', const <String, dynamic>{});

  /// Puts a track on, optionally from a position and playing straight away.
  void setTrack(
    JamTrack track, {
    int positionMs = 0,
    bool isPlaying = true,
  }) =>
      _control('setTrack', <String, dynamic>{
        'track': track.toJson(),
        'positionMs': positionMs,
        'isPlaying': isPlaying,
      });

  /// Replaces the whole shared queue.
  void setQueue(List<JamTrack> tracks, {int index = 0}) =>
      _control('setQueue', <String, dynamic>{
        'queue': tracks.map((JamTrack t) => t.toJson()).toList(),
        'queueIndex': index,
      });

  /// Adds tracks at the end, or straight after the current one.
  void addToQueue(List<JamTrack> tracks, {bool playNext = false}) =>
      _control('queueAdd', <String, dynamic>{
        'tracks': tracks.map((JamTrack t) => t.toJson()).toList(),
        'playNext': playNext,
      });

  void removeFromQueue(String videoId) =>
      _control('queueRemove', <String, dynamic>{'videoId': videoId});

  void clearQueue() => _control('queueClear', const <String, dynamic>{});

  void moveInQueue(int from, int to, {String? videoId}) =>
      _control('queueMove', <String, dynamic>{
        'fromIndex': from,
        'toIndex': to,
        if (videoId != null) 'videoId': videoId,
      });

  /// Host only: lock or unlock control.
  void setHostOnlyControl(bool enabled) =>
      _control('setHostOnlyControl', <String, dynamic>{'enabled': enabled});

  /// Host only: change how many devices fit in the room.
  void setMaxMembers(int count) =>
      _control('setMaxMembers', <String, dynamic>{'maxMembers': count});

  /// Host only: remove somebody.
  void kick(String deviceId) =>
      _control('kick', <String, dynamic>{'deviceId': deviceId});

  void _control(String action, Map<String, dynamic> extra) {
    if (!canControl) return;
    _send(<String, dynamic>{'type': 'control', 'action': action, ...extra});
  }

  /// Tells the server where this device really is. It is only logged there —
  /// a room is never averaged towards a straggler on a bad connection.
  void reportPosition(Duration position, {required bool isPlaying}) {
    _send(<String, dynamic>{
      'type': 'report',
      'positionMs': position.inMilliseconds,
      'isPlaying': isPlaying,
    });
  }

  /// Asks for the truth again — used after the app comes back to the front.
  void resync() {
    _send(<String, dynamic>{'type': 'sync'});
    _send(<String, dynamic>{'type': 'syncQueue'});
    _ping();
  }

  // -------------------------------------------------------------------- leave

  /// Gives up the slot and closes the socket.
  Future<void> leave() async {
    final String? code = _party?.code;
    if (code != null && hasServer && _token != null) {
      try {
        await _client
            .post(
              Uri.parse(
                '$serverBase/api/parties/${Uri.encodeComponent(code)}/leave',
              ),
              headers: _authHeaders,
            )
            .timeout(const Duration(seconds: 8));
      } catch (_) {
        // Leaving is best-effort: the server reclaims the slot on timeout.
      }
    }
    _teardown();
    _state = JamConnectionState.idle;
    _error = null;
    notifyListeners();
  }

  void _teardown() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _party = null;
    _you = null;
    _members = const <JamMember>[];
    _playback = null;
    _queue = const JamQueue();
    _appliedSeq = -1;
    _appliedQueueSeq = -1;
    _clockOffsetMs = null;
    _bestRoundTripMs = null;
    _token = null;
    try {
      _socket?.close();
    } catch (_) {
      // Already closed — nothing to do.
    }
    _socket = null;
    _sub?.cancel();
    _sub = null;
  }

  void _setState(JamConnectionState state) {
    _state = state;
    notifyListeners();
  }

  void _fail(String message) {
    _teardown();
    _state = JamConnectionState.error;
    _error = message;
    notifyListeners();
  }

  /// Clears a shown error without retrying.
  void clearError() {
    _error = null;
    if (_state == JamConnectionState.error) _state = JamConnectionState.idle;
    notifyListeners();
  }

  @override
  void dispose() {
    _teardown();
    _client.close();
    super.dispose();
  }
}
