import 'dart:math';

import 'lrc_parser.dart';

const resyncThresholdMs = 900;
const maxFrameMs = 500;
int advance(int from, int elapsedMs, double speed, int durationMs) =>
    (from + min(max(elapsedMs, 0), maxFrameMs) * (speed > 0 ? speed : 1))
        .round()
        .clamp(0, max(0, durationMs));
bool needsResync(int clock, int reported, bool playing) =>
    !playing || (clock - reported).abs() > resyncThresholdMs;
int activeLineIndex(List<LyricLine> lines, int positionMs) {
  int low = 0, high = lines.length - 1, answer = -1;
  while (low <= high) {
    final mid = (low + high) ~/ 2;
    if (lines[mid].startMs <= positionMs) {
      answer = mid;
      low = mid + 1;
    } else {
      high = mid - 1;
    }
  }
  return answer;
}
