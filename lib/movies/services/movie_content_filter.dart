import '../models/movie_models.dart';

/// A conservative, local signal-based guard for adult-labelled catalog rows.
/// Catalog search APIs do not consistently return genre/rating metadata, so
/// this checks the text that is available on a result and its detail page.
/// The unlock remains a user choice; this is intentionally not an age verifier.
final RegExp _adultContentSignal = RegExp(
  r'\b(adult|xxx|porn(?:o|ographic)?|hentai|erotic|nsfw|nudity|nude|uncensored|explicit|sex(?:ual)?|a-rated|r-?18|nc-17)\b|\b18\s*\+',
  caseSensitive: false,
);

bool containsAdultContentSignal(String text) =>
    _adultContentSignal.hasMatch(text);

bool moviePostLooksAdult(MoviePost post) =>
    post.isAdult ||
    containsAdultContentSignal(
      '${post.title} ${post.badge} ${post.subtitle} ${post.link}',
    );

bool movieDetailLooksAdult(MovieDetail detail) => containsAdultContentSignal(
      <String>[
        detail.title,
        detail.cleanTitle,
        detail.synopsis,
        detail.genres.join(' '),
        detail.qualityBadges.join(' '),
      ].join(' '),
    );

List<MoviePost> filterMoviePosts(
  Iterable<MoviePost> posts, {
  required bool adultContentUnlocked,
}) =>
    adultContentUnlocked
        ? List<MoviePost>.unmodifiable(posts)
        : List<MoviePost>.unmodifiable(
            posts.where((MoviePost post) => !moviePostLooksAdult(post)),
          );
