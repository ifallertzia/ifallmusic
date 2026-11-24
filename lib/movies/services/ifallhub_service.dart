import 'dart:convert';

import '../../config/backend_config.dart';
import '../models/movie_models.dart';
import '../models/movie_provider.dart';
import 'movie_content_filter.dart';
import 'movie_http_client.dart';
import 'movie_source.dart';

/// Movies & series powered by the **Ifallhub** server.
///
/// The app talks to the same HTTP API the Ifallhub web player uses:
///
/// * `GET /api/discover` — the catalogue's own front page,
/// * `GET /api/search`   — free text search,
/// * `GET /api/details`  — one title page (poster, synopsis, seasons),
/// * `GET /api/streams`  — the playable releases of a movie or episode,
/// * `POST /api/play`    — a short-lived, same-origin media URL.
///
/// The server keeps every provider header on its own side: the app only ever
/// receives an `https://ifallhub.vercel.app/api/media/...` URL, which libmpv
/// can open without any header of its own.
///
/// Every model object this service produces carries [MovieProvider.ifallhub],
/// so the UI badges it *ifallhub* and every later step — season expansion,
/// playback, download — comes straight back here.
class IfallhubService implements MovieSource {
  IfallhubService({
    MovieHttpTransport? transport,
    String? baseUrl,
  })  : _transport = transport ?? DioMovieHttpTransport(),
        _ownsTransport = transport == null,
        _baseUrl = _normaliseBase(baseUrl ?? defaultBaseUrl);

  /// The public Ifallhub deployment.
  static const String defaultBaseUrl = BackendConfig.ifallhubBaseUrl;

  /// The server's own name for the catalogue that powers the web player's
  /// home page and search ("Siddharth" in the web UI). It is the only one of
  /// the server's providers that has a discover feed.
  static const String primaryProvider = 'moviebox';

  /// The server's other catalogues. When the primary one has no stream for a
  /// title (or its upstream is unreachable from the deployment) the same
  /// title is looked up on these, so a result that was found can also be
  /// played. The person only ever sees the *ifallhub* chip.
  static const List<String> fallbackProviders = <String>[
    'dramachi',
    'fourkhdhub',
  ];

  static const Duration _requestTimeout = Duration(seconds: 30);

  /// The primary catalogue is tried briefly: when its upstream is down the
  /// request must not hold the title page (or the player) hostage.
  static const Duration _primaryStreamTimeout = Duration(seconds: 8);

  static const Map<String, String> _jsonHeaders = <String, String>{
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };

  final MovieHttpTransport _transport;
  final bool _ownsTransport;
  final String _baseUrl;

  /// `provider|query` → the last answer, so a fallback lookup and the search
  /// box do not ask the server the same thing twice.
  final Map<String, List<MoviePost>> _searchCache =
      <String, List<MoviePost>>{};

  /// `provider|id|title|year` → `provider|id` of the same title on another
  /// catalogue, so a series does not re-search for every single episode.
  final Map<String, String> _fallbackCache = <String, String>{};

  /// `provider|id|season|episode` → the last stream list, so re-opening a
  /// title page does not ask the server for the same releases again. A link
  /// that expired server-side is refreshed by [_openPlay].
  final Map<String, _StreamAnswer> _streamCache = <String, _StreamAnswer>{};

  @override
  MovieProvider get provider => MovieProvider.ifallhub;

  @override
  MovieHttpTransport get transport => _transport;

  String get baseUrl => _baseUrl;

  static String _normaliseBase(String raw) {
    final String trimmed = raw.trim().replaceAll(RegExp(r'/+$'), '');
    return trimmed.isEmpty ? defaultBaseUrl : trimmed;
  }

  // ----------------------------------------------------------------- catalog

  @override
  Future<List<MoviePost>> fetchPosts({
    MovieCategory category = MovieCategory.recommended,
    int page = 1,
  }) async {
    // The server has one ranked feed; the category chips belong to the main
    // EonMovies catalogue, so every category shows the same feed here.
    final int safePage = page < 1 ? 1 : page;
    try {
      final dynamic data = await _getJson('/api/discover', <String, String>{
        'provider': primaryProvider,
        'page': '$safePage',
      });
      return _postsFromItems(_itemsOf(data));
    } catch (_) {
      return const <MoviePost>[];
    }
  }

  @override
  Future<List<MoviePost>> searchPosts({
    required String query,
    int page = 1,
  }) async {
    final String q = query.trim();
    if (q.isEmpty) return const <MoviePost>[];
    final List<MoviePost>? cached = _searchCache['$primaryProvider|${q.toLowerCase()}'];
    if (cached != null) return cached;
    final List<MoviePost> posts = await _searchProvider(primaryProvider, q);
    return posts;
  }

  Future<List<MoviePost>> _searchProvider(String providerName, String query) async {
    try {
      final dynamic data = await _getJson('/api/search', <String, String>{
        'q': query,
        'provider': providerName,
        'page': '1',
      });
      final List<MoviePost> posts = _postsFromItems(_itemsOf(data));
      _searchCache['$providerName|${query.toLowerCase()}'] = posts;
      return posts;
    } catch (_) {
      return const <MoviePost>[];
    }
  }

  @override
  Future<MovieDetail> fetchDetail(
    String linkOrUrl, {
    int autoExpandLimit = 8,
  }) async {
    final _Ref? ref = _parseRef(linkOrUrl);
    if (ref == null || ref.id.isEmpty) {
      throw StateError('This title is not part of the ifallhub catalog.');
    }

    final dynamic data = await _getJson(
      '/api/details',
      <String, String>{
        'provider': ref.provider,
        'id': ref.id,
      },
      timeout: const Duration(seconds: 40),
    );
    if (data is! Map) {
      throw StateError('ifallhub did not return this title.');
    }
    final Map<String, dynamic> json = Map<String, dynamic>.from(data);

    final String rawTitle = _stringOf(json['title']).trim().isNotEmpty
        ? _stringOf(json['title']).trim()
        : ref.title.trim();
    final String title = rawTitle.isEmpty ? 'Untitled' : rawTitle;
    final String year = _stringOf(json['year']).trim().isNotEmpty
        ? _stringOf(json['year']).trim()
        : ref.year.trim();
    final String mediaType = _stringOf(json['media_type']);
    final List<Map<String, dynamic>> seasons = _mapsOf(json['seasons']);
    final bool isSeries = mediaType == 'series' || seasons.isNotEmpty;

    final String poster = _stringOf(json['poster_url']).trim();
    final String synopsis = _stringOf(json['description']).trim();
    final String director = _stringOf(json['director']).trim();
    final String rating = _stringOf(json['imdb_rating']).trim();
    final List<String> genres = _stringsOf(json['genres']);

    final List<String> languageList = <String>[];
    for (final Map<String, dynamic> dub in _mapsOf(json['dubs'])) {
      final String label = _stringOf(dub['label']).trim().isNotEmpty
          ? _stringOf(dub['label']).trim()
          : _stringOf(dub['language']).trim();
      if (label.isNotEmpty && !languageList.contains(label)) {
        languageList.add(label);
      }
    }
    final String languages = languageList.join(', ');

    List<MovieQualityLink> directQualities = const <MovieQualityLink>[];
    List<MovieEpisodeGroup> episodeGroups = const <MovieEpisodeGroup>[];

    if (isSeries && seasons.isNotEmpty) {
      episodeGroups = _seasonGroups(
        ref: ref,
        seasons: seasons,
        title: title,
        year: year,
        languages: languages,
      );
    } else {
      // A film, or a series whose listing does not spell out its episodes:
      // one stream list for the title itself.
      final _StreamAnswer? answer = await _streamSetWithFallback(
        ref: ref,
        title: title,
        year: year,
        season: 0,
        episode: 0,
      );
      if (answer != null) {
        directQualities = _qualitiesFromSet(
          answer: answer,
          season: 0,
          episode: 0,
          languages: languages,
        );
      }
    }

    return MovieDetail(
      title: title,
      cleanTitle: _cleanTitle(title),
      type: isSeries ? MovieMediaType.series : MovieMediaType.movie,
      webUrl: _titleLink(
        provider: ref.provider,
        id: ref.id,
        title: title,
        year: year,
        type: isSeries ? 'series' : 'movie',
      ),
      year: year,
      backdropUrl: poster,
      posterUrl: poster,
      languages: languages,
      languageList: languageList,
      genres: genres,
      director: director,
      qualityBadges: <String>[
        ...genres,
        if (_stringOf(json['duration']).trim().isNotEmpty)
          _stringOf(json['duration']).trim(),
      ],
      synopsis: synopsis,
      directQualities: directQualities,
      episodeGroups: episodeGroups,
      provider: MovieProvider.ifallhub,
      rating: rating,
    );
  }

  @override
  Future<MovieEpisodeGroup> expandEpisodeGroup(MovieEpisodeGroup group) async {
    final _Ref? ref = _parseRef(group.subPageDlUrl);
    if (ref == null) return group;

    final _StreamAnswer? answer = await _streamSetWithFallback(
      ref: ref,
      title: ref.title.isNotEmpty ? ref.title : group.title,
      year: ref.year,
      season: ref.season,
      episode: ref.episode,
    );
    if (answer == null) {
      return group.copyWith(
        isLoaded: true,
        qualities: const <MovieQualityLink>[],
      );
    }
    return group.copyWith(
      isLoaded: true,
      qualities: _qualitiesFromSet(
        answer: answer,
        season: ref.season,
        episode: ref.episode,
        languages: group.languages,
      ),
    );
  }

  // ----------------------------------------------------------------- streams

  @override
  Future<ResolvedMovieStream> resolvePlaybackStream(
    MovieQualityLink quality, {
    required String fallbackTitle,
  }) async {
    final _Ref? ref = _parseRef(quality.dlUrl);
    if (ref == null) {
      throw StateError('This link is not part of the ifallhub catalog.');
    }
    final List<MovieStreamCandidate> candidates =
        await _playAllMirrors(ref, fallbackTitle: fallbackTitle);
    return ResolvedMovieStream(
      candidates: candidates,
      filename: ref.filename.isNotEmpty ? ref.filename : fallbackTitle,
      sizeLabel: quality.sizeLabel,
      mimeType: _mimeFor(ref.filename),
      sharePageUrl: _sharePageUrl(ref),
    );
  }

  @override
  Future<ResolvedMovieStream> resolveDownloadStream(
    MovieQualityLink quality, {
    required String fallbackTitle,
  }) async {
    final _Ref? ref = _parseRef(quality.dlUrl);
    if (ref == null) {
      throw StateError('This link is not part of the ifallhub catalog.');
    }
    final List<MovieStreamCandidate> candidates =
        await _playAllMirrors(ref, fallbackTitle: fallbackTitle);
    final String filename =
        ref.filename.isNotEmpty ? ref.filename : fallbackTitle;
    return ResolvedMovieStream(
      candidates: candidates,
      filename: filename,
      sizeLabel: quality.sizeLabel,
      mimeType: _mimeFor(filename),
      sharePageUrl: _sharePageUrl(ref),
    );
  }

  /// Ifallhub serves single files, never season archives.
  @override
  Future<MovieZipPackListing> listZipPackEpisodes(
    MovieQualityLink quality, {
    required String fallbackTitle,
  }) async {
    throw StateError(
      'Season ZIP packs are not part of the ifallhub catalog — '
      'download an episode instead.',
    );
  }

  @override
  Future<({MovieStreamCandidate candidate, MovieZipEpisode episode})>
      prepareZipEpisodeDownload(
    MovieQualityLink packQuality, {
    required String fallbackTitle,
  }) async {
    throw StateError(
      'Season ZIP packs are not part of the ifallhub catalog — '
      'download an episode instead.',
    );
  }

  @override
  void dispose() {
    _searchCache.clear();
    _fallbackCache.clear();
    _streamCache.clear();
    if (_ownsTransport) _transport.close();
  }

  // ------------------------------------------------------------- stream walk

  /// The playable releases of one title / episode, and the title they belong
  /// to — which may be another catalogue than the one the page was opened
  /// from.
  ///
  /// The title's own catalogue is asked first and briefly. When it has
  /// nothing (or its upstream does not answer from the deployment) the same
  /// title is looked up on the server's other catalogues, so a title that was
  /// found can also be played. Every play link then carries the catalogue
  /// that actually answered.
  Future<_StreamAnswer?> _streamSetWithFallback({
    required _Ref ref,
    required String title,
    required String year,
    required int season,
    required int episode,
    bool useCache = true,
  }) async {
    final String cacheKey = '${ref.provider}|${ref.id}|$season|$episode';
    if (useCache) {
      final _StreamAnswer? cached = _streamCache[cacheKey];
      if (cached != null) return cached;
    }

    // Once a title has been found on another catalogue, every later episode
    // goes straight there instead of waiting out the primary attempt again.
    final String fallbackKey =
        '${ref.provider}|${ref.id}|${title.toLowerCase()}|$year';
    final bool knownFallback = _fallbackCache.containsKey(fallbackKey);

    if (!knownFallback) {
      final _StreamSet? own = await _tryStreamSet(
        provider: ref.provider,
        id: ref.id,
        season: season,
        episode: episode,
        timeout: _primaryStreamTimeout,
      );
      if (own != null && own.releases.isNotEmpty) {
        return _remember(cacheKey, _StreamAnswer(ref: ref, set: own));
      }
    }

    final _Ref? alt = await _fallbackRef(ref: ref, title: title, year: year);
    if (alt == null) return null;

    final _StreamSet? other = await _tryStreamSet(
      provider: alt.provider,
      id: alt.id,
      season: season,
      episode: episode,
    );
    if (other == null || other.releases.isEmpty) return null;
    return _remember(cacheKey, _StreamAnswer(ref: alt, set: other));
  }

  _StreamAnswer _remember(String key, _StreamAnswer answer) {
    _streamCache[key] = answer;
    return answer;
  }

  Future<_StreamSet?> _tryStreamSet({
    required String provider,
    required String id,
    required int season,
    required int episode,
    Duration timeout = _requestTimeout,
  }) async {
    try {
      final dynamic data = await _getJson('/api/streams', <String, String>{
        'provider': provider,
        'id': id,
        'season': '$season',
        'episode': '$episode',
      }, timeout: timeout);
      if (data is! Map) return null;
      final String setId = _stringOf(data['stream_set_id']).trim();
      if (setId.isEmpty) return null;
      final List<_Release> releases = _releasesOf(data['releases']);
      if (releases.isEmpty) return null;
      return _StreamSet(id: setId, releases: releases);
    } catch (_) {
      return null;
    }
  }

  /// One media URL per mirror the release has (at most two), in the
  /// server's own order. The player walks them, so a mirror that is down
  /// costs one retry instead of the whole title.
  Future<List<MovieStreamCandidate>> _playAllMirrors(
    _Ref ref, {
    required String fallbackTitle,
  }) async {
    final List<MovieStreamCandidate> candidates = <MovieStreamCandidate>[];
    Object? lastError;
    final int mirrors = ref.mirrorCount < 1 ? 1 : ref.mirrorCount;
    for (int mirror = 0; mirror < mirrors && mirror < 2; mirror++) {
      try {
        final _PlayResult played = await _openPlay(
          ref,
          fallbackTitle: fallbackTitle,
          mirrorIndex: mirror,
        );
        candidates.add(MovieStreamCandidate(server: 'Ifallhub', url: played.url));
      } catch (error) {
        lastError = error;
      }
    }
    if (candidates.isEmpty) {
      if (lastError is StateError) throw lastError;
      throw StateError('No playable stream is available right now.');
    }
    return candidates;
  }

  /// Opens one release: `POST /api/play` answers a short-lived media URL on
  /// the server's own origin.
  ///
  /// A stream list is forgotten by the server after an hour. When that
  /// happens (410) the list is fetched again for the same title and episode
  /// and the same release is played again — a page that was left open never
  /// becomes unplayable.
  Future<_PlayResult> _openPlay(
    _Ref ref, {
    required String fallbackTitle,
    int mirrorIndex = 0,
  }) async {
    if (ref.streamSetId.isEmpty || ref.releaseIndex < 0) {
      throw StateError('This stream link has expired. Open the title again.');
    }
    try {
      return await _postPlay(
        streamSetId: ref.streamSetId,
        releaseIndex: ref.releaseIndex,
        mirrorIndex: mirrorIndex,
      );
    } on IfallhubApiException catch (error) {
      final bool expired = error.statusCode == 410 || error.statusCode == 400;
      if (!expired) rethrow;
    }

    final _StreamAnswer? answer = await _streamSetWithFallback(
      ref: ref,
      title: ref.title.isNotEmpty ? ref.title : fallbackTitle,
      year: ref.year,
      season: ref.season,
      episode: ref.episode,
      // The cached list is the one that just expired — ask for a new one.
      useCache: false,
    );
    if (answer == null || answer.set.releases.isEmpty) {
      throw StateError('No playable stream is available right now.');
    }
    int index = ref.releaseIndex;
    if (index < 0 || index >= answer.set.releases.length) {
      index = _closestRelease(answer.set.releases, ref);
    }
    return _postPlay(
      streamSetId: answer.set.id,
      releaseIndex: index,
      // The same mirror is asked for again after a refresh.
      mirrorIndex: mirrorIndex,
    );
  }

  Future<_PlayResult> _postPlay({
    required String streamSetId,
    required int releaseIndex,
    required int mirrorIndex,
  }) async {
    final dynamic data = await _postJson('/api/play', <String, Object>{
      'stream_set_id': streamSetId,
      'release_index': releaseIndex,
      'mirror_index': mirrorIndex,
    });
    if (data is! Map) {
      throw StateError('ifallhub did not return a playback link.');
    }
    final String raw = _stringOf(data['playback_url']).trim();
    if (raw.isEmpty) {
      throw StateError('ifallhub did not return a playback link.');
    }
    final String url = raw.startsWith('/') ? '$_baseUrl$raw' : raw;
    return _PlayResult(url: url);
  }

  /// Index of the release closest to the one that expired — same quality and
  /// size when the list still has it, otherwise the first entry.
  int _closestRelease(List<_Release> releases, _Ref ref) {
    for (int i = 0; i < releases.length; i++) {
      final _Release release = releases[i];
      if (ref.quality.isNotEmpty && release.quality == ref.quality) {
        if (ref.sizeBytes <= 0 || release.sizeBytes == ref.sizeBytes) return i;
      }
    }
    for (int i = 0; i < releases.length; i++) {
      if (ref.quality.isNotEmpty && releases[i].quality == ref.quality) return i;
    }
    return 0;
  }

  // ---------------------------------------------------------- fallback titles

  /// The same title on another catalogue the server hosts, or null.
  Future<_Ref?> _fallbackRef({
    required _Ref ref,
    required String title,
    required String year,
  }) async {
    final String key =
        '${ref.provider}|${ref.id}|${title.toLowerCase()}|$year';
    final String? cached = _fallbackCache[key];
    if (cached != null) {
      final int split = cached.indexOf('|');
      if (split > 0) {
        return _Ref(
          provider: cached.substring(0, split),
          id: cached.substring(split + 1),
          season: ref.season,
          episode: ref.episode,
          title: title,
          year: year,
        );
      }
    }

    final String query = _searchQueryOf(title);
    if (query.isEmpty) return null;

    for (final String alt in fallbackProviders) {
      if (alt == ref.provider) continue;
      final _Ref? match = await _findTitle(
        provider: alt,
        query: query,
        title: title,
        year: year,
      );
      if (match == null) continue;
      _fallbackCache[key] = '${match.provider}|${match.id}';
      return _Ref(
        provider: match.provider,
        id: match.id,
        season: ref.season,
        episode: ref.episode,
        title: title,
        year: year,
      );
    }
    return null;
  }

  Future<_Ref?> _findTitle({
    required String provider,
    required String query,
    required String title,
    required String year,
  }) async {
    final String want = _titleKey(title);
    if (want.isEmpty) return null;
    final List<MoviePost> posts = await _searchProvider(provider, query);
    if (posts.isEmpty) return null;

    final List<MoviePost> exact = <MoviePost>[];
    final List<MoviePost> byYear = <MoviePost>[];
    final List<MoviePost> anyYear = <MoviePost>[];
    for (final MoviePost post in posts) {
      final String have = _titleKey(post.title);
      if (!_titlesMatch(want, have)) continue;
      anyYear.add(post);
      if (have == want) exact.add(post);
      if (year.isNotEmpty && post.subtitle.trim() == year.trim()) {
        byYear.add(post);
      }
    }
    // The same words first, then the same year, then anything with the title
    // in it — never a "The Last Avatar" when the film itself is listed.
    final List<MoviePost> pool =
        exact.isNotEmpty ? exact : (byYear.isNotEmpty ? byYear : anyYear);
    for (final MoviePost post in pool) {
      final _Ref? ref = _parseRef(post.link);
      if (ref != null && ref.id.isNotEmpty) return ref;
    }
    return null;
  }

  // ----------------------------------------------------------------- helpers

  Future<dynamic> _getJson(
    String path,
    Map<String, String> query, {
    Duration timeout = _requestTimeout,
  }) async {
    final Uri uri = Uri.parse('$_baseUrl$path').replace(queryParameters: query);
    final MovieHttpResponse response = await _transport
        .get(uri.toString(), headers: _jsonHeaders)
        .timeout(timeout);
    return _decode(response);
  }

  Future<dynamic> _postJson(String path, Map<String, Object> body) async {
    final MovieHttpResponse response = await _transport
        .post(
          '$_baseUrl$path',
          body: jsonEncode(body),
          headers: _jsonHeaders,
        )
        .timeout(_requestTimeout);
    return _decode(response);
  }

  dynamic _decode(MovieHttpResponse response) {
    final int status = response.statusCode;
    if (status < 200 || status >= 300) {
      throw IfallhubApiException(status, _messageOf(response.body, status));
    }
    final String body = response.body.trim();
    if (body.isEmpty) return null;
    try {
      return jsonDecode(body);
    } catch (_) {
      throw IfallhubApiException(
        status,
        'ifallhub sent an answer the app could not read.',
      );
    }
  }

  static String _messageOf(String body, int status) {
    try {
      final dynamic decoded = jsonDecode(body);
      if (decoded is Map) {
        final String message = _stringOf(decoded['error']).trim();
        if (message.isNotEmpty) return message;
      }
    } catch (_) {}
    if (body.trim().isEmpty) return 'ifallhub did not answer ($status).';
    final String flat = body.trim().replaceAll(RegExp(r'\s+'), ' ');
    return flat.length > 160 ? '${flat.substring(0, 160)}…' : flat;
  }

  List<MoviePost> _postsFromItems(List<Map<String, dynamic>> items) {
    final List<MoviePost> out = <MoviePost>[];
    for (final Map<String, dynamic> item in items) {
      final Map<String, dynamic>? idMap =
          item['id'] is Map ? item['id'] as Map<String, dynamic> : null;
      final String value = idMap != null
          ? _stringOf(idMap['value'])
          : _stringOf(item['id']);
      if (value.trim().isEmpty) continue;
      final String providerName = idMap != null
          ? _stringOf(idMap['provider'])
          : primaryProvider;
      final String title = _stringOf(item['title']).trim();
      if (title.isEmpty) continue;
      final String type = _stringOf(item['media_type']);
      final String year = _stringOf(item['year']).trim();
      final bool explicitlyAdult =
          item['adult'] == true ||
          item['is_adult'] == true ||
          _stringOf(item['adult']).toLowerCase() == 'true' ||
          _stringOf(item['is_adult']).toLowerCase() == 'true';
      final String adultHints = <String>[
        title,
        _stringOf(item['content_rating']),
        _stringOf(item['certification']),
        _stringOf(item['classification']),
        _stringOf(item['description']),
        _stringsOf(item['genres']).join(' '),
        _stringsOf(item['tags']).join(' '),
      ].join(' ');
      out.add(
        MoviePost(
          title: title,
          link: _titleLink(
            provider: providerName.isEmpty ? primaryProvider : providerName,
            id: value.trim(),
            title: title,
            year: year,
            type: type,
          ),
          imageUrl: _stringOf(item['poster_url']).trim(),
          badge: type == 'series' ? 'Series' : 'Movie',
          subtitle: year,
          isAdult: explicitlyAdult || containsAdultContentSignal(adultHints),
          provider: MovieProvider.ifallhub,
        ),
      );
    }
    return out;
  }

  List<MovieQualityLink> _qualitiesFromSet({
    required _StreamAnswer answer,
    required int season,
    required int episode,
    String languages = '',
  }) {
    final _Ref ref = answer.ref;
    final _StreamSet set = answer.set;
    final List<MovieQualityLink> out = <MovieQualityLink>[];
    for (int i = 0; i < set.releases.length; i++) {
      final _Release release = set.releases[i];
      final String quality = release.quality.isNotEmpty ? release.quality : 'Auto';
      final String language =
          release.language.isNotEmpty ? release.language : languages;
      out.add(
        MovieQualityLink(
          id: 'ifallhub_${ref.provider}_${ref.id}_${season}_${episode}_$i',
          rawLabel: quality,
          resolution: _resolutionOf(quality),
          codec: release.codec,
          sizeLabel: release.sizeBytes > 0
              ? MovieByteFmt.bytes(release.sizeBytes)
              : '',
          dlUrl: _playUri(
            ref: ref,
            set: set,
            releaseIndex: i,
            mirrorIndex: 0,
            release: release,
            quality: quality,
            mirrorCount: release.mirrorCount,
          ),
          languages: language,
          seasonLabel: season > 0 ? 'Season $season' : '',
          episodeLabel: episode > 0 ? 'Episode $episode' : '',
          provider: MovieProvider.ifallhub,
        ),
      );
    }
    return out;
  }

  List<MovieEpisodeGroup> _seasonGroups({
    required _Ref ref,
    required List<Map<String, dynamic>> seasons,
    required String title,
    required String year,
    required String languages,
  }) {
    final List<MovieEpisodeGroup> groups = <MovieEpisodeGroup>[];
    for (final Map<String, dynamic> season in seasons) {
      final int number = _intOf(season['number']);
      if (number <= 0) continue;
      final List<Map<String, dynamic>> episodes = _mapsOf(season['episodes']);
      final List<MovieEpisodeGroup> nested = <MovieEpisodeGroup>[];
      for (final Map<String, dynamic> episode in episodes) {
        final int epNumber = _intOf(episode['number']);
        if (epNumber <= 0) continue;
        nested.add(
          MovieEpisodeGroup(
            id: 'ifallhub_${ref.provider}_${ref.id}_s${number}_e$epNumber',
            title: 'Episode $epNumber',
            seasonLabel: 'Season $number',
            episodeLabel: 'Episode $epNumber',
            languages: languages,
            subPageDlUrl: _episodeUri(
              ref: ref,
              season: number,
              episode: epNumber,
              title: title,
              year: year,
            ),
            provider: MovieProvider.ifallhub,
          ),
        );
      }
      if (nested.isEmpty) {
        // Some listings only say how many seasons there are; still let the
        // person try the season instead of showing nothing.
        nested.add(
          MovieEpisodeGroup(
            id: 'ifallhub_${ref.provider}_${ref.id}_s${number}_e1',
            title: 'Episode 1',
            seasonLabel: 'Season $number',
            episodeLabel: 'Episode 1',
            languages: languages,
            subPageDlUrl: _episodeUri(
              ref: ref,
              season: number,
              episode: 1,
              title: title,
              year: year,
            ),
            provider: MovieProvider.ifallhub,
          ),
        );
      }
      groups.add(
        MovieEpisodeGroup(
          id: 'ifallhub_${ref.provider}_${ref.id}_s$number',
          title: 'Season $number',
          seasonLabel: 'Season $number',
          languages: languages,
          subPageDlUrl: _seasonUri(
            ref: ref,
            season: number,
            title: title,
            year: year,
          ),
          nestedGroups: nested,
          isLoaded: true,
          provider: MovieProvider.ifallhub,
        ),
      );
    }
    return groups;
  }

  String _sharePageUrl(_Ref ref) {
    return Uri.parse('$_baseUrl/title/${ref.provider}/${ref.id}').toString();
  }

  // ------------------------------------------------------------------- links

  String _titleLink({
    required String provider,
    required String id,
    required String title,
    required String year,
    required String type,
  }) {
    return Uri.parse('$_baseUrl/api/details').replace(
      queryParameters: <String, String>{
        'provider': provider,
        'id': id,
        'title': title,
        'year': year,
        'type': type,
      },
    ).toString();
  }

  String _seasonUri({
    required _Ref ref,
    required int season,
    required String title,
    required String year,
  }) {
    return Uri(
      scheme: 'ifallhub',
      host: 'season',
      queryParameters: <String, String>{
        'provider': ref.provider,
        'id': ref.id,
        'season': '$season',
        'title': title,
        'year': year,
      },
    ).toString();
  }

  String _episodeUri({
    required _Ref ref,
    required int season,
    required int episode,
    required String title,
    required String year,
  }) {
    return Uri(
      scheme: 'ifallhub',
      host: 'episode',
      queryParameters: <String, String>{
        'provider': ref.provider,
        'id': ref.id,
        'season': '$season',
        'episode': '$episode',
        'title': title,
        'year': year,
      },
    ).toString();
  }

  String _playUri({
    required _Ref ref,
    required _StreamSet set,
    required int releaseIndex,
    required int mirrorIndex,
    required _Release release,
    required String quality,
    required int mirrorCount,
  }) {
    return Uri(
      scheme: 'ifallhub',
      host: 'play',
      queryParameters: <String, String>{
        'provider': ref.provider,
        'id': ref.id,
        'season': '${ref.season}',
        'episode': '${ref.episode}',
        'title': ref.title,
        'year': ref.year,
        'set': set.id,
        'release': '$releaseIndex',
        'mirror': '$mirrorIndex',
        'mirrors': '$mirrorCount',
        'name': release.filename,
        'quality': quality,
        'size': '${release.sizeBytes}',
      },
    ).toString();
  }

  static _Ref? _parseRef(String raw) {
    final String text = raw.trim();
    if (text.isEmpty) return null;
    final Uri? uri = Uri.tryParse(text);
    if (uri == null) return null;
    if (uri.scheme == 'ifallhub') {
      final Map<String, String> query = uri.queryParameters;
      final String id = query['id'] ?? '';
      if (id.isEmpty) return null;
      return _Ref(
        provider: query['provider'] ?? primaryProvider,
        id: id,
        season: int.tryParse(query['season'] ?? '') ?? 0,
        episode: int.tryParse(query['episode'] ?? '') ?? 0,
        title: query['title'] ?? '',
        year: query['year'] ?? '',
        filename: query['name'] ?? '',
        quality: query['quality'] ?? '',
        sizeBytes: int.tryParse(query['size'] ?? '') ?? 0,
        streamSetId: query['set'] ?? '',
        releaseIndex: int.tryParse(query['release'] ?? '') ?? -1,
        mirrorIndex: int.tryParse(query['mirror'] ?? '') ?? 0,
        mirrorCount: int.tryParse(query['mirrors'] ?? '') ?? 1,
      );
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    final Map<String, String> query = uri.queryParameters;
    final String id = query['id'] ?? '';
    if (id.isEmpty) return null;
    return _Ref(
      provider: query['provider'] ?? primaryProvider,
      id: id,
      season: int.tryParse(query['season'] ?? '') ?? 0,
      episode: int.tryParse(query['episode'] ?? '') ?? 0,
      title: query['title'] ?? '',
      year: query['year'] ?? '',
    );
  }

  // ------------------------------------------------------------------ statics

  static List<Map<String, dynamic>> _itemsOf(dynamic data) {
    dynamic raw = data;
    if (data is Map) {
      raw = data['items'] ?? data['results'] ?? data['list'];
    }
    if (raw is! List) return const <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final dynamic item in raw) {
      if (item is Map) out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }

  static List<Map<String, dynamic>> _mapsOf(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    final List<Map<String, dynamic>> out = <Map<String, dynamic>>[];
    for (final dynamic item in raw) {
      if (item is Map) out.add(Map<String, dynamic>.from(item));
    }
    return out;
  }

  static List<String> _stringsOf(dynamic raw) {
    if (raw is! List) return const <String>[];
    final List<String> out = <String>[];
    for (final dynamic item in raw) {
      final String value = _stringOf(item).trim();
      if (value.isNotEmpty) out.add(value);
    }
    return out;
  }

  static List<_Release> _releasesOf(dynamic raw) {
    if (raw is! List) return const <_Release>[];
    final List<_Release> out = <_Release>[];
    for (final dynamic item in raw) {
      if (item is! Map) continue;
      final _Release release = _Release.fromJson(item);
      if (release.filename.isEmpty && release.quality.isEmpty) continue;
      out.add(release);
    }
    return out;
  }

  static String _stringOf(dynamic value) {
    if (value == null) return '';
    return value is String ? value : value.toString();
  }

  static int _intOf(dynamic value) {
    if (value is num) return value.toInt();
    return int.tryParse(_stringOf(value).trim()) ?? 0;
  }

  static String _resolutionOf(String quality) {
    final String q = quality.trim().toLowerCase();
    if (q == '4k' || q == 'uhd') return '2160p';
    if (q.isEmpty || q == 'auto' || q == 'multi' || q == 'multi-res') {
      return 'Auto';
    }
    return quality.trim();
  }

  /// A title without the tag noise the server's listings carry
  /// (`[Hindi]`, `[CAM]`, a trailing year), used for file names and for
  /// matching the same title on another catalogue.
  static String _cleanTitle(String raw) {
    String out = raw;
    out = out.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    out = out.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    out = out.replaceAll(RegExp(r'\b(?:19|20)\d{2}\b'), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    out = out.replaceAll(RegExp(r'^[\s:–—-]+|[\s:–—-]+$'), '');
    return out.isEmpty ? raw.trim() : out;
  }

  /// The plain title used as a search query on another catalogue.
  static String _searchQueryOf(String raw) {
    String out = _cleanTitle(raw);
    out = out.replaceAll(RegExp(r'\b(?:season|s)\s*\d+\b.*$', caseSensitive: false), ' ');
    out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
    return out;
  }

  static String _titleKey(String raw) {
    String out = raw.toLowerCase();
    out = out.replaceAll(RegExp(r'\[[^\]]*\]'), ' ');
    out = out.replaceAll(RegExp(r'\([^)]*\)'), ' ');
    out = out.replaceAll(RegExp(r'\b(?:19|20)\d{2}\b'), ' ');
    out = out.replaceAll(
      RegExp(r'\b(?:season|s)\s*\d+(?:\s*[-–]\s*s?\d+)?\b'),
      ' ',
    );
    out = out.replaceAll(RegExp(r'\b(?:episode|e)\s*\d+\b'), ' ');
    out = out.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    return out.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static bool _titlesMatch(String a, String b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a == b) return true;
    if (a.length >= 5 && b.contains(a)) return true;
    if (b.length >= 5 && a.contains(b)) return true;
    return false;
  }

  static String _mimeFor(String filename) {
    final String lower = filename.toLowerCase();
    if (lower.endsWith('.mp4') || lower.endsWith('.m4v')) return 'video/mp4';
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.ts')) return 'video/mp2t';
    return 'video/x-matroska';
  }
}

/// A non-2xx answer from the server, with the server's own sentence.
class IfallhubApiException implements Exception {
  const IfallhubApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => message;
}

/// Everything one synthetic `ifallhub://` link carries.
class _Ref {
  const _Ref({
    required this.provider,
    required this.id,
    this.season = 0,
    this.episode = 0,
    this.title = '',
    this.year = '',
    this.filename = '',
    this.quality = '',
    this.sizeBytes = 0,
    this.streamSetId = '',
    this.releaseIndex = -1,
    this.mirrorIndex = 0,
    this.mirrorCount = 1,
  });

  final String provider;
  final String id;
  final int season;
  final int episode;
  final String title;
  final String year;

  // Playback link only.
  final String filename;
  final String quality;
  final int sizeBytes;
  final String streamSetId;
  final int releaseIndex;
  final int mirrorIndex;

  /// How many mirrors the release had when the link was built.
  final int mirrorCount;
}

/// One playable release of a title / episode.
class _Release {
  const _Release({
    required this.filename,
    required this.quality,
    required this.codec,
    required this.language,
    required this.sizeBytes,
    required this.mirrorCount,
  });

  factory _Release.fromJson(Map<dynamic, dynamic> json) {
    final List<dynamic> mirrors =
        json['mirrors'] is List ? json['mirrors'] as List<dynamic> : const <dynamic>[];
    return _Release(
      filename: json['filename']?.toString() ?? '',
      quality: json['quality']?.toString() ?? '',
      codec: json['codec']?.toString() ?? '',
      language: json['language']?.toString() ?? '',
      sizeBytes: (json['size_bytes'] as num?)?.toInt() ?? 0,
      mirrorCount: mirrors.isEmpty ? 1 : mirrors.length,
    );
  }

  final String filename;
  final String quality;
  final String codec;
  final String language;
  final int sizeBytes;
  final int mirrorCount;
}

/// A stream list the server agreed to play from, together with the title it
/// belongs to — the title's own catalogue, or another one that had it.
class _StreamAnswer {
  const _StreamAnswer({required this.ref, required this.set});

  final _Ref ref;
  final _StreamSet set;
}

/// A stream list the server agreed to play from.
class _StreamSet {
  const _StreamSet({required this.id, required this.releases});

  final String id;
  final List<_Release> releases;
}

/// The answer of `POST /api/play`.
class _PlayResult {
  const _PlayResult({required this.url});

  final String url;
}
