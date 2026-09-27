class LyricLine {
  const LyricLine(this.startMs, this.text);
  final int startMs;
  final String text;
  Map<String, dynamic> toJson() => {'ms': startMs, 'text': text};
}

List<LyricLine> parseLrc(String lrc) {
  final offsetMatch = RegExp(
    r'^\[\s*offset\s*:\s*([+-]?\d+)\s*\]',
    multiLine: true,
    caseSensitive: false,
  ).firstMatch(lrc);
  final offset = int.tryParse(offsetMatch?.group(1) ?? '') ?? 0;
  final stamp = RegExp(r'\[(\d{1,3}):(\d{1,3})(?:[.:](\d{1,3}))?\]');
  final linePattern = RegExp(
    r'^((?:\[\d{1,3}:\d{1,3}(?:[.:]\d{1,3})?\])+)(.*)$',
  );
  final meta = RegExp(
    r'^\[(ar|ti|al|au|by|offset|re|ve|length|hash|sign|qq|total|tool|language|karaoke)\s*:',
    caseSensitive: false,
  );
  final word = RegExp(r'<\d{1,3}:\d{1,3}(?:[.:]\d{1,3})?>');
  final out = <LyricLine>[];
  for (final raw in lrc.split('\n')) {
    final line = raw.trim();
    if (meta.hasMatch(line)) continue;
    final match = linePattern.firstMatch(line);
    if (match == null) continue;
    var text = match.group(2)!.replaceAll(word, '').trim();
    if (text.isEmpty) continue;
    if (text.length > 500) text = text.substring(0, 500);
    for (final time in stamp.allMatches(match.group(1)!)) {
      final fraction = time.group(3) ?? '';
      final ms =
          int.parse(time.group(1)!) * 60000 +
          int.parse(time.group(2)!) * 1000 +
          (fraction.isEmpty ? 0 : int.parse(fraction.padRight(3, '0'))) +
          offset;
      out.add(LyricLine(ms < 0 ? 0 : ms, text));
      if (out.length >= 1200) break;
    }
    if (out.length >= 1200) break;
  }
  out.sort((a, b) => a.startMs.compareTo(b.startMs));
  return out;
}

bool usableSync(List<LyricLine> lines) =>
    lines.length >= 2 && lines.any((l) => l.startMs > 0);
