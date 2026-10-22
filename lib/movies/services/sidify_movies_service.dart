import 'dart:convert';

import '../models/movie_models.dart';
import 'eon_movies_service.dart';
import 'movie_http_client.dart';

/// Sidify-V2 API adapter. Files still stream/download directly on the device.
/// Override the origin with --dart-define=SIDIFY_MEDIA_API=https://your-host.
class SidifyMoviesService extends EonMoviesService {
  SidifyMoviesService({super.transport, this.apiOrigin = defaultApiOrigin});

  static const defaultApiOrigin = String.fromEnvironment(
    'SIDIFY_MEDIA_API',
    defaultValue: 'https://sidify.vercel.app',
  );
  final String apiOrigin;

  String _url(String path, [Map<String, String> query = const {}]) =>
      Uri.parse('${apiOrigin.replaceAll(RegExp(r'/+$'), '')}/api/media/$path')
          .replace(queryParameters: query.isEmpty ? null : query).toString();

  Map<String, dynamic> _decode(MovieHttpResponse response) {
    if (response.statusCode != 200) {
      throw StateError('Sidify HTTP ${response.statusCode}. Please retry later.');
    }
    final value = jsonDecode(response.body);
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid Sidify response');
    }
    return value;
  }

  static List<Map<String, dynamic>> _rows(dynamic value) => value is List
      ? value.whereType<Map<String, dynamic>>().toList()
      : <Map<String, dynamic>>[];
  static String _s(dynamic value) => value?.toString() ?? '';

  MoviePost _post(Map<String, dynamic> item) => MoviePost(
    title: _s(item['title']),
    link: _url('title/${item['kind'] == 'series' ? 'series' : 'movie'}/${Uri.encodeComponent(_s(item['slug']))}'),
    imageUrl: _s(item['poster']),
    fallbackImageUrl: _s(item['backdrop']),
    badge: item['kind'] == 'series' ? 'SERIES' : 'MOVIE',
    subtitle: _s(item['year']),
  );

  @override
  Future<List<MoviePost>> fetchPosts({MovieCategory category = MovieCategory.recommended, int page = 1}) async {
    final data = _decode(await transport.get(_url('browse', {
      'type': category == MovieCategory.webSeries ? 'series' : 'movie',
      'page': '$page',
      if (category == MovieCategory.bollywood) 'language': 'hi',
      if (category == MovieCategory.hollywood) 'language': 'en',
      if (category == MovieCategory.anime) 'genre': 'animation',
      if (category == MovieCategory.southIndian) 'language': 'te',
    })));
    return _rows(data['items']).map(_post).toList();
  }

  @override
  Future<List<MoviePost>> searchPosts({required String query, int page = 1}) async {
    if (query.trim().isEmpty) return fetchPosts(page: page);
    // Search is unpaginated; do not append the same results on scroll.
    if (page > 1) return <MoviePost>[];
    final data = _decode(await transport.get(_url('search', {'q': query.trim(), 'type': 'all', 'limit': '60'})));
    return _rows(data['items']).map(_post).toList();
  }

  List<MovieQualityLink> _releases(dynamic value) {
    final result = <MovieQualityLink>[];
    for (final release in _rows(value)) {
      for (final mirror in _rows(release['mirrors'])) {
        final url = _s(mirror['shortUrl']);
        if (!_http(url)) continue;
        result.add(MovieQualityLink(
          id: '${release['id']}-${mirror['id']}',
          rawLabel: '${_s(release['title'])} • ${_s(mirror['label'])}',
          resolution: _s(release['quality']), dlUrl: url,
          sizeLabel: _s(release['size']), languages: _s(release['languages']),
          isZipPack: release['isPack'] == true,
          seasonLabel: release['seasonNumber'] == null ? '' : 'Season ${release['seasonNumber']}',
          episodeLabel: release['episodeNumber'] == null ? '' : 'Episode ${release['episodeNumber']}',
          fileName: _s(release['fileName']),
        ));
      }
    }
    return result;
  }

  @override
  Future<MovieDetail> fetchDetail(String linkOrUrl, {int autoExpandLimit = 8}) async {
    if (!linkOrUrl.contains('/api/media/title/')) {
      return super.fetchDetail(linkOrUrl, autoExpandLimit: autoExpandLimit);
    }
    final data = _decode(await transport.get(linkOrUrl));
    final title = Map<String, dynamic>.from(data['title'] as Map);
    final qualities = _releases(data['releases']);
    for (final download in _rows(data['downloads'])) {
      if (!_http(_s(download['url']))) continue;
      qualities.add(MovieQualityLink(id: 'download-${qualities.length}', rawLabel: _s(download['label']), resolution: _s(download['format']), dlUrl: _s(download['url']), isZipPack: RegExp(r'\.(zip|rar|7z)(\?|$)', caseSensitive: false).hasMatch(_s(download['url']))));
    }
    for (final source in _rows(data['playback'])) {
      if (source['type'] == 'embed' || !_http(_s(source['url']))) continue;
      qualities.add(MovieQualityLink(id: 'stream-${qualities.length}', rawLabel: _s(source['label']), resolution: _s(source['label']), dlUrl: _s(source['url'])));
    }
    final groups = <MovieEpisodeGroup>[];
    for (final season in _rows(data['seasons'])) {
      for (final episode in _rows(season['episodes'])) {
        groups.add(MovieEpisodeGroup(id: _s(episode['id']), title: _s(episode['title']), seasonLabel: 'Season ${season['seasonNumber']}', episodeLabel: 'Episode ${episode['episodeNumber']}', qualities: _releases(episode['releases']), isLoaded: true));
      }
    }
    return MovieDetail(title: _s(title['title']), cleanTitle: _s(title['title']), type: title['kind'] == 'series' ? MovieMediaType.series : MovieMediaType.movie, webUrl: linkOrUrl, year: _s(title['year']), releaseDate: _s(title['releaseDate']), posterUrl: _s(title['poster']), backdropUrl: _s(title['backdrop']), synopsis: _s(title['overview']), languages: _s(title['languageName'] ?? title['language']), genres: _rows(title['genres']).map((g) => _s(g['name'])).toList(), directQualities: qualities, episodeGroups: groups, relatedPosts: _rows(data['related']).map(_post).toList());
  }

  static bool _http(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
  }

  /// POSTs `/api/media/resolve` exactly like the Sidify-V2 web app:
  /// `{url, fileName?, label?, refresh?}`. Non-200 answers (403 / 422 / 502)
  /// still carry the same result shape — read the body instead of flattening
  /// every failure into "HTTP 422".
  Future<Map<String, dynamic>> _postResolve(
    MovieQualityLink quality, {
    required String label,
    bool refresh = false,
  }) async {
    final MovieHttpResponse response = await transport.post(
      _url('resolve'),
      body: jsonEncode(<String, Object?>{
        'url': quality.dlUrl,
        if (quality.fileName.isNotEmpty) 'fileName': quality.fileName,
        'label': label,
        if (refresh) 'refresh': true,
      }),
      headers: const <String, String>{'Content-Type': 'application/json'},
    );
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      decoded = null;
    }
    if (decoded is Map<String, dynamic> &&
        (decoded.containsKey('links') || decoded.containsKey('status'))) {
      return decoded;
    }
    throw StateError('Sidify HTTP ${response.statusCode}. Please retry later.');
  }

  List<MovieStreamCandidate> _mirrorCandidates(
    Map<String, dynamic> data,
    MovieQualityLink quality,
  ) {
    final String shareUrl = _s(data['externalFallbackUrl']).isNotEmpty
        ? _s(data['externalFallbackUrl'])
        : quality.dlUrl;
    final Map<String, String> headers = shareUrl.isEmpty
        ? const <String, String>{}
        : <String, String>{'Referer': shareUrl};
    return _rows(data['links'])
        .where((link) => link['delivery'] != 'external' && _http(_s(link['url'])))
        .map((link) => MovieStreamCandidate(
              server: _s(link['server']),
              url: _s(link['url']),
              headers: headers,
              isZip: quality.isZipPack,
            ))
        .toList();
  }

  @override
  Future<ResolvedMovieStream> resolveDownloadStream(
    MovieQualityLink quality, {
    required String fallbackTitle,
  }) async {
    // Retain the old resolver for downloads saved before switching providers.
    if (quality.dlUrl.contains('eonmovies') || quality.dlUrl.contains('dotflix')) {
      return super.resolveDownloadStream(quality, fallbackTitle: fallbackTitle);
    }
    final String label =
        quality.rawLabel.isNotEmpty ? quality.rawLabel : fallbackTitle;

    Map<String, dynamic> data = const <String, dynamic>{};
    List<MovieStreamCandidate> candidates = const <MovieStreamCandidate>[];
    Object? lastError;
    // The mirror resolver caches direct links; when they expire a second call
    // with `refresh: true` yields fresh ones instead of failing the download.
    for (final bool refresh in const <bool>[false, true]) {
      try {
        data = await _postResolve(quality, label: label, refresh: refresh);
        candidates = _mirrorCandidates(data, quality);
        if (candidates.isNotEmpty) break;
      } catch (error) {
        lastError = error;
      }
    }

    final String external = _s(data['externalFallbackUrl']).isNotEmpty
        ? _s(data['externalFallbackUrl'])
        : quality.dlUrl;

    if (candidates.isEmpty) {
      final String message = _s(data['message']);
      if (message.isNotEmpty) throw StateError(message);
      if (lastError != null) throw lastError;
      throw StateError(
        'Sidify could not resolve this mirror (${_s(data['status'])}). '
        'Try another mirror or the Browser icon.',
      );
    }

    return ResolvedMovieStream(
      candidates: candidates,
      filename: quality.fileName,
      sizeLabel: quality.sizeLabel,
      sharePageUrl: external,
      mimeType: quality.isZipPack ? 'application/zip' : 'video/x-matroska',
    );
  }
}
