import 'package:youtube_explode_dart/youtube_explode_dart.dart';

enum TrackSource { ytMusic, youtube, localDevice }

enum QualityTier { high, normal }

QualityTier classifyQuality(String? type, String artist) =>
    type == 'MUSIC_VIDEO_TYPE_ATV' ||
        type == 'MUSIC_VIDEO_TYPE_OFFICIAL_SOURCE_MUSIC' ||
        RegExp(r'\s-\s?Topic$', caseSensitive: false).hasMatch(artist)
    ? QualityTier.high
    : QualityTier.normal;

/// A playable track. This is the app-wide currency between the YouTube backend
/// and every screen — nothing in the UI layer talks to `Video` directly.
class Song {
  const Song({
    required this.id,
    required this.title,
    required this.artist,
    required this.thumbnailUrl,
    this.duration,
    this.channelId,
    this.subtitle,
    this.artistId,
    this.album,
    this.albumId,
    this.musicVideoType,
    this.localUri,
    this.source = TrackSource.youtube,
    QualityTier? quality,
  }) : _quality = quality;

  final String? artistId, album, albumId, musicVideoType, localUri;
  final TrackSource source;
  final QualityTier? _quality;
  QualityTier get quality =>
      _quality ?? classifyQuality(musicVideoType, artist);
  String get videoId => id;
  String get artworkUrl => thumbnailUrl;
  int get durationSecs => duration?.inSeconds ?? 0;

  /// YouTube video id.
  final String id;
  final String title;
  final String artist;
  final String thumbnailUrl;
  final Duration? duration;

  /// YouTube channel id, when we know it (artist page deep links).
  final String? channelId;

  /// Optional extra line — album / playlist name on the site's "Recommended"
  /// rows.
  final String? subtitle;

  factory Song.fromVideo(Video video, {String? subtitle}) {
    return Song(
      id: video.id.value,
      title: video.title,
      artist: video.author,
      thumbnailUrl: video.thumbnails.highResUrl,
      duration: video.duration,
      channelId: video.channelId.value,
      subtitle: subtitle,
    );
  }

  Song copyWith({
    String? subtitle,
    Duration? duration,
    String? channelId,
    String? album,
    String? albumId,
    String? thumbnailUrl,
    String? localUri,
  }) {
    return Song(
      artistId: artistId,
      album: album ?? this.album,
      albumId: albumId ?? this.albumId,
      musicVideoType: musicVideoType,
      localUri: localUri ?? this.localUri,
      source: source,
      quality: quality,
      id: id,
      title: title,
      artist: artist,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      duration: duration ?? this.duration,
      channelId: channelId ?? this.channelId,
      subtitle: subtitle ?? this.subtitle,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'source': source.name,
    'quality': quality.name,
    'artistId': artistId,
    'album': album,
    'albumId': albumId,
    'musicVideoType': musicVideoType,
    'localUri': localUri,
    'id': id,
    'title': title,
    'artist': artist,
    'thumb': thumbnailUrl,
    if (duration != null) 'ms': duration!.inMilliseconds,
    if (channelId != null) 'channel': channelId,
    if (subtitle != null) 'sub': subtitle,
  };

  factory Song.fromJson(Map<String, dynamic> json) {
    final Object? ms = json['ms'];
    final Object? channel = json['channel'];
    final Object? sub = json['sub'];
    return Song(
      source: json['source'] == 'ytMusic'
          ? TrackSource.ytMusic
          : json['source'] == 'localDevice'
              ? TrackSource.localDevice
              : TrackSource.youtube,
      quality: json['quality'] == 'high'
          ? QualityTier.high
          : json['quality'] == 'normal'
          ? QualityTier.normal
          : null,
      artistId: json['artistId'] as String?,
      album: json['album'] as String?,
      albumId: json['albumId'] as String?,
      musicVideoType: json['musicVideoType'] as String?,
      localUri: json['localUri'] as String?,
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Unknown title',
      artist: json['artist'] as String? ?? 'Unknown artist',
      thumbnailUrl: json['thumb'] as String? ?? '',
      duration: ms is int ? Duration(milliseconds: ms) : null,
      channelId: channel is String ? channel : null,
      subtitle: sub is String ? sub : null,
    );
  }

  @override
  bool operator ==(Object other) => other is Song && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'Song($id · $title)';
}
