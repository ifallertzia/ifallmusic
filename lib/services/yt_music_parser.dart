import '../core/models/song.dart';

class MusicBrowseItem {
  const MusicBrowseItem(this.id, this.title, this.artwork, this.kind);
  final String id, title, artwork, kind;
}

class MusicSearchResult {
  const MusicSearchResult({
    this.tracks = const [],
    this.items = const [],
    this.continuation,
  });
  final List<Song> tracks;
  final List<MusicBrowseItem> items;
  final String? continuation;
}

/// Renderer traversal also supports cards and continuation responses. Never
/// classifies by translated shelf titles.
Iterable<Map<String, dynamic>> musicNodes(dynamic value) sync* {
  if (value is Map<String, dynamic>) {
    yield value;
    for (final child in value.values) {
      yield* musicNodes(child);
    }
  } else if (value is List) {
    for (final child in value) {
      yield* musicNodes(child);
    }
  }
}

String musicText(dynamic value) {
  if (value is! Map) return '';
  return value['simpleText'] as String? ??
      ((value['runs'] as List?) ?? []).map((r) => r['text'] ?? '').join();
}

String musicArtwork(dynamic value) {
  String url = '';
  for (final node in musicNodes(value)) {
    final thumbs = node['thumbnails'];
    if (thumbs is List && thumbs.isNotEmpty)
      url = thumbs.last['url'] as String? ?? '';
  }
  if (url.contains('googleusercontent.com')) {
    url = url.replaceFirst(RegExp(r'=w\d+[^?]*$'), '=w544-h544-l90-rj');
  }
  return url;
}

bool isTrackId(String id) => RegExp(r'^[A-Za-z0-9_-]{11}$').hasMatch(id);

MusicSearchResult parseMusicSearch(Map<String, dynamic> root) {
  final tracks = <Song>[];
  final items = <MusicBrowseItem>[];
  final seen = <String>{};
  String? continuation;
  for (final node in musicNodes(root)) {
    final next = node['nextContinuationData'];
    if (next is Map) continuation ??= next['continuation'] as String?;
    // Playlist/album shelves page through continuationItemRenderer rows.
    final cmd = node['continuationCommand'];
    if (cmd is Map) continuation ??= cmd['token'] as String?;
    final dynamic row =
        node['musicResponsiveListItemRenderer'] ??
        node['musicCardShelfRenderer'] ??
        node['musicTwoRowItemRenderer'];
    if (row is! Map<String, dynamic>) continue;
    final flex = row['flexColumns'] as List? ?? [];
    final title = flex.isNotEmpty
        ? musicText(
            flex.first['musicResponsiveListItemFlexColumnRenderer']?['text'],
          )
        : musicText(row['title']);
    String id = row['playlistItemData']?['videoId'] as String? ?? '';
    String? type;
    // Overlay/title endpoints only: don't mistake a nested card's song for its parent.
    for (final endpoint in musicNodes([
      row['overlay'],
      row['title'],
      row['navigationEndpoint'],
      if (flex.isNotEmpty) flex.first,
    ])) {
      final watch = endpoint['watchEndpoint'];
      if (watch is Map) {
        if (id.isEmpty) id = watch['videoId'] as String? ?? '';
        type ??=
            watch['watchEndpointMusicSupportedConfigs']?['watchEndpointMusicConfig']?['musicVideoType']
                as String?;
      }
    }
    final art = musicArtwork(row['thumbnail'] ?? row['thumbnailRenderer']);
    if (!isTrackId(id)) {
      final browse =
          row['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String? ??
          '';
      final kind = browse.startsWith('UC')
          ? 'artist'
          : browse.startsWith('MPREb') || browse.startsWith('OLAK5uy')
          ? 'album'
          : browse.startsWith('VL')
          ? 'playlist'
          : '';
      if (kind.isNotEmpty && seen.add(browse))
        items.add(MusicBrowseItem(browse, title, art, kind));
      continue;
    }
    if (title.isEmpty || !seen.add(id)) continue;
    final List runs = flex.length > 1
        ? (flex[1]['musicResponsiveListItemFlexColumnRenderer']?['text']?['runs']
                  as List? ??
              [])
        : (row['subtitle']?['runs'] as List? ?? []);
    final artists = <String>[];
    String? artistId, album, albumId;
    int seconds = 0;
    for (final run in runs) {
      final text = (run['text'] as String? ?? '').trim();
      final browse =
          run['navigationEndpoint']?['browseEndpoint']?['browseId']
              as String? ??
          '';
      if (browse.startsWith('UC')) {
        artists.add(text);
        artistId ??= browse;
      }
      if (browse.startsWith('MPREb') || browse.startsWith('OLAK5uy')) {
        album = text;
        albumId = browse;
      }
      if (RegExp(r'^\d+:\d{2}(:\d{2})?$').hasMatch(text)) {
        seconds = text.split(':').fold(0, (int n, s) => n * 60 + int.parse(s));
      }
    }
    // Duration may be in a fixed column rather than the artist flex column.
    for (final n in musicNodes(row['fixedColumns'])) {
      final text = n['text'];
      if (text is String && RegExp(r'^\d+:\d{2}(:\d{2})?$').hasMatch(text)) {
        seconds = text.split(':').fold(0, (int n, s) => n * 60 + int.parse(s));
      }
    }
    if (artists.isEmpty) {
      final parts = runs
          .map((r) => (r['text'] as String? ?? '').trim())
          .where(
            (s) =>
                s.isNotEmpty &&
                s != '•' &&
                !['Song', 'Video'].contains(s) &&
                !RegExp(r'^\d+:').hasMatch(s),
          );
      if (parts.isNotEmpty) artists.add(parts.first);
    }
    tracks.add(
      Song(
        id: id,
        title: title,
        artist: artists.join(', '),
        artistId: artistId,
        channelId: artistId,
        album: album,
        albumId: albumId,
        musicVideoType: type,
        source: TrackSource.ytMusic,
        thumbnailUrl: art.isEmpty
            ? 'https://i.ytimg.com/vi/$id/hqdefault.jpg'
            : art,
        duration: seconds > 0 ? Duration(seconds: seconds) : null,
      ),
    );
  }
  return MusicSearchResult(
    tracks: tracks,
    items: items,
    continuation: continuation,
  );
}

List<Song> mergeMusicResults(
  List<Song> songs,
  List<Song> all,
  List<Song> youtube,
) {
  final seen = <String>{};
  final List<Song> out = <Song>[];

  void add(Iterable<Song> source) {
    for (final Song s in source) {
      if (seen.add(s.id)) out.add(s);
    }
  }

  // YouTube-Music order: the real songs first, best sources ahead of weaker
  // ones. Everything else (albums, artists, videos) only follows once the
  // songs filter is exhausted, and the raw video fallback comes last.
  add(songs.where((Song s) => s.quality == QualityTier.high));
  add(songs.where((Song s) => s.quality != QualityTier.high));
  add(all.where((Song s) => s.quality == QualityTier.high));
  add(all.where((Song s) => s.quality != QualityTier.high));
  add(youtube);
  return out;
}

MusicSearchResult parseMusicRadio(Map<String, dynamic> root) {
  final tracks = <Song>[];
  final seen = <String>{};
  for (final node in musicNodes(root)) {
    final row = node['playlistPanelVideoRenderer'];
    if (row is! Map<String, dynamic>) continue;
    final id = row['videoId'] as String? ?? '';
    if (!isTrackId(id) || !seen.add(id)) continue;
    String? type;
    for (final endpoint in musicNodes(row['navigationEndpoint'])) {
      type ??= endpoint['musicVideoType'] as String?;
    }
    final durationText = musicText(row['lengthText']);
    final seconds = RegExp(r'^\d+:\d{2}(:\d{2})?$').hasMatch(durationText)
        ? durationText.split(':').fold(0, (int n, v) => n * 60 + int.parse(v))
        : 0;
    tracks.add(
      Song(
        id: id,
        title: musicText(row['title']),
        artist: musicText(row['longBylineText'] ?? row['shortBylineText']),
        thumbnailUrl: musicArtwork(row['thumbnail']),
        source: TrackSource.ytMusic,
        musicVideoType: type,
        duration: seconds > 0 ? Duration(seconds: seconds) : null,
      ),
    );
  }
  return MusicSearchResult(tracks: tracks);
}
