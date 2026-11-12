/// Reads the score a title page states about itself.
///
/// Both catalogs print the score as text when they have one — "IMDb Rating:
/// 7.4/10", "⭐ 7.4", "Rating: 8.1 / 10". This finds that number and returns
/// it with one decimal ("7.4"). When the page states no score the result is
/// empty and the UI shows no rating at all: nothing is estimated or invented.
library;

final RegExp _labelled = RegExp(
  r'(?:imdb|tmdb|rating|score)[^0-9\n]{0,24}?(\d{1,2}(?:\.\d)?)\s*/\s*10\b',
  caseSensitive: false,
);

final RegExp _starred = RegExp(
  '(?:\u2B50|\u2605|\u{1F31F})\\uFE0F?\\s*(\\d(?:\\.\\d)?)(?:\\s*/\\s*10)?(?![\\d.])',
  unicode: true,
);

final RegExp _bareOutOfTen = RegExp(r'^\s*(\d(?:\.\d)?)\s*/\s*10\s*$');

String _format(String? raw) {
  final double? value = double.tryParse(raw ?? '');
  if (value == null || value <= 0 || value > 10) return '';
  return value.toStringAsFixed(1);
}

/// The score in a short label such as a metadata pill ("⭐ 7.4", "7.4/10").
String extractMovieRatingFromLabel(String label) {
  final String text = label.trim();
  if (text.isEmpty || text.length > 40) return '';
  final String starred = _format(_starred.firstMatch(text)?.group(1));
  if (starred.isNotEmpty) return starred;
  final String bare = _format(_bareOutOfTen.firstMatch(text)?.group(1));
  if (bare.isNotEmpty) return bare;
  return _format(_labelled.firstMatch(text)?.group(1));
}

/// The score stated somewhere in a page's text ("IMDb Rating: 7.4/10").
///
/// Only a labelled score counts here: a bare star next to a number elsewhere
/// on a page usually belongs to some other title's card.
String extractMovieRatingFromText(String text) {
  if (text.isEmpty) return '';
  return _format(_labelled.firstMatch(text)?.group(1));
}
