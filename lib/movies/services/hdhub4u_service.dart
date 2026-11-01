import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/movie_models.dart';
import '../models/movie_provider.dart';
import 'hdhub4u_html_parser.dart';
import 'movie_http_client.dart';
import 'movie_source.dart';
import 'remote_zip.dart';

/// Client for the HDHub4U catalog (the *premium* Movies & Series source) and
/// for the HubCloud / HubDrive mirror pages its title pages point at.
///
/// The catalog side is plain HTML scraping with a JSON search endpoint. The
/// stream side walks `hdhub4u page → hubcloud / hubdrive → hubcdn / r2 /
/// pixeldrain / gdrive / cf-worker` and returns every direct mirror it finds,
/// so the player and the downloader can walk the list instead of failing on
/// the first dead host.
class Hdhub4uService implements MovieSource {
  Hdhub4uService({
    MovieHttpTransport? transport,
    String? initialBaseUrl,
    List<String>? mirrorCandidates,
  })  : _transport = transport ?? DioMovieHttpTransport(),
        _ownsTransport = transport == null,
        _baseUrl = (initialBaseUrl ?? defaultMirrors.first),
        _mirrorCandidates = List<String>.from(
          mirrorCandidates ?? defaultMirrors,
        );

  /// HDHub4U rotates domains often; these are tried in order and the live one
  /// wins. `urls.json` (the same file the EonMovies client reads) is checked
  /// first because it is kept current upstream.
  static const String defaultBaseUrl = 'https://new10.hdhub4u.cl';

  static const List<String> defaultMirrors = <String>[
    'https://new10.hdhub4u.cl',
    'https://hdhub4u.com.ws',
    'https://new3.hdhub4u.com',
    'https://new9.hdhub4u.cl',
    'https://4khdhub.one',
  ];

  static const String _providerUrlsJson =
      'https://raw.githubusercontent.com/Zenda-Cross/vega-providers/refs/heads/main/urls.json';

  static const String _searchEndpoint =
      'https://search.pingora.fyi/collections/post/documents/search';

  static const Map<String, String> _searchHeaders = <String, String>{
    'Accept': 'application/json, text/plain, */*',
  };

  static const String _siteCookie = 'xla=s4t';

  /// Media extensions the downloader/player can use as-is.
  static final RegExp _mediaExtRe = RegExp(
    r'\.(mkv|mp4|m4v|avi|webm|mov|ts)(\?|$)',
    caseSensitive: false,
  );

  static final RegExp _archiveExtRe = RegExp(
    r'\.(zip|rar|7z)(\?|$)',
    caseSensitive: false,
  );

  final MovieHttpTransport _transport;
  final bool _ownsTransport;
  final List<String> _mirrorCandidates;
  String _baseUrl;
  bool _mirrorChecked = false;
  final Map<String, _ResolvedMirrors> _resolveCache = <String, _ResolvedMirrors>{};
  final Map<String, MovieZipPackListing> _zipListingCache =
      <String, MovieZipPackListing>{};

  @override
  MovieProvider get provider => MovieProvider.hdhub4u;

  @override
  MovieHttpTransport get transport => _transport;

  String get baseUrl => _baseUrl;

  void setBaseUrl(String next) {
    final String cleaned = next.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleaned.isNotEmpty) _baseUrl = cleaned;
  }

  /// Whether this service should be used at all (kept for callers that want to
  /// feature-detect the premium catalog).
  bool get isAvailable => _baseUrl.startsWith('http');

  // ---------------------------------------------------------------- catalog

  @override
  Future<List<MoviePost>> fetchPosts({
    MovieCategory category = MovieCategory.recommended,
    int page = 1,
  }) async {
    final String path = _categoryPath(category);
    final String url = page <= 1
        ? '$_baseUrl$path/'
        : '$_baseUrl$path/page/$page/';
    final MovieHttpResponse res = await _get(url);
    return Hdhub4uHtmlParser.parsePosts(res.body, _baseUrl);
  }

  @override
  Future<List<MoviePost>> searchPosts({
    required String query,
    int page = 1,
  }) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) return fetchPosts(page: page);

    final List<MoviePost> remote = await _searchViaEndpoint(trimmed, page);
    if (remote.isNotEmpty) return remote;

    // Fallback: the site's own search page.
    final String encoded = Uri.encodeQueryComponent(trimmed);
    try {
      final MovieHttpResponse res = await _get('$_baseUrl/?s=$encoded');
      final List<MoviePost> posts =
          Hdhub4uHtmlParser.parsePosts(res.body, _baseUrl);
      if (posts.isNotEmpty) return posts;
    } catch (_) {}

    try {
      final MovieHttpResponse res = await _get('$_baseUrl/search/$encoded/');
      return Hdhub4uHtmlParser.parsePosts(res.body, _baseUrl);
    } catch (_) {
      return const <MoviePost>[];
    }
  }

  Future<List<MoviePost>> _searchViaEndpoint(String query, int page) async {
    try {
      final String today = DateTime.now().toIso8601String().split('T').first;
      final Map<String, String> params = <String, String>{
        'q': query,
        'query_by': 'post_title,category,stars,director,imdb_id',
        'query_by_weights': '4,2,2,2,4',
        'sort_by': 'sort_by_date:desc',
        'limit': '15',
        'highlight_fields': 'none',
        'use_cache': 'true',
        'page': '$page',
        'analytics_tag': today,
      };
      final List<String> pairs = <String>[];
      for (final MapEntry<String, String> entry in params.entries) {
        pairs.add(
          '${Uri.encodeQueryComponent(entry.key)}='
          '${Uri.encodeQueryComponent(entry.value)}',
        );
      }
      final String url = '$_searchEndpoint?${pairs.join('&')}';
      final MovieHttpResponse res = await _transport.get(
        url,
        headers: <String, String>{
          ..._searchHeaders,
          'Cookie': _siteCookie,
          'Referer': '$_baseUrl/',
        },
      );
      if (res.statusCode < 200 || res.statusCode >= 300 || res.body.isEmpty) {
        return const <MoviePost>[];
      }
      return Hdhub4uHtmlParser.parseSearchJson(res.body, _baseUrl);
    } catch (_) {
      return const <MoviePost>[];
    }
  }

  @override
  Future<MovieDetail> fetchDetail(
    String linkOrUrl, {
    int autoExpandLimit = 8,
  }) async {
    final String url = Hdhub4uHtmlParser.resolveUrl(linkOrUrl, _baseUrl);
    final MovieHttpResponse res = await _get(url);
    final String pageUrl =
        res.effectiveUrl.isNotEmpty ? res.effectiveUrl : url;
    return Hdhub4uHtmlParser.parseDetail(
      html: res.body,
      pageUrl: pageUrl,
      baseUrl: _baseUrl,
    );
  }

  /// HDHub4U lists every season and episode on the title page itself, so a
  /// group is already complete by the time the UI receives it.
  @override
  Future<MovieEpisodeGroup> expandEpisodeGroup(MovieEpisodeGroup group) async {
    return group;
  }

  // ---------------------------------------------------------------- streams

  @override
  Future<ResolvedMovieStream> resolveDownloadStream(
    MovieQualityLink quality, {
    required String fallbackTitle,
  }) async {
    final _ResolvedMirrors resolved = await _resolveMirrorsFor(quality.dlUrl);
    final List<MovieStreamCandidate> candidates = resolved.candidates;

    String filename = resolved.filename;
    String sizeLabel =
        quality.sizeLabel.isNotEmpty ? quality.sizeLabel : resolved.sizeLabel;
    String mimeType = quality.isZipPack ? 'application/zip' : 'video/x-matroska';

    if (filename.isEmpty) {
      filename = _buildCleanFilename(
        title: fallbackTitle,
        quality: quality,
        isArchive: quality.isZipPack ||
            candidates.any((MovieStreamCandidate c) => c.isZip),
      );
    }
    final String lowerName = filename.toLowerCase();
    bool isArchive = quality.isZipPack || lowerName.endsWith('.zip');
    if (lowerName.endsWith('.rar') || lowerName.endsWith('.7z')) {
      isArchive = true;
    }
    if (isArchive) {
      mimeType = lowerName.endsWith('.rar')
          ? 'application/x-rar-compressed'
          : 'application/zip';
    } else if (lowerName.endsWith('.mp4') || lowerName.endsWith('.m4v')) {
      mimeType = 'video/mp4';
    } else if (mimeType.contains('zip')) {
      mimeType = 'video/x-matroska';
    }

    final List<MovieStreamCandidate> finalCandidates = candidates
        .map(
          (MovieStreamCandidate c) => MovieStreamCandidate(
            server: c.server,
            url: c.url,
            headers: c.headers,
            isZip: isArchive || c.isZip,
          ),
        )
        .toList();

    return ResolvedMovieStream(
      candidates: finalCandidates,
      filename: filename,
      sizeLabel: sizeLabel,
      mimeType: mimeType,
      sharePageUrl: resolved.sharePageUrl.isNotEmpty
          ? resolved.sharePageUrl
          : quality.dlUrl,
    );
  }

  @override
  Future<ResolvedMovieStream> resolvePlaybackStream(
    MovieQualityLink quality, {
    required String fallbackTitle,
  }) async {
    if (!movieQualityCanStreamOnline(quality)) {
      throw StateError(
        'ZIP / RAR season packs need to be downloaded before playback.',
      );
    }
    final ResolvedMovieStream resolved = await resolveDownloadStream(
      quality,
      fallbackTitle: fallbackTitle,
    );
    final List<MovieStreamCandidate> streamable = streamableMovieCandidates(
      resolved,
    ).where(
      (MovieStreamCandidate c) =>
          !_archiveExtRe.hasMatch(Uri.tryParse(c.url)?.path ?? c.url),
    ).toList();
    if (streamable.isEmpty) {
      throw StateError(
        'No streamable mirror is available for this quality right now.',
      );
    }
    return ResolvedMovieStream(
      candidates: List<MovieStreamCandidate>.unmodifiable(streamable),
      filename: resolved.filename,
      sizeLabel: resolved.sizeLabel,
      mimeType: resolved.mimeType,
      sharePageUrl: resolved.sharePageUrl,
    );
  }

  /// Only season archives reach this path on HDHub4U (episodes are separate
  /// files), and ZIP listing works exactly like on EonMovies.
  @override
  Future<MovieZipPackListing> listZipPackEpisodes(
    MovieQualityLink quality, {
    required String fallbackTitle,
  }) async {
    final MovieZipPackListing? cached = _zipListingCache[quality.id];
    if (cached != null) return cached;

    final ResolvedMovieStream resolved = await resolveDownloadStream(
      quality,
      fallbackTitle: fallbackTitle,
    );
    final String lowerName = resolved.filename.toLowerCase();
    if (!lowerName.endsWith('.zip')) {
      throw StateError(
        'This season pack is not a ZIP archive (${resolved.filename}) — '
        'download it as a single file.',
      );
    }
    if (resolved.candidates.isEmpty) {
      throw StateError('No mirror is reachable for this season pack right now.');
    }

    Object? lastError;
    for (final MovieStreamCandidate candidate in resolved.candidates) {
      try {
        final RemoteZipReader reader =
            RemoteZipReader(_rangeFetchFor(candidate));
        final int total = await reader.probeTotalSize();
        final List<RemoteZipEntry> entries = await reader.readEntries();
        final List<RemoteZipEntry> videos = entries
            .where(
              (RemoteZipEntry e) =>
                  !e.isDirectory && isZipVideoEntryName(e.name),
            )
            .toList();
        if (videos.isEmpty) {
          throw StateError('No episode videos found inside this ZIP.');
        }
        final List<MovieZipEpisode> episodes = <MovieZipEpisode>[];
        for (int i = 0; i < videos.length; i++) {
          final RemoteZipEntry e = videos[i];
          final ({int episode, int season}) numbers =
              seasonEpisodeNumbersFromName(e.name);
          episodes.add(
            MovieZipEpisode(
              index: i,
              entryName: e.name,
              compressedSize: e.compressedSize,
              uncompressedSize: e.uncompressedSize,
              compressionMethod: e.compressionMethod,
              localHeaderOffset: e.localHeaderOffset,
              seasonNumber: numbers.season,
              episodeNumber: numbers.episode,
              isEncrypted: e.isEncrypted,
            ),
          );
        }
        episodes.sort((MovieZipEpisode a, MovieZipEpisode b) {
          if (a.seasonNumber != b.seasonNumber) {
            return a.seasonNumber.compareTo(b.seasonNumber);
          }
          if (a.episodeNumber != b.episodeNumber) {
            return a.episodeNumber.compareTo(b.episodeNumber);
          }
          return a.localHeaderOffset.compareTo(b.localHeaderOffset);
        });
        final List<MovieZipEpisode> indexed = <MovieZipEpisode>[
          for (int i = 0; i < episodes.length; i++)
            MovieZipEpisode(
              index: i,
              entryName: episodes[i].entryName,
              compressedSize: episodes[i].compressedSize,
              uncompressedSize: episodes[i].uncompressedSize,
              compressionMethod: episodes[i].compressionMethod,
              localHeaderOffset: episodes[i].localHeaderOffset,
              seasonNumber: episodes[i].seasonNumber,
              episodeNumber: episodes[i].episodeNumber,
              isEncrypted: episodes[i].isEncrypted,
            ),
        ];
        final MovieZipPackListing listing = MovieZipPackListing(
          zipFileName: resolved.filename,
          totalBytes: total,
          candidate: candidate,
          episodes: indexed,
        );
        _zipListingCache[quality.id] = listing;
        return listing;
      } catch (err) {
        lastError = err;
      }
    }

    throw StateError(
      'Could not list episodes inside this ZIP'
      '${lastError != null ? ' (${lastError.toString().replaceFirst('Bad state: ', '')})' : ''} '
      '— try downloading the whole season pack instead.',
    );
  }

  @override
  Future<({MovieStreamCandidate candidate, MovieZipEpisode episode})>
      prepareZipEpisodeDownload(
    MovieQualityLink packQuality, {
    required String fallbackTitle,
  }) async {
    final String packId = packQuality.id.split('__zep').first;
    final MovieQualityLink pack = packQuality.copyWith(
      id: packId,
      isZipPack: true,
      zipEntryName: '',
    );
    final MovieZipPackListing listing = await listZipPackEpisodes(
      pack,
      fallbackTitle: fallbackTitle,
    );

    MovieZipEpisode? match;
    for (final MovieZipEpisode episode in listing.episodes) {
      if (episode.entryName == packQuality.zipEntryName) {
        match = episode;
        break;
      }
    }
    if (match == null) {
      throw StateError(
        'Episode "${packQuality.zipEntryName}" not found inside the ZIP.',
      );
    }
    if (!match.isSupported) {
      throw StateError(
        match.isEncrypted
            ? 'This episode is encrypted inside the ZIP — download the full pack.'
            : 'Episode compression (method ${match.compressionMethod}) is not '
                'supported — download the full pack.',
      );
    }

    final RemoteZipReader reader =
        RemoteZipReader(_rangeFetchFor(listing.candidate));
    final int dataOffset = await reader.dataOffsetFor(
      RemoteZipEntry(
        name: match.entryName,
        compressionMethod: match.compressionMethod,
        compressedSize: match.compressedSize,
        uncompressedSize: match.uncompressedSize,
        localHeaderOffset: match.localHeaderOffset,
        isDirectory: false,
        isEncrypted: match.isEncrypted,
      ),
    );
    return (
      candidate: listing.candidate,
      episode: match.copyWith(dataOffset: dataOffset),
    );
  }

  static MovieQualityLink qualityForZipEpisode(
    MovieQualityLink pack,
    MovieZipEpisode episode,
  ) {
    return pack.copyWith(
      id: '${pack.id}__zep${episode.index}',
      isZipPack: false,
      sizeLabel: episode.sizeLabel,
      seasonLabel: episode.seasonLabel.isNotEmpty
          ? episode.seasonLabel
          : pack.seasonLabel,
      episodeLabel: episode.episodeLabel.isNotEmpty
          ? episode.episodeLabel
          : episode.fileName,
      zipEntryName: episode.entryName,
    );
  }

  ZipRangeFetch _rangeFetchFor(MovieStreamCandidate candidate) {
    return (int start, int? end) async {
      final MovieRangeResponse res = await _transport.getRange(
        candidate.url,
        headers: candidate.headers,
        start: start,
        end: end,
      );
      return ZipRangeResult(
        statusCode: res.statusCode,
        bytes: res.bytes,
        totalSize: res.totalSize,
      );
    };
  }

  // ------------------------------------------------------------ mirror walk

  Future<_ResolvedMirrors> _resolveMirrorsFor(String rawUrl) async {
    final String key = rawUrl.trim();
    final _ResolvedMirrors? cached = _resolveCache[key];
    if (cached != null && cached.candidates.isNotEmpty) return cached;
    _ResolvedMirrors resolved;
    try {
      // A single unreachable mirror host must never hang a whole download or
      // a player start: the chain gives up and reports "no mirror".
      resolved = await _resolveMirrors(key, depth: 0)
          .timeout(const Duration(seconds: 45));
    } on TimeoutException {
      resolved = _ResolvedMirrors(sharePageUrl: key);
    }
    if (resolved.candidates.isNotEmpty) _resolveCache[key] = resolved;
    return resolved;
  }

  Future<_ResolvedMirrors> _resolveMirrors(
    String rawUrl, {
    required int depth,
  }) async {
    final _ResolvedMirrors result = _ResolvedMirrors(sharePageUrl: rawUrl);
    final String url = rawUrl.trim();
    if (url.isEmpty || depth > 2) return result;

    final String lower = url.toLowerCase();
    if (_isDirectMedia(url)) {
      result.add('Direct CDN', url, headers: _refererHeaders(url));
      return result;
    }

    if (lower.contains('hubcloud') || lower.contains('/drive/')) {
      final bool ok = await _resolveHubcloud(url, result);
      if (ok && result.candidates.isNotEmpty) return result;
    }

    if (lower.contains('hubdrive')) {
      final String? target = await _hubdriveTarget(url);
      if (target != null && target.isNotEmpty) {
        if (target.toLowerCase().contains('hubcloud') ||
            target.toLowerCase().contains('/drive/')) {
          await _resolveHubcloud(target, result);
        } else if (_isDirectMedia(target)) {
          result.add('HubDrive Direct', target);
        } else {
          final _ResolvedMirrors nested =
              await _resolveMirrors(target, depth: depth + 1);
          result.merge(nested);
        }
        if (result.candidates.isNotEmpty) return result;
      }
    }

    final List<String> hubs = await _expandHubLinks(url);
    for (final String hub in hubs) {
      if (hub == url) {
        if (_isDirectMedia(hub)) result.add('Source', hub);
        continue;
      }
      final _ResolvedMirrors nested =
          await _resolveMirrors(hub, depth: depth + 1);
      result.merge(nested);
      if (result.candidates.length >= 8) break;
    }

    if (result.candidates.isEmpty && _isDirectMedia(url)) {
      result.add('Source', url);
    }
    return result;
  }

  /// The page is one of HDHub4U's own pages (or a gdflix / filepress style
  /// wrapper): follow its `meta refresh` / `var reurl` / obfuscated hop and
  /// return the hub links it finally exposes.
  Future<List<String>> _expandHubLinks(String url) async {
    final List<String> found = <String>[];
    final Set<String> seen = <String>{};
    String current = url;

    for (int hop = 0; hop < 3; hop++) {
      MovieHttpResponse res;
      try {
        res = await _get(current);
      } catch (_) {
        break;
      }
      final String body = res.body;
      final List<String> anchors = _extractHubAnchors(body, current);
      for (final String anchor in anchors) {
        if (anchor == url) continue;
        if (seen.add(anchor)) found.add(anchor);
      }
      if (found.isNotEmpty) break;

      String? next = _metaRefreshTarget(body, current);
      next ??= _reurlTarget(body, current);
      next ??= _sioTarget(body, current);
      if (next == null || next.isEmpty || next == current) break;
      current = next;
    }

    return found;
  }

  List<String> _extractHubAnchors(String html, String pageUrl) {
    final List<String> links = <String>[];
    final Set<String> seen = <String>{};
    final Document doc = html_parser.parse(html);
    for (final Element anchor in doc.querySelectorAll('a[href]')) {
      final String href = anchor.attributes['href']?.trim() ?? '';
      if (href.isEmpty) continue;
      final String url = Hdhub4uHtmlParser.resolveUrl(href, pageUrl);
      if (url.isEmpty || url == pageUrl) continue;
      final String lower = url.toLowerCase();
      final bool hub = lower.contains('hubcloud') ||
          lower.contains('hubdrive') ||
          lower.contains('gdflix') ||
          lower.contains('gdtot') ||
          lower.contains('filepress') ||
          lower.contains('hubcdn') ||
          lower.contains('r2.dev') ||
          lower.contains('pixeldrain') ||
          lower.contains('workers.dev') ||
          lower.contains('cloudflarestorage') ||
          lower.contains('googleusercontent') ||
          lower.contains('drive.google') ||
          lower.contains('/drive/');
      if (!hub) continue;
      if (seen.add(url)) links.add(url);
    }
    return links;
  }

  /// HubCloud page → its vcloud page → the button list of real mirrors.
  Future<bool> _resolveHubcloud(
    String link,
    _ResolvedMirrors result,
  ) async {
    final String origin = _originOf(link);
    final Map<String, String> headers = <String, String>{
      'Referer': '$origin/',
    };
    String pageBody;
    try {
      final MovieHttpResponse page = await _get(link, headers: headers);
      pageBody = page.body;
      result.sharePageUrl = result.sharePageUrl.isEmpty
          ? link
          : result.sharePageUrl;
      result.absorbFilename(_filenameFromBody(pageBody));
      result.absorbSize(_sizeFromBody(pageBody));
    } catch (_) {
      return false;
    }

    String vcloud = _vcloudTarget(pageBody, origin) ?? '';
    String vcloudBody = '';
    if (vcloud.isNotEmpty && vcloud != link) {
      try {
        final MovieHttpResponse res = await _get(
          vcloud,
          headers: <String, String>{'Referer': link},
        );
        vcloudBody = res.body;
        result.absorbFilename(_filenameFromBody(vcloudBody));
        result.absorbSize(_sizeFromBody(vcloudBody));
      } catch (_) {}
    }

    final String combined = '$pageBody $vcloudBody';
    final String? pxl = _pxlTarget(combined);
    if (pxl != null && pxl.isNotEmpty) {
      result.add('Pixeldrain High-Speed', pxl);
    }

    for (final String href in _extractButtons(combined, vcloud.isNotEmpty ? vcloud : link)) {
      await _classifyHref(href, result);
      if (result.candidates.length >= 8) break;
    }
    return result.candidates.isNotEmpty;
  }

  List<String> _extractButtons(String html, String pageUrl) {
    final Document doc = html_parser.parse(html);
    final List<String> hrefs = <String>[];
    final Set<String> seen = <String>{};

    void consider(Element anchor) {
      final String href = anchor.attributes['href']?.trim() ?? '';
      if (href.isEmpty || href.startsWith('#')) return;
      final String url = Hdhub4uHtmlParser.resolveUrl(href, pageUrl);
      if (url.isEmpty) return;
      if (seen.add(url)) hrefs.add(url);
    }

    for (final Element anchor in doc.querySelectorAll(
      '.btn-success.btn-lg.h6, .btn-danger, .btn-secondary, '
      '.btn-success, .btn-primary, .btn.btn-user, a[href]',
    )) {
      final String href = anchor.attributes['href'] ?? '';
      final String lower = href.toLowerCase();
      final bool interesting = lower.contains('pixeld')
          || lower.contains('r2.dev')
          || lower.contains('workers.dev')
          || lower.contains('.dev')
          || lower.contains('hubcloud')
          || lower.contains('?id=')
          || lower.contains('cloudflarestorage')
          || lower.contains('fastdl')
          || lower.contains('fsl.')
          || lower.contains('hubcdn')
          || lower.contains('gofile')
          || lower.contains('googleusercontent')
          || lower.contains('drive.google')
          || _mediaExtRe.hasMatch(lower)
          || lower.contains('token=');
      if (!interesting) continue;
      consider(anchor);
    }
    return hrefs;
  }

  Future<void> _classifyHref(String href, _ResolvedMirrors result) async {
    final String lower = href.toLowerCase();
    if (lower.contains('pixeld')) {
      result.add('Pixeldrain High-Speed', _pixeldrainApi(href));
      return;
    }
    if (lower.contains('hubdrive')) {
      final String? target = await _hubdriveTarget(href);
      if (target != null && target.isNotEmpty) {
        await _classifyHref(target, result);
      }
      return;
    }
    if (lower.contains('gofile.io')) {
      result.add('Gofile', href, headers: <String, String>{
        'Referer': 'https://gofile.io/',
      });
      return;
    }
    if (lower.contains('hubcloud') || lower.contains('/?id=') || lower.contains('?id=')) {
      final String direct = await _followToDirect(href);
      if (direct.isNotEmpty && direct != href) {
        result.add('GDrive Direct', direct);
      }
      return;
    }
    if (lower.contains('cloudflarestorage')) {
      result.add('Cloudflare Storage', href);
      return;
    }
    if (lower.contains('fastdl') || lower.contains('fsl.')) {
      result.add('FastDL', href);
      return;
    }
    if (lower.contains('hubcdn')) {
      result.add('HubCDN', href);
      return;
    }
    if (lower.contains('.dev') || _mediaExtRe.hasMatch(lower) || lower.contains('token=')) {
      result.add('CF Worker', href);
      return;
    }
    if (lower.contains('googleusercontent') || lower.contains('drive.google')) {
      result.add('GDrive Direct', href);
    }
  }

  String _pixeldrainApi(String href) {
    final String lower = href.toLowerCase();
    if (!lower.contains('/api/')) {
      final Uri? uri = Uri.tryParse(href);
      if (uri != null) {
        final List<String> segments = uri.pathSegments
            .where((String s) => s.isNotEmpty)
            .toList();
        final String token = segments.isEmpty ? '' : segments.last;
        if (token.isNotEmpty) {
          return '${uri.scheme}://${uri.host}/api/file/$token?download';
        }
      }
    }
    return href;
  }

  String? _vcloudTarget(String html, String origin) {
    final RegExpMatch? doubleAtob = RegExp(
      r'''(?:var|let|const)\s+\w+\s*=\s*atob\(atob\(["\']([^"\']+)["\']\)\)''',
    ).firstMatch(html);
    if (doubleAtob != null) {
      final String? first = _b64(doubleAtob.group(1) ?? '');
      final String? second = first == null ? null : _b64(first);
      if (second != null && second.startsWith('http')) return second;
    }

    final RegExpMatch? plain =
        RegExp(r'''var\s+url\s*=\s*['"]([^'"]+)['"]''').firstMatch(html);
    if (plain != null) {
      final String raw = plain.group(1) ?? '';
      final int rIndex = raw.indexOf('r=');
      if (rIndex >= 0) {
        final String? decoded = _b64(raw.substring(rIndex + 2));
        if (decoded != null && decoded.startsWith('http')) return decoded;
      }
      if (raw.startsWith('http')) return raw;
      if (raw.startsWith('/')) return '$origin$raw';
    }

    final Document doc = html_parser.parse(html);
    final Element? icon = doc.querySelector('.fa-file-download.fa-lg');
    final String href = icon?.parent?.attributes['href']?.trim() ?? '';
    if (href.isNotEmpty) {
      final String url = Hdhub4uHtmlParser.resolveUrl(href, origin);
      if (url.isNotEmpty) return url;
    }
    return null;
  }

  String? _pxlTarget(String html) {
    final RegExpMatch? match =
        RegExp(r'''var\s+pxl\s*=\s*['"]([^'"]+)['"]''', caseSensitive: false)
            .firstMatch(html);
    final String raw = match?.group(1)?.trim() ?? '';
    if (raw.isEmpty) return null;
    return _pixeldrainApi(raw);
  }

  Future<String?> _hubdriveTarget(String link) async {
    try {
      final MovieHttpResponse res = await _get(
        link,
        headers: <String, String>{'Referer': '${_originOf(link)}/'},
      );
      final Document doc = html_parser.parse(res.body);
      for (final String selector in <String>[
        '.btn.btn-primary.btn-user.btn-success1.m-1',
        '.btn.btn-primary.btn-user.btn-success1',
        'a[href*="hubcloud"]',
        'a[href*="r2.dev"]',
        'a[href*="workers.dev"]',
      ]) {
        final Element? anchor = doc.querySelector(selector);
        final String href = anchor?.attributes['href']?.trim() ?? '';
        if (href.isEmpty) continue;
        final String url = Hdhub4uHtmlParser.resolveUrl(href, link);
        if (url.isNotEmpty) return url;
      }
      return _metaRefreshTarget(res.body, link);
    } catch (_) {
      return null;
    }
  }

  /// Follows a hubcloud `?id=` / drive hop until it lands on something a
  /// player can open (a `googleusercontent` file or a direct media URL).
  Future<String> _followToDirect(String link) async {
    String current = link;
    for (int hop = 0; hop < 4; hop++) {
      String? location;
      String body = '';
      try {
        final MovieHttpResponse res = await _transport.get(
          current,
          headers: <String, String>{'Referer': '${_originOf(current)}/'},
          followRedirects: false,
        );
        location = res.header('location');
        body = res.body;
      } catch (_) {
        return current;
      }
      final String rawLocation = location?.trim() ?? '';
      if (rawLocation.isNotEmpty) {
        String next = Hdhub4uHtmlParser.resolveUrl(rawLocation, current);
        if (next.contains('?link=')) {
          next = Uri.decodeComponent(next.split('?link=').last);
        }
        current = next;
        if (current.contains('googleusercontent') || _isDirectMedia(current)) {
          return current;
        }
        continue;
      }
      final String? refresh = _metaRefreshTarget(body, current);
      if (refresh != null && refresh != current) {
        current = refresh;
        continue;
      }
      final RegExpMatch? jsRedirect =
          RegExp(r'''location\.href\s*=\s*['"]([^'"]+)['"]''').firstMatch(body);
      if (jsRedirect != null) {
        current = Hdhub4uHtmlParser.resolveUrl(jsRedirect.group(1) ?? '', current);
        continue;
      }
      return current;
    }
    return current;
  }

  // ------------------------------------------------------------- utilities

  String _categoryPath(MovieCategory category) {
    switch (category) {
      case MovieCategory.recommended:
        return '';
      case MovieCategory.bollywood:
        return '/category/bollywood-movies';
      case MovieCategory.hollywood:
        return '/category/hollywood-movies';
      case MovieCategory.southIndian:
        return '/category/south-hindi-movies';
      case MovieCategory.webSeries:
        return '/category/web-series';
      case MovieCategory.anime:
        return '/category/anime';
    }
  }

  Future<MovieHttpResponse> _get(
    String url, {
    Map<String, String> headers = const <String, String>{},
  }) async {
    final Map<String, String> merged = <String, String>{
      'Referer': '$_baseUrl/',
      if (url.contains('hubcloud') || url.contains('hubdrive'))
        'Cookie': _siteCookie,
      ...headers,
    };
    try {
      final MovieHttpResponse res =
          await _transport.get(url, headers: merged);
      if (res.statusCode >= 200 && res.statusCode < 400) return res;
      if (res.statusCode == 404 && !_mirrorChecked) {
        await _refreshMirror();
        return await _transport.get(_rewriteToMirror(url), headers: merged);
      }
      return res;
    } catch (_) {
      if (!_mirrorChecked) {
        await _refreshMirror();
        return await _transport.get(_rewriteToMirror(url), headers: merged);
      }
      rethrow;
    }
  }

  String _rewriteToMirror(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return url;
    final Uri base = Uri.parse(_baseUrl);
    if (uri.host == base.host) return url;
    return '$_baseUrl${uri.path}${uri.hasQuery ? '?${uri.query}' : ''}';
  }

  Future<void> _refreshMirror() async {
    if (_mirrorChecked) return;
    _mirrorChecked = true;

    try {
      final MovieHttpResponse res = await _transport.get(_providerUrlsJson);
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final Object? decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          final Object? entry = decoded['hdhub'];
          if (entry is Map && entry['url'] is String) {
            final String candidate =
                (entry['url'] as String).trim().replaceAll(RegExp(r'/+$'), '');
            if (candidate.startsWith('http')) {
              setBaseUrl(candidate);
              return;
            }
          }
        }
      }
    } catch (_) {}

    for (final String mirror in _mirrorCandidates) {
      final String candidate = mirror.trim().replaceAll(RegExp(r'/+$'), '');
      if (candidate.isEmpty || candidate == _baseUrl) continue;
      try {
        final MovieHttpResponse res = await _transport.get('$candidate/');
        if (res.statusCode >= 200 && res.statusCode < 400 && res.body.isNotEmpty) {
          setBaseUrl(candidate);
          return;
        }
      } catch (_) {}
    }
  }

  Map<String, String> _refererHeaders(String url) {
    final String lower = url.toLowerCase();
    if (lower.contains('hubcloud') ||
        lower.contains('hubdrive') ||
        lower.contains('hubcdn')) {
      return <String, String>{'Referer': '${_originOf(url)}/'};
    }
    return const <String, String>{};
  }

  static String _originOf(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return '';
    return '${uri.scheme}://${uri.host}';
  }

  static bool _isDirectMedia(String url) {
    final Uri? uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return false;
    if (_mediaExtRe.hasMatch(uri.path)) return true;
    if (_archiveExtRe.hasMatch(uri.path)) return true;
    return false;
  }

  static String _filenameFromBody(String body) {
    if (body.isEmpty) return '';
    final RegExpMatch? match = RegExp(
      r'''([A-Za-z0-9][A-Za-z0-9._()\[\]\- ]{2,120}\.(?:mkv|mp4|m4v|avi|webm|mov|zip|rar))''',
      caseSensitive: false,
    ).firstMatch(body);
    if (match == null) return '';
    final String raw = match.group(1)?.trim() ?? '';
    if (raw.isEmpty) return '';
    return raw.replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _sizeFromBody(String body) {
    if (body.isEmpty) return '';
    final RegExpMatch? match = RegExp(
      r'(\d+(?:\.\d+)?)\s*(GB|MB|GIB|MIB)\b',
      caseSensitive: false,
    ).firstMatch(body);
    if (match == null) return '';
    return '${match.group(1)} ${match.group(2)!.toUpperCase()}';
  }

  static String? _metaRefreshTarget(String html, String pageUrl) {
    final RegExpMatch? match = RegExp(
      r'''http-equiv=["']?refresh["']?[^>]*content=["'][^"']*url=([^"'>]+)''',
      caseSensitive: false,
    ).firstMatch(html);
    final String raw = match?.group(1)?.trim() ?? '';
    if (raw.isEmpty) return null;
    final String url = Hdhub4uHtmlParser.resolveUrl(raw, pageUrl);
    return url.isEmpty ? null : url;
  }

  static String? _reurlTarget(String body, String pageUrl) {
    final RegExpMatch? match = RegExp(
      r'''var\s+reurl\s*=\s*["']([^"']+)["']''',
      caseSensitive: false,
    ).firstMatch(body);
    final String raw = match?.group(1)?.trim() ?? '';
    if (raw.isEmpty) return null;
    final String url = Hdhub4uHtmlParser.resolveUrl(raw, pageUrl);
    return url.isEmpty ? null : url;
  }

  /// The `s('o','<base64 x3 + rot13>')` hop some of these pages use.
  static String? _sioTarget(String body, String pageUrl) {
    final int start = body.indexOf("s('o','");
    if (start < 0) return null;
    final int end = body.indexOf("',180", start);
    if (end <= start) return null;
    final String encrypted = body.substring(start + "s('o','".length, end);
    final Map<String, dynamic>? decoded = _decodeObfuscated(encrypted);
    final Object? target = decoded?['o'];
    if (target is! String) return null;
    final String? url = _b64(target);
    if (url == null || !url.startsWith('http')) return null;
    return url;
  }

  static Map<String, dynamic>? _decodeObfuscated(String encrypted) {
    try {
      final String? first = _b64(encrypted);
      if (first == null) return null;
      final String? second = _b64(first);
      if (second == null) return null;
      final String rotated = _rot13(second);
      final String? third = _b64(rotated);
      if (third == null) return null;
      final Object? json = jsonDecode(third);
      if (json is Map<String, dynamic>) return json;
      return null;
    } catch (_) {
      return null;
    }
  }

  static String? _b64(String value) {
    try {
      return utf8.decode(base64.decode(base64.normalize(value.trim())));
    } catch (_) {
      return null;
    }
  }

  static String _rot13(String input) {
    final StringBuffer out = StringBuffer();
    for (final int code in input.codeUnits) {
      if (code >= 65 && code <= 90) {
        out.writeCharCode(((code - 65 + 13) % 26) + 65);
      } else if (code >= 97 && code <= 122) {
        out.writeCharCode(((code - 97 + 13) % 26) + 97);
      } else {
        out.writeCharCode(code);
      }
    }
    return out.toString();
  }

  static String _buildCleanFilename({
    required String title,
    required MovieQualityLink quality,
    required bool isArchive,
  }) {
    final List<String> parts = <String>[
      title,
      if (quality.seasonLabel.isNotEmpty) quality.seasonLabel,
      if (quality.episodeLabel.isNotEmpty &&
          !quality.episodeLabel.contains('ZIP'))
        quality.episodeLabel,
      quality.displayQuality,
      if (quality.languages.isNotEmpty) quality.languages,
    ];
    final String safe = parts
        .join(' - ')
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final String ext = isArchive ? 'zip' : 'mkv';
    return '$safe.$ext';
  }

  @override
  void dispose() {
    _resolveCache.clear();
    _zipListingCache.clear();
    if (_ownsTransport) _transport.close();
  }
}

/// Mirrors collected while walking one quality link.
class _ResolvedMirrors {
  _ResolvedMirrors({this.sharePageUrl = ''});

  String sharePageUrl;
  String filename = '';
  String sizeLabel = '';
  final List<MovieStreamCandidate> candidates = <MovieStreamCandidate>[];
  final Set<String> _seen = <String>{};

  /// Which server to try first, separately for playback and download. The
  /// player wants something that streams and seeks; a download wants
  /// something that resumes.
  static const List<String> _order = <String>[
    'Cloudflare Storage',
    'CF Worker',
    'Direct CDN',
    'GDrive Direct',
    'HubCDN',
    'Pixeldrain High-Speed',
    'FastDL',
    'Gofile',
    'Direct Link',
  ];

  void add(
    String server,
    String url, {
    Map<String, String> headers = const <String, String>{},
  }) {
    final String trimmed = url.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('http')) return;
    if (!_seen.add(trimmed)) return;
    candidates.add(
      MovieStreamCandidate(
        server: server,
        url: trimmed,
        headers: headers,
        isZip: RegExp(r'\.(zip|rar|7z)(\?|$)', caseSensitive: false)
            .hasMatch(trimmed),
      ),
    );
    candidates.sort((MovieStreamCandidate a, MovieStreamCandidate b) {
      final int ia = _order.indexOf(a.server);
      final int ib = _order.indexOf(b.server);
      return (ia < 0 ? _order.length : ia).compareTo(ib < 0 ? _order.length : ib);
    });
  }

  void merge(_ResolvedMirrors other) {
    if (filename.isEmpty) filename = other.filename;
    if (sizeLabel.isEmpty) sizeLabel = other.sizeLabel;
    if (sharePageUrl.isEmpty) sharePageUrl = other.sharePageUrl;
    for (final MovieStreamCandidate candidate in other.candidates) {
      add(candidate.server, candidate.url, headers: candidate.headers);
    }
  }

  void absorbFilename(String value) {
    if (filename.isEmpty && value.isNotEmpty) filename = value;
  }

  void absorbSize(String value) {
    if (sizeLabel.isEmpty && value.isNotEmpty) sizeLabel = value;
  }
}
