/// Human-readable names for the audio and subtitle tracks a video carries.
///
/// Files coming off the mirrors are muxed by whoever uploaded them, and they
/// name their tracks after their own site: a raw track title arrives as
/// something like `-eonmovies.com.hin.aac.2ch`, which is exactly what the
/// playback sheet used to print verbatim.
///
/// Two things happen here, and only these two:
///
///   * every uploader domain/URL in the title is replaced with this app's own
///     name ([trackSourceName]) — the rest of the title is kept, and
///   * what is left is made readable: `hin` → Hindi, `aac` → AAC,
///     `2ch` → Stereo, `DTS-HD.MA` → DTS-HD MA.
///
/// Nothing is invented: a token this file does not recognise is passed through
/// exactly as the file wrote it, so a track named after a real release group
/// still says so.
library;

/// What an uploader's own domain is replaced with in every track name.
const String trackSourceName = 'Ifallertzia';

/// Top-level domains worth recognising. Deliberately narrow and alphabetic:
/// `720p.mp4` or `S01.E04` must never be mistaken for somebody's website.
const String _tlds =
    r'(?:com|net|org|info|biz|click|link|site|online|xyz|club|live|hub|top|'
    r'fun|space|website|world|icu|buzz|cyou|app|me|tv|to|cc|ws|io|co|in|us|'
    r'uk|de|fr|jp|ru|cn|es|it|br|au|ca|nl|se|pl|tr|id|my|sg|hk|kr|mx|za|pk|'
    r'bd|lk|np|ae|sa|il|gr|cz|sk|hu|ro|bg|rs|hr|si|lt|lv|ee|ua|by|kz|uz)';

/// `http://x.y/z`, `www.x.y` or a bare `x.y` host.
final RegExp _urlPattern = RegExp(
  r'''(?:https?://|www\.)[^\s\]\[(){}<>|"'`,;]+''',
  caseSensitive: false,
);

final RegExp _hostPattern = RegExp(
  r'\b[a-z0-9][a-z0-9+-]*(?:[._-][a-z0-9+-]+)*\.' +
      _tlds +
      r'(?:\.' +
      _tlds +
      r')?(?:[:/][^\s]*)?',
  caseSensitive: false,
);

/// `2ch`, `6 ch` … — replaced before the separators go.
final RegExp _channelCount = RegExp(r'\b([1-9])\s*ch\b', caseSensitive: false);

/// Separators between the words of a track title.
final RegExp _separators = RegExp(r'''[\[\](){}<>|/\\:,;*_+=~`"'!?#@$%^&.-]+''');

final RegExp _spaces = RegExp(r'\s+');

/// Names that span a separator, keyed by the lower-cased words they leave
/// behind once `.`/`-`/`_` have become spaces. Longest match wins, so
/// `DTS HD MA` is one codec and not `DTS-HD` plus a stray `MA`.
const Map<String, String> _phrases = <String, String>{
  'dts hd ma': 'DTS-HD MA',
  'dts hd hra': 'DTS-HD HRA',
  'dts hd': 'DTS-HD',
  'dts es': 'DTS-ES',
  'he aac': 'HE-AAC',
  'e ac3': 'E-AC3',
  'true hd': 'TrueHD',
  'h 264': 'H.264',
  'x 264': 'H.264',
  'h 265': 'HEVC',
  'x 265': 'HEVC',
  'web vtt': 'WebVTT',
  'dvd sub': 'VobSub',
  'mov text': 'TX3G',
  'dual audio': 'Dual audio',
  'multi audio': 'Multi audio',
  '1 0': 'Mono',
  '2 0': 'Stereo',
  '4 0': '4.0',
  '5 1': '5.1',
  '6 1': '6.1',
  '7 1': '7.1',
};

/// Two-letter codes are trusted only when they come from the container's own
/// metadata ([audioTrackLanguage]); inside a free-text title `as`, `id` and
/// `hi` are far more often ordinary words.
const Map<String, String> _languages = <String, String>{
  'hin': 'Hindi', 'hindi': 'Hindi',
  'eng': 'English', 'english': 'English',
  'tam': 'Tamil', 'tamil': 'Tamil',
  'tel': 'Telugu', 'telugu': 'Telugu',
  'kan': 'Kannada', 'kannada': 'Kannada',
  'mal': 'Malayalam', 'malayalam': 'Malayalam',
  'ben': 'Bengali', 'bengali': 'Bengali', 'bangla': 'Bengali',
  'mar': 'Marathi', 'marathi': 'Marathi',
  'guj': 'Gujarati', 'gujarati': 'Gujarati',
  'pan': 'Punjabi', 'pun': 'Punjabi', 'punjabi': 'Punjabi',
  'urd': 'Urdu', 'urdu': 'Urdu',
  'ori': 'Odia', 'oriya': 'Odia', 'odia': 'Odia',
  'asm': 'Assamese', 'assamese': 'Assamese',
  'ara': 'Arabic', 'arabic': 'Arabic',
  'fra': 'French', 'fre': 'French', 'french': 'French',
  'spa': 'Spanish', 'spanish': 'Spanish',
  'deu': 'German', 'ger': 'German', 'german': 'German',
  'ita': 'Italian', 'italian': 'Italian',
  'por': 'Portuguese', 'portuguese': 'Portuguese',
  'rus': 'Russian', 'russian': 'Russian',
  'jpn': 'Japanese', 'japanese': 'Japanese',
  'kor': 'Korean', 'korean': 'Korean',
  'zho': 'Chinese', 'chi': 'Chinese', 'chinese': 'Chinese',
  'mandarin': 'Chinese',
  'tha': 'Thai', 'thai': 'Thai',
  'vie': 'Vietnamese', 'vietnamese': 'Vietnamese',
  'ind': 'Indonesian', 'indonesian': 'Indonesian',
  'tur': 'Turkish', 'turkish': 'Turkish',
  'nep': 'Nepali', 'nepali': 'Nepali',
  'sin': 'Sinhala', 'sinhala': 'Sinhala',
  'fas': 'Persian', 'per': 'Persian', 'persian': 'Persian',
  'heb': 'Hebrew', 'hebrew': 'Hebrew',
  'pol': 'Polish', 'polish': 'Polish',
  'nld': 'Dutch', 'dut': 'Dutch', 'dutch': 'Dutch',
  'swe': 'Swedish', 'swedish': 'Swedish',
  'und': '', 'unknown': '', 'none': '', 'undefined': '',
};

/// Two-letter codes, applied to container metadata only.
const Map<String, String> _shortLanguages = <String, String>{
  'hi': 'Hindi', 'en': 'English', 'ta': 'Tamil', 'te': 'Telugu',
  'kn': 'Kannada', 'ml': 'Malayalam', 'bn': 'Bengali', 'mr': 'Marathi',
  'gu': 'Gujarati', 'pa': 'Punjabi', 'ur': 'Urdu', 'or': 'Odia',
  'as': 'Assamese', 'ar': 'Arabic', 'fr': 'French', 'es': 'Spanish',
  'de': 'German', 'it': 'Italian', 'pt': 'Portuguese', 'ru': 'Russian',
  'ja': 'Japanese', 'ko': 'Korean', 'zh': 'Chinese', 'th': 'Thai',
  'vi': 'Vietnamese', 'id': 'Indonesian', 'tr': 'Turkish', 'ne': 'Nepali',
  'si': 'Sinhala', 'fa': 'Persian', 'he': 'Hebrew', 'pl': 'Polish',
  'nl': 'Dutch', 'sv': 'Swedish',
};

const Map<String, String> _codecs = <String, String>{
  'aac': 'AAC', 'ac3': 'AC3', 'ac4': 'AC4', 'eac3': 'E-AC3',
  'heaac': 'HE-AAC', 'dts': 'DTS', 'dtshd': 'DTS-HD', 'truehd': 'TrueHD',
  'atmos': 'Atmos', 'mp3': 'MP3', 'mp2': 'MP2', 'flac': 'FLAC',
  'opus': 'Opus', 'vorbis': 'Vorbis', 'ogg': 'Ogg', 'pcm': 'PCM',
  'alac': 'ALAC', 'wma': 'WMA', 'wmav2': 'WMA',
  'h264': 'H.264', 'x264': 'H.264', 'avc': 'H.264', 'hevc': 'HEVC',
  'h265': 'HEVC', 'x265': 'HEVC', 'av1': 'AV1', 'vp9': 'VP9',
  'mpeg2': 'MPEG-2', 'mpeg4': 'MPEG-4',
  'srt': 'SRT', 'subrip': 'SRT', 'ass': 'ASS', 'ssa': 'SSA', 'sub': 'SUB',
  'idx': 'VobSub', 'vobsub': 'VobSub', 'vtt': 'WebVTT', 'webvtt': 'WebVTT',
  'pgs': 'PGS', 'sup': 'PGS', 'hdmv': 'PGS', 'dvdsub': 'VobSub',
  'mov_text': 'TX3G', 'tx3g': 'TX3G', 'arib': 'ARIB',
};

/// Words worth spelling out rather than dropping.
const Map<String, String> _words = <String, String>{
  'dual': 'Dual audio',
  'multi': 'Multi audio',
  'dub': 'Dubbed',
  'dubbed': 'Dubbed',
};

/// Container noise: the word says nothing about which track this is.
const Set<String> _noise = <String>{
  'audio', 'track', 'subtitle', 'subtitles', 'subs',
  'stream', 'default', 'www', 'http', 'https',
};

/// `2ch`, `6ch` … as the speaker layout people actually read.
String channelLayoutLabel(int channels) {
  switch (channels) {
    case 0:
      return '';
    case 1:
      return 'Mono';
    case 2:
      return 'Stereo';
    case 6:
      return '5.1';
    case 8:
      return '7.1';
    default:
      return '$channels ch';
  }
}

/// A container's language tag (`hin`, `hi`, `Hindi`) as a word.
///
/// Returns the upper-cased tag when it is not a language this app knows, so
/// nothing is ever silently dropped.
String audioTrackLanguage(String? language) {
  final String tag = (language ?? '').trim().toLowerCase();
  if (tag.isEmpty) return '';
  final String? long = _languages[tag];
  if (long != null) return long;
  final String? short = _shortLanguages[tag];
  if (short != null) return short;
  return tag.toUpperCase();
}

/// A container's codec tag (`aac`, `eac3`, `subrip`) as a name.
String audioTrackCodec(String? codec) {
  final String tag = (codec ?? '').trim().toLowerCase();
  if (tag.isEmpty) return '';
  final String? known = _codecs[tag];
  if (known != null) return known;
  final String? flat = _codecs[tag.replaceAll(_separators, '')];
  if (flat != null) return flat;
  return tag.toUpperCase();
}

/// The readable version of a raw track title.
///
/// `-eonmovies.com.hin.aac.2ch` → `Ifallertzia Hindi AAC Stereo`.
String cleanTrackTitle(String raw) {
  String text = raw.trim();
  if (text.isEmpty) return '';

  // 1. The uploader's site becomes ours — however many times it appears.
  text = text
      .replaceAll(_urlPattern, ' $trackSourceName ')
      .replaceAll(_hostPattern, ' $trackSourceName ');

  // 2. `2ch` while the dot it may sit next to still means something.
  text = text.replaceAllMapped(
    _channelCount,
    (Match m) => ' ${channelLayoutLabel(int.parse(m.group(1)!))} ',
  );

  // 3. Everything else that separates words becomes a space.
  final List<String> tokens = text
      .replaceAll(_separators, ' ')
      .replaceAll(_spaces, ' ')
      .trim()
      .split(' ')
      .where((String token) => token.isNotEmpty)
      .toList();

  // 4. Names that span a separator are rebuilt first (longest match wins);
  //    single words are mapped or kept exactly as the file wrote them.
  final List<String> words = <String>[];
  int i = 0;
  while (i < tokens.length) {
    String? phrase;
    int used = 0;
    for (int span = 3; span >= 2; span--) {
      if (i + span > tokens.length) continue;
      final String key = tokens
          .sublist(i, i + span)
          .map((String t) => t.toLowerCase())
          .join(' ');
      final String? hit = _phrases[key];
      if (hit != null) {
        phrase = hit;
        used = span;
        break;
      }
    }
    if (phrase != null) {
      words.add(phrase);
      i += used;
      continue;
    }

    final String token = tokens[i++];
    final String key = token.toLowerCase();
    if (_noise.contains(key)) continue;
    final String mapped = _words[key] ??
        _languages[key] ??
        _codecs[key] ??
        (key == trackSourceName.toLowerCase() ? trackSourceName : token);
    if (mapped.isNotEmpty) words.add(mapped);
  }

  // 5. `Ifallertzia Ifallertzia`, `Hindi Hindi` — say it once.
  final List<String> out = <String>[];
  for (final String word in words) {
    if (out.isNotEmpty &&
        out.last.toLowerCase() == word.toLowerCase()) {
      continue;
    }
    out.add(word);
  }
  final String joined = out.join(' ');
  // A bare number is the container's own track index, not a name worth
  // showing on its own — the caller falls back to `Audio 2` instead.
  if (joined.isEmpty || RegExp(r'^\d+$').hasMatch(joined)) return '';
  return joined;
}

bool _mentions(String text, String detail) {
  if (detail.isEmpty) return false;
  final String flat = detail.replaceAll(_separators, '').toLowerCase();
  if (flat.isEmpty) return false;
  return text.replaceAll(_separators, '').toLowerCase().contains(flat);
}

/// Joins the file's own title with what the container reports about the track,
/// never repeating a detail the title already gave.
String _describe({
  required String base,
  required List<String> details,
  required String fallback,
}) {
  final List<String> parts = <String>[if (base.isNotEmpty) base];
  for (final String detail in details) {
    if (detail.isEmpty) continue;
    if (parts.any((String p) => _mentions(p, detail))) continue;
    parts.add(detail);
  }
  if (parts.isEmpty) return fallback;
  return parts.join(' • ');
}

/// The line the playback sheet shows for one audio track.
String describeAudioTrack({
  String? title,
  String? language,
  String? codec,
  int channels = 0,
  int index = 0,
}) {
  return _describe(
    base: cleanTrackTitle(title ?? ''),
    details: <String>[
      audioTrackLanguage(language),
      audioTrackCodec(codec),
      channelLayoutLabel(channels),
    ],
    fallback: 'Audio ${index + 1}',
  );
}

/// The line the playback sheet shows for one subtitle track.
String describeSubtitleTrack({
  String? title,
  String? language,
  String? codec,
  int index = 0,
}) {
  return _describe(
    base: cleanTrackTitle(title ?? ''),
    details: <String>[
      audioTrackLanguage(language),
      audioTrackCodec(codec),
    ],
    fallback: 'Subtitle ${index + 1}',
  );
}
