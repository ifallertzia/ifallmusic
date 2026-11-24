import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/movies/models/movie_models.dart';
import 'package:ifallmusic/movies/models/movie_provider.dart';
import 'package:ifallmusic/movies/services/movie_content_filter.dart';

void main() {
  const MoviePost ordinary = MoviePost(
    title: 'The Quiet City',
    link: 'https://catalog.invalid/the-quiet-city',
    imageUrl: '',
    provider: MovieProvider.eonMovies,
  );
  const MoviePost adult = MoviePost(
    title: 'Midnight Uncensored 18+',
    link: 'https://catalog.invalid/midnight',
    imageUrl: '',
    provider: MovieProvider.ifallhub,
  );

  test('adult-signalled catalog results are hidden until unlocked', () {
    expect(moviePostLooksAdult(adult), isTrue);
    expect(moviePostLooksAdult(ordinary), isFalse);
    expect(
      filterMoviePosts(<MoviePost>[ordinary, adult], adultContentUnlocked: false),
      <MoviePost>[ordinary],
    );
    expect(
      filterMoviePosts(<MoviePost>[ordinary, adult], adultContentUnlocked: true),
      <MoviePost>[ordinary, adult],
    );
  });

  test('adult signal matching is case-insensitive and handles 18+ labels', () {
    expect(containsAdultContentSignal('An EROTIC film'), isTrue);
    expect(containsAdultContentSignal('Rated 18+'), isTrue);
    expect(containsAdultContentSignal('A family animation'), isFalse);
  });
}
