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
}
