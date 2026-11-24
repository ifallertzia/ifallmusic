import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/movie_models.dart';
import '../models/movie_provider.dart';
import 'eon_movies_service.dart';
import 'hdhub4u_service.dart';
import 'ifallhub_service.dart';
import 'movie_http_client.dart';
import 'movie_source.dart';

/// Everything Sidify Movies needs, across **all three** catalogs.
///
/// * browsing (Recommended, Bollywood, …) is served by EonMovies — the catalog
///   that actually has those sections,
/// * search asks every catalog and merges the answers, so the same title shows
///   up once as a normal EonMovies row, once as a *premium* HDHub4U row and
///   once as an *ifallhub* row,
/// * every model object carries its [MovieProvider], so resolving a quality,
///   expanding a season or listing a ZIP always goes back to the service that
///   produced the link.
class MoviesRepository {
  MoviesRepository({
    EonMoviesService? eon,
    Hdhub4uService? hdhub4u,
    IfallhubService? ifallhub,
    bool? includePremiumProvider,
  })  : eon = eon ?? EonMoviesService(),
        hdhub4u = hdhub4u ?? Hdhub4uService(),
        ifallhub = ifallhub,
        _includePremiumProvider = includePremiumProvider ?? !_runningTests;

  final EonMoviesService eon;
  final Hdhub4uService hdhub4u;

  /// The Ifallhub-powered catalog. Optional so a widget test (which has no
  /// network) can build a repository without it; the real app always passes
  /// one.
  final IfallhubService? ifallhub;
  final bool _includePremiumProvider;

  /// Whether mixed search results include the premium catalogs.
  bool get includesPremiumProvider => _includePremiumProvider;

  /// Whether the ifallhub catalog takes part in search and browsing.
  bool get includesIfallhub => _includePremiumProvider && ifallhub != null;

  /// Widget tests have no network: the premium catalogs are skipped unless a
  /// test builds a repository with its own fake transport and asks for them.
  static bool get _runningTests {
    if (kIsWeb) return false;
    try {
      return Platform.environment.containsKey('FLUTTER_TEST');
    } catch (_) {
      return false;
    }
  }

  MovieSource sourceFor(MovieProvider provider) {
    switch (provider) {
      case MovieProvider.eonMovies:
        return eon;
      case MovieProvider.hdhub4u:
        return hdhub4u;
      case MovieProvider.ifallhub:
        final IfallhubService? hub = ifallhub;
        if (hub == null) {
          throw StateError('The ifallhub catalog is not available.');
        }
        return hub;
    }
  }

  /// Shared transport — the downloader streams bytes through it.
  MovieHttpTransport get transport => eon.transport;

  // ----------------------------------------------------------------- catalog

  /// Browse page (Recommended / Bollywood / …) — EonMovies catalog.
  Future<List<MoviePost>> fetchPosts({
    MovieCategory category = MovieCategory.recommended,
    int page = 1,
  }) {
    return eon.fetchPosts(category: category, page: page);
  }

  /// Latest premium titles — HDHub4U's own listing.
  Future<List<MoviePost>> fetchPremiumPosts({
    MovieCategory category = MovieCategory.recommended,
    int page = 1,
  }) async {
    if (!_includePremiumProvider || page > 1) return const <MoviePost>[];
    try {
      return await hdhub4u.fetchPosts(category: category, page: page);
    } catch (_) {
      return const <MoviePost>[];
    }
  }

  /// Latest titles of the Ifallhub-powered catalog.
  Future<List<MoviePost>> fetchIfallhubPosts({
    MovieCategory category = MovieCategory.recommended,
    int page = 1,
  }) async {
    final IfallhubService? hub = ifallhub;
    if (!_includePremiumProvider || hub == null || page > 1) {
      return const <MoviePost>[];
    }
    try {
      return await hub.fetchPosts(category: category, page: page);
    } catch (_) {
      return const <MoviePost>[];
    }
  }

  /// Mixed search: EonMovies rows first, then the premium HDHub4U rows, then
  /// the ifallhub rows.
  Future<List<MoviePost>> search({
    required String query,
    int page = 1,
  }) async {
    final String trimmed = query.trim();
    final List<MoviePost> results = <MoviePost>[];
    final Set<String> seen = <String>{};

    void addAll(List<MoviePost> posts) {
      for (final MoviePost post in posts) {
        final String key =
            '${post.provider.id}|${post.title.toLowerCase()}|${post.link}';
        if (seen.add(key)) results.add(post);
      }
    }

    try {
      addAll(await eon.searchPosts(query: trimmed, page: page));
    } catch (_) {}

    if (_includePremiumProvider && trimmed.isNotEmpty) {
      try {
        addAll(await hdhub4u.searchPosts(query: trimmed, page: page));
      } catch (_) {}

      final IfallhubService? hub = ifallhub;
      if (hub != null) {
        try {
          addAll(await hub.searchPosts(query: trimmed, page: page));
        } catch (_) {}
      }
    }

    return results;
  }

  Future<MovieDetail> fetchDetail(
    MovieProvider provider,
    String link, {
    int autoExpandLimit = 8,
  }) async {
    final MovieSource source = sourceFor(provider);
    try {
      return await source.fetchDetail(
        link,
        autoExpandLimit: autoExpandLimit,
      );
    } catch (_) {
      // Catalog endpoints occasionally wake up slowly or return a transient
      // gateway error while the app has been left open. Retry the idempotent
      // title request once, rather than making a relaunch the recovery path.
      await Future<void>.delayed(const Duration(milliseconds: 450));
      return source.fetchDetail(
        link,
        autoExpandLimit: autoExpandLimit,
      );
    }
  }

  Future<MovieEpisodeGroup> expandEpisodeGroup(MovieEpisodeGroup group) {
    return sourceFor(group.provider).expandEpisodeGroup(group);
  }

  // ----------------------------------------------------------------- streams

  Future<ResolvedMovieStream> resolveDownloadStream(
    MovieQualityLink quality, {
    required String fallbackTitle,
  }) {
    return sourceFor(quality.provider)
        .resolveDownloadStream(quality, fallbackTitle: fallbackTitle);
  }

  Future<ResolvedMovieStream> resolvePlaybackStream(
    MovieQualityLink quality, {
    required String fallbackTitle,
  }) {
    return sourceFor(quality.provider)
        .resolvePlaybackStream(quality, fallbackTitle: fallbackTitle);
  }

  Future<MovieZipPackListing> listZipPackEpisodes(
    MovieQualityLink quality, {
    required String fallbackTitle,
  }) {
    return sourceFor(quality.provider)
        .listZipPackEpisodes(quality, fallbackTitle: fallbackTitle);
  }

  Future<({MovieStreamCandidate candidate, MovieZipEpisode episode})>
      prepareZipEpisodeDownload(
    MovieQualityLink packQuality, {
    required String fallbackTitle,
  }) {
    return sourceFor(packQuality.provider)
        .prepareZipEpisodeDownload(packQuality, fallbackTitle: fallbackTitle);
  }

  /// Builds the synthetic per-episode quality for one entry inside a season
  /// ZIP pack, using the provider that owns the pack.
  MovieQualityLink qualityForZipEpisode(
    MovieQualityLink pack,
    MovieZipEpisode episode,
  ) {
    switch (pack.provider) {
      case MovieProvider.eonMovies:
        return EonMoviesService.qualityForZipEpisode(pack, episode);
      case MovieProvider.hdhub4u:
        return Hdhub4uService.qualityForZipEpisode(pack, episode);
      case MovieProvider.ifallhub:
        throw StateError(
          'Season ZIP packs are not part of the ifallhub catalog — '
          'download an episode instead.',
        );
    }
  }

  void dispose() {
    eon.dispose();
    hdhub4u.dispose();
    ifallhub?.dispose();
  }
}

/// Reads [MoviesRepository] from the widget tree.
///
/// Widget tests (and any older page that only provided the EonMovies service)
/// still work: a repository is then built around whichever service is
/// registered, with the premium catalogs switched off.
MoviesRepository moviesRepositoryOf(BuildContext context) {
  final MoviesRepository? provided = context.read<MoviesRepository?>();
  if (provided != null) return provided;
  final EonMoviesService? eon = context.read<EonMoviesService?>();
  return MoviesRepository(eon: eon, includePremiumProvider: false);
}
