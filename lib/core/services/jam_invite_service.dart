import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'jam_friends_service.dart';
import 'listen_together_service.dart';
import 'settings_service.dart';

/// "Alice wants to listen with you" — one pending room invitation.
class JamInvite {
  const JamInvite({
    required this.id,
    required this.fromUserId,
    required this.fromName,
    required this.code,
    required this.atMs,
    required this.expiresAtMs,
  });

  final String id;
  final String fromUserId;
  final String fromName;
  final String code;
  final int atMs;
  final int expiresAtMs;

  factory JamInvite.fromJson(Map<String, dynamic> json) => JamInvite(
        id: json['id']?.toString() ?? '',
        fromUserId: json['fromUserId']?.toString() ?? '',
        fromName: json['fromName']?.toString() ?? 'A friend',
        code: json['code']?.toString() ?? '',
        atMs: (json['atMs'] as num?)?.round() ?? 0,
        expiresAtMs: (json['expiresAtMs'] as num?)?.round() ?? 0,
      );

  bool expiredAt(int nowMs) => expiresAtMs > 0 && nowMs >= expiresAtMs;
}

/// The answer to an invitation this device sent.
class JamInviteResponse {
  const JamInviteResponse({
    required this.inviteId,
    required this.byUserId,
    required this.byName,
    required this.code,
    required this.accepted,
    required this.atMs,
  });

  final String inviteId;
  final String byUserId;
  final String byName;
  final String code;
  final bool accepted;
  final int atMs;

  factory JamInviteResponse.fromJson(Map<String, dynamic> json) =>
      JamInviteResponse(
        inviteId: json['inviteId']?.toString() ?? '',
        byUserId: json['byUserId']?.toString() ?? '',
        byName: json['byName']?.toString() ?? 'A friend',
        code: json['code']?.toString() ?? '',
        accepted: json['accepted'] == true,
        atMs: (json['atMs'] as num?)?.round() ?? 0,
      );
}

/// Friend invitations over a gentle heartbeat.
///
/// While the app runs (in front, or behind playing music) this pings the
/// party server every ~20 s: "I'm here — anything for me?". Invites and
/// answers ride back on the reply, and which friends are around right now
/// comes with it. That is what makes a game-style "X wants to listen with
/// you" pop up on a friend's phone within seconds — without accounts and
/// without Firebase. (A phone whose app has been force-stopped cannot be
/// woken this way; that last step is what a push service would add later.)
class JamInviteService extends ChangeNotifier {
  JamInviteService({
    required SettingsService settings,
    required JamFriendsService friends,
    http.Client? client,
  })  : _settings = settings,
        _friends = friends,
        _client = client ?? http.Client();

  final SettingsService _settings;
  final JamFriendsService _friends;
  final http.Client _client;

  /// A new invitation arrived (already in [pending]) — show it to the user.
  void Function(JamInvite invite)? onInvite;

  /// Someone answered an invitation this device sent.
  void Function(JamInviteResponse response)? onResponse;

  Timer? _timer;
  bool _running = false;
  bool _beating = false;
  int _intervalSec = 20;

  List<JamInvite> _pending = const <JamInvite>[];
  final Set<String> _online = <String>{};
  final Set<String> _announced = <String>{};

  List<JamInvite> get pending {
    final int now = DateTime.now().millisecondsSinceEpoch;
    return List<JamInvite>.unmodifiable(
      _pending.where((JamInvite i) => !i.expiredAt(now)),
    );
  }

  bool isOnline(String userId) => _online.contains(userId);

  String get _base {
    final String custom =
        _settings.jamServer.trim().replaceAll(RegExp(r'/+$'), '');
    return custom.isNotEmpty ? custom : JamService.defaultServer;
  }

  String get _me => _settings.installId;

  String get _myName {
    if (_settings.jamDisplayName.isNotEmpty) return _settings.jamDisplayName;
    if (_settings.displayName.isNotEmpty) return _settings.displayName;
    return 'Listener';
  }

  void start() {
    if (_running) return;
    _running = true;
    unawaited(_beat());
  }

  void stop() {
    _running = false;
    _timer?.cancel();
    _timer = null;
  }

  void _schedule() {
    _timer?.cancel();
    if (!_running) return;
    _timer = Timer(Duration(seconds: _intervalSec), () => unawaited(_beat()));
  }

  Future<void> _beat() async {
    if (_beating) return;
    _beating = true;
    try {
      final http.Response response = await _client
          .post(
            Uri.parse('$_base/api/invites/heartbeat'),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'userId': _me,
              'displayName': _myName,
              'friendIds': _friends.friendIds,
            }),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final Object? decoded = jsonDecode(response.body);
        if (decoded is Map) {
          _absorbBeat(decoded.cast<String, dynamic>());
        }
      }
    } catch (_) {
      // Offline, server down, wrong address — the next beat tries again.
      // Invites are a bonus on top of plain codes, never a hard error.
    } finally {
      _beating = false;
      _schedule();
    }
  }

  void _absorbBeat(Map<String, dynamic> payload) {
    bool changed = false;
    final int? interval = (payload['intervalSec'] as num?)?.round();
    if (interval != null && interval >= 10 && interval <= 120) {
      _intervalSec = interval;
    }

    // Presence of friends.
    final Set<String> online = <String>{
      for (final Object? id
          in (payload['onlineFriendIds'] as List<dynamic>? ?? const <dynamic>[]))
        if (id != null) id.toString(),
    };
    if (!setEquals(online, _online)) {
      _online
        ..clear()
        ..addAll(online);
      changed = true;
    }

    // Pending invitations: the server's list is the truth.
    final List<JamInvite> invites =
        (payload['invites'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map((Map m) => JamInvite.fromJson(m.cast<String, dynamic>()))
            .where((JamInvite i) => i.id.isNotEmpty && i.code.isNotEmpty)
            .toList();
    final Set<String> previousIds =
        _pending.map((JamInvite i) => i.id).toSet();
    _pending = invites;
    for (final JamInvite invite in invites) {
      if (!previousIds.contains(invite.id) &&
          !_announced.contains(invite.id)) {
        _announced.add(invite.id);
        onInvite?.call(invite);
      }
    }
    _announced.removeWhere(
      (String id) => !invites.any((JamInvite i) => i.id == id),
    );
    changed = true;

    // Answers are delivered exactly once by the server.
    for (final Object? entry
        in (payload['responses'] as List<dynamic>? ?? const <dynamic>[])) {
      if (entry is Map) {
        onResponse?.call(
          JamInviteResponse.fromJson(entry.cast<String, dynamic>()),
        );
      }
    }
    if (changed) notifyListeners();
  }

  /// Invites a friend into a room this device is in. Returns whether the
  /// invite was filed, whether the friend looks reachable right now, and a
  /// message worth showing when it was not.
  Future<({bool ok, bool online, String? error})> sendInvite({
    required String toUserId,
    required String code,
  }) async {
    try {
      final http.Response response = await _client
          .post(
            Uri.parse('$_base/api/invites/send'),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'fromUserId': _me,
              'toUserId': toUserId,
              'code': normalizeJamCode(code),
            }),
          )
          .timeout(const Duration(seconds: 10));
      String serverMessage = '';
      bool online = false;
      try {
        final Object? decoded = jsonDecode(response.body);
        if (decoded is Map) {
          serverMessage =
              (decoded['message'] ?? decoded['error'])?.toString() ?? '';
          online = decoded['online'] == true;
        }
      } catch (_) {}
      if (response.statusCode == 200) {
        return (ok: true, online: online, error: null);
      }
      return (
        ok: false,
        online: false,
        error: serverMessage.isNotEmpty
            ? serverMessage
            : 'The invite could not be sent (${response.statusCode}).',
      );
    } on TimeoutException {
      return (ok: false, online: false, error: 'The server did not answer.');
    } catch (_) {
      return (
        ok: false,
        online: false,
        error: 'Could not reach the Listen Together server.',
      );
    }
  }

  /// Answers an invitation. The invite leaves the pending list either way.
  Future<bool> respond(JamInvite invite, {required bool accept}) async {
    _pending =
        _pending.where((JamInvite i) => i.id != invite.id).toList();
    notifyListeners();
    try {
      final http.Response response = await _client
          .post(
            Uri.parse('$_base/api/invites/respond'),
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: jsonEncode(<String, dynamic>{
              'userId': _me,
              'inviteId': invite.id,
              'accept': accept,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    stop();
    _client.close();
    super.dispose();
  }
}
