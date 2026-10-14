import 'dart:convert';

import 'package:http/http.dart' as http;

import 'lrc_parser.dart';
import 'lyrics_service.dart';

/// On-demand lyrics translation (BitChord's documented pipeline, in
/// miniature): translate the words, **project the translation back onto the
/// original timings**, and never let a failed translation hide lyrics that
/// were already found.
///
/// The provider is MyMemory's free endpoint — no key, generous enough for
/// line-batched song text. Requests batch whole lines (joined by newlines,
/// chunked under the provider's query limit), and a chunk whose translated
/// line count no longer matches the original is dropped rather than
/// misaligned: synced lyrics stay synced or stay original.
class LyricsTranslator {
  LyricsTranslator._();

  static final http.Client _client = http.Client();
  static final Map<String, String> _cache = <String, String>{};

  /// Language names offered in Settings → Lyrics → "Translate lyrics into".
  static const Map<String, String> codes = <String, String>{
    'English': 'en',
    'Hindi': 'hi',
    'Spanish': 'es',
    'French': 'fr',
    'German': 'de',
    'Portuguese': 'pt',
    'Japanese': 'ja',
    'Korean': 'ko',
    'Arabic': 'ar',
  };

  /// Returns [result] translated into [targetName], or [result] itself when
  /// translation is off, unneeded, or unavailable.
  static Future<LyricsResult> translate(
    LyricsResult result,
    String targetName,
  ) async {
    final String? code = codes[targetName.trim()];
    if (code == null || result.status != LyricsStatus.found) return result;
    try {
      if (result.lines.isNotEmpty) {
        final List<String>? texts = await _translateLines(
          result.lines.map((LyricLine l) => l.text).toList(),
          code,
        );
        if (texts == null) return result;
        // Timing projection: translated words ride the original timestamps.
        final List<LyricLine> lines = <LyricLine>[
          for (int i = 0; i < result.lines.length; i++)
            LyricLine(result.lines[i].startMs, texts[i]),
        ];
        return LyricsResult(
          plain: texts.join('\n'),
          lines: lines,
          source: '${result.source} · translated to $targetName',
          instrumental: result.instrumental,
          status: result.status,
        );
      }
      if (result.plain.trim().isNotEmpty) {
        final List<String>? plain = await _translateLines(
          result.plain.split('\n'),
          code,
        );
        if (plain == null) return result;
        return LyricsResult(
          plain: plain.join('\n'),
          source: '${result.source} · translated to $targetName',
          instrumental: result.instrumental,
          status: result.status,
        );
      }
    } catch (_) {
      // Translation is a garnish; the original lyrics always survive it.
    }
    return result;
  }

  /// Translates [texts] line-for-line. `null` when any chunk cannot be
  /// trusted to line up with the input (count changed, provider silent).
  static Future<List<String>?> _translateLines(
    List<String> texts,
    String code,
  ) async {
    // Blank lines cost nothing and must survive untouched.
    final List<int> filled = <int>[
      for (int i = 0; i < texts.length; i++)
        if (texts[i].trim().isNotEmpty) i,
    ];
    if (filled.isEmpty) return null;
    final Map<int, String> done = <int, String>{};

    // Batch consecutive lines into <=400-char chunks.
    int start = 0;
    while (start < filled.length) {
      int end = start;
      int size = 0;
      while (end < filled.length) {
        final int len = texts[filled[end]].length + 1;
        if (end > start && size + len > 400) break;
        size += len;
        end++;
      }
      final List<int> batch = filled.sublist(start, end);
      final String joined = batch.map((int i) => texts[i]).join('\n');
      final String? translated = await _translateChunk(joined, code);
      if (translated == null) return null;
      final List<String> parts = translated.split('\n');
      if (parts.length != batch.length) return null;
      for (int i = 0; i < batch.length; i++) {
        done[batch[i]] = parts[i].trim();
      }
      start = end;
    }

    return <String>[
      for (int i = 0; i < texts.length; i++) done[i] ?? texts[i],
    ];
  }

  static Future<String?> _translateChunk(String text, String code) async {
    final String key = '$code\n$text';
    final String? hit = _cache[key];
    if (hit != null) return hit;
    try {
      final Uri uri = Uri.https(
        'api.mymemory.translated.net',
        '/get',
        <String, String>{'q': text, 'langpair': 'Autodetect|$code'},
      );
      final http.Response response =
          await _client.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode < 200 || response.statusCode >= 300) return null;
      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map) return null;
      final Object? data = decoded['responseData'];
      if (data is! Map) return null;
      final String out = (data['translatedText'] ?? '').toString().trim();
      if (out.isEmpty) return null;
      if (_cache.length > 200) _cache.clear();
      _cache[key] = out;
      return out;
    } catch (_) {
      return null;
    }
  }
}
