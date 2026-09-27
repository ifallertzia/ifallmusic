import '../models/song.dart';
import '../../services/lyrics_query.dart';

/// Only automatic radio deduplicates recordings. Explicit albums/playlists keep
/// their order, even when the listener deliberately included alternate versions.
String recordingKey(Song song) {
  var title = cleanTitle(song.title)
      .split(RegExp(r'\s*[|•]\s*'))
      .first
      .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ');
  final dash = title.split(RegExp(r'\s+[-–—]\s+'));
  if (dash.length > 1) {
    final artist = normalize(cleanArtist(song.artist));
    title = artist.contains(normalize(dash.first)) ? dash[1] : dash.first;
  }
  title = title.replaceAll(
    RegExp(
      r'\b(slowed|slowed down|reverb|remix|remastered|sped up|speed up|nightcore|lofi|lo-fi|acoustic|instrumental|karaoke|cover|live|full song|full|song|version|original|extended|mix)\b',
      caseSensitive: false,
    ),
    ' ',
  );
  return normalize(title);
}

bool sameRecording(Song a, Song b) {
  if (a.id == b.id) return true;
  final x = recordingKey(a), y = recordingKey(b);
  if (x.isEmpty || y.isEmpty) return false;
  if (x == y) return true;
  final short = x.length < y.length ? x : y;
  final long = x.length < y.length ? y : x;
  // Handles video titles with trailing singer/film metadata, without treating
  // single short words such as "Hi" as the identity of an entire song.
  return short.length >= 5 && (' $long ').contains(' $short ');
}

List<Song> radioCandidates(
  Song anchor,
  Iterable<Song> candidates, {
  Iterable<Song> history = const [],
  Set<String> excludedIds = const {},
  int limit = 12,
}) {
  final seen = <Song>[anchor, ...history];
  final result = <Song>[];
  for (final song in candidates) {
    if (excludedIds.contains(song.id) ||
        seen.any((s) => sameRecording(s, song)))
      continue;
    result.add(song);
    seen.add(song);
    if (result.length >= limit) break;
  }
  return result;
}

/// Completion and error callbacks can both arrive repeatedly for one source.
/// Claim once and invalidate old work when the user chooses another track.
class PlaybackEpoch {
  int value = 0;
  int _ready = -1, _completed = -1, _failed = -1;
  int begin() {
    _ready = -1;
    return ++value;
  }

  bool current(int epoch) => epoch == value;
  void ready(int epoch) {
    if (current(epoch)) _ready = epoch;
  }

  bool complete() {
    if (_ready != value || _completed == value || _failed == value)
      return false;
    _completed = value;
    return true;
  }

  bool fail(int epoch) {
    if (!current(epoch) || _failed == epoch) return false;
    _failed = epoch;
    _ready = -1;
    return true;
  }
}
