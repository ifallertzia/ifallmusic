import '../models/movie_models.dart';
import '../models/movie_provider.dart';
import 'movie_http_client.dart';

/// One movie / series catalog (EonMovies, HDHub4U, …).
///
/// Everything the UI and the download queue need from a catalog goes through
/// this interface, so pages, the player and the downloader never know which
/// provider they are talking to — they only carry a [MovieProvider] tag on the
/// link and let [MoviesRepository] pick the right implementation.
abstract class MovieSource {
  /// Which catalog this instance serves.
  MovieProvider get provider;

  /// Shared HTTP transport (also used by the downloader for byte streams).
  MovieHttpTransport get transport;

  /// Catalog page: recommended / Bollywood / Hollywood / … (36 per page).
  Future<List<MoviePost>> fetchPosts({
    MovieCategory category = MovieCategory.recommended,
    int page = 1,
  });

  /// Free text search inside this catalog.
  Future<List<MoviePost>> searchPosts({
    required String query,
    int page = 1,
  });

  /// Full title page: metadata, direct qualities and season/episode groups.
  Future<MovieDetail> fetchDetail(
    String linkOrUrl, {
    int autoExpandLimit = 8,
  });

  /// Expands one season / episode sub-page into its quality links.
  Future<MovieEpisodeGroup> expandEpisodeGroup(MovieEpisodeGroup group);

  /// Resolves a quality into ordered direct download mirrors.
  Future<ResolvedMovieStream> resolveDownloadStream(
    MovieQualityLink quality, {
    required String fallbackTitle,
  });

  /// Same as [resolveDownloadStream] but restricted to streamable mirrors.
  Future<ResolvedMovieStream> resolvePlaybackStream(
    MovieQualityLink quality, {
    required String fallbackTitle,
  });

  /// Lists the episodes inside a season ZIP pack without downloading it.
  Future<MovieZipPackListing> listZipPackEpisodes(
    MovieQualityLink quality, {
    required String fallbackTitle,
  });

  /// Prepares a single-episode-out-of-a-ZIP download.
  Future<({MovieStreamCandidate candidate, MovieZipEpisode episode})>
      prepareZipEpisodeDownload(
    MovieQualityLink packQuality, {
    required String fallbackTitle,
  });

  void dispose();
}

/// Whether a quality can be attempted in the online player.
///
/// Season ZIP packs and single episodes contained inside a ZIP stay
/// download-first: libmpv cannot seek into one compressed entry of a remote
/// archive without a local extraction/proxy layer. Ordinary movie and
/// per-episode links resolve to direct video files and can be streamed.
bool movieQualityCanStreamOnline(MovieQualityLink quality) {
  return !quality.isZipPack && !quality.isZipEntryEpisode;
}

/// Filters a resolved stream down to candidates that are safe to hand to the
/// streaming player, preserving mirror order and request headers.
List<MovieStreamCandidate> streamableMovieCandidates(
  ResolvedMovieStream resolved,
) {
  final String filename = resolved.filename.trim().toLowerCase();
  final String mimeType = resolved.mimeType.trim().toLowerCase();
  if (filename.endsWith('.zip') || mimeType.contains('zip')) {
    return const <MovieStreamCandidate>[];
  }

  return List<MovieStreamCandidate>.unmodifiable(
    resolved.candidates.where((MovieStreamCandidate candidate) {
      if (candidate.isZip) return false;
      final Uri? uri = Uri.tryParse(candidate.url.trim());
      if (uri == null || uri.host.isEmpty) return false;
      if (uri.scheme != 'http' && uri.scheme != 'https') return false;
      if (uri.path.toLowerCase().endsWith('.zip')) return false;
      return true;
    }),
  );
}
