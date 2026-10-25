import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'listen_together_service.dart';

/// Someone this device has shared a Listen Together room with.
class JamFriend {
  const JamFriend({
    required this.userId,
    required this.name,
    required this.lastSeenMs,
    this.roomsTogether = 1,
  });

  /// The other install's stable anonymous id.
  final String userId;
  final String name;
  final int lastSeenMs;
  final int roomsTogether;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'userId': userId,
        'name': name,
        'lastSeenMs': lastSeenMs,
        'roomsTogether': roomsTogether,
      };

  factory JamFriend.fromJson(Map<String, dynamic> json) => JamFriend(
        userId: json['userId']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Listener',
        lastSeenMs: (json['lastSeenMs'] as num?)?.round() ?? 0,
        roomsTogether: (json['roomsTogether'] as num?)?.round() ?? 1,
      );
}

/// The people you have listened with, remembered on this device only.
///
/// There are no accounts: two phones learn each other's install id only by
/// being in a room together, and the friendship is just this list. Nothing
/// here is ever uploaded — the invite heartbeat only ever asks the server
/// "are any of these ids currently around, and is anything waiting for me".
class JamFriendsService extends ChangeNotifier {
  JamFriendsService(this._prefs, {required this.selfUserId}) {
    _load();
  }

  static const String kFriends = 'ifall.jam_friends.v1';
  static const int maxFriends = 50;

  /// The invite heartbeat can ask about at most this many friends.
  static const int maxHeartbeatFriends = 50;

  final SharedPreferences _prefs;
  final String selfUserId;

  final Map<String, JamFriend> _byId = <String, JamFriend>{};

  /// Most recent first.
  List<JamFriend> get friends {
    final List<JamFriend> list = _byId.values.toList()
      ..sort((JamFriend a, JamFriend b) =>
          b.lastSeenMs.compareTo(a.lastSeenMs));
    return List<JamFriend>.unmodifiable(list);
  }

  List<String> get friendIds =>
      friends.take(maxHeartbeatFriends).map((JamFriend f) => f.userId).toList();

  JamFriend? byId(String userId) => _byId[userId];

  void _load() {
    try {
      final String? raw = _prefs.getString(kFriends);
      if (raw == null || raw.isEmpty) return;
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return;
      for (final Object? entry in decoded) {
        if (entry is Map) {
          final JamFriend friend =
              JamFriend.fromJson(entry.cast<String, dynamic>());
          if (friend.userId.isNotEmpty && friend.userId != selfUserId) {
            _byId[friend.userId] = friend;
          }
        }
      }
    } catch (_) {
      // A torn write just means starting the list over — never crash boot.
      _byId.clear();
    }
  }

  Future<void> _persist() async {
    try {
      await _prefs.setString(
        kFriends,
        jsonEncode(friends.map((JamFriend f) => f.toJson()).toList()),
      );
    } catch (_) {
      // Storage trouble must not disturb the room.
    }
  }

  /// Remembers everyone currently in a room with us. Cheap to call on every
  /// room update: it only writes when somebody is new, renamed, back after
  /// a while, or due a "last seen" refresh (more than a minute stale).
  void recordMembers(Iterable<JamMember> members) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    bool changed = false;
    for (final JamMember member in members) {
      final String id = member.userId;
      if (id.isEmpty || id == selfUserId) continue;
      final JamFriend? existing = _byId[id];
      if (existing == null) {
        _byId[id] = JamFriend(
          userId: id,
          name: member.displayName,
          lastSeenMs: now,
        );
        changed = true;
        continue;
      }
      final bool newSession =
          now - existing.lastSeenMs > const Duration(minutes: 30).inMilliseconds;
      final bool renamed = existing.name != member.displayName;
      final bool stale =
          now - existing.lastSeenMs > const Duration(minutes: 1).inMilliseconds;
      if (newSession || renamed || stale) {
        _byId[id] = JamFriend(
          userId: id,
          name: member.displayName,
          lastSeenMs: now,
          roomsTogether:
              existing.roomsTogether + (newSession ? 1 : 0),
        );
        changed = true;
      }
    }
    if (_byId.length > maxFriends) {
      final List<JamFriend> sorted = friends;
      for (final JamFriend f in sorted.sublist(maxFriends)) {
        _byId.remove(f.userId);
      }
      changed = true;
    }
    if (changed) {
      // Fire and forget: writing preferences never blocks the room.
      unawaited(_persist());
      notifyListeners();
    }
  }

  Future<void> remove(String userId) async {
    if (_byId.remove(userId) != null) {
      await _persist();
      notifyListeners();
    }
  }
}
