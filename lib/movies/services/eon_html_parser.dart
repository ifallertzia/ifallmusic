import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/movie_models.dart';

class LinksBoxMirror {
  const LinksBoxMirror({required this.label, required this.url});
  final String label;
  final String url;
}

class LinksBoxPageResult {
  const LinksBoxPageResult({
    required this.mirrors,
    this.filename = '',
    this.sizeLabel = '',
    this.mimeType = '',
    this.directShareUrl = '',
  });

  final List<LinksBoxMirror> mirrors;
  final String filename;
  final String sizeLabel;
  final String mimeType;
  final String directShareUrl;
}

class DotflixRscResult {
  const DotflixRscResult({
    this.filename = '',
    this.formattedSize = '',
    this.cloudflareUrl = '',
    this.isCloudflareLocked = true,
    this.pixeldrainUrl = '',
    this.dotplayUrl = '',
    this.vikingfileUrl = '',
    this.scriptChunks = const <String>[],
  });

  final String filename;
  final String formattedSize;
  final String cloudflareUrl;
  final bool isCloudflareLocked;
  final String pixeldrainUrl;
  final String dotplayUrl;
  final String vikingfileUrl;
  final List<String> scriptChunks;
}

/// Deterministic HTML & Next.js RSC parser for EonMovies and Dotflix pages.
abstract final class EonHtmlParser {
  static final Set<String> _knownLanguages = <String>{
    'hindi',
    'english',
    'tamil',
    'telugu',
    'malayalam',
    'kannada',
    'punjabi',
    'bengali',
    'marathi',
    'gujarati',
    'bhojpuri',
    'urdu',
    'japanese',
    'korean',
    'chinese',
    'mandarin',
    'spanish',
    'french',
    'german',
    'italian',
    'russian',
    'turkish',
    'indonesian',
    'thai',
    'arabic',
    'portuguese',
    'dual audio',
    'multi audio',
    'org',
  };

  static String _collapse(String input) =>
      input.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _cleanBase(String baseUrl) =>
      baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  /// Rewrites blocked `image.tmdb.org` URLs through `<baseUrl>/img/...` while
  /// preserving a fallback image URL.
  static ({String primary, String fallback}) normalizeImage(
    String raw,
    String baseUrl,
  ) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return (primary: '', fallback: '');
    final String base = _cleanBase(baseUrl);

    if (trimmed.startsWith('https://image.tmdb.org/')) {
      final String path = trimmed.substring('https://image.tmdb.org'.length);
      return (primary: '$base/img$path', fallback: trimmed);
    }
    if (trimmed.startsWith('http://image.tmdb.org/')) {
      final String path = trimmed.substring('http://image.tmdb.org'.length);
      return (primary: '$base/img$path', fallback: trimmed);
    }
    if (trimmed.startsWith('/img/')) {
      final String tmdb =
          'https://image.tmdb.org${trimmed.substring('/img'.length)}';
      return (primary: '$base$trimmed', fallback: tmdb);
    }
    if (trimmed.startsWith('//')) {
      return (primary: 'https:$trimmed', fallback: '');
    }
    if (trimmed.startsWith('/')) {
      return (primary: '$base$trimmed', fallback: '');
    }
    if (trimmed.contains('/img/t/p/')) {
      final int idx = trimmed.indexOf('/img/t/p/');
      final String tmdb =
          'https://image.tmdb.org${trimmed.substring(idx + 4)}';
      return (primary: trimmed, fallback: tmdb);
    }
    return (primary: trimmed, fallback: '');
  }

  static String resolveUrl(String href, String baseUrl) {
    final String clean = href.trim();
    if (clean.isEmpty) return '';
    final Uri base = Uri.parse('${_cleanBase(baseUrl)}/');
    return base.resolve(clean).toString();
  }

  static String toRelativeLink(String href, String baseUrl) {
    final String full = resolveUrl(href, baseUrl);
    if (full.isEmpty) return '';
    final Uri uri = Uri.parse(full);
    final String query = uri.hasQuery ? '?${uri.query}' : '';
    return '${uri.path}$query';
  }

  static Element? _closestAnchor(Element el) {
    Element? current = el;
    while (current != null) {
      if (current.localName == 'a' &&
          (current.attributes['href']?.trim().isNotEmpty ?? false)) {
        return current;
      }
      current = current.parent;
    }
    return null;
  }

  /// Parses catalog / category / search / related posts grids.
  static List<MoviePost> parsePostList(String html, String baseUrl) {
    final Document doc = html_parser.parse(html);
    return _extractPostsFromNodes(
      doc.querySelectorAll('.image-container'),
      baseUrl,
    );
  }

  static List<MoviePost> _extractPostsFromNodes(
    List<Element> containers,
    String baseUrl,
  ) {
    final List<MoviePost> posts = <MoviePost>[];
    final Set<String> seen = <String>{};

    for (final Element container in containers) {
      final Element? anchor = _closestAnchor(container);
      if (anchor == null) continue;

      final String link =
          toRelativeLink(anchor.attributes['href'] ?? '', baseUrl);
      if (link.isEmpty || seen.contains(link)) continue;

      final Element? img = container.querySelector('img');
      final String rawImg =
          img?.attributes['data-src'] ?? img?.attributes['src'] ?? '';
      final ({String primary, String fallback}) imgPair =
          normalizeImage(rawImg, baseUrl);

      final String title = _collapse(
        anchor.querySelector('.card-title')?.text ??
            img?.attributes['alt'] ??
            '',
      );
      if (title.isEmpty) continue;

      String badge = '';
      for (final Element el in container.children) {
        final String t = _collapse(el.text);
        if (t == 'Movie' || t == 'Series') {
          badge = t;
          break;
        }
      }
      if (badge.isEmpty) {
        final String allContainerText = _collapse(container.text);
        if (allContainerText.startsWith('Series')) {
          badge = 'Series';
        } else if (allContainerText.startsWith('Movie')) {
          badge = 'Movie';
        }
      }

      String subtitle = '';
      final Element? titleEl = anchor.querySelector('.card-title');
      if (titleEl != null && titleEl.parent != null) {
        for (final Element sibling in titleEl.parent!.children) {
          if (sibling == titleEl || sibling == container) continue;
          final String text = _collapse(sibling.text);
          if (text.isNotEmpty && text != badge) {
            subtitle = text;
            break;
          }
        }
      }

      seen.add(link);
      posts.add(
        MoviePost(
          title: title,
          link: link,
          imageUrl: imgPair.primary,
          fallbackImageUrl: imgPair.fallback,
          badge: badge,
          subtitle: subtitle,
        ),
      );
    }

    return posts;
  }

  static bool _looksLikeLanguageString(String value) {
    final String cleaned = _collapse(value);
    if (cleaned.isEmpty || cleaned.length > 60) return false;
    final List<String> tokens = cleaned
        .split(RegExp(r'\s*(?:,|&|/|\+|\band\b)\s*', caseSensitive: false))
        .map((String s) => s.trim().toLowerCase())
        .where((String s) => s.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return false;
    return tokens.every(_knownLanguages.contains);
  }

  static String _normalizeLanguageFormatting(String raw) {
    final List<String> parts = raw
        .split(RegExp(r'\s*(?:,|&|/|\+)\s*'))
        .map((String s) => _collapse(s))
        .where((String s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '';
    return parts.map((String p) {
      return p
          .split(' ')
          .map(
            (String w) => w.isEmpty
                ? w
                : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}',
          )
          .join(' ');
    }).join(', ');
  }

  static String extractLanguagesFromDocument(
    Document doc, {
    List<String> metaPills = const <String>[],
  }) {
    // 1. Check all `[Hindi,Telugu]` / `[Hindi, English]` bracket groups in `<title>`.
    final String pageTitle = _collapse(doc.querySelector('title')?.text ?? '');
    for (final RegExpMatch match
        in RegExp(r'\[([^\]]+)\]').allMatches(pageTitle)) {
      final String candidate = match.group(1) ?? '';
      if (_looksLikeLanguageString(candidate)) {
        return _normalizeLanguageFormatting(candidate);
      }
    }

    // 2. Check `.meta-pill` items.
    for (final String pill in metaPills) {
      if (_looksLikeLanguageString(pill)) {
        return _normalizeLanguageFormatting(pill);
      }
    }

    // 3. Check Download heading `Download ... in Hindi, Telugu`.
    for (final Element el in doc.querySelectorAll('h1, h2, h3, h4, .dl-title')) {
      final String text = _collapse(el.text);
      final RegExpMatch? m =
          RegExp(r'\bin\s+([A-Za-z,\s&+/]+)$').firstMatch(text);
      if (m != null) {
        final String candidate = m.group(1) ?? '';
        if (_looksLikeLanguageString(candidate)) {
          return _normalizeLanguageFormatting(candidate);
        }
      }
    }

    // 4. Scan body text fallback for `WEB-DL in <Languages>`.
    final String bodyText = _collapse(doc.body?.text ?? '');
    final RegExpMatch? fallback = RegExp(
      r'WEB-DL\s+in\s+([A-Za-z]+(?:\s*,\s*[A-Za-z]+){0,5})',
      caseSensitive: false,
    ).firstMatch(bodyText);
    if (fallback != null &&
        _looksLikeLanguageString(fallback.group(1) ?? '')) {
      return _normalizeLanguageFormatting(fallback.group(1)!);
    }

    return '';
  }

  static String _extractDlId(String dlUrl) {
    final RegExpMatch? m = RegExp(r'/dl/([^/?#]+)').firstMatch(dlUrl);
    if (m != null) return m.group(1)!;
    return dlUrl.hashCode.abs().toString();
  }

  static String _extractSize(String text) {
    final RegExpMatch? m = RegExp(
      r'\b(\d+(?:\.\d+)?\s*(?:GB|MB|KB|TB))\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (m == null) return '';
    return _collapse(m.group(1)!).toUpperCase();
  }

  static ({String resolution, String codec}) _parseQualityComponents(
    String rawLabel,
  ) {
    final RegExpMatch? resMatch =
        RegExp(r'\b(2160p|1440p|1080p|720p|540p|480p|360p|4K)\b',
                caseSensitive: false)
            .firstMatch(rawLabel);
    String resolution = resMatch != null ? resMatch.group(1)! : '';
    if (resolution.toUpperCase() == '2160P') {
      resolution = '2160p 4K';
    } else if (resolution.isNotEmpty && resolution.toUpperCase() != '4K') {
      resolution = resolution.toLowerCase();
    }

    final List<String> codecs = <String>[];
    if (RegExp(r'\b(?:HEVC|H\.?265|x265)\b', caseSensitive: false)
        .hasMatch(rawLabel)) {
      codecs.add('HEVC');
    } else if (RegExp(r'\bAV1\b', caseSensitive: false).hasMatch(rawLabel)) {
      codecs.add('AV1');
    } else if (RegExp(r'\b(?:H\.?264|x264|AVC)\b', caseSensitive: false)
        .hasMatch(rawLabel)) {
      codecs.add('H.264');
    }
    if (RegExp(r'\b10\s*bit\b', caseSensitive: false).hasMatch(rawLabel)) {
      codecs.add('10bit');
    }

    return (resolution: resolution, codec: codecs.join(' '));
  }

  static bool _isQualityRow(String label, String sizeLabel) {
    if (RegExp(
      r'\b(?:2160p|1440p|1080p|720p|540p|480p|360p|4K)\b',
      caseSensitive: false,
    ).hasMatch(label)) {
      return true;
    }
    if (sizeLabel.isNotEmpty &&
        !RegExp(r'^(?:season|episode)\b', caseSensitive: false)
            .hasMatch(label.trim())) {
      return true;
    }
    return false;
  }

  static String _inferSeasonFromTitle(String title) {
    final RegExpMatch? range = RegExp(
      r'\bSeason\s+(\d+\s*-\s*\d+)\b',
      caseSensitive: false,
    ).firstMatch(title);
    if (range != null) return '';

    final RegExpMatch? single = RegExp(
      r'\bSeason\s+(\d+)\b',
      caseSensitive: false,
    ).firstMatch(title);
    if (single != null) return 'Season ${single.group(1)}';

    final RegExpMatch? short =
        RegExp(r'\bS0?(\d+)\b', caseSensitive: false).firstMatch(title);
    if (short != null) return 'Season ${short.group(1)}';

    return '';
  }

  static ({String season, String episode}) _parseSeasonEpisodeLabels(
    String rawLabel,
    String fallbackSeason,
  ) {
    final String clean = _collapse(rawLabel);
    String season = fallbackSeason;
    String episode = '';

    final RegExpMatch? sMatch = RegExp(
      r'\bSeason\s+(\d+(?:\s*-\s*\d+)?)\b',
      caseSensitive: false,
    ).firstMatch(clean);
    if (sMatch != null) {
      season = 'Season ${_collapse(sMatch.group(1)!)}';
    } else {
      final RegExpMatch? shortS =
          RegExp(r'\bS0?(\d+)\b', caseSensitive: false).firstMatch(clean);
      if (shortS != null) {
        season = 'Season ${shortS.group(1)}';
      }
    }

    final RegExpMatch? epMatch = RegExp(
      r'\b(?:Episode|Ep\.?)\s*(\d+(?:\s*-\s*\d+)?)\b',
      caseSensitive: false,
    ).firstMatch(clean);
    if (epMatch != null) {
      episode = 'Episode ${_collapse(epMatch.group(1)!)}';
    } else {
      final RegExpMatch? shortE =
          RegExp(r'\bE0?(\d+(?:\s*-\s*\d+)?)\b', caseSensitive: false)
              .firstMatch(clean);
      if (shortE != null) {
        episode = 'Episode ${_collapse(shortE.group(1)!)}';
      }
    }

    return (season: season, episode: episode);
  }

  static List<({String label, String size, String dlUrl})> _extractRawDlRows(
    Document doc,
    String baseUrl,
  ) {
    final List<({String label, String size, String dlUrl})> rows =
        <({String label, String size, String dlUrl})>[];

    for (final Element row in doc.querySelectorAll('.dl-row')) {
      final Element? anchor = row.querySelector("a[href*='/dl/']") ??
          row.querySelector('a[href]');
      final String href = anchor?.attributes['href'] ?? '';
      if (href.isEmpty) continue;

      final String dlUrl = resolveUrl(href, baseUrl);
      final String rowText = _collapse(row.text);
      final String size = _extractSize(rowText);

      String label = _collapse(
        row.attributes['data-dlname'] ??
            row.querySelector('.dl-row-name')?.text ??
            '',
      );
      if (label.isEmpty) {
        label = rowText
            .replaceAll(size, '')
            .replaceAll(RegExp(r'\bDownload\b', caseSensitive: false), '')
            .trim();
      }
      if (label.isEmpty) continue;

      rows.add((label: label, size: size, dlUrl: dlUrl));
    }

    return rows;
  }

  /// Parses full Movie or Series detail page HTML into [MovieDetail].
  static MovieDetail parseDetail(
    String html, {
    required String pageUrl,
    required String baseUrl,
  }) {
    final Document doc = html_parser.parse(html);

    final String ogTitle = _collapse(
      doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
          '',
    ).replaceAll(
      RegExp(r'\s*-\s*Download in HD\s*\|\s*EonMovies\s*$', caseSensitive: false),
      '',
    );
    final String h1Title = _collapse(doc.querySelector('h1')?.text ?? '');
    final String title = ogTitle.isNotEmpty ? ogTitle : h1Title;

    final String cleanTitle = title
        .replaceAll(RegExp(r'\s*\(\d{4}\)\s*$'), '')
        .replaceAll(RegExp(r'\s*\[Episode[^\]]*\]', caseSensitive: false), '')
        .trim();

    final String yearMatch = RegExp(r'\b((?:19|20)\d{2})\b')
            .firstMatch('$h1Title $title')
            ?.group(1) ??
        '';

    final String heroStyle =
        doc.querySelector('#heroBackdrop')?.attributes['style'] ?? '';
    final String rawBackdrop = RegExp(
          r"""background-image\s*:\s*url\(['"]?([^'")]+)['"]?\)""",
          caseSensitive: false,
        ).firstMatch(heroStyle)?.group(1) ??
        doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
        '';
    final ({String primary, String fallback}) backdropPair =
        normalizeImage(rawBackdrop, baseUrl);

    String rawPoster = '';
    for (final Element img in doc.querySelectorAll('img')) {
      final String src =
          img.attributes['data-src'] ?? img.attributes['src'] ?? '';
      if (src.isEmpty) continue;
      final String alt = _collapse(img.attributes['alt'] ?? '');
      if (alt.isNotEmpty &&
          title.toLowerCase().contains(
                alt.toLowerCase().substring(0, alt.length.clamp(0, 8)),
              )) {
        rawPoster = src;
        break;
      }
      rawPoster = rawPoster.isEmpty ? src : rawPoster;
    }
    final ({String primary, String fallback}) posterPair = normalizeImage(
      rawPoster.isNotEmpty ? rawPoster : rawBackdrop,
      baseUrl,
    );

    final List<String> metaPills = doc
        .querySelectorAll('.meta-pill')
        .map((Element e) => _collapse(e.text))
        .where((String s) => s.isNotEmpty)
        .toList();

    final List<String> genres = doc
        .querySelectorAll('#movieGenresBox .genre-pill')
        .map((Element e) => _collapse(e.text))
        .where((String s) => s.isNotEmpty)
        .toSet()
        .toList();

    final bool isSeries = metaPills.any(
          (String p) => p.toLowerCase() == 'series',
        ) ||
        RegExp(
          r'\b(?:Season\s+\d+|Episode\s+\d+)\b',
          caseSensitive: false,
        ).hasMatch('$h1Title $title');

    final String languages =
        extractLanguagesFromDocument(doc, metaPills: metaPills);
    final List<String> languageList = languages
        .split(',')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();

    String releaseDate = '';
    String director = '';
    final List<String> qualityBadges = <String>[];
    for (final String pill in metaPills) {
      if (RegExp(r'^\d{1,2}\s+[A-Za-z]{3,9}\s+\d{4}$').hasMatch(pill)) {
        releaseDate = pill;
      } else if (RegExp(
        r'^(?:4K|2160p|1440p|1080p|720p|540p|480p|WEB-DL|BluRay|HDTC|HDRip)$',
        caseSensitive: false,
      ).hasMatch(pill)) {
        qualityBadges.add(pill);
      } else if (pill != 'Movie' &&
          pill != 'Series' &&
          !_looksLikeLanguageString(pill) &&
          !RegExp(r'^\d+\s*min', caseSensitive: false).hasMatch(pill)) {
        director = director.isEmpty ? pill : director;
      }
    }

    final String synopsis = _collapse(
      doc.querySelector('.overview-text')?.text ?? '',
    );

    final String defaultSeason = _inferSeasonFromTitle('$h1Title $title');
    final List<({String label, String size, String dlUrl})> rawRows =
        _extractRawDlRows(doc, baseUrl);

    final List<MovieQualityLink> directQualities = <MovieQualityLink>[];
    final List<MovieEpisodeGroup> episodeGroups = <MovieEpisodeGroup>[];

    for (final ({String dlUrl, String label, String size}) row in rawRows) {
      if (_isQualityRow(row.label, row.size)) {
        final ({String codec, String resolution}) q =
            _parseQualityComponents(row.label);
        directQualities.add(
          MovieQualityLink(
            id: _extractDlId(row.dlUrl),
            rawLabel: row.label,
            resolution: q.resolution.isNotEmpty ? q.resolution : row.label,
            codec: q.codec,
            sizeLabel: row.size,
            dlUrl: row.dlUrl,
            languages: languages,
            isZipPack: isSeries,
            seasonLabel: isSeries
                ? (defaultSeason.isNotEmpty ? defaultSeason : 'Complete Pack')
                : '',
            episodeLabel: isSeries ? 'All Episodes (ZIP)' : '',
          ),
        );
      } else {
        final ({String episode, String season}) se =
            _parseSeasonEpisodeLabels(row.label, defaultSeason);
        episodeGroups.add(
          MovieEpisodeGroup(
            id: _extractDlId(row.dlUrl),
            title: row.label,
            seasonLabel: se.season,
            episodeLabel: se.episode,
            languages: languages,
            subPageDlUrl: row.dlUrl,
            isLoaded: false,
          ),
        );
      }
    }

    // If a series exposes Complete Season ZIP qualities directly on the detail
    // page (e.g. "The Terminal List - Season 2"), also expose it cleanly as a
    // named Season group so Season Name + ZIP Pack + Qualities show clearly.
    final List<MovieEpisodeGroup> finalGroups = <MovieEpisodeGroup>[
      if (isSeries && directQualities.isNotEmpty)
        MovieEpisodeGroup(
          id: 'season-pack-${defaultSeason.isEmpty ? 'all' : defaultSeason}',
          title: defaultSeason.isNotEmpty
              ? '$defaultSeason • Complete Pack (ZIP)'
              : 'Complete Season Pack (ZIP)',
          seasonLabel: defaultSeason,
          episodeLabel: 'All Episodes (ZIP)',
          languages: languages,
          isCompletePack: true,
          qualities: directQualities,
          isLoaded: true,
        ),
      ...episodeGroups,
    ];

    final List<MoviePost> relatedPosts = _extractPostsFromNodes(
      doc.querySelectorAll('.image-container'),
      baseUrl,
    );

    return MovieDetail(
      title: h1Title.isNotEmpty ? h1Title : title,
      cleanTitle: cleanTitle.isNotEmpty ? cleanTitle : title,
      type: isSeries ? MovieMediaType.series : MovieMediaType.movie,
      webUrl: pageUrl,
      year: yearMatch,
      releaseDate: releaseDate,
      backdropUrl: backdropPair.primary,
      fallbackBackdropUrl: backdropPair.fallback,
      posterUrl: posterPair.primary,
      fallbackPosterUrl: posterPair.fallback,
      languages: languages,
      languageList: languageList,
      genres: genres,
      director: director,
      qualityBadges: qualityBadges,
      synopsis: synopsis,
      defaultSeasonLabel: defaultSeason,
      directQualities: isSeries ? const <MovieQualityLink>[] : directQualities,
      episodeGroups: finalGroups,
      relatedPosts: relatedPosts,
    );
  }

  /// Parses an episode or season sub-page (`/page/<id>`) into populated
  /// [MovieQualityLink] items (and optional nested episode sub-groups).
  static MovieEpisodeGroup parseSubPage(
    String html, {
    required MovieEpisodeGroup parentGroup,
    required String baseUrl,
  }) {
    final Document doc = html_parser.parse(html);
    final String subPageLang = extractLanguagesFromDocument(doc);
    final String effectiveLang =
        subPageLang.isNotEmpty ? subPageLang : parentGroup.languages;

    final String heading = _collapse(
      doc.querySelector('h1, h2')?.text ?? doc.querySelector('title')?.text ?? '',
    );
    final ({String episode, String season}) inferred = _parseSeasonEpisodeLabels(
      heading,
      parentGroup.seasonLabel,
    );
    final String season =
        parentGroup.seasonLabel.isNotEmpty ? parentGroup.seasonLabel : inferred.season;
    final String episode = parentGroup.episodeLabel.isNotEmpty
        ? parentGroup.episodeLabel
        : inferred.episode;

    final List<({String dlUrl, String label, String size})> rawRows =
        _extractRawDlRows(doc, baseUrl);
    final List<MovieQualityLink> qualities = <MovieQualityLink>[];
    final List<MovieEpisodeGroup> nested = <MovieEpisodeGroup>[];
    final bool isSeasonPack = episode.isEmpty && season.isNotEmpty;

    for (final ({String dlUrl, String label, String size}) row in rawRows) {
      if (_isQualityRow(row.label, row.size)) {
        final ({String codec, String resolution}) q =
            _parseQualityComponents(row.label);
        qualities.add(
          MovieQualityLink(
            id: _extractDlId(row.dlUrl),
            rawLabel: row.label,
            resolution: q.resolution.isNotEmpty ? q.resolution : row.label,
            codec: q.codec,
            sizeLabel: row.size,
            dlUrl: row.dlUrl,
            languages: effectiveLang,
            isZipPack: isSeasonPack,
            seasonLabel: season,
            episodeLabel: isSeasonPack ? 'Complete Season (ZIP)' : episode,
          ),
        );
      } else {
        final ({String episode, String season}) se =
            _parseSeasonEpisodeLabels(row.label, season);
        nested.add(
          MovieEpisodeGroup(
            id: _extractDlId(row.dlUrl),
            title: row.label,
            seasonLabel: se.season,
            episodeLabel: se.episode,
            languages: effectiveLang,
            subPageDlUrl: row.dlUrl,
            isLoaded: false,
          ),
        );
      }
    }

    return parentGroup.copyWith(
      seasonLabel: season,
      episodeLabel: episode,
      languages: effectiveLang,
      isCompletePack: isSeasonPack && qualities.isNotEmpty,
      qualities: qualities,
      nestedGroups: nested,
      isLoaded: true,
    );
  }

  /// Parses EonMovies `/links/<10-char-code>` mirror chooser box page.
  static LinksBoxPageResult parseLinksBoxPage(String html, String baseUrl) {
    final Document doc = html_parser.parse(html);
    final String fullText = _collapse(doc.body?.text ?? html);

    final String filename = RegExp(
          r'([A-Za-z0-9._\-\[\]()]+EonMovies[^\s<>"]*\.(?:mkv|mp4|zip|avi|webm))',
          caseSensitive: false,
        ).firstMatch(fullText)?.group(1) ??
        RegExp(
          r'([A-Za-z0-9._\-]{6,}\.(?:mkv|mp4|zip|avi|webm))',
          caseSensitive: false,
        ).firstMatch(fullText)?.group(1) ??
        '';

    final String sizeLabel = _extractSize(fullText);

    String mimeType = '';
    if (fullText.contains('application/zip') ||
        filename.toLowerCase().endsWith('.zip')) {
      mimeType = 'application/zip';
    } else if (fullText.contains('video/mp4') ||
        filename.toLowerCase().endsWith('.mp4')) {
      mimeType = 'video/mp4';
    } else if (fullText.contains('video/x-matroska') ||
        filename.toLowerCase().endsWith('.mkv')) {
      mimeType = 'video/x-matroska';
    }

    final String embeddedDotflix = extractDotflixUrl(html);
    final List<LinksBoxMirror> mirrors = <LinksBoxMirror>[];

    for (final Element a in doc.querySelectorAll('a[href]')) {
      final String href = a.attributes['href']?.trim() ?? '';
      if (href.isEmpty) continue;
      final String label = _collapse(a.text);
      final String fullUrl = resolveUrl(href, baseUrl);
      if (href.contains('/dl/') ||
          extractDotflixSharingCode(fullUrl).isNotEmpty ||
          fullUrl.contains('tmbcloud') ||
          fullUrl.contains('hubcloud')) {
        mirrors.add(LinksBoxMirror(label: label, url: fullUrl));
      }
    }

    // Prioritize DOTFLIX mirrors ahead of Turnstile-gated mirrors.
    mirrors.sort((LinksBoxMirror a, LinksBoxMirror b) {
      int score(LinksBoxMirror m) {
        final String s = '${m.label} ${m.url}'.toLowerCase();
        if (s.contains('dotflix') || s.contains('dtflix') || s.contains('fajlix')) {
          return 0;
        }
        if (s.contains('hubcloud')) return 1;
        if (s.contains('tmbcloud')) return 3;
        return 2;
      }

      return score(a).compareTo(score(b));
    });

    return LinksBoxPageResult(
      mirrors: mirrors,
      filename: filename,
      sizeLabel: sizeLabel,
      mimeType: mimeType,
      directShareUrl: embeddedDotflix,
    );
  }

  static String extractDotflixUrl(String text) {
    return RegExp(
          r'https?:\/\/(?:[a-z\d-]+\.)*(?:dotflix|dtflix|fajlix)\.[a-z\d.]+\/share\/[a-z\d]+',
          caseSensitive: false,
        ).firstMatch(text)?.group(0) ??
        '';
  }

  static String extractDotflixSharingCode(String url) {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null) return '';
    if (!RegExp(r'(?:^|\.)(?:dotflix|dtflix|fajlix)\.', caseSensitive: false)
        .hasMatch(uri.host)) {
      return '';
    }
    return RegExp(r'^\/share\/([a-z\d]+)', caseSensitive: false)
            .firstMatch(uri.path)
            ?.group(1) ??
        '';
  }

  static String normalizePixeldrainDownloadUrl(String rawUrl) {
    final String clean = rawUrl.trim();
    if (clean.isEmpty) return '';
    final Uri? uri = Uri.tryParse(clean);
    if (uri == null) return '';
    if (!uri.host.toLowerCase().contains('pixeldrain')) return clean;

    final RegExpMatch? uMatch =
        RegExp(r'^\/(?:u|api\/file)\/([A-Za-z0-9_-]+)').firstMatch(uri.path);
    if (uMatch != null) {
      return '${uri.scheme}://${uri.host}/api/file/${uMatch.group(1)}?download';
    }
    return clean;
  }

  /// Extracts `initialShareData`, `initialCloudflareData`, and JS chunk paths
  /// from Dotflix Next.js App Router HTML (`self.__next_f.push([1,"..."])`).
  static DotflixRscResult parseDotflixRsc(String html) {
    final StringBuffer combined = StringBuffer(html);

    final Iterable<RegExpMatch> pushes = RegExp(
      r'self\.__next_f\.push\(\[\s*1\s*,\s*("(?:\\.|[^"\\])*")\s*\]\)',
      dotAll: true,
    ).allMatches(html);

    for (final RegExpMatch m in pushes) {
      final String? quoted = m.group(1);
      if (quoted == null) continue;
      try {
        final Object? decoded = jsonDecode(quoted);
        if (decoded is String) {
          combined.writeln(decoded);
        }
      } catch (_) {
        combined.writeln(
          quoted
              .substring(1, quoted.length - 1)
              .replaceAll(r'\"', '"')
              .replaceAll(r'\/', '/')
              .replaceAll(r'\\', r'\'),
        );
      }
    }

    final String full = combined.toString();
    Map<String, dynamic> shareData = const <String, dynamic>{};
    Map<String, dynamic> cfData = const <String, dynamic>{};

    final RegExpMatch? sdMatch =
        RegExp(r'"initialShareData"\s*:\s*(\{[^{}]+\})').firstMatch(full);
    if (sdMatch != null) {
      try {
        final Object? parsed = jsonDecode(sdMatch.group(1)!);
        if (parsed is Map<String, dynamic>) shareData = parsed;
      } catch (_) {}
    }

    final RegExpMatch? cfMatch =
        RegExp(r'"initialCloudflareData"\s*:\s*(\{[^{}]+\})').firstMatch(full);
    if (cfMatch != null) {
      try {
        final Object? parsed = jsonDecode(cfMatch.group(1)!);
        if (parsed is Map<String, dynamic>) cfData = parsed;
      } catch (_) {}
    }

    final List<String> chunks = RegExp(r'src="([^"]*\/static\/chunks\/[^"]+\.js)"')
        .allMatches(html)
        .map((RegExpMatch m) => m.group(1) ?? '')
        .where((String s) => s.isNotEmpty)
        .toSet()
        .toList();

    return DotflixRscResult(
      filename: shareData['filename']?.toString() ?? '',
      formattedSize: shareData['formattedFileSize']?.toString() ?? '',
      cloudflareUrl: cfData['cloudflareFileUrl']?.toString() ?? '',
      isCloudflareLocked: cfData['isCloudflareLocked'] != false,
      pixeldrainUrl: normalizePixeldrainDownloadUrl(
        shareData['pixeldrainLink']?.toString() ?? '',
      ),
      dotplayUrl: shareData['dotplayLink']?.toString() ?? '',
      vikingfileUrl: shareData['vikingfileLink']?.toString() ?? '',
      scriptChunks: chunks,
    );
  }

  /// Extracts `downloadUrl` or `driveUrl` from a Next.js Flight / Server Action
  /// streaming text response (`0:...`, `1:{"success":true,"downloadUrl":"..."}`).
  static String parseServerActionField(String responseBody, String fieldName) {
    for (final String line in responseBody.split(RegExp(r'\r?\n'))) {
      final int colon = line.indexOf(':');
      if (colon < 0 || colon + 1 >= line.length) continue;
      final String payloadRaw = line.substring(colon + 1).trim();
      if (!payloadRaw.startsWith('{')) continue;
      try {
        final Object? decoded = jsonDecode(payloadRaw);
        if (decoded is Map<String, dynamic>) {
          final Object? val = decoded[fieldName];
          if (decoded['success'] == true && val is String && val.isNotEmpty) {
            return val;
          }
          final Object? nested = decoded['data'];
          if (nested is Map<String, dynamic> &&
              nested[fieldName] is String &&
              (nested[fieldName] as String).isNotEmpty) {
            return nested[fieldName] as String;
          }
        }
      } catch (_) {}
    }
    return '';
  }
}
