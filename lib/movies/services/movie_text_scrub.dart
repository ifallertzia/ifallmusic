/// Keeps a source site's own name out of everything a person can read.
///
/// The extra catalogs' pages, file names and track titles are stamped with the
/// site's name ("Movie.2025.1080p.x264-<site>.Ms.mkv", "Download … from
/// <site>", "Avatar_2009_Full_<site>.com.mkv"). That name is an implementation
/// detail: the app shows the catalog as "IMAX HD" or "ifallhub" and nothing
/// else. Every visible string that originates from those catalogs goes through
/// [scrubSourceNames] before it is displayed.
///
/// Only the site's name is removed — the rest of the text is left exactly as
/// it was written.
library;

/// The source sites behind the two extra catalogs: the IMAX HD catalog's own
/// site, and the three sites the Ifallhub server fronts for. Spelled loosely
/// (`Kimoi TV`, `kimoi.tv`, `4k HD Hub`, …) so a stamp in any of those shapes
/// is caught.
const String _siteCore = r'(?:www\.)?(?:'
    r'hd[\s._-]?hub[\s._-]?4[\s._-]?u'
    r'|kimoi[\s._-]?tv'
    r'|4k[\s._-]?hd[\s._-]?hub'
    r'|dra[\s._-]?machi'
    r')';

/// A domain ending glued to the name (`.ms`, `.com`, …, with any path behind
/// it) — but never a media file extension, so `Movie-<site>.mkv` keeps its
/// `.mkv`.
const String _siteTld =
    r'(?:\.(?!(?:mkv|mp4|avi|webm|m4v|mov|ts|zip|rar|7z|srt|ass|mp3|m4a)\b)'
    r'[a-z]{2,6}\b(?:/\S*)?)?';

final RegExp _sourceNameOnly = RegExp(_siteCore, caseSensitive: false);

/// The name together with the separator / opening bracket in front of it and a
/// closing bracket behind it, so removing it does not leave `x264-.mkv` or
/// `Title ()` behind.
final RegExp _sourceName = RegExp(
  r'[\s._\-|\[({]*' + _siteCore + _siteTld + r'[\])}]*',
  caseSensitive: false,
);

final RegExp _joinsWithoutSpace = RegExp(r'[\s._\-|,;:!?)\]}]');
final RegExp _spaces = RegExp(r'\s{2,}');
final RegExp _edgeSeparators =
    RegExp('^[\\s._\\-|:,\u2013\u2014]+|[\\s_\\-|:,\u2013\u2014]+\$');

/// Whether [text] names the source site.
bool mentionsSourceName(String text) => _sourceNameOnly.hasMatch(text);

/// [text] without the source site's name. Returns an empty string when the
/// site name was all there was.
String scrubSourceNames(String text) {
  if (text.isEmpty || !_sourceNameOnly.hasMatch(text)) return text;
  String out = text.replaceAllMapped(_sourceName, (Match m) {
    if (m.start == 0 || m.end >= text.length) return '';
    return _joinsWithoutSpace.hasMatch(text[m.end]) ? '' : ' ';
  });
  out = out.replaceAll(_spaces, ' ');
  out = out.replaceAll(_edgeSeparators, '');
  return out.trim();
}
