import 'package:unorm_dart/unorm_dart.dart' as unicode;

String cleanTitle(String title) {
  var s = title;
  for (final pattern in [
    r'\[[^\]]*(?:official|video|audio|lyrics?|visualizer|hd|remaster)[^\]]*\]',
    r'\([^)]*(?:official|video|audio|lyrics?|visualizer|remaster|version|feat\.?)[^)]*\)',
    r'\b(?:official\s+)?(?:music\s+)?(?:video|audio)\b',
    r'\b(?:lyrics?|visualizer|4k|8k|hd|hq)\b',
    r'\s*[-–—|]+\s*$',
  ]) {
    s = s.replaceAll(RegExp(pattern, caseSensitive: false), ' ');
  }
  return s.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String cleanArtist(String artist) => artist
    .replaceAll(RegExp(r'\s*[-–—]\s*Topic\s*$|VEVO$', caseSensitive: false), '')
    .replaceAll(
      RegExp(r'^(Unknown Artist|Various Artists)$', caseSensitive: false),
      '',
    )
    .trim();
typedef LyricsQuery = ({String title, String artist});
List<LyricsQuery> queryVariants({
  required String title,
  required String artist,
}) {
  final out = <LyricsQuery>[];
  artist = cleanArtist(artist);
  void add(String t, String a) {
    final q = (title: cleanTitle(t), artist: cleanArtist(a));
    if (q.title.isNotEmpty &&
        !out.any(
          (v) =>
              normalize(v.title) == normalize(q.title) &&
              normalize(v.artist) == normalize(q.artist),
        ) &&
        out.length < 4)
      out.add(q);
  }

  add(title, artist);
  final first = title.split(RegExp(r'\s*\|\s*|\s+[–—]\s+')).first;
  if (first.contains(' - ')) {
    final parts = first.split(' - ');
    add(parts[1], parts[0]);
    add(parts[0], artist);
  } else if (first != title) {
    add(first, artist);
  }
  add(
    first.replaceAll(RegExp(r'\s*\(from\s+[^)]*\)', caseSensitive: false), ''),
    artist,
  );
  return out;
}

String normalize(String value) => unicode
    .nfkc(value)
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

Map<String, dynamic>? rankLyrics(
  List<Map<String, dynamic>> records,
  List<LyricsQuery> variants,
  int durationSecs,
) {
  final matches = <({Map<String, dynamic> record, int score})>[];
  for (final record in records) {
    if (record['instrumental'] != true &&
        (record['plainLyrics'] as String? ?? '').trim().isEmpty &&
        (record['syncedLyrics'] as String? ?? '').trim().isEmpty)
      continue;
    int best = -1;
    for (final variant in variants) {
      if (normalize(cleanTitle(record['trackName'] as String? ?? '')) !=
          normalize(variant.title))
        continue;
      int score = 0;
      if (variant.artist.isNotEmpty &&
          normalize(
            record['artistName'] as String? ?? '',
          ).contains(normalize(variant.artist)))
        score += 4;
      if (durationSecs > 0 &&
          record['duration'] is num &&
          ((record['duration'] as num) - durationSecs).abs() <= 5)
        score += 2;
      if (score > best) best = score;
    }
    if (best >= 0) matches.add((record: record, score: best));
  }
  if (matches.isEmpty) return null;
  matches.sort((a, b) => b.score.compareTo(a.score));
  if (matches.first.score > 0 ||
      matches
              .map((m) => normalize(m.record['artistName'] as String? ?? ''))
              .toSet()
              .length ==
          1)
    return matches.first.record;
  return null;
}
