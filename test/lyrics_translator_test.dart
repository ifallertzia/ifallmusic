import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/services/lyrics_service.dart';
import 'package:ifallmusic/services/lyrics_translator.dart';

void main() {
  test('translation targets map to provider codes', () {
    expect(LyricsTranslator.codes['Hindi'], 'hi');
    expect(LyricsTranslator.codes['English'], 'en');
    expect(LyricsTranslator.codes[''], isNull);
  });

  test('off or unknown target returns the original result untouched', () async {
    const LyricsResult result = LyricsResult(
      plain: 'One\nTwo',
      source: 'LRCLIB',
    );
    expect(await LyricsTranslator.translate(result, ''), same(result));
    expect(await LyricsTranslator.translate(result, 'Klingon'), same(result));
    const LyricsResult missing = LyricsResult(status: LyricsStatus.notFound);
    expect(await LyricsTranslator.translate(missing, 'Hindi'), same(missing));
  });
}
