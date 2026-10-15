import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/ui/player/waveform_seek_bar.dart';

void main() {
  test('wave tapers smoothly to the straight rail', () {
    expect(WaveformPainter.envelope(0), 0);
    expect(WaveformPainter.envelope(16), 1);
    expect(WaveformPainter.envelope(100), 1);
    expect(WaveformPainter.envelope(0.01), lessThan(0.00001));
  });

  testWidgets('tap and drag seek, unknown duration does not seek', (tester) async {
    double value = 0.25;
    int commits = 0;
    Future<void> mount(bool enabled) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(
        child: SizedBox(width: 300, child: WaveformSeekBar(
          value: value, enabled: enabled, playing: false, artworkUrl: '',
          reduceMotion: true,
          onChanged: (v) => value = v,
          onEnd: (commit) { if (commit) commits++; },
        )),
      ))));
      await tester.pump();
    }
    await mount(true);
    final bar = find.byType(WaveformSeekBar);
    final rect = tester.getRect(bar);
    await tester.tapAt(Offset(rect.left + 150, rect.center.dy));
    expect(value, closeTo(0.5, 0.01));
    expect(commits, 1);
    await tester.dragFrom(Offset(rect.left + 60, rect.center.dy), const Offset(180, 0));
    expect(value, greaterThan(0.7));
    expect(commits, 2);
    await mount(false);
    await tester.tapAt(rect.center);
    expect(commits, 2);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  testWidgets('pausing stops the animation ticker', (tester) async {
    Future<void> mount(bool playing) async {
      await tester.pumpWidget(MaterialApp(home: WaveformSeekBar(
        value: 0.5, enabled: true, playing: playing, artworkUrl: '',
        reduceMotion: false, onChanged: (_) {}, onEnd: (_) {},
      )));
      await tester.pump();
    }
    await mount(true);
    expect(tester.binding.transientCallbackCount, greaterThan(0));
    await mount(false);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.binding.transientCallbackCount, 0);
    await tester.pumpWidget(const SizedBox());
  });
}
