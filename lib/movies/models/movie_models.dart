import 'package:flutter/foundation.dart';

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
  });

  final String title;
  final String link;
  final String imageUrl;
  final String fallbackImageUrl;
  final String badge;
  final String subtitle;

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
    );
  }
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

  bool get isSeries => type == MovieMediaType.series;
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
    this.downloadedBytes = 0,
    this.totalBytes = 0,
    this.speedBytesPerSec = 0,
    this.errorMessage = '',
    this.completedAtMs = 0,
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
  final MovieDownloadStatus status;
  final int downloadedBytes;
  final int totalBytes;
  final double speedBytesPerSec;
  final String errorMessage;
  final int createdAtMs;
  final int completedAtMs;

  bool get isActive =>
      status == MovieDownloadStatus.resolving ||
      status == MovieDownloadStatus.queued ||
      status == MovieDownloadStatus.downloading;

  bool get isZip =>
      fileName.toLowerCase().endsWith('.zip') || mimeType.contains('zip');

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
    MovieDownloadStatus? status,
    int? downloadedBytes,
    int? totalBytes,
    double? speedBytesPerSec,
    String? errorMessage,
    int? createdAtMs,
    int? completedAtMs,
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
      status: status ?? this.status,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      speedBytesPerSec: speedBytesPerSec ?? this.speedBytesPerSec,
      errorMessage: errorMessage ?? this.errorMessage,
      createdAtMs: createdAtMs ?? this.createdAtMs,
      completedAtMs: completedAtMs ?? this.completedAtMs,
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
        'status': status.name,
        'downloadedBytes': downloadedBytes,
        'totalBytes': totalBytes,
        'errorMessage': errorMessage,
        'createdAtMs': createdAtMs,
        'completedAtMs': completedAtMs,
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
      status: parsedStatus,
      downloadedBytes: (json['downloadedBytes'] as num?)?.toInt() ?? 0,
      totalBytes: (json['totalBytes'] as num?)?.toInt() ?? 0,
      errorMessage: json['errorMessage']?.toString() ?? '',
      createdAtMs: (json['createdAtMs'] as num?)?.toInt() ?? 0,
      completedAtMs: (json['completedAtMs'] as num?)?.toInt() ?? 0,
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
