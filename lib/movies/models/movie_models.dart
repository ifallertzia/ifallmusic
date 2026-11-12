import 'package:flutter/foundation.dart';

import 'movie_provider.dart';

enum MovieMediaType { movie, series }

enum MovieCategory {
  recommended('', 'Recommended'),
  bollywood('bollywood', 'Bollywood'),
  hollywood('hollywood', 'Hollywood'),
  southIndian('tollywood', 'South Indian'),
  webSeries('series', 'Web Series'),
  anime('anime', 'Anime');

  const MovieCategory(this.slug, this.label);
  final String slug;
  final String label;
}

@immutable
class MoviePost {
  const MoviePost({
    required this.title,
    required this.link,
    required this.imageUrl,
    this.fallbackImageUrl = '',
    this.badge = '',
    this.subtitle = '',
    this.provider = MovieProvider.eonMovies,
  });

  final String title;
  final String link;
  final String imageUrl;
  final String fallbackImageUrl;
  final String badge;
  final String subtitle;

  /// Catalog this post came from — decides which service opens it.
  final MovieProvider provider;

  MoviePost copyWith({
    String? title,
    String? link,
    String? imageUrl,
    String? fallbackImageUrl,
    String? badge,
    String? subtitle,
    MovieProvider? provider,
  }) {
    return MoviePost(
      title: title ?? this.title,
      link: link ?? this.link,
      imageUrl: imageUrl ?? this.imageUrl,
      fallbackImageUrl: fallbackImageUrl ?? this.fallbackImageUrl,
      badge: badge ?? this.badge,
      subtitle: subtitle ?? this.subtitle,
      provider: provider ?? this.provider,
    );
  }

  bool get isSeries =>
      badge.toLowerCase().contains('series') ||
      RegExp(r'\b(?:season|episode|s0?\d+)\b', caseSensitive: false)
          .hasMatch('$title $subtitle');
}

@immutable
class MovieQualityLink {
  const MovieQualityLink({
    required this.id,
    required this.rawLabel,
    required this.resolution,
    required this.dlUrl,
    this.codec = '',
    this.sizeLabel = '',
    this.languages = '',
    this.isZipPack = false,
    this.seasonLabel = '',
    this.episodeLabel = '',
    this.zipEntryName = '',
    this.provider = MovieProvider.eonMovies,
  });

  final String id;
  final String rawLabel;
  final String resolution;
  final String codec;
  final String sizeLabel;
  final String dlUrl;
  final String languages;
  final bool isZipPack;
  final String seasonLabel;
  final String episodeLabel;

  /// When non-empty, this link does not download [dlUrl]'s whole file.
  /// Instead it downloads only this single episode entry from inside the
  /// season ZIP pack that [dlUrl] resolves to (HTTP Range + local extract),
  /// so one episode can be fetched without pulling the complete season ZIP.
  final String zipEntryName;

  bool get isZipEntryEpisode => zipEntryName.isNotEmpty;

  /// Catalog that owns [dlUrl] — the resolver is picked from this.
  final MovieProvider provider;

  String get displayQuality {
    if (codec.isNotEmpty &&
        !resolution.toUpperCase().contains(codec.toUpperCase())) {
      return '$resolution $codec'.trim();
    }
    return resolution.isNotEmpty ? resolution : rawLabel;
  }

  MovieQualityLink copyWith({
    String? id,
    String? rawLabel,
    String? resolution,
    String? codec,
    String? sizeLabel,
    String? dlUrl,
    String? languages,
    bool? isZipPack,
    String? seasonLabel,
    String? episodeLabel,
    String? zipEntryName,
    MovieProvider? provider,
  }) {
    return MovieQualityLink(
      id: id ?? this.id,
      rawLabel: rawLabel ?? this.rawLabel,
      resolution: resolution ?? this.resolution,
      codec: codec ?? this.codec,
      sizeLabel: sizeLabel ?? this.sizeLabel,
      dlUrl: dlUrl ?? this.dlUrl,
      languages: languages ?? this.languages,
      isZipPack: isZipPack ?? this.isZipPack,
      seasonLabel: seasonLabel ?? this.seasonLabel,
      episodeLabel: episodeLabel ?? this.episodeLabel,
      zipEntryName: zipEntryName ?? this.zipEntryName,
      provider: provider ?? this.provider,
    );
  }
}

/// One episode video file found inside a season ZIP pack by reading only the
/// ZIP central directory over HTTP Range requests — the ZIP itself has not
/// been downloaded at this point.
@immutable
class MovieZipEpisode {
  const MovieZipEpisode({
    required this.index,
    required this.entryName,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.compressionMethod,
    required this.localHeaderOffset,
    this.dataOffset = -1,
    this.seasonNumber = 0,
    this.episodeNumber = 0,
    this.isEncrypted = false,
  });

  /// Position of this entry in the pack's episode listing (stable per file).
  final int index;

  /// Full path of the file inside the ZIP, exactly as stored in the archive.
  final String entryName;
  final int compressedSize;
  final int uncompressedSize;

  /// ZIP compression method: 0 = stored, 8 = deflate.
  final int compressionMethod;
  final int localHeaderOffset;

  /// Absolute byte offset where this entry's (compressed) data starts in the
  /// remote ZIP file. -1 until resolved for a concrete download.
  final int dataOffset;
  final int seasonNumber;
  final int episodeNumber;
  final bool isEncrypted;

  String get fileName {
    final String flat = entryName.replaceAll('\\', '/');
    final int slash = flat.lastIndexOf('/');
    return slash >= 0 ? flat.substring(slash + 1) : flat;
  }

  String get seasonLabel => seasonNumber > 0 ? 'Season $seasonNumber' : '';

  String get episodeLabel =>
      episodeNumber > 0 ? 'Episode $episodeNumber' : '';

  String get sizeLabel => MovieByteFmt.bytes(uncompressedSize);

  bool get isSupported =>
      !isEncrypted && (compressionMethod == 0 || compressionMethod == 8);

  MovieZipEpisode copyWith({int? dataOffset}) {
    return MovieZipEpisode(
      index: index,
      entryName: entryName,
      compressedSize: compressedSize,
      uncompressedSize: uncompressedSize,
      compressionMethod: compressionMethod,
      localHeaderOffset: localHeaderOffset,
      dataOffset: dataOffset ?? this.dataOffset,
      seasonNumber: seasonNumber,
      episodeNumber: episodeNumber,
      isEncrypted: isEncrypted,
    );
  }
}

/// Episode listing of one season ZIP pack, probed on a concrete mirror.
@immutable
class MovieZipPackListing {
  const MovieZipPackListing({
    required this.zipFileName,
    required this.totalBytes,
    required this.candidate,
    required this.episodes,
  });

  final String zipFileName;
  final int totalBytes;

  /// Mirror on which the ZIP layout was probed. Entry offsets are only
  /// guaranteed to be valid for this mirror's copy of the file.
  final MovieStreamCandidate candidate;
  final List<MovieZipEpisode> episodes;
}

@immutable
class MovieEpisodeGroup {
  const MovieEpisodeGroup({
    required this.id,
    required this.title,
    this.seasonLabel = '',
    this.episodeLabel = '',
    this.languages = '',
    this.subPageDlUrl = '',
    this.isCompletePack = false,
    this.qualities = const <MovieQualityLink>[],
    this.nestedGroups = const <MovieEpisodeGroup>[],
    this.isLoaded = false,
    this.provider = MovieProvider.eonMovies,
  });

  final String id;
  final String title;
  final String seasonLabel;
  final String episodeLabel;
  final String languages;
  final String subPageDlUrl;
  final bool isCompletePack;
  final List<MovieQualityLink> qualities;
  final List<MovieEpisodeGroup> nestedGroups;
  final bool isLoaded;

  /// Catalog this season / episode listing belongs to.
  final MovieProvider provider;

  String get fullHeading {
    if (seasonLabel.isNotEmpty && episodeLabel.isNotEmpty) {
      return '$seasonLabel • $episodeLabel';
    }
    if (seasonLabel.isNotEmpty && isCompletePack) {
      return '$seasonLabel • Complete Pack (ZIP)';
    }
    return title;
  }

  MovieEpisodeGroup copyWith({
    String? id,
    String? title,
    String? seasonLabel,
    String? episodeLabel,
    String? languages,
    String? subPageDlUrl,
    bool? isCompletePack,
    List<MovieQualityLink>? qualities,
    List<MovieEpisodeGroup>? nestedGroups,
    bool? isLoaded,
    MovieProvider? provider,
  }) {
    return MovieEpisodeGroup(
      id: id ?? this.id,
      title: title ?? this.title,
      seasonLabel: seasonLabel ?? this.seasonLabel,
      episodeLabel: episodeLabel ?? this.episodeLabel,
      languages: languages ?? this.languages,
      subPageDlUrl: subPageDlUrl ?? this.subPageDlUrl,
      isCompletePack: isCompletePack ?? this.isCompletePack,
      qualities: qualities ?? this.qualities,
      nestedGroups: nestedGroups ?? this.nestedGroups,
      isLoaded: isLoaded ?? this.isLoaded,
      provider: provider ?? this.provider,
    );
  }
}

@immutable
class MovieDetail {
  const MovieDetail({
    required this.title,
    required this.cleanTitle,
    required this.type,
    required this.webUrl,
    this.year = '',
    this.releaseDate = '',
    this.backdropUrl = '',
    this.fallbackBackdropUrl = '',
    this.posterUrl = '',
    this.fallbackPosterUrl = '',
    this.languages = '',
    this.languageList = const <String>[],
    this.genres = const <String>[],
    this.director = '',
    this.qualityBadges = const <String>[],
    this.synopsis = '',
    this.defaultSeasonLabel = '',
    this.directQualities = const <MovieQualityLink>[],
    this.episodeGroups = const <MovieEpisodeGroup>[],
    this.relatedPosts = const <MoviePost>[],
    this.provider = MovieProvider.eonMovies,
    this.rating = '',
  });

  final String title;
  final String cleanTitle;
  final MovieMediaType type;
  final String webUrl;
  final String year;
  final String releaseDate;
  final String backdropUrl;
  final String fallbackBackdropUrl;
  final String posterUrl;
  final String fallbackPosterUrl;
  final String languages;
  final List<String> languageList;
  final List<String> genres;
  final String director;
  final List<String> qualityBadges;
  final String synopsis;
  final String defaultSeasonLabel;
  final List<MovieQualityLink> directQualities;
  final List<MovieEpisodeGroup> episodeGroups;
  final List<MoviePost> relatedPosts;

  /// Catalog that served this title.
  final MovieProvider provider;

  /// The score the title's own page states ("7.4"), out of ten. Empty when
  /// the page does not state one — a rating is never made up.
  final String rating;

  bool get isSeries => type == MovieMediaType.series;

  MovieDetail copyWith({
    String? title,
    String? cleanTitle,
    MovieMediaType? type,
    String? webUrl,
    String? year,
    String? releaseDate,
    String? backdropUrl,
    String? fallbackBackdropUrl,
    String? posterUrl,
    String? fallbackPosterUrl,
    String? languages,
    List<String>? languageList,
    List<String>? genres,
    String? director,
    List<String>? qualityBadges,
    String? synopsis,
    String? defaultSeasonLabel,
    List<MovieQualityLink>? directQualities,
    List<MovieEpisodeGroup>? episodeGroups,
    List<MoviePost>? relatedPosts,
    MovieProvider? provider,
    String? rating,
  }) {
    return MovieDetail(
      title: title ?? this.title,
      cleanTitle: cleanTitle ?? this.cleanTitle,
      type: type ?? this.type,
      webUrl: webUrl ?? this.webUrl,
      year: year ?? this.year,
      releaseDate: releaseDate ?? this.releaseDate,
      backdropUrl: backdropUrl ?? this.backdropUrl,
      fallbackBackdropUrl: fallbackBackdropUrl ?? this.fallbackBackdropUrl,
      posterUrl: posterUrl ?? this.posterUrl,
      fallbackPosterUrl: fallbackPosterUrl ?? this.fallbackPosterUrl,
      languages: languages ?? this.languages,
      languageList: languageList ?? this.languageList,
      genres: genres ?? this.genres,
      director: director ?? this.director,
      qualityBadges: qualityBadges ?? this.qualityBadges,
      synopsis: synopsis ?? this.synopsis,
      defaultSeasonLabel: defaultSeasonLabel ?? this.defaultSeasonLabel,
      directQualities: directQualities ?? this.directQualities,
      episodeGroups: episodeGroups ?? this.episodeGroups,
      relatedPosts: relatedPosts ?? this.relatedPosts,
      provider: provider ?? this.provider,
      rating: rating ?? this.rating,
    );
  }
}

@immutable
class MovieStreamCandidate {
  const MovieStreamCandidate({
    required this.server,
    required this.url,
    this.headers = const <String, String>{},
    this.isZip = false,
  });

  final String server;
  final String url;
  final Map<String, String> headers;
  final bool isZip;
}

@immutable
class ResolvedMovieStream {
  const ResolvedMovieStream({
    required this.candidates,
    this.filename = '',
    this.sizeLabel = '',
    this.mimeType = 'video/x-matroska',
    this.sharePageUrl = '',
  });

  final List<MovieStreamCandidate> candidates;
  final String filename;
  final String sizeLabel;
  final String mimeType;
  final String sharePageUrl;
}

enum MovieDownloadStatus {
  resolving,
  queued,
  downloading,
  paused,
  completed,
  failed,
  canceled,
}

@immutable
class MovieDownloadItem {
  const MovieDownloadItem({
    required this.id,
    required this.movieTitle,
    required this.qualityLabel,
    required this.sourceDlUrl,
    required this.status,
    required this.createdAtMs,
    this.posterUrl = '',
    this.isSeries = false,
    this.seasonLabel = '',
    this.episodeLabel = '',
    this.languages = '',
    this.sizeLabel = '',
    this.fileName = '',
    this.savedPath = '',
    this.publicUri = '',
    this.mimeType = 'video/x-matroska',
    this.activeServer = '',
    this.sharePageUrl = '',
    this.zipEntryName = '',
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0,
    this.errorMessage = '',
    this.completedAtMs = 0,
    this.provider = MovieProvider.eonMovies,
    this.attempts = 0,
  });

  final String id;
  final String movieTitle;
  final String posterUrl;
  final bool isSeries;
  final String seasonLabel;
  final String episodeLabel;
  final String qualityLabel;
  final String languages;
  final String sizeLabel;
  final String sourceDlUrl;
  final String fileName;
  final String savedPath;
  final String publicUri;
  final String mimeType;
  final String activeServer;
  final String sharePageUrl;

  /// For episode-wise downloads from a season ZIP pack: the single episode
  /// file to extract out of the pack [sourceDlUrl] resolves to. Empty for
  /// normal whole-file downloads (movies, per-episode files, full ZIPs).
  final String zipEntryName;
  final MovieDownloadStatus status;
  final int downloadedBytes;
  final int totalBytes;
  final double speedBytesPerSec;
  final String errorMessage;
  final int createdAtMs;
  final int completedAtMs;

  /// Catalog the [sourceDlUrl] came from — resume/retry resolves through it.
  final MovieProvider provider;

  /// How many automatic attempts this download has already used. Persisted so
  /// a download that keeps failing does not retry forever.
  final int attempts;

  bool get isActive =>
      status == MovieDownloadStatus.resolving ||
      status == MovieDownloadStatus.queued ||
      status == MovieDownloadStatus.downloading;

  bool get isZip =>
      fileName.toLowerCase().endsWith('.zip') || mimeType.contains('zip');

  bool get isZipEntryEpisode => zipEntryName.isNotEmpty;

  double get progress {
    if (status == MovieDownloadStatus.completed) return 1.0;
    if (totalBytes <= 0 || downloadedBytes <= 0) return 0.0;
    return (downloadedBytes / totalBytes).clamp(0.0, 1.0);
  }

  String get subtitleSummary {
    final List<String> parts = <String>[
      if (seasonLabel.isNotEmpty) seasonLabel,
      if (episodeLabel.isNotEmpty) episodeLabel,
      if (qualityLabel.isNotEmpty) qualityLabel,
      if (languages.isNotEmpty) languages,
    ];
    return parts.join(' • ');
  }

  MovieDownloadItem copyWith({
    String? movieTitle,
    String? posterUrl,
    bool? isSeries,
    String? seasonLabel,
    String? episodeLabel,
    String? qualityLabel,
    String? languages,
    String? sizeLabel,
    String? sourceDlUrl,
    String? fileName,
    String? savedPath,
    String? publicUri,
    String? mimeType,
    String? activeServer,
    String? sharePageUrl,
    String? zipEntryName,
    MovieDownloadStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    double? speedBytesPerSec,
    String? errorMessage,
    int? createdAtMs,
    int? completedAtMs,
    MovieProvider? provider,
    int? attempts,
  }) {
    return MovieDownloadItem(
      id: id,
      movieTitle: movieTitle ?? this.movieTitle,
      posterUrl: posterUrl ?? this.posterUrl,
      isSeries: isSeries ?? this.isSeries,
      seasonLabel: seasonLabel ?? this.seasonLabel,
      episodeLabel: episodeLabel ?? this.episodeLabel,
      qualityLabel: qualityLabel ?? this.qualityLabel,
      languages: languages ?? this.languages,
      sizeLabel: sizeLabel ?? this.sizeLabel,
      sourceDlUrl: sourceDlUrl ?? this.sourceDlUrl,
      fileName: fileName ?? this.fileName,
      savedPath: savedPath ?? this.savedPath,
      publicUri: publicUri ?? this.publicUri,
      mimeType: mimeType ?? this.mimeType,
      activeServer: activeServer ?? this.activeServer,
      sharePageUrl: sharePageUrl ?? this.sharePageUrl,
      zipEntryName: zipEntryName ?? this.zipEntryName,
      status: status ?? this.status,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      completedAtMs: completedAtMs ?? this.completedAtMs,
      provider: provider ?? this.provider,
      attempts: attempts ?? this.attempts,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'movieTitle': movieTitle,
        'posterUrl': posterUrl,
        'isSeries': isSeries,
        'seasonLabel': seasonLabel,
        'episodeLabel': episodeLabel,
        'qualityLabel': qualityLabel,
        'languages': languages,
        'sizeLabel': sizeLabel,
        'sourceDlUrl': sourceDlUrl,
        'fileName': fileName,
        'savedPath': savedPath,
        'publicUri': publicUri,
        'mimeType': mimeType,
        'activeServer': activeServer,
        'sharePageUrl': sharePageUrl,
        'zipEntryName': zipEntryName,
        'status': status.name,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        'errorMessage': errorMessage,
        'createdAtMs': createdAtMs,
        'completedAtMs': completedAtMs,
        'provider': provider.id,
        'attempts': attempts,
      };

  factory MovieDownloadItem.fromJson(Map<String, dynamic> json) {
    final String statusName = json['status']?.toString() ?? 'failed';
    MovieDownloadStatus parsedStatus = MovieDownloadStatus.values.firstWhere(
      (MovieDownloadStatus s) => s.name == statusName,
      orElse: () => MovieDownloadStatus.failed,
    );
    // Any download interrupted by process exit becomes resumable `paused`.
    if (parsedStatus == MovieDownloadStatus.downloading ||
        parsedStatus == MovieDownloadStatus.resolving ||
        parsedStatus == MovieDownloadStatus.queued) {
      parsedStatus = MovieDownloadStatus.paused;
    }
    return MovieDownloadItem(
      id: json['id']?.toString() ?? '',
      movieTitle: json['movieTitle']?.toString() ?? 'Unknown Title',
      posterUrl: json['posterUrl']?.toString() ?? '',
      isSeries: json['isSeries'] == true,
      seasonLabel: json['seasonLabel']?.toString() ?? '',
      episodeLabel: json['episodeLabel']?.toString() ?? '',
      qualityLabel: json['qualityLabel']?.toString() ?? '',
      languages: json['languages']?.toString() ?? '',
      sizeLabel: json['sizeLabel']?.toString() ?? '',
      sourceDlUrl: json['sourceDlUrl']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? '',
      savedPath: json['savedPath']?.toString() ?? '',
      publicUri: json['publicUri']?.toString() ?? '',
      mimeType: json['mimeType']?.toString() ?? 'video/x-matroska',
      activeServer: json['activeServer']?.toString() ?? '',
      sharePageUrl: json['sharePageUrl']?.toString() ?? '',
      zipEntryName: json['zipEntryName']?.toString() ?? '',
      status: parsedStatus,
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      errorMessage: json['errorMessage']?.toString() ?? '',
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      completedAtMs: (json['completedAtMs'] as num?)?.toInt() ?? 0,
      provider: MovieProvider.fromId(json['provider']),
      attempts: (json['attempts'] as num?)?.toInt() ?? 0,
    );
  }
}

abstract final class MovieByteFmt {
  static String bytes(int value) {
    if (value <= 0) return '0 B';
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double size = value.toDouble();
    int idx = 0;
    while (size >= 1024 && idx < units.length - 1) {
      size /= 1024;
      idx++;
    }
    final int decimals = idx >= 3 ? 2 : (idx >= 2 ? 1 : 0);
    return '${size.toStringAsFixed(decimals)} ${units[idx]}';
  }

  static String speed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '';
    return '${bytes(bytesPerSec.round())}/s';
  }
}
