import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/services/lrc_parser.dart';

void main() {
  test('multi-stamp, positive offset, metadata and enhanced word markers', () {
    final lines = parseLrc(
      '[ar:Artist]\n[offset:+500]\n[00:12.43][01:02.435]<00:12.43> Chorus\n[00:00.4] Intro\n[00:03.00]',
    );
    expect(lines.map((l) => l.startMs), [900, 12930, 62935]);
    expect(lines.map((l) => l.text), ['Intro', 'Chorus', 'Chorus']);
    expect(usableSync(lines), isTrue);
  });
  test('negative offset clamps, fraction forms and unusable timestamps', () {
    expect(parseLrc('[offset:-500]\n[00:00.4]Zero').single.startMs, 0);
    expect(
      parseLrc('[00:01]A\n[00:01:43]B\n[00:01.435]C').map((l) => l.startMs),
      [1000, 1430, 1435],
    );
    expect(usableSync(parseLrc('[00:00.00]Intro')), isFalse);
    expect(usableSync(parseLrc('[00:00]A\n[00:00]B')), isFalse);
  });
  test('line and text caps', () {
    final lines = parseLrc(List.filled(1300, '[00:01]${'a' * 600}').join('\n'));
    expect(lines.length, 1200);
    expect(lines.first.text.length, 500);
  });
}
