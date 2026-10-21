import '../models/movie_models.dart';

enum MovieExploreType { all, movies, series }

final RegExp _yearPattern = RegExp(r'\b((?:19|20)\d{2})\b');

int? moviePostYear(MoviePost post) {
  final RegExpMatch? inSubtitle = _yearPattern.firstMatch(post.subtitle);
  if (inSubtitle != null) return int.tryParse(inSubtitle.group(1)!);
  final RegExpMatch? inTitle = _yearPattern.firstMatch(post.title);
  if (inTitle != null) return int.tryParse(inTitle.group(1)!);
  return null;
}

List<int> moviePostYears(Iterable<MoviePost> posts) {
  final Set<int> years = <int>{};
  for (final MoviePost post in posts) {
    final int? year = moviePostYear(post);
    if (year != null) years.add(year);
  }
  return years.toList()..sort((int a, int b) => b.compareTo(a));
}

List<MoviePost> filterMoviePosts(
  List<MoviePost> posts, {
  MovieExploreType type = MovieExploreType.all,
  int? year,
}) {
  return posts.where((MoviePost post) {
    if (type == MovieExploreType.movies && post.isSeries) return false;
    if (type == MovieExploreType.series && !post.isSeries) return false;
    if (year != null && moviePostYear(post) != year) return false;
    return true;
  }).toList();
}

bool movieDetailHasLanguage(MovieDetail detail, String language) {
  final String wanted = language.trim().toLowerCase();
  if (wanted.isEmpty) return true;
  for (final String entry in detail.languageList) {
    if (entry.trim().toLowerCase() == wanted) return true;
  }
  return detail.languages.toLowerCase().contains(wanted);
}

bool movieDetailHasGenre(MovieDetail detail, String genre) {
  final String wanted = genre.trim().toLowerCase();
  if (wanted.isEmpty) return true;
  for (final String entry in detail.genres) {
    final String actual = entry.trim().toLowerCase();
    if (actual == wanted || actual.contains(wanted) || wanted.contains(actual)) {
      return true;
    }
  }
  return false;
}

bool movieDetailMatchesExplore(
  MovieDetail detail, {
  String language = '',
  String genre = '',
}) {
  return movieDetailHasLanguage(detail, language) &&
      movieDetailHasGenre(detail, genre);
}
