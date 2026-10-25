import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../core/services/app_feedback.dart';
import '../../core/services/listen_together_service.dart';
import '../../core/services/playback_service.dart';

/// Routes a transport tap ('toggle', 'next', 'previous') to the room when
/// this device is in one. Returns true when the room took the tap — the
/// caller then leaves the local player alone.
///
/// Guests without control get told so instead of a silently reverting
/// button, and pausing also pauses this device on the spot so the tap
/// feels instant even before the server echoes it back.
bool roomTransport(
  BuildContext context,
  PlaybackService playback,
  String action,
) {
  final JamService jam = context.read<JamService>();
  if (!jam.inRoom) return false;
  if (!jam.isConnected) {
    showAppNotice('Reconnecting to the room…');
    return true;
  }
  if (!jam.canControl) {
    showAppNotice('Only the host controls playback in this room.');
    return true;
  }
  switch (action) {
    case 'toggle':
      if (jam.playback?.isPlaying ?? false) {
        unawaited(playback.pause());
      }
      jam.togglePlayPause();
    case 'next':
      jam.next();
    case 'previous':
      jam.previous();
  }
  return true;
}

/// Routes a seek to the room (and applies it locally straight away so the
/// scrubber feels responsive; the coordinator re-aligns to the server's
/// echo if needed). Returns true when handled.
bool roomSeek(BuildContext context, PlaybackService playback, Duration to) {
  final JamService jam = context.read<JamService>();
  if (!jam.inRoom) return false;
  if (!jam.isConnected) {
    showAppNotice('Reconnecting to the room…');
    return true;
  }
  if (!jam.canControl) {
    showAppNotice('Only the host controls playback in this room.');
    return true;
  }
  jam.seek(to);
  unawaited(playback.seekTo(to));
  return true;
}

/// Shuffle and repeat are per-device queue reshapers; in a room they would
/// quietly pull this phone out of step with everyone else. Returns true
/// when the tap was explained and swallowed.
bool roomModeNotice(BuildContext context) {
  final JamService jam = context.read<JamService>();
  if (!jam.inRoom) return false;
  showAppNotice('Shuffle and repeat pause inside a room — the room queue leads.');
  return true;
}
