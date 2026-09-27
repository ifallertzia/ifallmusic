import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/services/lrc_parser.dart';
import 'package:ifallmusic/services/lyrics_clock.dart';

void main() {
  test('speed, frame clamp, duration clamp and invalid speed', () {
    expect(advance(100, 200, 2, 5000), 500);
    expect(advance(0, 1200, 2, 5000), 1000);
    expect(advance(4900, 500, 1, 5000), 5000);
    expect(advance(0, 200, 0, 5000), 200);
    expect(advance(0, 200, .5, 5000), 100);
  });
  test('resync only beyond threshold or when paused', () {
    expect(needsResync(900, 0, true), isFalse);
    expect(needsResync(901, 0, true), isTrue);
    expect(needsResync(0, 0, false), isTrue);
  });
  test('binary search boundaries and equal timestamps', () {
    const lines = [
      LyricLine(100, 'A'),
      LyricLine(200, 'B'),
      LyricLine(200, 'C'),
      LyricLine(500, 'D'),
    ];
    expect(activeLineIndex([], 0), -1);
    expect(activeLineIndex(lines, 0), -1);
    expect(activeLineIndex(lines, 199), 0);
    expect(activeLineIndex(lines, 200), 2);
    expect(activeLineIndex(lines, 600), 3);
  });
}
