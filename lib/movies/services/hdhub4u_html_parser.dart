import 'dart:convert';

import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/movie_models.dart';
import '../models/movie_provider.dart';
import 'movie_rating.dart';
import 'movie_text_scrub.dart';

/// One link found on an HDHub4U title page, already labelled with everything
/// the UI needs (resolution, codec, size, language, season / episode).
class HdhubLinkSpec {
  const HdhubLinkSpec({
    required this.url,
    this.label = '',
    this.resolution = '',
    this.codec = '',
    this.sizeLabel = '',
    this.languages = '',
    this.isZip = false,
    this.seasonLabel = '',
    this.episodeLabel = '',
    this.episodeNumber = 0,
    this.isSeasonPack = false,
  });

  final String url;
  final String label;
  final String resolution;
  final String codec;
  final String sizeLabel;
  final String languages;
  final bool isZip;
  final String seasonLabel;
  final String episodeLabel;
  final int episodeNumber;
  final bool isSeasonPack;
}

/// Deterministic HTML parser for HDHub4U title / listing pages plus the
/// JSON returned by the site's own search endpoint.
abstract final class Hdhub4uHtmlParser {
  static final RegExp _qualityRe =
      RegExp(r'\b(2160p|1080p|720p|480p|360p|4k)\b', caseSensitive: false);

  static final RegExp _episodeRe = RegExp(
    r'\b(?:episodes?|ep|e)\s*[:.\-]?\s*0*(\d{1,3})\b',
    caseSensitive: false,
  );

  static final RegExp _seasonRe =
      RegExp(r'\bseason\s*0*(\d{1,2})\b', caseSensitive: false);

  static const Set<String> _knownLanguages = <String>{
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
    'spanish',
    'french',
    'german',
    'italian',
    'russian',
    'turkish',
    'thai',
    'arabic',
    'portuguese',
  };

  /// Hosts / URL shapes that hold the real download behind a title page.
  static const List<String> _linkHostHints = <String>[
    'hubcloud',
    'hubdrive',
    'gdflix',
    'gdtot',
    'filepress',
    'hubcdn',
    'r2.dev',
    'pixeldrain',
    'workers.dev',
    'cloudflarestorage',
    'drive.google',
    'drive.usercontent',
    'googleusercontent',
    'gofile.io',
    'fastdl',
    'fsl.',
    'hdstream4u',
    'katflix',
    'drivehub',
  ];

  static String collapse(String input) =>
      input.replaceAll(RegExp(r'\s+'), ' ').trim();

  static String cleanBase(String baseUrl) =>
      baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  /// Absolute URL for [href] relative to [base].
  static String resolveUrl(String href, String base) {
    final String raw = href.trim();
    if (raw.isEmpty) return '';
    if (raw.startsWith('//')) return 'https:$raw';
    final Uri? baseUri = Uri.tryParse(base);
    final Uri? parsed = Uri.tryParse(raw);
    if (parsed == null) return raw;
    if (parsed.hasScheme) return parsed.toString();
    if (baseUri == null) return raw;
    return baseUri.resolveUri(parsed).toString();
  }

  static String extractResolution(String text) {
    final RegExpMatch? match = _qualityRe.firstMatch(text);
    if (match == null) return '';
    final String raw = (match.group(1) ?? '').toLowerCase();
    if (raw == '4k' || raw == '2160p') return '2160p';
    return raw;
  }

  static String extractCodec(String text) {
    final String lower = text.toLowerCase();
    if (RegExp(r'\bx\s?265\b|\bhevc\b|\bh\.?265\b').hasMatch(lower)) {
      return 'HEVC';
    }
    if (RegExp(r'\bx\s?264\b|\bh\.?264\b|\bavc\b').hasMatch(lower)) {
      return 'x264';
    }
    if (RegExp(r'\bav1\b').hasMatch(lower)) return 'AV1';
    return '';
  }

  static String extractSize(String text) {
    final RegExpMatch? match = RegExp(
      r'(\d+(?:\.\d+)?)\s*(gb|mb|gib|mib)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return '';
    return '${match.group(1)} ${match.group(2)!.toUpperCase()}';
  }

  static String extractLanguages(String text) {
    final String lower = text.toLowerCase();
    final List<String> found = <String>[];
    for (final String language in _knownLanguages) {
      if (RegExp('\\b$language\\b').hasMatch(lower)) {
        found.add(language[0].toUpperCase() + language.substring(1));
      }
    }
    return found.join(', ');
  }

  static int extractEpisodeNumber(String text) {
    final RegExpMatch? match = _episodeRe.firstMatch(text);
    if (match == null) return 0;
    return int.tryParse(match.group(1) ?? '') ?? 0;
  }

  static String extractSeasonLabel(String text) {
    final RegExpMatch? match = _seasonRe.firstMatch(text);
    if (match == null) return '';
    final int number = int.tryParse(match.group(1) ?? '') ?? 0;
    if (number <= 0) return '';
    return 'Season $number';
  }

  /// Whether [url] is one of the hosts that actually serves bytes.
  static bool looksResolvable(String url) {
    final String lower = url.trim().toLowerCase();
    if (!lower.startsWith('http')) return false;
    for (final String hint in _linkHostHints) {
      if (lower.contains(hint)) return true;
    }
    if (RegExp(r'\.(mkv|mp4|avi|webm|m4v|mov|zip|rar)(\?|$)').hasMatch(lower)) {
      return true;
    }
    if (lower.contains('/drive/') || lower.contains('?id=')) return true;
    return false;
  }

  /// Whether [url] is one of this site's own intermediate download pages.
  static bool looksLikeSiteDownloadPage(String url, String baseUrl) {
    final String lower = url.toLowerCase();
    final String base = cleanBase(baseUrl).toLowerCase();
    if (base.isEmpty || !lower.startsWith(base)) return false;
    return lower.contains('/drive/') ||
        lower.contains('/dl/') ||
        lower.contains('download') ||
        lower.contains('/links/');
  }

  static bool looksZip(String url) =>
      RegExp(r'\.(zip|rar)(\?|$)', caseSensitive: false).hasMatch(url);

  static bool looksVideo(String url) => RegExp(
        r'\.(mkv|mp4|avi|webm|m4v|mov|ts)(\?|$)',
        caseSensitive: false,
      ).hasMatch(url);

  /// Stable, restart-safe id for a quality row.
  static String stableId(String seed) {
    int hash = 0x811c9dc5;
    for (final int code in seed.codeUnits) {
      hash ^= code;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return '${hash.toRadixString(16).padLeft(8, '0')}_${seed.length}';
  }

  static String cleanTitleText(String raw) {
    String text = collapse(raw.replaceAll(RegExp('[\uE000-\uF8FF]'), ' '));
    if (text.toLowerCase().startsWith('download ')) {
      text = text.substring('download '.length).trim();
    }
    // HDHub4U titles carry the print on the same line:
    // "Obsession (2025) WEB-DL 1080p …" — keep the name only.
    final RegExpMatch? cut = RegExp(
      r'\s+(?:web-?dl|webrip|bluray|blu-ray|hdrip|camrip|hdcam|480p|720p|'
      r'1080p|2160p|4k|hevc|x264|x265|hindi|dual audio|esub|esubs)\b',
      caseSensitive: false,
    ).firstMatch(text);
    if (cut != null && cut.start > 0) {
      text = text.substring(0, cut.start).trim();
    }
    // The site stamps its own name on titles; a person never sees it.
    text = scrubSourceNames(text);
    return text.replaceAll(RegExp(r'[\s\-:]+$'), '').trim();
  }

  /// The site's own chrome — its logo, a "home" link, a banner — rather than a
  /// title. The layout fallback in [parsePosts] looks at every linked image on
  /// the page, and without this check the site logo became a result named
  /// after the site at the top of the list.
  static bool _isSiteChrome({
    required String link,
    required String rawTitle,
    required String cleanedTitle,
    required String imageSource,
    required String baseUrl,
  }) {
    final Uri? uri = Uri.tryParse(link);
    if (uri == null) return true;
    final String path = uri.path.replaceAll(RegExp(r'/+$'), '');
    // The home page itself (or a bare "?s=" style link) is never a title.
    if (path.isEmpty) return true;
    final String lowerPath = path.toLowerCase();
    // Whole path segments only: a title slug such as `/tag-team-2024/` or
    // `/about-time-2013/` is a movie, `/tag/…` and `/about/` are site pages.
    if (RegExp(
      r'^/(?:page|tag|author|feed|category|genre|year|search|contact|'
      r'contact-us|about|about-us|dmca|disclaimer|privacy-policy|sitemap)'
      r'(?:/|$)',
    ).hasMatch(lowerPath)) {
      return true;
    }
    if (RegExp(r'^/wp-(?:content|admin|includes|json|login)').hasMatch(lowerPath)) {
      return true;
    }
    // Nothing left once the site's name is taken out: it was the logo.
    if (cleanedTitle.trim().length < 2) return true;
    final String compactTitle =
        rawTitle.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
    final String host = (Uri.tryParse(baseUrl)?.host ?? '')
        .toLowerCase()
        .replaceAll(RegExp(r'^www\.'), '');
    final String hostLabel = host.split('.').first;
    if (compactTitle.isNotEmpty &&
        (compactTitle == host.replaceAll(RegExp(r'[^a-z0-9]+'), '') ||
            compactTitle == hostLabel ||
            compactTitle == 'logo' ||
            compactTitle == 'home' ||
            compactTitle == 'homepage')) {
      return true;
    }
    // An image file that is literally the logo / favicon.
    if (RegExp(
      r'(?:^|/)(?:logo|favicon|site-icon|site-logo)\.[a-z0-9]+(?:\?.*)?$',
    ).hasMatch(imageSource.toLowerCase())) {
      return true;
    }
    return false;
  }

  static ({String primary, String fallback}) _imageUrls(
    String raw,
    String baseUrl,
  ) {
    final String trimmed = raw.trim();
    if (trimmed.isEmpty) return (primary: '', fallback: '');
    if (trimmed.startsWith('data:')) return (primary: '', fallback: '');
    if (trimmed.startsWith('//')) {
      return (primary: 'https:$trimmed', fallback: '');
    }
    if (trimmed.startsWith('http')) return (primary: trimmed, fallback: '');
    if (trimmed.startsWith('/')) {
      return (primary: '${cleanBase(baseUrl)}$trimmed', fallback: '');
    }
    return (primary: '${cleanBase(baseUrl)}/$trimmed', fallback: '');
  }

  static String? imgSource(Element image) {
    for (final String attribute in <String>[
      'data-src',
      'data-original',
      'data-lazy-src',
      'src',
    ]) {
      final String value = image.attributes[attribute]?.trim() ?? '';
      if (value.isNotEmpty && !value.contains('data:image')) return value;
    }
    for (final String attribute in <String>['srcset', 'data-srcset']) {
      final String value = image.attributes[attribute]?.trim() ?? '';
      if (value.isEmpty) continue;
      final String first = value.split(',').first.trim().split(' ').first;
      if (first.isNotEmpty && !first.contains('data:image')) return first;
    }
    return null;
  }

  /// Catalog / search listing page.
  static List<MoviePost> parsePosts(String html, String baseUrl) {
    final Document doc = html_parser.parse(html);
    for (final Element el in doc.querySelectorAll('script,style')) {
      el.remove();
    }

    final List<MoviePost> posts = <MoviePost>[];
    final Set<String> seen = <String>{};

    void addCard(Element anchor, Element? image) {
      final String href = anchor.attributes['href']?.trim() ?? '';
      final String link = resolveUrl(href, baseUrl);
      if (link.isEmpty || !link.startsWith('http')) return;
      if (link.toLowerCase().contains('/category/')) return;
      if (seen.contains(link)) return;

      final String title = collapse(
        image?.attributes['alt'] ??
            anchor.attributes['title'] ??
            anchor.text,
      );
      if (title.isEmpty) return;
      final String cleanedTitle = cleanTitleText(title);
      final String rawImage = image == null ? '' : (imgSource(image) ?? '');
      if (_isSiteChrome(
        link: link,
        rawTitle: title,
        cleanedTitle: cleanedTitle,
        imageSource: rawImage,
        baseUrl: baseUrl,
      )) {
        return;
      }

      final ({String primary, String fallback}) imageUrls =
          _imageUrls(rawImage, baseUrl);
      seen.add(link);

      final String cardContext = collapse(anchor.parent?.text ?? anchor.text);
      posts.add(
        MoviePost(
          title: cleanedTitle,
          link: link,
          imageUrl: imageUrls.primary,
          fallbackImageUrl: imageUrls.fallback,
          badge: _seasonRe.hasMatch('$title $cardContext') ? 'Series' : 'Movie',
          subtitle: RegExp(r'\b(19|20)\d{2}\b').firstMatch(cardContext)?.group(0) ??
              '',
          provider: MovieProvider.hdhub4u,
        ),
      );
    }

    final Element? recent = doc.querySelector('.recent-movies');
    if (recent != null) {
      for (final Element child in recent.children) {
        final Element? anchor = child.querySelector('a[href]');
        if (anchor == null) continue;
        final Element? image =
            child.querySelector('figure img') ?? child.querySelector('img');
        addCard(anchor, image);
      }
    }

    if (posts.isEmpty) {
      // Layout fallback: any card-like anchor that carries a poster.
      for (final Element anchor in doc.querySelectorAll('a[href]')) {
        final Element? image = anchor.querySelector('img');
        if (image == null) continue;
        final String href = anchor.attributes['href'] ?? '';
        if (!href.contains('/') || href.contains('/category/')) continue;
        addCard(anchor, image);
      }
    }

    return posts;
  }

  /// Response of the site's own search endpoint (Pingora / Typesense shape).
  static List<MoviePost> parseSearchJson(String body, String baseUrl) {
    final Object? decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) return const <MoviePost>[];
    final Object? hits = decoded['hits'];
    if (hits is! List) return const <MoviePost>[];

    final List<MoviePost> posts = <MoviePost>[];
    for (final Object? hit in hits) {
      if (hit is! Map) continue;
      final Object? document = hit['document'];
      if (document is! Map) continue;
      final String title = collapse(
        (document['post_title']?.toString() ?? '')
            .replaceAll(RegExp(r'\bDownload\b', caseSensitive: false), ' '),
      );
      final String permalink = document['permalink']?.toString() ?? '';
      if (title.isEmpty || permalink.isEmpty) continue;
      final String link = resolveUrl(permalink, baseUrl);
      if (link.isEmpty) continue;
      final ({String primary, String fallback}) imageUrls = _imageUrls(
        document['post_thumbnail']?.toString() ?? '',
        baseUrl,
      );
      final String year =
          RegExp(r'\b(19|20)\d{2}\b').firstMatch(title)?.group(0) ?? '';
      final String cleanedTitle = cleanTitleText(title);
      // A hit that is only the site's own name is not a title.
      if (cleanedTitle.trim().length < 2) continue;
      posts.add(
        MoviePost(
          title: cleanedTitle,
          link: link,
          imageUrl: imageUrls.primary,
          fallbackImageUrl: imageUrls.fallback,
          badge: _seasonRe.hasMatch(title) ? 'Series' : 'Movie',
          subtitle: year,
          provider: MovieProvider.hdhub4u,
        ),
      );
    }
    return posts;
  }

  /// Walks up from [anchor] looking for the narrowest row that names exactly
  /// one resolution — the nearest labelled row is the one that belongs to it.
  static String _rowQuality(Element anchor) {
    Element? row = anchor.parent;
    for (int depth = 0; depth < 4 && row != null; depth++) {
      final String text = collapse(row.text);
      final Set<String> found = <String>{};
      for (final RegExpMatch match in _qualityRe.allMatches(text)) {
        final String raw = (match.group(1) ?? '').toLowerCase();
        found.add(raw == '4k' ? '2160p' : raw);
      }
      if (found.length == 1) return found.first;
      if (found.length > 1) break;
      row = row.parent;
    }
    return '';
  }

  /// Every downloadable link on a title page, labelled with the resolution,
  /// episode and season context it sits under.
  static List<HdhubLinkSpec> parseLinks(
    String html, {
    required String pageUrl,
    required String baseUrl,
  }) {
    final Document doc = html_parser.parse(html);
    for (final Element el in doc.querySelectorAll('script,style')) {
      el.remove();
    }
    final Element container = doc.querySelector('.page-body') ??
        doc.querySelector('.entry-content') ??
        doc.body ??
        doc.documentElement!;

    final List<HdhubLinkSpec> specs = <HdhubLinkSpec>[];
    final Set<String> seenUrls = <String>{};

    String seasonLabel = extractSeasonLabel(collapse(container.text));
    String rowQuality = '';
    int rowEpisode = 0;

    void collect(Element anchor, String contextText) {
      final String href = anchor.attributes['href']?.trim() ?? '';
      if (href.isEmpty) return;
      final String url = resolveUrl(href, pageUrl);
      if (url.isEmpty) return;
      final bool resolvable =
          looksResolvable(url) || looksLikeSiteDownloadPage(url, baseUrl);
      if (!resolvable) return;
      if (seenUrls.contains(url)) return;

      final String ownText = collapse(anchor.text);
      final String rowText = collapse(anchor.parent?.text ?? '');
      final String blockText = collapse(anchor.parent?.parent?.text ?? '');
      final String merged = collapse('$contextText $ownText $rowText');
      final String widened = collapse('$merged $blockText');

      String resolution = extractResolution(ownText);
      if (resolution.isEmpty) resolution = extractResolution(rowText);
      // The nearest ancestor that names exactly one resolution is the most
      // trustworthy label; the running heading state is only a fallback.
      if (resolution.isEmpty) resolution = _rowQuality(anchor);
      if (resolution.isEmpty) resolution = rowQuality;
      if (resolution.isEmpty) resolution = extractResolution(widened);
      if (resolution.isEmpty) return;

      int episode = extractEpisodeNumber(ownText);
      if (episode <= 0) episode = extractEpisodeNumber(contextText);
      if (episode <= 0) episode = rowEpisode;

      String season = extractSeasonLabel(merged);
      if (season.isEmpty) season = extractSeasonLabel(widened);
      if (season.isEmpty) season = seasonLabel;

      String sizeLabel = extractSize(merged);
      if (sizeLabel.isEmpty) sizeLabel = extractSize(widened);
      String languages = extractLanguages(merged);
      if (languages.isEmpty) languages = extractLanguages(widened);
      String codec = extractCodec(merged);
      if (codec.isEmpty) codec = extractCodec(widened);

      seenUrls.add(url);
      specs.add(
        HdhubLinkSpec(
          url: url,
          label: scrubSourceNames(ownText),
          resolution: resolution,
          codec: codec,
          sizeLabel: sizeLabel,
          languages: languages,
          isZip: looksZip(url),
          seasonLabel: season,
          episodeLabel: episode > 0 ? 'Episode $episode' : '',
          episodeNumber: episode,
          isSeasonPack: episode <= 0,
        ),
      );
    }

    for (final Element el
        in container.querySelectorAll('h2,h3,h4,h5,h6,p,strong,a[href],li')) {
      final String text = collapse(el.text);
      if (text.isEmpty) continue;

      if (el.localName != 'a') {
        final String season = extractSeasonLabel(text);
        if (season.isNotEmpty) seasonLabel = season;
        if (RegExp(r'episode.*(?:links|index)|single episode',
                caseSensitive: false)
            .hasMatch(text)) {
          rowEpisode = 0;
          final String quality = extractResolution(text);
          if (quality.isNotEmpty) rowQuality = quality;
          continue;
        }
        final String qualityInText = extractResolution(text);
        if (qualityInText.isNotEmpty) rowQuality = qualityInText;
        final int episode = extractEpisodeNumber(text);
        if (episode > 0) {
          rowEpisode = episode;
        } else if (RegExp(
          r'complete|full season|season pack|storyline|review|description|'
          r'synopsis|screenshot',
          caseSensitive: false,
        ).hasMatch(text)) {
          // A new block: a pack link or the synopsis must not inherit the last
          // episode number seen above it.
          rowEpisode = 0;
        }
        continue;
      }

      if (el.children.isNotEmpty) {
        // A wrapper anchor that contains whole blocks would swallow every link
        // beneath it; the inner anchors are visited on their own.
        continue;
      }
      collect(el, text);
    }

    return specs;
  }

  /// Title page metadata plus its labelled links.
  static MovieDetail parseDetail({
    required String html,
    required String pageUrl,
    required String baseUrl,
    List<HdhubLinkSpec>? specs,
  }) {
    final Document doc = html_parser.parse(html);
    for (final Element el in doc.querySelectorAll('script,style')) {
      el.remove();
    }
    final String metaDescription =
        doc.querySelector('meta[name="description"]')?.attributes['content'] ??
            '';
    String rawTitle = collapse(
      doc.querySelector('h1.page-title .material-text')?.text ??
          doc.querySelector('h1.entry-title')?.text ??
          doc.querySelector('h1')?.text ??
          doc.querySelector('meta[property="og:title"]')?.attributes['content'] ??
          '',
    );
    rawTitle = rawTitle.replaceAll(RegExp('[\uE000-\uF8FF]'), ' ').trim();
    final String title = cleanTitleText(rawTitle);

    final Element? body = doc.body;
    final String bodyText = collapse(body?.text ?? '');
    final String poster = resolveUrl(
      doc.querySelector('meta[property="og:image"]')?.attributes['content'] ??
          _firstPoster(doc) ??
          '',
      baseUrl,
    );
    final String year =
        RegExp(r'\b(19|20)\d{2}\b').firstMatch('$rawTitle $bodyText')?.group(0) ??
            '';

    String synopsis = '';
    final Element? container = doc.querySelector('.page-body') ??
        doc.querySelector('.entry-content') ??
        body;
    if (container != null) {
      for (final Element paragraph in container.querySelectorAll('p')) {
        final String text = collapse(paragraph.text);
        if (text.length < 60) continue;
        if (RegExp(r'^(?:download|watch|click|join|telegram|note)\b',
                caseSensitive: false)
            .hasMatch(text)) {
          continue;
        }
        synopsis = text;
        break;
      }
    }
    if (synopsis.isEmpty) synopsis = collapse(metaDescription);
    synopsis = scrubSourceNames(synopsis);

    final String languages = extractLanguages(bodyText);
    final List<HdhubLinkSpec> links = specs ??
        parseLinks(html, pageUrl: pageUrl, baseUrl: baseUrl);
    final bool hasEpisodes =
        links.any((HdhubLinkSpec spec) => spec.episodeNumber > 0);
    final bool isSeries = hasEpisodes || _seasonRe.hasMatch(bodyText);

    final List<MovieQualityLink> directQualities = <MovieQualityLink>[];
    final List<MovieEpisodeGroup> groups = <MovieEpisodeGroup>[];

    if (!isSeries) {
      final Map<String, MovieQualityLink> byKey = <String, MovieQualityLink>{};
      for (final HdhubLinkSpec spec in links) {
        if (spec.episodeNumber > 0) continue;
        final String key = '${spec.resolution}|${spec.codec}';
        final MovieQualityLink link = _toQualityLink(spec);
        final MovieQualityLink? existing = byKey[key];
        if (existing == null || _preferMirror(link, existing)) {
          byKey[key] = link;
        }
      }
      directQualities.addAll(byKey.values);
      directQualities.sort(_byResolutionDesc);
    } else {
      groups.addAll(_buildSeriesGroups(links));
    }

    final Set<String> availableResolutions = <String>{
      for (final MovieQualityLink quality in directQualities) quality.resolution,
      for (final MovieEpisodeGroup group in groups)
        for (final MovieQualityLink quality in group.qualities)
          quality.resolution,
      for (final MovieEpisodeGroup group in groups)
        for (final MovieEpisodeGroup nested in group.nestedGroups)
          for (final MovieQualityLink quality in nested.qualities)
            quality.resolution,
    };

    return MovieDetail(
      title: title.isNotEmpty ? title : 'Untitled',
      cleanTitle: title.isNotEmpty ? title : 'Untitled',
      type: isSeries ? MovieMediaType.series : MovieMediaType.movie,
      webUrl: pageUrl,
      year: year,
      posterUrl: poster,
      backdropUrl: poster,
      languages: languages,
      languageList: languages.isEmpty
          ? const <String>[]
          : languages.split(',').map((String s) => s.trim()).toList(),
      qualityBadges: <String>[
        for (final String resolution in <String>['2160p', '1080p', '720p', '480p'])
          if (availableResolutions.contains(resolution)) resolution,
      ],
      synopsis: synopsis,
      defaultSeasonLabel: groups.isNotEmpty ? groups.first.seasonLabel : '',
      directQualities: directQualities,
      episodeGroups: groups,
      provider: MovieProvider.hdhub4u,
      rating: extractMovieRatingFromText(bodyText),
    );
  }

  static String? _firstPoster(Document doc) {
    for (final Element image in doc.querySelectorAll('img')) {
      final String src = imgSource(image) ?? '';
      final String lower = src.toLowerCase();
      if (src.isEmpty) continue;
      if (lower.contains('logo') || lower.contains('icon') || lower.contains('banner')) {
        continue;
      }
      return src;
    }
    return null;
  }

  static bool _preferMirror(MovieQualityLink candidate, MovieQualityLink existing) {
    final String a = candidate.dlUrl.toLowerCase();
    final String b = existing.dlUrl.toLowerCase();
    final bool candidateHubcloud = a.contains('hubcloud');
    final bool existingHubcloud = b.contains('hubcloud');
    if (candidateHubcloud && !existingHubcloud) return true;
    if (existingHubcloud && !candidateHubcloud) return false;
    return candidate.sizeLabel.isNotEmpty && existing.sizeLabel.isEmpty;
  }

  static int _byResolutionDesc(MovieQualityLink a, MovieQualityLink b) {
    final int ha = int.tryParse(
          RegExp(r'\d+').firstMatch(a.resolution)?.group(0) ?? '',
        ) ??
        0;
    final int hb = int.tryParse(
          RegExp(r'\d+').firstMatch(b.resolution)?.group(0) ?? '',
        ) ??
        0;
    return hb.compareTo(ha);
  }

  static MovieQualityLink _toQualityLink(HdhubLinkSpec spec) {
    final String envelope =
        '${spec.resolution}|${spec.codec}|${spec.languages}|${spec.url}';
    return MovieQualityLink(
      id: 'hdh_${stableId(envelope)}',
      rawLabel: spec.label.isNotEmpty ? spec.label : spec.resolution,
      resolution: spec.resolution,
      codec: spec.codec,
      sizeLabel: spec.sizeLabel,
      dlUrl: spec.url,
      languages: spec.languages,
      isZipPack: spec.isZip,
      seasonLabel: spec.seasonLabel,
      episodeLabel: spec.episodeLabel,
      provider: MovieProvider.hdhub4u,
    );
  }

  /// One group per season, one nested group per episode, and (when the page
  /// offers them) a complete-season pack group. Every group's quality list
  /// holds the resolutions of that single episode only, so the player's
  /// fallback ladder walks 480p → 720p → 1080p and never jumps to the next
  /// episode.
  static List<MovieEpisodeGroup> _buildSeriesGroups(
    List<HdhubLinkSpec> links,
  ) {
    final Map<String, List<HdhubLinkSpec>> episodes =
        <String, List<HdhubLinkSpec>>{};
    final Map<String, List<HdhubLinkSpec>> packs = <String, List<HdhubLinkSpec>>{};

    for (final HdhubLinkSpec spec in links) {
      final String season = spec.seasonLabel;
      if (spec.episodeNumber > 0) {
        final String key = '$season#${spec.episodeNumber}';
        episodes.putIfAbsent(key, () => <HdhubLinkSpec>[]).add(spec);
      } else {
        packs.putIfAbsent(season, () => <HdhubLinkSpec>[]).add(spec);
      }
    }

    final Map<String, List<MovieEpisodeGroup>> perSeason =
        <String, List<MovieEpisodeGroup>>{};

    final List<String> episodeKeys = episodes.keys.toList()
      ..sort((String a, String b) {
        final int sa = int.tryParse(
              RegExp(r'#(\d+)').firstMatch(a)?.group(1) ?? '',
            ) ??
            0;
        final int sb = int.tryParse(
              RegExp(r'#(\d+)').firstMatch(b)?.group(1) ?? '',
            ) ??
            0;
        return sa.compareTo(sb);
      });

    for (final String key in episodeKeys) {
      final List<HdhubLinkSpec> specs = episodes[key]!;
      if (specs.isEmpty) continue;
      final HdhubLinkSpec first = specs.first;
      final Map<String, MovieQualityLink> byResolution =
          <String, MovieQualityLink>{};
      for (final HdhubLinkSpec spec in specs) {
        final MovieQualityLink link = _toQualityLink(spec);
        final MovieQualityLink? existing = byResolution[spec.resolution];
        if (existing == null || _preferMirror(link, existing)) {
          byResolution[spec.resolution] = link;
        }
      }
      final List<MovieQualityLink> qualities = byResolution.values.toList()
        ..sort(_byResolutionDesc);
      perSeason
          .putIfAbsent(first.seasonLabel, () => <MovieEpisodeGroup>[])
          .add(
            MovieEpisodeGroup(
              id: 'hdh_${stableId('$key|group')}',
              title: first.episodeLabel,
              seasonLabel: first.seasonLabel,
              episodeLabel: first.episodeLabel,
              languages: first.languages,
              qualities: qualities,
              isLoaded: true,
              provider: MovieProvider.hdhub4u,
            ),
          );
    }

    final List<MovieEpisodeGroup> seasonGroups = <MovieEpisodeGroup>[];
    for (final MapEntry<String, List<MovieEpisodeGroup>> entry
        in perSeason.entries) {
      final String season = entry.key;
      final List<MovieEpisodeGroup> episodeGroups = entry.value;
      final List<MovieQualityLink> packQualities = <MovieQualityLink>[];
      for (final HdhubLinkSpec spec in packs[season] ?? const <HdhubLinkSpec>[]) {
        packQualities.add(_toQualityLink(spec));
      }
      packQualities.sort(_byResolutionDesc);
      if (packQualities.isNotEmpty) {
        episodeGroups.add(
          MovieEpisodeGroup(
            id: 'hdh_${stableId('$season|pack')}',
            title: season.isEmpty ? 'Complete Season Pack' : '$season Pack',
            seasonLabel: season,
            languages: packQualities.first.languages,
            isCompletePack: true,
            qualities: packQualities,
            isLoaded: true,
            provider: MovieProvider.hdhub4u,
          ),
        );
      }
      seasonGroups.add(
        MovieEpisodeGroup(
          id: 'hdh_${stableId('$season|season')}',
          title: season.isEmpty ? 'All Episodes' : season,
          seasonLabel: season,
          languages: episodeGroups.isEmpty ? '' : episodeGroups.first.languages,
          nestedGroups: episodeGroups,
          isLoaded: true,
          provider: MovieProvider.hdhub4u,
        ),
      );
    }

    // Season packs on a page that lists no per-episode links at all still have
    // to be reachable — keep them as their own groups.
    for (final MapEntry<String, List<HdhubLinkSpec>> entry in packs.entries) {
      if (perSeason.containsKey(entry.key)) continue;
      final List<MovieQualityLink> packQualities = <MovieQualityLink>[
        for (final HdhubLinkSpec spec in entry.value) _toQualityLink(spec),
      ]..sort(_byResolutionDesc);
      if (packQualities.isEmpty) continue;
      seasonGroups.add(
        MovieEpisodeGroup(
          id: 'hdh_${stableId('${entry.key}|pack-only')}',
          title: entry.key.isEmpty ? 'Complete Pack' : '${entry.key} Pack',
          seasonLabel: entry.key,
          isCompletePack: true,
          qualities: packQualities,
          isLoaded: true,
          provider: MovieProvider.hdhub4u,
        ),
      );
    }

    seasonGroups.sort((MovieEpisodeGroup a, MovieEpisodeGroup b) =>
        a.seasonLabel.compareTo(b.seasonLabel));
    return seasonGroups;
  }
}
