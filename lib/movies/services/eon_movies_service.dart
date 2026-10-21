import 'dart:convert';

import '../models/movie_models.dart';
import 'eon_html_parser.dart';
import 'movie_http_client.dart';

/// Full client for EonMovies catalog/search/details + Dotflix multi-mirror
/// direct download URL extraction.
class EonMoviesService {
  EonMoviesService({
    MovieHttpTransport? transport,
    String initialBaseUrl = defaultBaseUrl,
  })  : _transport = transport ?? DioMovieHttpTransport(),
        _ownsTransport = transport == null,
        _baseUrl = initialBaseUrl;

  static const String defaultBaseUrl = 'https://new4.eonmovies.click';
  static const String _gatewayUrl = 'https://eonmovies.com';
  static const String _providerUrlsJson =
      'https://raw.githubusercontent.com/Zenda-Cross/vega-providers/refs/heads/main/urls.json';
  static const String _dotflixWorkerUrl =
      'https://dotflix.pobmovie0301.workers.dev/api/generate-link';

  final MovieHttpTransport _transport;
  final bool _ownsTransport;
  String _baseUrl;
  bool _mirrorChecked = false;

  String _cachedProxyAction = '40be6d9fdcc81dd69cf943cccce3e8fcf190219950';
  String _cachedDriveAction = '40e5348909ff78510ee46337a237c1352fcc630ad2';
  final Map<String, MovieEpisodeGroup> _subPageCache =
      <String, MovieEpisodeGroup>{};

  MovieHttpTransport get transport => _transport;
  String get baseUrl => _baseUrl;

  void setBaseUrl(String next) {
    final String cleaned = next.trim().replaceAll(RegExp(r'/+$'), '');
    if (cleaned.isNotEmpty) {
      _baseUrl = cleaned;
    }
  }

  /// Refreshes active mirror from upstream config if the default mirror rotates.
  Future<String> _refreshMirrorUrl() async {
    try {
      final MovieHttpResponse res = await _transport.get(_providerUrlsJson);
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final Object? decoded = jsonDecode(res.body);
        if (decoded is Map<String, dynamic>) {
          final Object? entry = decoded['eonMovies'];
          if (entry is Map && entry['url'] is String) {
            final String candidate =
                (entry['url'] as String).trim().replaceAll(RegExp(r'/+$'), '');
            if (candidate.startsWith('http')) {
              _baseUrl = candidate;
              return _baseUrl;
            }
          }
        }
      }
    } catch (_) {}

    try {
      final MovieHttpResponse gw =
          await _transport.get(_gatewayUrl, followRedirects: false);
      final String? loc = gw.header('location');
      if (loc != null && loc.startsWith('http')) {
        final Uri u = Uri.parse(loc);
        _baseUrl = '${u.scheme}://${u.host}';
      }
    } catch (_) {}

    return _baseUrl;
  }

  Future<MovieHttpResponse> _getFromCatalog(String pathAndQuery) async {
    try {
      final MovieHttpResponse res =
          await _transport.get('$_baseUrl$pathAndQuery');
      if (res.statusCode >= 200 &&
          res.statusCode < 400 &&
          res.body.isNotEmpty) {
        return res;
      }
    } catch (_) {
      if (_mirrorChecked) rethrow;
    }

    if (!_mirrorChecked) {
      _mirrorChecked = true;
      await _refreshMirrorUrl();
      return _transport.get('$_baseUrl$pathAndQuery');
    }

    return _transport.get('$_baseUrl$pathAndQuery');
  }

  /// Loads recommended / filtered category catalog page (`36` titles per page).
  Future<List<MoviePost>> fetchPosts({
    MovieCategory category = MovieCategory.recommended,
    int page = 1,
  }) async {
    final String encodedCat = Uri.encodeQueryComponent(category.slug);
    final MovieHttpResponse res = await _getFromCatalog(
      '/?action=&page=$page&name=&category=$encodedCat',
    );
    return EonHtmlParser.parsePostList(res.body, _baseUrl);
  }

  /// Live server-side title search (`GET /?action=search&page=<n>&name=<q>`).
  Future<List<MoviePost>> searchPosts({
    required String query,
    int page = 1,
  }) async {
    final String trimmed = query.trim();
    if (trimmed.isEmpty) {
      return fetchPosts(page: page);
    }
    final String encodedQuery = Uri.encodeQueryComponent(trimmed);
    final MovieHttpResponse res = await _getFromCatalog(
      '/?action=search&page=$page&name=$encodedQuery',
    );
    return EonHtmlParser.parsePostList(res.body, _baseUrl);
  }

  /// Fetches movie/series metadata and automatically expands up to
  /// [autoExpandLimit] season/episode sub-pages concurrently so quality-wise
  /// download options are immediately ready to tap.
  Future<MovieDetail> fetchDetail(
    String linkOrUrl, {
    int autoExpandLimit = 8,
  }) async {
    final String fullUrl = EonHtmlParser.resolveUrl(linkOrUrl, _baseUrl);
    final Uri uri = Uri.parse(fullUrl);
    final String pathPart =
        uri.hasQuery ? '${uri.path}?${uri.query}' : uri.path;

    final MovieHttpResponse res = await _getFromCatalog(pathPart);
    final MovieDetail parsed = EonHtmlParser.parseDetail(
      res.body,
      pageUrl: '$_baseUrl${uri.path}',
      baseUrl: _baseUrl,
    );

    if (parsed.episodeGroups.isEmpty || autoExpandLimit <= 0) {
      return parsed;
    }

    final List<MovieEpisodeGroup> updatedGroups =
        List<MovieEpisodeGroup>.from(parsed.episodeGroups);

    final List<Future<void>> tasks = <Future<void>>[];
    int expandedCount = 0;
    for (int i = 0; i < updatedGroups.length; i++) {
      final MovieEpisodeGroup g = updatedGroups[i];
      if (g.isLoaded || g.subPageDlUrl.isEmpty) continue;
      if (expandedCount >= autoExpandLimit) break;
      expandedCount++;
      final int idx = i;
      tasks.add(() async {
        try {
          updatedGroups[idx] = await expandEpisodeGroup(g);
        } catch (_) {}
      }());
    }

    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
    }

    return MovieDetail(
      title: parsed.title,
      cleanTitle: parsed.cleanTitle,
      type: parsed.type,
      webUrl: parsed.webUrl,
      year: parsed.year,
      releaseDate: parsed.releaseDate,
      backdropUrl: parsed.backdropUrl,
      fallbackBackdropUrl: parsed.fallbackBackdropUrl,
      posterUrl: parsed.posterUrl,
      fallbackPosterUrl: parsed.fallbackPosterUrl,
      languages: parsed.languages,
      languageList: parsed.languageList,
      genres: parsed.genres,
      director: parsed.director,
      qualityBadges: parsed.qualityBadges,
      synopsis: parsed.synopsis,
      defaultSeasonLabel: parsed.defaultSeasonLabel,
      directQualities: parsed.directQualities,
      episodeGroups: updatedGroups,
      relatedPosts: parsed.relatedPosts,
    );
  }

  /// Resolves a season/episode sub-page (`/dl/<id>` -> `/page/<id>`) into its
  /// quality-wise download options (and any nested episode groups).
  Future<MovieEpisodeGroup> expandEpisodeGroup(MovieEpisodeGroup group) async {
    if (group.isLoaded || group.subPageDlUrl.isEmpty) return group;
    final MovieEpisodeGroup? cached = _subPageCache[group.subPageDlUrl];
    if (cached != null) return cached;

    final ({String body, String url}) page = await _followRedirectChain(
      group.subPageDlUrl,
      headers: <String, String>{'Referer': '$_baseUrl/'},
    );

    MovieEpisodeGroup expanded = EonHtmlParser.parseSubPage(
      page.body,
      parentGroup: group,
      baseUrl: _baseUrl,
    );

    // If a multi-season show has Season -> Episode nested groups, expand up to 6.
    if (expanded.qualities.isEmpty && expanded.nestedGroups.isNotEmpty) {
      final List<MovieEpisodeGroup> nestedUpdated =
          List<MovieEpisodeGroup>.from(expanded.nestedGroups);
      final List<Future<void>> nestedTasks = <Future<void>>[];
      for (int i = 0; i < nestedUpdated.length && i < 6; i++) {
        final int idx = i;
        nestedTasks.add(() async {
          try {
            nestedUpdated[idx] = await expandEpisodeGroup(nestedUpdated[idx]);
          } catch (_) {}
        }());
      }
      if (nestedTasks.isNotEmpty) {
        await Future.wait(nestedTasks);
      }
      expanded = expanded.copyWith(nestedGroups: nestedUpdated);
    }

    _subPageCache[group.subPageDlUrl] = expanded;
    return expanded;
  }

  Future<({String body, String url})> _followRedirectChain(
    String startUrl, {
    Map<String, String> headers = const <String, String>{},
    int maxHops = 6,
  }) async {
    String current = startUrl;
    for (int hop = 0; hop < maxHops; hop++) {
      final MovieHttpResponse res = await _transport.get(
        current,
        headers: headers,
        followRedirects: false,
      );
      final String? loc = res.header('location');
      if (loc != null && loc.trim().isNotEmpty) {
        current = Uri.parse(current).resolve(loc.trim()).toString();
        continue;
      }
      return (
        body: res.body,
        url: res.effectiveUrl.isNotEmpty ? res.effectiveUrl : current,
      );
    }
    throw StateError('Redirect chain exceeded $maxHops hops for $startUrl');
  }

  /// Resolves an EonMovies `/dl/<id>` link into ordered direct binary CDN links
  /// (`Cloudflare R2`, `Dotflix Direct`, `Dotflix Proxy`, `Google Drive Worker`,
  /// `Pixeldrain Direct API`), exact filename, and fallback browser share URL.
  Future<ResolvedMovieStream> resolveDownloadStream(
    MovieQualityLink quality, {
    required String fallbackTitle,
  }) async {
    final Map<String, String> baseHeaders = <String, String>{
      'Referer': '$_baseUrl/',
    };

    final ({String body, String url}) step1 = await _followRedirectChain(
      quality.dlUrl,
      headers: baseHeaders,
    );

    String filename = '';
    String sizeLabel = quality.sizeLabel;
    String mimeType = quality.isZipPack ? 'application/zip' : 'video/x-matroska';
    String shareUrl = '';

    if (EonHtmlParser.extractDotflixSharingCode(step1.url).isNotEmpty) {
      shareUrl = step1.url;
    } else {
      final LinksBoxPageResult box =
          EonHtmlParser.parseLinksBoxPage(step1.body, _baseUrl);
      if (box.filename.isNotEmpty) filename = box.filename;
      if (box.sizeLabel.isNotEmpty && sizeLabel.isEmpty) {
        sizeLabel = box.sizeLabel;
      }
      if (box.mimeType.isNotEmpty) mimeType = box.mimeType;

      if (box.directShareUrl.isNotEmpty) {
        shareUrl = box.directShareUrl;
      } else if (box.mirrors.isNotEmpty) {
        String fallbackExternal = '';
        for (final LinksBoxMirror mirror in box.mirrors) {
          if (EonHtmlParser.extractDotflixSharingCode(mirror.url).isNotEmpty) {
            shareUrl = mirror.url;
            break;
          }
          try {
            final ({String body, String url}) resolvedMirror =
                await _followRedirectChain(
              mirror.url,
              headers: <String, String>{'Referer': step1.url},
            );
            final String foundDotflix = EonHtmlParser.extractDotflixSharingCode(
                      resolvedMirror.url,
                    ).isNotEmpty
                ? resolvedMirror.url
                : EonHtmlParser.extractDotflixUrl(resolvedMirror.body);
            if (foundDotflix.isNotEmpty) {
              shareUrl = foundDotflix;
              break;
            }
            if (fallbackExternal.isEmpty && resolvedMirror.url.startsWith('http')) {
              fallbackExternal = resolvedMirror.url;
            }
          } catch (_) {}
        }
        if (shareUrl.isEmpty) {
          shareUrl = fallbackExternal;
        }
      }
    }

    final List<MovieStreamCandidate> candidates = <MovieStreamCandidate>[];
    final Set<String> seenUrls = <String>{};

    void addCandidate(
      String server,
      String rawUrl, {
      Map<String, String> headers = const <String, String>{},
    }) {
      final String trimmed = rawUrl.trim();
      if (trimmed.isEmpty || !trimmed.startsWith('http')) return;
      if (seenUrls.contains(trimmed)) return;
      seenUrls.add(trimmed);
      final bool zip =
          quality.isZipPack || RegExp(r'\.zip(\?|$)', caseSensitive: false).hasMatch(trimmed);
      candidates.add(
        MovieStreamCandidate(
          server: server,
          url: trimmed,
          headers: headers,
          isZip: zip,
        ),
      );
    }

    final String sharingCode =
        EonHtmlParser.extractDotflixSharingCode(shareUrl);
    if (sharingCode.isNotEmpty) {
      final Uri shareUri = Uri.parse(shareUrl);
      final String origin = '${shareUri.scheme}://${shareUri.host}';
      final Map<String, String> dotflixHeaders = <String, String>{
        'Origin': origin,
        'Referer': shareUrl,
      };

      final ({
        DotflixRscResult? rsc,
        String cfApiUrl,
        String extractApiUrl,
        String proxyUrl,
        String driveUrl,
      }) firstPass = await _probeDotflixAll(
        shareUrl: shareUrl,
        origin: origin,
        sharingCode: sharingCode,
        headers: dotflixHeaders,
      );

      if (firstPass.rsc != null) {
        if (firstPass.rsc!.filename.isNotEmpty) {
          filename = firstPass.rsc!.filename;
        }
        if (firstPass.rsc!.formattedSize.isNotEmpty && sizeLabel.isEmpty) {
          sizeLabel = firstPass.rsc!.formattedSize;
        }
      }

      if (firstPass.cfApiUrl.isNotEmpty) {
        addCandidate('Cloudflare R2 Fast CDN', firstPass.cfApiUrl);
      }
      if (firstPass.rsc != null &&
          !firstPass.rsc!.isCloudflareLocked &&
          firstPass.rsc!.cloudflareUrl.isNotEmpty) {
        addCandidate('Cloudflare R2 CDN', firstPass.rsc!.cloudflareUrl);
      }
      if (firstPass.extractApiUrl.isNotEmpty) {
        addCandidate('Dotflix Direct', firstPass.extractApiUrl);
      }

      String proxyUrl = firstPass.proxyUrl;
      String driveUrl = firstPass.driveUrl;

      // Refresh Next.js Server Action hashes from static JS chunks if needed.
      if (proxyUrl.isEmpty &&
          driveUrl.isEmpty &&
          firstPass.rsc != null &&
          firstPass.rsc!.scriptChunks.isNotEmpty) {
        final bool refreshed = await _refreshDotflixActionIds(
          origin: origin,
          shareUrl: shareUrl,
          chunks: firstPass.rsc!.scriptChunks,
          headers: dotflixHeaders,
        );
        if (refreshed) {
          final List<String> retried = await Future.wait(<Future<String>>[
            _callServerActionUrl(
              shareUrl: shareUrl,
              actionId: _cachedProxyAction,
              sharingCode: sharingCode,
              fieldName: 'downloadUrl',
              headers: dotflixHeaders,
            ),
            _callServerActionUrl(
              shareUrl: shareUrl,
              actionId: _cachedDriveAction,
              sharingCode: sharingCode,
              fieldName: 'driveUrl',
              headers: dotflixHeaders,
            ),
          ]);
          proxyUrl = retried[0];
          driveUrl = retried[1];
        }
      }

      if (proxyUrl.isNotEmpty) {
        addCandidate('Dotflix Direct Proxy', proxyUrl, headers: dotflixHeaders);
      }
      if (driveUrl.isNotEmpty) {
        final String workerLink = await _resolveWorkerLink(driveUrl);
        if (workerLink.isNotEmpty) {
          addCandidate('Google Drive Fast Worker', workerLink);
        }
      }
      if (firstPass.rsc != null && firstPass.rsc!.pixeldrainUrl.isNotEmpty) {
        addCandidate('Pixeldrain High-Speed', firstPass.rsc!.pixeldrainUrl);
      }
      if (firstPass.rsc != null && firstPass.rsc!.dotplayUrl.isNotEmpty) {
        addCandidate('DotPlay Stream', firstPass.rsc!.dotplayUrl);
      }
    }

    if (filename.isEmpty) {
      filename = _buildCleanFilename(
        title: fallbackTitle,
        quality: quality,
        isZip: mimeType.contains('zip') ||
            candidates.any((MovieStreamCandidate c) => c.isZip),
      );
    }
    if (filename.toLowerCase().endsWith('.zip')) {
      mimeType = 'application/zip';
    } else if (filename.toLowerCase().endsWith('.mp4')) {
      mimeType = 'video/mp4';
    }

    return ResolvedMovieStream(
      candidates: candidates,
      filename: filename,
      sizeLabel: sizeLabel,
      mimeType: mimeType,
      sharePageUrl: shareUrl.isNotEmpty ? shareUrl : step1.url,
    );
  }

  Future<
      ({
        DotflixRscResult? rsc,
        String cfApiUrl,
        String extractApiUrl,
        String proxyUrl,
        String driveUrl,
      })> _probeDotflixAll({
    required String shareUrl,
    required String origin,
    required String sharingCode,
    required Map<String, String> headers,
  }) async {
    DotflixRscResult? rsc;
    String cfApiUrl = '';
    String extractApiUrl = '';
    String proxyUrl = '';
    String driveUrl = '';

    await Future.wait(<Future<void>>[
      () async {
        try {
          final MovieHttpResponse res = await _transport.get(
            '$origin/api/secure-cloudflare-url/$sharingCode',
            headers: headers,
          );
          if (res.statusCode == 200 && res.body.isNotEmpty) {
            final Object? json = jsonDecode(res.body);
            if (json is Map<String, dynamic> && json['success'] == true) {
              final Object? data = json['data'];
              if (data is Map && data['cloudflare_url'] is String) {
                cfApiUrl = data['cloudflare_url'] as String;
              } else if (json['downloadUrl'] is String) {
                cfApiUrl = json['downloadUrl'] as String;
              } else if (json['url'] is String) {
                cfApiUrl = json['url'] as String;
              }
            }
          }
        } catch (_) {}
      }(),
      () async {
        try {
          final MovieHttpResponse res = await _transport.post(
            '$origin/api/extract-download',
            body: jsonEncode(<String, String>{'sharingCode': sharingCode}),
            headers: <String, String>{
              ...headers,
              'Content-Type': 'application/json',
            },
          );
          if (res.statusCode == 200 && res.body.isNotEmpty) {
            final Object? json = jsonDecode(res.body);
            if (json is Map<String, dynamic> && json['success'] == true) {
              if (json['downloadUrl'] is String) {
                extractApiUrl = json['downloadUrl'] as String;
              } else if (json['data'] is Map &&
                  (json['data'] as Map)['downloadUrl'] is String) {
                extractApiUrl =
                    (json['data'] as Map)['downloadUrl'] as String;
              }
            }
          }
        } catch (_) {}
      }(),
      () async {
        try {
          final MovieHttpResponse page =
              await _transport.get(shareUrl, headers: headers);
          if (page.statusCode == 200 && page.body.isNotEmpty) {
            rsc = EonHtmlParser.parseDotflixRsc(page.body);
          }
        } catch (_) {}
      }(),
      () async {
        proxyUrl = await _callServerActionUrl(
          shareUrl: shareUrl,
          actionId: _cachedProxyAction,
          sharingCode: sharingCode,
          fieldName: 'downloadUrl',
          headers: headers,
        );
      }(),
      () async {
        driveUrl = await _callServerActionUrl(
          shareUrl: shareUrl,
          actionId: _cachedDriveAction,
          sharingCode: sharingCode,
          fieldName: 'driveUrl',
          headers: headers,
        );
      }(),
    ]);

    return (
      rsc: rsc,
      cfApiUrl: cfApiUrl,
      extractApiUrl: extractApiUrl,
      proxyUrl: proxyUrl,
      driveUrl: driveUrl,
    );
  }

  Future<String> _callServerActionUrl({
    required String shareUrl,
    required String actionId,
    required String sharingCode,
    required String fieldName,
    required Map<String, String> headers,
  }) async {
    try {
      final String routerState = Uri.encodeComponent(
        jsonEncode(<Object?>[
          '',
          <String, Object?>{
            'children': <Object?>[
              'share',
              <String, Object?>{
                'children': <Object?>[
                  <String>['code', sharingCode, 'd'],
                  <String, Object?>{
                    'children': <Object?>['__PAGE__', <String, Object?>{}, null, null],
                  },
                  null,
                  null,
                ],
              },
              null,
              null,
            ],
          },
          null,
          null,
          true,
        ]),
      );

      final MovieHttpResponse res = await _transport.post(
        shareUrl,
        body: jsonEncode(<String>[sharingCode]),
        headers: <String, String>{
          ...headers,
          'Accept': 'text/x-component',
          'Content-Type': 'text/plain;charset=UTF-8',
          'Next-Action': actionId,
          'Next-Router-State-Tree': routerState,
        },
      );
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        return EonHtmlParser.parseServerActionField(res.body, fieldName);
      }
    } catch (_) {}
    return '';
  }

  Future<String> _resolveWorkerLink(String driveUrl) async {
    try {
      final MovieHttpResponse res = await _transport.post(
        _dotflixWorkerUrl,
        body: jsonEncode(<String, String>{'driveUrl': driveUrl}),
        headers: const <String, String>{'Content-Type': 'application/json'},
      );
      if (res.statusCode == 200 && res.body.isNotEmpty) {
        final Object? json = jsonDecode(res.body);
        if (json is Map<String, dynamic> &&
            json['success'] == true &&
            json['workerUrl'] is String) {
          return json['workerUrl'] as String;
        }
      }
    } catch (_) {}
    return '';
  }

  Future<bool> _refreshDotflixActionIds({
    required String origin,
    required String shareUrl,
    required List<String> chunks,
    required Map<String, String> headers,
  }) async {
    bool foundAny = false;
    final Set<String> secondLevel = <String>{};

    Future<void> scanChunk(String src, {required bool collectDynamic}) async {
      try {
        final String url = src.startsWith('http') ? src : '$origin$src';
        final MovieHttpResponse res =
            await _transport.get(url, headers: headers);
        if (res.statusCode != 200 || res.body.isEmpty) return;

        final RegExpMatch? p = RegExp(
          r'createServerReference\)\("([a-f0-9]+)",[^)]*?"resolveProxyDownload"\)',
        ).firstMatch(res.body);
        if (p != null) {
          _cachedProxyAction = p.group(1)!;
          foundAny = true;
        }

        final RegExpMatch? d = RegExp(
          r'createServerReference\)\("([a-f0-9]+)",[^)]*?"getDriveUrl"\)',
        ).firstMatch(res.body);
        if (d != null) {
          _cachedDriveAction = d.group(1)!;
          foundAny = true;
        }

        if (collectDynamic) {
          for (final RegExpMatch m in RegExp(
            r'static\/chunks\/[A-Za-z0-9_\-.]+\.js',
          ).allMatches(res.body)) {
            secondLevel.add('/_next/${m.group(0)!}');
          }
        }
      } catch (_) {}
    }

    await Future.wait(
      chunks.take(10).map((String c) => scanChunk(c, collectDynamic: true)),
    );
    if (!foundAny && secondLevel.isNotEmpty) {
      await Future.wait(
        secondLevel
            .take(10)
            .map((String c) => scanChunk(c, collectDynamic: false)),
      );
    }
    return foundAny;
  }

  static String _buildCleanFilename({
    required String title,
    required MovieQualityLink quality,
    required bool isZip,
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
    final String ext = isZip ? 'zip' : 'mkv';
    return '$safe.$ext';
  }

  void dispose() {
    if (_ownsTransport) {
      _transport.close();
    }
  }
}
