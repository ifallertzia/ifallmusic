import 'dart:async';

import '../models/song.dart';
import 'listen_together_service.dart';
import 'playback_service.dart';
import 'youtube_service.dart';

/// The glue between a Listen Together room and this device's player.
///
/// * Room → device: play the room's track at the room's position, keep the
///   local queue mirroring the shared one, and nudge the playhead back
///   whenever it drifts.
/// * Device → room: when this listener changes something locally (a new
///   song from anywhere in the app, pause from the notification, …) the
///   change is reported to the room — unless the host has locked control,
///   in which case the local player is quietly pulled back into line.
///
/// The coordinator deliberately never trusts a single notification: it also
/// reconciles on a sub-second timer, comparing room truth to local reality
/// and settling differences. Applying remote state opens a short window
/// during which local changes are treated as echoes rather than intent,
/// and a device that *was* in step gets a couple of seconds of grace when
/// it veers off — that is a listener picking a new song, whose intent must
/// reach the server before the room's older truth is reloaded over it.
class RoomPlaybackCoordinator {
  RoomPlaybackCoordinator({
    required this.jam,
    required this.playback,
    this.youtube,
  }) {
    playback.onTrackCompleted = _onLocalTrackCompleted;
  }

  final JamService jam;
  final PlaybackService playback;

  /// When present and this device hosts, keeps a room with AutoPlay on
  /// topped up with similar songs before the queue runs dry.
  final YoutubeService? youtube;

  /// Shown to the listener (e.g. "Only the host controls playback here").
  void Function(String message)? onNotice;

  bool _attached = false;
  Timer? _timer;

  bool _wasInRoom = false;
  bool _everSynced = false;
  String _divergedTrackId = '';
  DateTime? _divergedAt;
  bool _emptiedOnce = false;
  List<String> _lastQueueIds = const <String>[];
  String? _loadingTrackId;
  DateTime? _applyingUntil;
  DateTime? _intentHoldUntil;

  int _lastFreshSeq = -1;
  int _driftStrikes = 0;
  DateTime? _seekCooldownUntil;

  DateTime? _lastNoticeAt;
  DateTime? _lastCompletionAt;
  String _lastCompletionId = '';
  bool _topUpInFlight = false;
  String _topUpForTrackId = '';

  void attach() {
    if (_attached) return;
    _attached = true;
    jam.addListener(_onJamChanged);
    playback.addListener(_onPlaybackChanged);
    _timer = Timer.periodic(
      const Duration(milliseconds: 700),
      (_) => _reconcile(),
    );
    _onJamChanged();
  }

  void dispose() {
    if (!_attached) return;
    _attached = false;
    jam.removeListener(_onJamChanged);
    playback.removeListener(_onPlaybackChanged);
    _timer?.cancel();
    playback.deferTrackCompletion = false;
    playback.onTrackCompleted = null;
  }

  // ------------------------------------------------------------ room tracking

  void _onJamChanged() {
    final bool inRoom = jam.inRoom;
    if (inRoom && !_wasInRoom) {
      playback.deferTrackCompletion = true;
      _everSynced = false;
      _divergedTrackId = '';
      _divergedAt = null;
      _emptiedOnce = false;
      _lastQueueIds =
          jam.queueItems.map((JamTrack t) => t.videoId).toList();
      _lastFreshSeq = -1;
      // Whatever was playing before the room opened is not "intent" — give
      // the first room state a moment to land before reporting anything.
      _intentHoldUntil = DateTime.now().add(const Duration(seconds: 3));
      _markApplying();
    }
    if (!inRoom && _wasInRoom) {
      playback.deferTrackCompletion = false;
      _loadingTrackId = null;
      _everSynced = false;
      _divergedTrackId = '';
      _divergedAt = null;
      _lastQueueIds = const <String>[];
    }
    _wasInRoom = inRoom;
    if (jam.isConnected) _applyRemote();
  }

  void _reconcile() {
    if (!jam.inRoom || !jam.isConnected) return;
    // Intent first: a fresh local change gets reported before the room's
    // (older) truth is re-applied over it. Echoes of our own applying are
    // already filtered by the applying window inside _pushLocalIntent.
    _pushLocalIntent();
    _applyRemote();
    _maybeTopUpAutoplay();
  }

  /// Host-only AutoPlay top-up: while the last songs play, fetch similar
  /// ones so the room never runs dry. One attempt per track, and only
  /// tracks the queue does not already hold.
  void _maybeTopUpAutoplay() {
    final YoutubeService? yt = youtube;
    if (yt == null) return;
    if (!jam.isConnected || !jam.isHost || !jam.autoplayEnabled) return;
    final JamTrack? track = jam.currentTrack;
    if (track == null) return;
    final int upcoming = jam.queueItems.length - (jam.queue.index + 1);
    if (upcoming > 1) return;
    if (_topUpInFlight || _topUpForTrackId == track.videoId) return;
    _topUpInFlight = true;
    _topUpForTrackId = track.videoId;
    unawaited(() async {
      try {
        final Set<String> exclude =
            jam.queueItems.map((JamTrack t) => t.videoId).toSet();
        final List<Song> songs = await yt.radioSongs(
          track.toSong(),
          exclude: exclude,
          limit: 6,
        );
        final List<JamTrack> fresh = songs
            .where((Song s) => !exclude.contains(s.id))
            .take(5)
            .map((Song s) => JamTrack.fromSong(s, fromAutoplay: true))
            .toList();
        if (fresh.isEmpty || !jam.isConnected || !jam.isHost) return;
        jam.addToQueue(fresh);
        // If the room already ran dry and stopped at the end, move it on
        // to what just arrived (frames are ordered, the add lands first).
        final JamPlayback? pb = jam.playback;
        if (pb != null && !pb.isPlaying && _localAtEnd()) {
          jam.next();
        }
      } catch (_) {
        // No radio right now is fine — the queue just ends as it would.
      } finally {
        _topUpInFlight = false;
      }
    }());
  }

  void _markApplying() =>
      _applyingUntil =
          DateTime.now().add(const Duration(milliseconds: 1500));

  bool get _isApplying =>
      _applyingUntil != null && DateTime.now().isBefore(_applyingUntil!);

  bool get _intentHeld =>
      _intentHoldUntil != null && DateTime.now().isBefore(_intentHoldUntil!);

  /// Whether the room has made a newer decision (its playback `seq`
  /// advanced) since this device was last in step with it — someone,
  /// possibly this device's own room-aware buttons, pressed next /
  /// previous / picked a song *in the room*. That is the room moving,
  /// not this listener veering off: the new track must be loaded at
  /// once, and the still-playing old one must not be reported back as
  /// "intent" over it. Without this distinction a mid-song skip only
  /// ever changed the UI: the push below helpfully re-reported the old
  /// track, the server reverted to it, and the old song kept playing.
  /// (A natural ending always worked because [_justCompleted] and
  /// [_localAtEnd] bypass both paths.)
  bool get _roomMovedSinceSync {
    final JamPlayback? pb = jam.playback;
    return pb != null && _lastFreshSeq >= 0 && pb.seq != _lastFreshSeq;
  }

  // ------------------------------------------------------------- room → local

  void _applyRemote() {
    final JamPlayback? pb = jam.playback;
    if (pb == null) return;
    final JamTrack? track = pb.track;
    if (track == null) {
      // An empty room: settle this device down once, then leave it alone
      // (the listener may keep browsing; starting a song reports it).
      if (!_emptiedOnce && playback.hasTrack && playback.isPlaying) {
        _markApplying();
        unawaited(playback.pause());
      }
      _emptiedOnce = true;
      _loadingTrackId = null;
      return;
    }
    _emptiedOnce = false;
    final List<String> roomIds =
        jam.queueItems.map((JamTrack t) => t.videoId).toList();
    final List<String> localIds =
        playback.queue.map((Song s) => s.id).toList();

    if (playback.current?.id != track.videoId) {
      if (_loadingTrackId == track.videoId && playback.isLoading) return;
      // A device that was in step and just veered off is almost certainly
      // its listener picking a new song: give the intent push a couple of
      // seconds to reach the server before the room's track is reloaded
      // over it. A just-finished track is not intent, and neither is
      // whatever was playing before this device ever synced up — and nor
      // is a room that itself moved since we were last in step: that is
      // a skip or a new pick landing *from* the room (the mid-song Next
      // that only changed the UI), and it must simply be loaded.
      final String localId = playback.current?.id ?? '';
      final DateTime now = DateTime.now();
      if (_everSynced &&
          jam.canControl &&
          !_roomMovedSinceSync &&
          localId.isNotEmpty &&
          !_justCompleted(localId, now) &&
          !_localAtEnd()) {
        if (_divergedTrackId != localId) {
          _divergedTrackId = localId;
          _divergedAt = now;
        }
        final bool withinGrace = _intentHeld ||
            now.difference(_divergedAt!) <
                const Duration(milliseconds: 2500);
        if (withinGrace) return;
      }
      _loadRoomTrack(track, roomIds, localIds);
    } else {
      _everSynced = true;
      _divergedTrackId = '';
      _divergedAt = null;
      if (roomIds.isNotEmpty && !_sameIds(localIds, roomIds)) {
        // Same song, different company: mirror the shared order without
        // touching what is playing, reusing rich local Song objects where
        // this device already has them.
        final Map<String, Song> localById = <String, Song>{
          for (final Song s in playback.queue) s.id: s,
        };
        final List<Song> songs = jam.queueItems
            .map((JamTrack t) => localById[t.videoId] ?? t.toSong())
            .toList();
        _markApplying();
        playback.reorderQueue(songs);
      }
      _enforcePlayState(pb);
      if (pb.seq != _lastFreshSeq) {
        _lastFreshSeq = pb.seq;
        _enforcePosition(hard: true);
      } else {
        _enforcePosition(hard: false);
      }
    }
    _lastQueueIds = roomIds;
  }

  void _loadRoomTrack(
    JamTrack track,
    List<String> roomIds,
    List<String> localIds,
  ) {
    _loadingTrackId = track.videoId;
    _markApplying();
    final bool sameQueue = _sameIds(localIds, roomIds) &&
        localIds.contains(track.videoId);
    final List<Song> songs;
    if (sameQueue) {
      songs = playback.queue;
    } else if (roomIds.isNotEmpty) {
      final Map<String, Song> localById = <String, Song>{
        for (final Song s in playback.queue) s.id: s,
      };
      songs = jam.queueItems
          .map((JamTrack t) => localById[t.videoId] ?? t.toSong())
          .toList();
    } else {
      songs = <Song>[track.toSong()];
    }
    final int startIndex =
        songs.indexWhere((Song s) => s.id == track.videoId);
    unawaited(() async {
      try {
        await playback.playQueue(
          songs,
          startIndex: startIndex < 0 ? 0 : startIndex,
        );
        _markApplying();
        final Duration want = jam.positionNow;
        if (want > const Duration(seconds: 1) &&
            playback.current?.id == track.videoId) {
          await playback.seekTo(want);
        }
        final JamPlayback? now = jam.playback;
        if (now != null &&
            !now.isPlaying &&
            playback.current?.id == track.videoId) {
          await playback.pause();
        }
        if (playback.current?.id == track.videoId) _everSynced = true;
      } catch (_) {
        // A failed load is retried by the reconcile loop; nothing to do.
      }
      if (_loadingTrackId == track.videoId) _loadingTrackId = null;
      _markApplying();
    }());
  }

  void _enforcePlayState(JamPlayback pb) {
    if (playback.isLoading) return;
    if (pb.isPlaying && !playback.isPlaying) {
      if (_localAtEnd()) return; // finished locally; the room will advance
      _markApplying();
      unawaited(playback.resume());
    } else if (!pb.isPlaying && playback.isPlaying) {
      _markApplying();
      unawaited(playback.pause());
    }
  }

  void _enforcePosition({required bool hard}) {
    if (playback.isLoading || playback.current == null) return;
    final DateTime now = DateTime.now();
    if (_seekCooldownUntil != null && now.isBefore(_seekCooldownUntil!)) {
      return;
    }
    final Duration drift = jam.positionNow - playback.position;
    if (hard) {
      if (drift.abs() > const Duration(milliseconds: 350)) {
        _seekToRoom();
      }
      return;
    }
    if (drift.abs() > const Duration(milliseconds: 1200)) {
      _driftStrikes++;
      if (_driftStrikes >= 2) {
        _driftStrikes = 0;
        _seekCooldownUntil = now.add(const Duration(seconds: 4));
        _seekToRoom();
      }
    } else {
      _driftStrikes = 0;
    }
  }

  void _seekToRoom() {
    final Duration want = jam.positionNow;
    final Duration duration = playback.duration;
    if (duration > Duration.zero &&
        want >= duration - const Duration(milliseconds: 800)) {
      return; // the song is ending anyway; never seek into the void
    }
    _markApplying();
    unawaited(playback.seekTo(want));
  }

  bool _localAtEnd() {
    final Duration duration = playback.duration;
    if (duration <= Duration.zero) return false;
    return playback.position >= duration - const Duration(milliseconds: 1200);
  }

  // ------------------------------------------------------------- local → room

  void _onPlaybackChanged() {
    if (jam.inRoom && jam.isConnected) _pushLocalIntent();
  }

  void _pushLocalIntent() {
    if (!jam.isConnected || _isApplying) return;
    final Song? song = playback.current;
    if (song == null) return;
    final DateTime now = DateTime.now();
    final JamTrack? roomTrack = jam.currentTrack;

    // 1) A different song is on locally: that is the listener taking over
    //    (tapped a song somewhere in the app) — tell the room.
    if (roomTrack == null || song.id != roomTrack.videoId) {
      if (_roomMovedSinceSync) {
        return; // the room just moved; _applyRemote loads its track —
        // pushing our still-playing old one would undo the change
      }
      if (_loadingTrackId != null && _loadingTrackId == roomTrack?.videoId) {
        return; // the room's track is still loading here
      }
      if (_justCompleted(song.id, now)) return; // waiting on the room
      if (_intentHeld) return;
      if (!jam.canControl) {
        _noticeLocked();
        return;
      }
      final List<Song> queue = playback.queue;
      final List<String> queueIds = queue.map((Song s) => s.id).toList();
      final int index = playback.currentIndex;
      final int safeIndex = queue.isEmpty
          ? 0
          : index.clamp(0, queue.length - 1).toInt();
      if (queue.isNotEmpty && !_sameIds(queueIds, _lastQueueIds)) {
        jam.setQueue(
          queue.map((Song s) => JamTrack.fromSong(s)).toList(),
          index: safeIndex,
        );
        _lastQueueIds = queueIds;
      }
      jam.setTrack(
        JamTrack.fromSong(song),
        positionMs: playback.position.inMilliseconds,
        isPlaying: playback.isPlaying,
        queueIndex: safeIndex,
      );
      _intentHoldUntil = now.add(const Duration(seconds: 3));
      return;
    }

    // 2) Same song, but the local queue around it changed.
    final List<String> localIds =
        playback.queue.map((Song s) => s.id).toList();
    if (localIds.isNotEmpty && !_sameIds(localIds, _lastQueueIds)) {
      if (_loadingTrackId != null || _intentHeld) return;
      if (!jam.canControl) {
        _noticeLocked();
        return;
      }
      final int index = playback.currentIndex;
      jam.setQueue(
        playback.queue.map((Song s) => JamTrack.fromSong(s)).toList(),
        index: index.clamp(0, localIds.length - 1).toInt(),
      );
      _lastQueueIds = localIds;
      _intentHoldUntil = now.add(const Duration(seconds: 2));
      return;
    }

    // 3) Play/pause drifted from the room.
    final JamPlayback? pb = jam.playback;
    if (pb == null) return;
    if (playback.isPlaying != pb.isPlaying) {
      if (playback.isLoading || _loadingTrackId != null || _intentHeld) {
        return;
      }
      if (_justCompleted(song.id, now)) return;
      if (!jam.canControl) {
        _noticeLocked();
        return; // the next enforce pulls this device back into line
      }
      final int at = playback.position.inMilliseconds;
      if (playback.isPlaying) {
        jam.play(positionMs: at);
      } else {
        jam.pause(positionMs: at);
      }
      _intentHoldUntil = now.add(const Duration(seconds: 3));
    }
  }

  bool _justCompleted(String songId, DateTime now) =>
      songId == _lastCompletionId &&
      _lastCompletionAt != null &&
      now.difference(_lastCompletionAt!) < const Duration(seconds: 6);

  void _noticeLocked() {
    final DateTime now = DateTime.now();
    if (_lastNoticeAt != null &&
        now.difference(_lastNoticeAt!) < const Duration(seconds: 6)) {
      return;
    }
    _lastNoticeAt = now;
    onNotice?.call('Only the host controls playback in this room.');
  }

  void _onLocalTrackCompleted(String finishedTrackId) {
    _lastCompletionId = finishedTrackId;
    _lastCompletionAt = DateTime.now();
    jam.reportEnded(finishedTrackId);
  }

  bool _sameIds(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
