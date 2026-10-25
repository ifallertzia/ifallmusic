import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/song.dart';
import '../utils/ids.dart';
import 'settings_service.dart';

/// What the socket is doing right now.
enum JamConnectionState {
  /// Nothing is connected. The steady state before a room is opened.
  idle,

  /// The room is being created or joined over REST.
  joining,

  /// The WebSocket is up and the room is live.
  connected,

  /// The socket dropped but the seat is being held open on the server;
  /// the client is trying to get back in by itself.
  reconnecting,

  /// The socket dropped (or never came up). [JamService.error] explains why.
  error,
}

/// Why the server sent us away.
enum JamByeReason { left, kicked, ended, unknown }

/// The characters a room code may use: digits and capitals without I, L or
/// O, so a code read aloud can't be misheard as 1 or 0. Mirrors the server.
const String jamCodeAlphabet = '0123456789ABCDEFGHJKMNPQRSTUVWXYZ';
const int jamCodeLength = 6;

/// Reads a code the way the server does: uppercases, drops anything that
/// isn't a letter or digit, and reads I/L as 1 and O as 0 — so a mistyped
/// or spacey code from a chat message still lands in the right room.
String normalizeJamCode(String input) {
  final String cleaned = input
      .toUpperCase()
      .replaceAll(RegExp(r'[^A-Z0-9]'), '')
      .replaceAll(RegExp(r'[IL]'), '1')
      .replaceAll('O', '0');
  return cleaned.length > jamCodeLength
      ? cleaned.substring(0, jamCodeLength)
      : cleaned;
}

bool isValidJamCode(String code) =>
    code.length == jamCodeLength &&
    code.split('').every(jamCodeAlphabet.contains);

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

  factory JamTrack.fromSong(Song song, {bool fromAutoplay = false}) =>
      JamTrack(
        videoId: song.id,
        title: song.title,
        artist: song.artist,
        thumbnailUrl: song.thumbnailUrl,
        durationMs: song.duration?.inMilliseconds ?? 0,
        fromAutoplay: fromAutoplay,
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
    required this.memberId,
    required this.userId,
    required this.displayName,
    this.deviceId = '',
    this.avatarUrl,
    this.isHost = false,
    this.connected = true,
    this.joinedAtMs = 0,
    this.lastSeenMs = 0,
  });

  /// The server's per-room seat id (what `kick` names).
  final String memberId;

  /// The install's stable anonymous id — what friends and invites key on.
  final String userId;

  /// Kept for older call sites; the server never sends it back.
  final String deviceId;
  final String displayName;
  final String? avatarUrl;
  final bool isHost;
  final bool connected;
  final int joinedAtMs;
  final int lastSeenMs;

  factory JamMember.fromJson(Map<String, dynamic> json) => JamMember(
        memberId: json['memberId']?.toString() ?? '',
        userId: json['userId']?.toString() ?? '',
        deviceId: json['deviceId']?.toString() ?? '',
        displayName: json['displayName']?.toString() ?? 'Listener',
        avatarUrl: json['avatarUrl']?.toString(),
        isHost: json['isHost'] == true,
        connected: json['connected'] != false,
        joinedAtMs: (json['joinedAtMs'] as num?)?.round() ?? 0,
        lastSeenMs: (json['lastSeenMs'] as num?)?.round() ?? 0,
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
    this.queueSeq = 0,
    this.queueIndex = -1,
    this.queueLength = 0,
    this.autoplayEnabled = false,
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

  /// Version of the queue contents at the time of this state; the queue
  /// itself travels in its own frame, and a mismatch here is how a missed
  /// queue broadcast gets noticed and healed.
  final int queueSeq;
  final int queueIndex;
  final int queueLength;
  final bool autoplayEnabled;
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
        queueSeq: (json['queueSeq'] as num?)?.round() ?? 0,
        queueIndex: (json['queueIndex'] as num?)?.round() ?? -1,
        queueLength: (json['queueLength'] as num?)?.round() ?? 0,
        autoplayEnabled: json['autoplayEnabled'] == true,
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

/// One line of room chat. [pending] / [failed] are local-only delivery
/// states for the optimistic bubble; the server's copy never carries them.
class JamChatMessage {
  const JamChatMessage({
    required this.id,
    required this.memberId,
    required this.userId,
    required this.by,
    required this.text,
    required this.atMs,
    this.pending = false,
    this.failed = false,
  });

  final String id;
  final String memberId;
  final String userId;
  final String by;
  final String text;
  final int atMs;
  final bool pending;
  final bool failed;

  factory JamChatMessage.fromJson(Map<String, dynamic> json) =>
      JamChatMessage(
        id: json['id']?.toString() ?? '',
        memberId: json['memberId']?.toString() ?? '',
        userId: json['userId']?.toString() ?? '',
        by: json['by']?.toString() ?? 'Listener',
        text: json['text']?.toString() ?? '',
        atMs: (json['atMs'] as num?)?.round() ?? 0,
      );

  JamChatMessage copyWith({bool? pending, bool? failed}) => JamChatMessage(
        id: id,
        memberId: memberId,
        userId: userId,
        by: by,
        text: text,
        atMs: atMs,
        pending: pending ?? this.pending,
        failed: failed ?? this.failed,
      );
}

/// One "Alice skipped to the next song" line, shown interleaved with chat.
class JamActivity {
  const JamActivity({
    required this.action,
    required this.by,
    required this.detail,
    required this.atMs,
  });

  final String action;
  final String by;
  final String detail;
  final int atMs;

  factory JamActivity.fromJson(Map<String, dynamic> json) => JamActivity(
        action: json['action']?.toString() ?? '',
        by: json['by']?.toString() ?? '',
        detail: json['detail']?.toString() ?? '',
        atMs: (json['atMs'] as num?)?.round() ?? 0,
      );
}

/// Who is in a room, without joining it — the join screen's preview.
class JamPreview {
  const JamPreview({
    required this.code,
    required this.hostName,
    required this.memberCount,
    required this.maxMembers,
    required this.isFull,
    required this.memberNames,
  });

  final String code;
  final String hostName;
  final int memberCount;
  final int maxMembers;
  final bool isFull;
  final List<String> memberNames;

  factory JamPreview.fromJson(Map<String, dynamic> json) => JamPreview(
        code: json['code']?.toString() ?? '',
        hostName: json['hostName']?.toString() ?? '',
        memberCount: (json['memberCount'] as num?)?.round() ?? 0,
        maxMembers: (json['maxMembers'] as num?)?.round() ?? 5,
        isFull: json['isFull'] == true,
        memberNames: (json['members'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map m) => m['displayName']?.toString() ?? 'Listener')
            .toList(),
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
    String? serverOverride,
    Duration openAttemptTimeout = const Duration(seconds: 20),
    Duration createAttemptTimeout = const Duration(seconds: 120),
    Duration? openBudget,
    Duration rateLimitDelay = const Duration(seconds: 20),
    List<Duration> openRetryDelays = const <Duration>[
      Duration(seconds: 1),
      Duration(seconds: 2),
      Duration(seconds: 3),
      Duration(seconds: 5),
    ],
  })  : _settings = settings,
        _client = client ?? http.Client(),
        _serverOverride = serverOverride,
        _openAttemptTimeout = openAttemptTimeout,
        _createAttemptTimeout = createAttemptTimeout,
        _openBudget = openBudget,
        _rateLimitDelay = rateLimitDelay,
        _openRetryDelays = openRetryDelays;

  final SettingsService _settings;
  final http.Client _client;

  /// Test seam: point the client at a fake server. Production passes
  /// nothing — the address is [defaultServer], a product constant that
  /// is deliberately never shown in or editable from the UI.
  final String? _serverOverride;

  /// How patiently the REST calls treat a sleeping server — modelled on
  /// BitChord's client, whose party requests carry no read timeout at
  /// all and whose socket loop never gives up.
  ///
  /// The free host shuts the process down when idle and needs most of a
  /// minute to boot, and while it boots its router *holds* requests
  /// instead of answering them. Firing short-timeout retries into that
  /// hold is worse than waiting: every queued attempt is delivered when
  /// the process comes up, so the first creates a throwaway room, the
  /// second another — and the server's two-creates-a-minute limit then
  /// rejects the attempt the user is actually waiting on. So:
  ///
  ///  - create/join get a long per-attempt timeout ([_createAttemptTimeout])
  ///    that lets one request ride out a cold start, retry after that,
  ///    treat 429 as "your own earlier attempt landed — wait it out",
  ///    and have no overall budget: they run until they succeed, get a
  ///    definitive answer, or the user cancels via [cancelOpen].
  ///  - preview/test get the shorter [_openAttemptTimeout] and bounded
  ///    budgets of their own.
  ///
  /// Constructor seams all, so tests run in milliseconds.
  final Duration _openAttemptTimeout;
  final Duration _createAttemptTimeout;
  final Duration? _openBudget;
  final Duration _rateLimitDelay;
  final List<Duration> _openRetryDelays;

  /// True while an open/preview/test call has had to retry — the UI uses
  /// it to say "waking the server up" instead of spinning in silence.
  bool _serverWaking = false;
  DateTime? _lastWarmUp;

  WebSocket? _socket;
  StreamSubscription<dynamic>? _sub;
  Timer? _pingTimer;
  Timer? _reconnectTimer;

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
  List<JamChatMessage> _chatMessages = const <JamChatMessage>[];
  int _chatSeq = 0;
  List<JamActivity> _activities = const <JamActivity>[];

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

  bool _intentionalClose = false;

  /// Cancellation for an in-flight create/join. The generation makes a
  /// late-finishing open harmless when a newer one has taken its place;
  /// the completer is what [cancelOpen] fires to unblock the waiter.
  int _openGeneration = 0;
  Completer<void>? _openCanceller;
  int _reconnectAttempt = 0;
  int _connectionGeneration = 0;

  static const int maxChatMessages = 80;
  static const int maxActivities = 30;
  static const int maxChatRunes = 300;

  // ------------------------------------------------------------------ getters
  JamConnectionState get state => _state;
  String? get error => _error;

  /// Whether a create/join/preview/test call is currently retrying
  /// against a server that is probably waking up from idle sleep.
  bool get serverWaking => _serverWaking;
  bool get isConnected => _state == JamConnectionState.connected;
  bool get isReconnecting => _state == JamConnectionState.reconnecting;

  /// True from the moment a room opens until it is left for good, including
  /// while a dropped socket is being re-established.
  bool get inRoom =>
      _party != null &&
      (_state == JamConnectionState.connected ||
          _state == JamConnectionState.reconnecting ||
          _state == JamConnectionState.joining);
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
  bool get autoplayEnabled => _playback?.autoplayEnabled ?? false;
  List<JamChatMessage> get chatMessages =>
      List<JamChatMessage>.unmodifiable(_chatMessages);
  List<JamActivity> get activities =>
      List<JamActivity>.unmodifiable(_activities);

  /// The host's name for "Alice's room" headings; '' when unknown.
  String get hostName {
    for (final JamMember m in _members) {
      if (m.isHost) return m.displayName;
    }
    return '';
  }

  /// True when this device is allowed to drive playback.
  bool get canControl => isConnected && (!hostOnlyControl || isHost);

  /// How far the device clock is from the server's, once measured.
  int? get clockOffsetMs => _clockOffsetMs;

  /// Best (smallest) measured socket round trip — the "· 84 ms" in the UI.
  int? get roundTripMs => _bestRoundTripMs;

  /// The room's playhead *right now*, derived locally from the last anchor.
  Duration get positionNow => positionAt(DateTime.now());

  Duration positionAt(DateTime deviceNow) {
    final JamPlayback? p = _playback;
    if (p == null) return Duration.zero;
    int pos = p.positionMs;
    if (p.isPlaying) {
      final int serverNow =
          deviceNow.millisecondsSinceEpoch + (_clockOffsetMs ?? 0);
      pos += math.max(0, serverNow - p.anchorMs);
    }
    final int durationMs = p.track?.durationMs ?? 0;
    if (durationMs > 0 && pos > durationMs) pos = durationMs;
    if (pos < 0) pos = 0;
    return Duration(milliseconds: pos);
  }

  /// This device's server time right now (for "away since" maths in the UI).
  int get serverNowMs =>
      DateTime.now().millisecondsSinceEpoch + (_clockOffsetMs ?? 0);

  /// The production party server (the Go program in `backend/`, running
  /// as a free Render web service — see `backend/DEPLOY.md`).
  ///
  /// This is a product constant, full stop: it is never displayed in
  /// the UI and there is no way to edit it from the app, so a listener
  /// can neither see it nor break rooms by typing a wrong one. (It
  /// necessarily travels inside shared invite links — that is what a
  /// link is.) A custom address saved by an older build is ignored.
  static const String defaultServer = 'https://ifallmusic-party.onrender.com';

  /// The base address every request goes to. Only tests bend it, via
  /// the constructor's `serverOverride`.
  String get serverBase => _serverOverride ?? defaultServer;

  bool get hasServer => serverBase.isNotEmpty;

  /// The shareable web link for the current room (the server's invite page,
  /// which hands Android straight to the app).
  String get inviteUrl {
    final String? c = code;
    if (c == null || c.isEmpty) return '';
    return '$serverBase/invite/${Uri.encodeComponent(c)}';
  }

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

  /// The name others see, in the order the app already resolves names:
  /// a room-specific name from Settings, then the profile name, then
  /// whatever [identify] was given.
  String get effectiveDisplayName {
    if (_settings.jamDisplayName.isNotEmpty) return _settings.jamDisplayName;
    if (_settings.displayName.isNotEmpty) return _settings.displayName;
    if (_displayName.isNotEmpty) return _displayName;
    return 'Listener';
  }

  Map<String, dynamic> get _identity => <String, dynamic>{
        'userId': _userId,
        'deviceId': _deviceId,
        'displayName': effectiveDisplayName,
        if (_avatarUrl != null && _avatarUrl!.isNotEmpty) 'avatarUrl': _avatarUrl,
      };

  Map<String, String> get _authHeaders => <String, String>{
        'Authorization': 'Bearer ${_token ?? ''}',
        'Content-Type': 'application/json',
      };

  // ------------------------------------------------------ waking the server

  /// One REST call, asked patiently.
  ///
  /// Free hosts sleep when idle and take the better part of a minute to
  /// wake: while the process boots, requests either hang at the edge or
  /// bounce off with 502/503/504. This loop is how the tolerance above
  /// is implemented: retry timeouts, socket errors and waking statuses
  /// — and, for create/join, also 429, which in practice means a
  /// request the router held during boot was delivered just before
  /// this one and spent the per-minute create allowance; the honest
  /// move is to wait out the fixed window and ask again.
  ///
  /// [budget] bounds the whole effort (`null` = until [cancelSignal]);
  /// [attemptTimeout] bounds one try. A definitive answer (any other
  /// status: 404 room gone, 409 full…) returns at once for the caller
  /// to explain; if the budget runs out on a waking status, the last
  /// response is returned for the same treatment. Network/timeout
  /// errors rethrow the last one, preserving the callers' existing
  /// message split. [serverWaking] is flagged while this runs long, so
  /// the UI can say what is happening.
  Future<http.Response> _withWakeRetry(
    Future<http.Response> Function() send, {
    Duration? budget,
    Duration? attemptTimeout,
    Future<void>? cancelSignal,
    bool retryRateLimit = false,
  }) async {
    final Duration? limit = budget ?? _openBudget;
    final Duration perAttempt = attemptTimeout ?? _openAttemptTimeout;
    final Stopwatch watch = Stopwatch()..start();
    bool budgetSpent() => limit != null && watch.elapsed >= limit;

    // First completion wins. (Not Future.any: that swallows an early
    // error while the loser is still pending, which would hang here.)
    Future<T> raceCancel<T>(Future<T> future) {
      if (cancelSignal == null) return future;
      final Completer<T> out = Completer<T>();
      future.then((T value) {
        if (!out.isCompleted) out.complete(value);
      }, onError: (Object error, StackTrace stack) {
        if (!out.isCompleted) out.completeError(error, stack);
      });
      cancelSignal.then((_) {
        if (!out.isCompleted) out.completeError(const _OpenCancelled());
      });
      return out.future;
    }

    int attempt = 0;
    // Even a single hung first attempt should explain itself quickly,
    // long before the attempt timeout gives the retry loop its cue.
    final Timer wakingHint = Timer(const Duration(seconds: 4), () {
      if (!_serverWaking) {
        _serverWaking = true;
        notifyListeners();
      }
    });
    try {
      while (true) {
        attempt++;
        bool rateLimited = false;
        try {
          final http.Response response =
              await raceCancel(send().timeout(perAttempt));
          rateLimited = retryRateLimit && response.statusCode == 429;
          if (!rateLimited && !_isWakingStatus(response.statusCode)) {
            return response;
          }
          if (budgetSpent()) return response;
        } on _OpenCancelled {
          rethrow;
        } catch (_) {
          // Timeout, socket or TLS blip while the host boots: ask again,
          // unless the patience budget is spent — then surface it.
          if (budgetSpent()) rethrow;
        }
        if (!_serverWaking) {
          _serverWaking = true;
          notifyListeners();
        }
        // A 429 window is a minute long and does not slide, so a longer
        // pause clears it in a few tries instead of hammering.
        final Duration delay = rateLimited
            ? _rateLimitDelay
            : _openRetryDelays.isEmpty
                ? Duration.zero
                : _openRetryDelays[
                    math.min(attempt - 1, _openRetryDelays.length - 1)];
        await raceCancel(Future<void>.delayed(delay));
      }
    } finally {
      wakingHint.cancel();
      if (_serverWaking) {
        _serverWaking = false;
        notifyListeners();
      }
    }
  }

  /// Backs out of an in-flight create/join. The underlying HTTP request
  /// cannot be un-sent, but the waiter unblocks at once and whatever it
  /// eventually does land is ignored (a stray room simply expires).
  void cancelOpen() {
    if (_state != JamConnectionState.joining && _openCanceller == null) {
      return;
    }
    _openGeneration++;
    _intentionalClose = true;
    final Completer<void>? canceller = _openCanceller;
    if (canceller != null && !canceller.isCompleted) canceller.complete();
    if (_state == JamConnectionState.joining) {
      _error = null;
      _setState(JamConnectionState.idle);
    }
  }

  /// The statuses a booting free-tier host answers with before the app
  /// process is ready to take requests.
  static bool _isWakingStatus(int status) =>
      status == 502 || status == 503 || status == 504;

  /// Nudges the server awake before anyone taps anything (the lobby
  /// calls this on open), so by the time a room is created the process
  /// is usually already up. Fire-and-forget and coalesced: at most one
  /// nudge every couple of minutes, and never while inside a room.
  void warmUp({bool force = false}) {
    if (!hasServer || inRoom) return;
    final DateTime now = DateTime.now();
    if (!force &&
        _lastWarmUp != null &&
        now.difference(_lastWarmUp!) < const Duration(minutes: 2)) {
      return;
    }
    _lastWarmUp = now;
    unawaited(() async {
      try {
        await _client
            .get(Uri.parse('$serverBase/healthz'))
            .timeout(const Duration(seconds: 75));
      } catch (_) {
        // Best effort only; create/join retry on their own.
      }
    }());
  }

  /// Asks the server whether it is alive, and explains the answer in
  /// words a person can act on (never naming the address — it is not
  /// shown anywhere in the app). This is the no-new-build sanity
  /// check: it separates "server asleep/down" from "app bug" on the
  /// spot.
  Future<(bool, String)> testServer() async {
    final Stopwatch watch = Stopwatch()..start();
    try {
      final http.Response response = await _withWakeRetry(
        () => _client.get(
          Uri.parse('$serverBase/healthz'),
          headers: const <String, String>{'Accept': 'application/json'},
        ),
        budget: const Duration(seconds: 75),
      );
      watch.stop();
      final String secs =
          (watch.elapsedMilliseconds / 1000).toStringAsFixed(1);
      if (response.statusCode == 200) {
        bool ok = false;
        try {
          final Object? decoded = jsonDecode(response.body);
          ok = decoded is Map && decoded['ok'] == true;
        } catch (_) {
          // Not JSON at all — something answered, but not our server.
        }
        return ok
            ? (true, 'Server is up — it answered in ${secs}s.')
            : (
                false,
                'Something answered in ${secs}s, but it does not look '
                    'like the room server. Try again in a bit.'
              );
      }
      return (
        false,
        'The server answered with an error (${response.statusCode}). '
            'If it was asleep, give it a minute and run the test again.'
      );
    } on TimeoutException {
      return (
        false,
        'No answer yet. The server may still be waking up — wait a '
            'few seconds and run the test again.'
      );
    } catch (_) {
      return (
        false,
        'Could not reach the server. Check your connection and run '
            'the test again.'
      );
    }
  }

  // ------------------------------------------------------------- create / join

  /// Opens a new room and joins it as the host.
  Future<bool> create({int? maxMembers, bool autoplay = true}) => _open(
        create: true,
        extra: <String, dynamic>{
          if (maxMembers != null) 'maxMembers': maxMembers,
          'autoplayEnabled': autoplay,
        },
      );

  /// Joins an existing room from its six-character code.
  Future<bool> join(String code) {
    final String normalised = normalizeJamCode(code);
    if (!isValidJamCode(normalised)) {
      _fail('Room codes are six letters or digits — check the code and try again.');
      return Future<bool>.value(false);
    }
    return _open(create: false, code: normalised);
  }

  /// Who is in a room, without taking a seat in it — for the join screen.
  /// Returns the preview, or an error message to show.
  Future<(JamPreview?, String?)> preview(String rawCode) async {
    final String code = normalizeJamCode(rawCode);
    if (!isValidJamCode(code)) {
      return (null, 'Room codes are six letters or digits.');
    }
    try {
      final http.Response response = await _withWakeRetry(
        () => _client.get(
          Uri.parse(
              '$serverBase/api/parties/${Uri.encodeComponent(code)}/preview'),
          headers: const <String, String>{'Accept': 'application/json'},
        ),
        // A look-up, not a commitment: patient through one cold start,
        // but never an open-ended wait behind a six-letter code.
        budget: const Duration(seconds: 45),
      );
      if (response.statusCode != 200) {
        return (null, _explainStatus(response.statusCode, response.body));
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        return (null, 'The server sent something we could not read.');
      }
      return (
        JamPreview.fromJson(decoded.cast<String, dynamic>()),
        null,
      );
    } on TimeoutException {
      return (null, 'The Listen Together server did not answer in time.');
    } catch (e) {
      return (null, 'Could not reach the Listen Together server.');
    }
  }

  Future<bool> _open({
    required bool create,
    String? code,
    Map<String, dynamic> extra = const <String, dynamic>{},
  }) async {
    if (!hasServer) {
      _fail('No Listen Together server is set. Add one in Settings.');
      return false;
    }
    if (_userId.isEmpty || _deviceId.isEmpty) {
      _fail('This device has no room identity yet — restart the app and try again.');
      return false;
    }
    final String normalised = (code ?? '').trim().toUpperCase();
    if (inRoom && _party != null) {
      if (!create && _party!.code == normalised && isConnected) return true;
      await leave();
    }
    _intentionalClose = false;
    _cancelReconnect();
    _reconnectAttempt = 0;
    final int gen = ++_openGeneration;
    final Completer<void> canceller = Completer<void>();
    _openCanceller = canceller;
    _setState(JamConnectionState.joining);
    _error = null;
    try {
      final Uri uri = create
          ? Uri.parse('$serverBase/api/parties')
          : Uri.parse(
              '$serverBase/api/parties/${Uri.encodeComponent(normalised)}/join',
            );
      // No overall budget: a cold start takes as long as it takes, and
      // the way out is the Cancel button, not a stopwatch.
      final http.Response response = await _withWakeRetry(
        () => _client.post(
          uri,
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: jsonEncode(<String, dynamic>{..._identity, ...extra}),
        ),
        attemptTimeout: _createAttemptTimeout,
        cancelSignal: canceller.future,
        retryRateLimit: true,
      );
      if (gen != _openGeneration) return false; // cancelled as it landed

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
      // A room with a token counts as opened even if the first socket
      // is still being earned back by the reconnect loop — the room
      // view shows "Reconnecting…" rather than an error.
      return inRoom;
    } on _OpenCancelled {
      return false; // cancelOpen() already reset the state
    } on TimeoutException {
      if (gen != _openGeneration) return false;
      _fail('The Listen Together server did not answer in time.');
      return false;
    } catch (e) {
      if (gen != _openGeneration) return false;
      _fail('Could not reach the Listen Together server. Check your connection.');
      return false;
    } finally {
      if (identical(_openCanceller, canceller)) _openCanceller = null;
    }
  }

  /// Reads the fields that both the REST snapshot and `welcome` carry. The
  /// create/join answers nest everything under `party`; the bare party
  /// snapshot (GET) carries the same fields at the top level.
  void _absorbSnapshot(Map<String, dynamic> payload) {
    _token = payload['token']?.toString() ?? _token;
    if (payload['you'] is Map) {
      _you = JamMember.fromJson((payload['you'] as Map).cast<String, dynamic>());
    }
    final Map<String, dynamic> partyMap = payload['party'] is Map
        ? (payload['party'] as Map).cast<String, dynamic>()
        : payload;
    if (partyMap['code'] != null) {
      _party = JamParty.fromJson(partyMap);
    }
    if (partyMap['queue'] is Map) {
      _applyQueue((partyMap['queue'] as Map).cast<String, dynamic>());
    }
    if (partyMap['playback'] is Map) {
      _applyPlayback((partyMap['playback'] as Map).cast<String, dynamic>());
    }
    if (partyMap['members'] is List) {
      _members = (partyMap['members'] as List)
          .whereType<Map>()
          .map((Map m) => JamMember.fromJson(m.cast<String, dynamic>()))
          .toList();
      _refreshYouFromMembers();
    }
    if (partyMap['chat'] is List) {
      _chatMessages = (partyMap['chat'] as List)
          .whereType<Map>()
          .map((Map m) => JamChatMessage.fromJson(m.cast<String, dynamic>()))
          .toList();
      _chatSeq = (partyMap['chatSeq'] as num?)?.round() ?? _chatMessages.length;
    }
    final Object? serverMs = payload['serverMs'] ?? partyMap['serverMs'];
    if (serverMs is num && _clockOffsetMs == null) {
      _clockOffsetMs =
          serverMs.round() - DateTime.now().millisecondsSinceEpoch;
    }
  }

  void _refreshYouFromMembers() {
    final JamMember? me = _you;
    if (me == null || me.memberId.isEmpty) return;
    for (final JamMember m in _members) {
      if (m.memberId == me.memberId) {
        _you = m;
        return;
      }
    }
  }

  String _explainStatus(int status, String body) {
    String server = '';
    try {
      final Object? decoded = jsonDecode(body);
      if (decoded is Map) {
        server = (decoded['message'] ?? decoded['error'])?.toString() ?? '';
      }
    } catch (_) {
      // A plain-text body is fine; fall through to the generic message.
    }
    return switch (status) {
      404 => 'No room with that code — check it and try again.',
      409 => server.isNotEmpty ? server : 'That room is full.',
      422 => 'The server needs a name before you can join.',
      429 => 'Too many rooms too quickly. Try again in a minute.',
      // Only reached after the wake-up budget is spent (see _withWakeRetry).
      502 || 503 || 504 =>
        'The room server did not wake up in time. Give it a minute and try again.',
      _ => server.isNotEmpty
          ? server
          : 'The server refused the request ($status).',
    };
  }

  Future<void> _connectSocket() async {
    final String? code = _party?.code;
    if (code == null || !hasServer) return;
    final int generation = ++_connectionGeneration;
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
      _socketFailed('The room did not answer in time.');
      return;
    } catch (e) {
      _socketFailed('Could not open the room connection.');
      return;
    }
    if (generation != _connectionGeneration || _intentionalClose) {
      try {
        await _socket?.close();
      } catch (_) {}
      _socket = null;
      return;
    }
    await _sub?.cancel();
    _sub = _socket!.listen(
      _onFrame,
      onError: (Object error) {
        if (generation == _connectionGeneration) _onSocketDropped();
      },
      onDone: () {
        if (generation == _connectionGeneration) _onSocketDropped();
      },
      cancelOnError: false,
    );
    _reconnectAttempt = 0;
    _setState(JamConnectionState.connected);
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _ping());
    _ping();
    _send(<String, dynamic>{'type': 'sync'});
    _send(<String, dynamic>{'type': 'syncQueue'});
    _send(<String, dynamic>{'type': 'syncChat'});
  }

  void _socketFailed(String message) {
    // Holding a room and a token is enough: even the very first socket
    // failing is a reconnect-loop problem, not a dead end. (BitChord's
    // client is built the same way — the loop is the design, and the
    // server's grace window holds the seat meanwhile.)
    if (_party != null && !_intentionalClose) {
      _onSocketDropped();
    } else {
      _fail(message);
    }
  }

  void _onSocketDropped() {
    if (_intentionalClose) return;
    _pingTimer?.cancel();
    _pingTimer = null;
    _sub?.cancel();
    _sub = null;
    try {
      _socket?.close();
    } catch (_) {}
    _socket = null;
    if (_party == null) {
      _fail('The room connection closed.');
      return;
    }
    // The server holds this seat for a grace window, host crown included.
    // Mark the room reconnecting and quietly earn it back.
    _state = JamConnectionState.reconnecting;
    _error = null;
    notifyListeners();
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    if (_intentionalClose || _party == null) return;
    _cancelReconnect();
    const List<int> backoffSeconds = <int>[1, 2, 4, 8, 15, 20];
    final int delay =
        backoffSeconds[math.min(_reconnectAttempt, backoffSeconds.length - 1)];
    _reconnectTimer = Timer(Duration(seconds: delay), _attemptReconnect);
  }

  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  Future<void> _attemptReconnect() async {
    if (_intentionalClose || _party == null) return;
    if (_state == JamConnectionState.connected) return;
    _reconnectAttempt++;
    final String code = _party!.code;
    try {
      final http.Response response = await _client
          .post(
            Uri.parse(
                '$serverBase/api/parties/${Uri.encodeComponent(code)}/join'),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(_identity),
          )
          .timeout(const Duration(seconds: 12));
      if (_intentionalClose || _party?.code != code) return;
      if (response.statusCode == 404) {
        _fail('This room has ended.');
        return;
      }
      if (response.statusCode != 200 && response.statusCode != 201) {
        _scheduleReconnect();
        return;
      }
      final Object? decoded = jsonDecode(response.body);
      if (decoded is Map) {
        _absorbSnapshot(decoded.cast<String, dynamic>());
        notifyListeners();
      }
      await _connectSocket();
    } catch (_) {
      _scheduleReconnect();
    }
  }

  /// Called when the app comes back to the front: re-earn a dropped socket
  /// now instead of at the next backoff tick, or re-ask for the truth.
  void onAppResumed() {
    // Coming back to the app after a while is the other moment a room
    // is about to be wanted; keep the server warm for it (coalesced,
    // and a no-op while in a room).
    warmUp();
    if (_state == JamConnectionState.reconnecting) {
      _cancelReconnect();
      unawaited(_attemptReconnect());
    } else if (isConnected) {
      resync();
    }
  }

  /// Asks for the truth again — after the app comes back to the front.
  void resync() {
    _send(<String, dynamic>{'type': 'sync'});
    _send(<String, dynamic>{'type': 'syncQueue'});
    _send(<String, dynamic>{'type': 'syncChat'});
    _ping();
  }

  // --------------------------------------------------------------- transport

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
          final Map<String, dynamic> pb =
              (frame['playback'] as Map).cast<String, dynamic>();
          _applyPlayback(pb);
          final int? queueSeq = (pb['queueSeq'] as num?)?.round();
          if (queueSeq != null && queueSeq != _appliedQueueSeq) {
            // Self-healing half: a missed queue broadcast is noticed on the
            // very next state frame rather than lived with.
            _send(<String, dynamic>{'type': 'syncQueue'});
          }
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
          _refreshYouFromMembers();
        }
        if (_party != null) {
          _party = JamParty(
            code: _party!.code,
            maxMembers: (frame['maxMembers'] as num?)?.round() ??
                _party!.maxMembers,
            hostOnlyControl: frame['hostOnlyControl'] is bool
                ? frame['hostOnlyControl'] == true
                : _party!.hostOnlyControl,
          );
        }
        notifyListeners();
      case 'chat':
        _applyChatFrame(frame);
        notifyListeners();
      case 'activity':
        final JamActivity activity = JamActivity.fromJson(frame);
        if (activity.detail.isNotEmpty) {
          final List<JamActivity> next = <JamActivity>[..._activities, activity];
          _activities = next.length > maxActivities
              ? next.sublist(next.length - maxActivities)
              : next;
        }
        notifyListeners();
      case 'error':
        final String code = frame['error']?.toString() ?? '';
        if (code == 'chat_rate_limited' || code == 'invalid_message') {
          _markLastPendingChatFailed();
        }
        _error = (frame['message'] ?? frame['error'])?.toString() ??
            'The room refused that.';
        notifyListeners();
      case 'bye':
        final JamByeReason reason = switch (frame['reason']) {
          'left' => JamByeReason.left,
          'kicked' => JamByeReason.kicked,
          'ended' => JamByeReason.ended,
          _ => JamByeReason.unknown,
        };
        _intentionalClose = true;
        _teardown();
        _state = JamConnectionState.idle;
        _error = switch (reason) {
          JamByeReason.kicked => 'The host removed you from the room.',
          JamByeReason.ended => 'The host ended the room.',
          _ => null,
        };
        notifyListeners();
    }
  }

  void _applyChatFrame(Map<String, dynamic> frame) {
    final int seq = (frame['chatSeq'] as num?)?.round() ?? _chatSeq;
    if (frame['snapshot'] == true && frame['messages'] is List) {
      final List<JamChatMessage> fresh = (frame['messages'] as List)
          .whereType<Map>()
          .map((Map m) => JamChatMessage.fromJson(m.cast<String, dynamic>()))
          .toList();
      final Set<String> landed = fresh.map((JamChatMessage m) => m.id).toSet();
      // Keep any optimistic bubbles the snapshot predates; they either land
      // next (and dedupe by id) or were refused and already marked failed.
      final List<JamChatMessage> pending = _chatMessages
          .where((JamChatMessage m) => m.pending && !landed.contains(m.id))
          .toList();
      _chatMessages = <JamChatMessage>[...fresh, ...pending];
      _chatSeq = seq;
      return;
    }
    if (frame['message'] is! Map) return;
    final JamChatMessage message =
        JamChatMessage.fromJson((frame['message'] as Map).cast<String, dynamic>());
    final int existing =
        _chatMessages.indexWhere((JamChatMessage m) => m.id == message.id);
    if (existing >= 0) {
      final List<JamChatMessage> next =
          List<JamChatMessage>.of(_chatMessages);
      next[existing] = message;
      _chatMessages = next;
      _chatSeq = math.max(_chatSeq, seq);
      return;
    }
    if (seq <= _chatSeq) return;
    if (seq > _chatSeq + 1) {
      // A message was missed: keep this one and ask for the whole window.
      _send(<String, dynamic>{'type': 'syncChat'});
    }
    final List<JamChatMessage> next = <JamChatMessage>[
      ..._chatMessages,
      message,
    ];
    _chatMessages = next.length > maxChatMessages
        ? next.sublist(next.length - maxChatMessages)
        : next;
    _chatSeq = seq;
  }

  void _markLastPendingChatFailed() {
    for (int i = _chatMessages.length - 1; i >= 0; i--) {
      if (_chatMessages[i].pending) {
        final List<JamChatMessage> next =
            List<JamChatMessage>.of(_chatMessages);
        next[i] = next[i].copyWith(pending: false, failed: true);
        _chatMessages = next;
        return;
      }
    }
  }

  /// Applies a state frame — **unless its `seq` has gone backwards**, which is
  /// what stops two devices from fighting over the same pause.
  void _applyPlayback(Map<String, dynamic> json) {
    final JamPlayback incoming = JamPlayback.fromJson(json);
    if (incoming.seq < _appliedSeq) return;
    if (incoming.seq == _appliedSeq) {
      // The server deliberately does not bump seq for an AutoPlay toggle
      // (it is not a playback change), so let just that flag through.
      final JamPlayback? current = _playback;
      if (current != null &&
          incoming.autoplayEnabled != current.autoplayEnabled) {
        _playback = JamPlayback(
          track: current.track,
          positionMs: current.positionMs,
          anchorMs: current.anchorMs,
          isPlaying: current.isPlaying,
          seq: current.seq,
          queueSeq: current.queueSeq,
          queueIndex: current.queueIndex,
          queueLength: current.queueLength,
          autoplayEnabled: incoming.autoplayEnabled,
          startedBy: current.startedBy,
          startedByName: current.startedByName,
          updatedBy: current.updatedBy,
        );
      }
      return;
    }
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

  /// Play or pause, whichever the room is not doing — from the room's own
  /// clock, so a drifting local player never anchors the room to itself.
  void togglePlayPause() {
    final JamPlayback? p = _playback;
    if (p == null || p.track == null) return;
    final int at = positionNow.inMilliseconds;
    if (p.isPlaying) {
      pause(positionMs: at);
    } else {
      play(positionMs: at);
    }
  }

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
    int? queueIndex,
  }) =>
      _control('setTrack', <String, dynamic>{
        'track': track.toJson(),
        'positionMs': positionMs,
        'isPlaying': isPlaying,
        if (queueIndex != null) 'queueIndex': queueIndex,
      });

  /// Replaces the whole shared queue. Only a window around [index] is
  /// sent: a listener's local queue can run to hundreds of songs, and the
  /// server (rightly) refuses oversized frames by closing the socket —
  /// which would drop the very room the queue was meant for.
  void setQueue(List<JamTrack> tracks, {int index = 0}) {
    const int window = 30;
    List<JamTrack> list = tracks;
    int idx = index;
    if (list.length > window) {
      final int start =
          math.max(0, math.min(idx - 5, list.length - window));
      list = list.sublist(start, start + window);
      idx -= start;
    }
    idx = list.isEmpty ? 0 : idx.clamp(0, list.length - 1).toInt();
    _control('setQueue', <String, dynamic>{
      'queue': list.map((JamTrack t) => t.toJson()).toList(),
      'queueIndex': idx,
    });
  }

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

  void setAutoplay(bool enabled) =>
      _control('setAutoplay', <String, dynamic>{'enabled': enabled});

  /// Host only: lock or unlock control.
  void setHostOnlyControl(bool enabled) =>
      _control('setHostOnlyControl', <String, dynamic>{'enabled': enabled});

  /// Host only: change how many devices fit in the room.
  void setMaxMembers(int count) =>
      _control('setMaxMembers', <String, dynamic>{'maxMembers': count});

  /// Host only: remove somebody (by their room seat id).
  void kick(String memberId) =>
      _control('kick', <String, dynamic>{'memberId': memberId});

  /// Host only: end the room for everyone.
  void endRoom() => _control('end', const <String, dynamic>{});

  /// Reports that this device's player finished [videoId]. Not gated by
  /// [canControl]: the server checks for itself that the track really is
  /// over, and only the first report moves the room on.
  void reportEnded(String videoId) {
    if (!isConnected || videoId.isEmpty) return;
    _send(<String, dynamic>{
      'type': 'control',
      'action': 'ended',
      'trackId': videoId,
    });
  }

  void _control(String action, Map<String, dynamic> extra) {
    if (!canControl) return;
    _send(<String, dynamic>{'type': 'control', 'action': action, ...extra});
  }

  // ---------------------------------------------------------------------- chat

  /// Sends a chat message with an optimistic local bubble; the server's
  /// broadcast of the same id settles it. Returns false when there was
  /// nothing to send or no live socket to send it on.
  bool sendChat(String rawText) {
    if (!isConnected) return false;
    String text = rawText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (text.isEmpty) return false;
    if (text.runes.length > maxChatRunes) {
      text = String.fromCharCodes(text.runes.take(maxChatRunes));
    }
    final String id = newUuid();
    final JamChatMessage optimistic = JamChatMessage(
      id: id,
      memberId: _you?.memberId ?? '',
      userId: _userId,
      by: effectiveDisplayName,
      text: text,
      atMs: serverNowMs,
      pending: true,
    );
    final List<JamChatMessage> next = <JamChatMessage>[
      ..._chatMessages,
      optimistic,
    ];
    _chatMessages = next.length > maxChatMessages
        ? next.sublist(next.length - maxChatMessages)
        : next;
    notifyListeners();
    _send(<String, dynamic>{'type': 'chat', 'id': id, 'text': text});
    return true;
  }

  /// Retries a message the server refused earlier.
  bool resendChat(JamChatMessage message) {
    _chatMessages = _chatMessages
        .where((JamChatMessage m) => m.id != message.id)
        .toList();
    notifyListeners();
    return sendChat(message.text);
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

  // -------------------------------------------------------------------- leave

  /// Gives up the slot and closes the socket.
  Future<void> leave() async {
    cancelOpen(); // an in-flight create/join stops racing us
    _intentionalClose = true;
    _cancelReconnect();
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
    _cancelReconnect();
    _pingTimer?.cancel();
    _pingTimer = null;
    _connectionGeneration++;
    _party = null;
    _you = null;
    _members = const <JamMember>[];
    _playback = null;
    _queue = const JamQueue();
    _chatMessages = const <JamChatMessage>[];
    _activities = const <JamActivity>[];
    _chatSeq = 0;
    _appliedSeq = -1;
    _appliedQueueSeq = -1;
    _clockOffsetMs = null;
    _bestRoundTripMs = null;
    _token = null;
    _reconnectAttempt = 0;
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
    _intentionalClose = true;
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
    cancelOpen();
    _intentionalClose = true;
    _teardown();
    _client.close();
    super.dispose();
  }
}

/// Thrown inside the wake-retry loop when [JamService.cancelOpen] fires.
/// Private on purpose: cancellation is a control path, not an error.
class _OpenCancelled implements Exception {
  const _OpenCancelled();
}
