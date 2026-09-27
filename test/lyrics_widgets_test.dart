import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/services/lrc_parser.dart';
import 'package:ifallmusic/widgets/copy_lyrics_button.dart';
import 'package:ifallmusic/widgets/lyrics_view.dart';

void main() {
  testWidgets('copy sends full plain text and resets after two seconds', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData')
          copied = (call.arguments as Map)['text'] as String;
        return null;
      },
    );
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: CopyLyricsButton(plain: 'One\nTwo')),
      ),
    );
    await tester.tap(find.text('Copy'));
    await tester.pump();
    expect(copied, 'One\nTwo');
    expect(find.text('Copied'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Copy'), findsOneWidget);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
  testWidgets('unusable sync falls back to selectable static text', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LyricsView(
            plain: 'Full text',
            lines: [LyricLine(0, 'Intro')],
            mode: LyricsMode.synced,
            source: 'LRCLIB',
          ),
        ),
      ),
    );
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Full text'), findsOneWidget);
  });

  testWidgets('static lyrics use compact line spacing', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: LyricsView(
            plain: 'One\nTwo\nThree',
            lines: [],
            mode: LyricsMode.staticText,
            source: 'LRCLIB',
          ),
        ),
      ),
    );
    final text = tester.widget<SelectableText>(find.byType(SelectableText));
    expect(text.style?.height, 1.45);
    expect(text.data, 'One\nTwo\nThree');
  });

  testWidgets('synced rows are compact, tappable and follow the active line', (
    tester,
  ) async {
    final lines = List.generate(30, (i) => LyricLine(i * 1000, 'Line $i'));
    int? sought;
    Widget view(int position) => MaterialApp(
      home: Scaffold(
        body: LyricsView(
          plain: '',
          lines: lines,
          mode: LyricsMode.synced,
          positionMs: position,
          source: 'LRCLIB',
          onSeek: (ms) => sought = ms,
        ),
      ),
    );
    await tester.pumpWidget(view(0));
    await tester.pumpAndSettle();
    final gap = tester.getCenter(find.text('Line 1')).dy -
        tester.getCenter(find.text('Line 0')).dy;
    expect(gap, closeTo(48, 1));
    await tester.tap(find.text('Line 1'));
    expect(sought, 1000);

    // Jump to a row that started offscreen; centering must use the new sizes.
    await tester.pumpWidget(view(20000));
    await tester.pumpAndSettle();
    final viewport = tester.getRect(find.byType(ListView));
    expect(tester.getCenter(find.text('Line 20')).dy,
        closeTo(viewport.center.dy, 2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wrapped lyrics have room at large text sizes and still center', (
    tester,
  ) async {
    final lines = List.generate(
      20,
      (i) => LyricLine(i * 1000, 'Verse $i with several words wrapping over lines'),
    );
    Widget view(int position) => MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              height: 500,
              child: LyricsView(
                plain: '',
                lines: lines,
                mode: LyricsMode.synced,
                positionMs: position,
                source: 'LRCLIB',
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(view(0));
    await tester.pumpAndSettle();
    final first = tester.getRect(find.text(lines[0].text));
    final second = tester.getRect(find.text(lines[1].text));
    expect(first.height, greaterThan(48));
    expect(second.top, greaterThan(first.bottom));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(view(10000));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text(lines[10].text)).dy,
        closeTo(tester.getRect(find.byType(ListView)).center.dy, 2));
    expect(tester.takeException(), isNull);
  });

}
