import 'dart:math' as math;

import '../models/song.dart';
import 'radio_queue.dart';

/// One track in the listener's vibe memory: what it was, and how strongly it
/// counts (a full listen, a like, a skip that never made it).
class VibeTrack {
  const VibeTrack({
    required this.id,
    required this.title,
    required this.artist,
    this.weight = 1,
  });

  final String id;
  final String title;
  final String artist;

  /// +1 played through · +0.6 history from an earlier session · +1.6 liked
  /// · −0.7 skipped almost immediately.
  final double weight;
}

/// The rolling "what does this person actually like right now" memory.
///
/// It is deliberately tiny and local: the last handful of tracks, what was
/// skipped, what was loved, and the pairs that followed each other in earlier
/// sessions (a Markov-ish co-play graph). No AI model, no network — but it is
/// what turns "search the artist and hope" into a queue that keeps the vibe
/// going, the way the big services do it with embeddings.
class VibeMemory {
  VibeMemory({int capacity = 60}) : _capacity = capacity;

  final int _capacity;
  final List<VibeTrack> _affinity = <VibeTrack>[];
  final List<String> _played = <String>[];

  /// song id → the tracks that historically followed it here.
  final Map<String, Map<String, int>> _transitions =
      <String, Map<String, int>>{};

  final Set<String> _skipped = <String>{};
  final Set<String> _liked = <String>{};

  VibeProfile? _profile;

  /// Ids that must not come back in the next few tracks.
  List<String> get recentIds => List<String>.unmodifiable(_played);

  void notePlay(Song song) {
    _affinity.insert(
      0,
      VibeTrack(id: song.id, title: song.title, artist: song.artist),
    );
    _bounded();
    _played.remove(song.id);
    _played.insert(0, song.id);
    while (_played.length > 200) {
      _played.removeLast();
    }
    _profile = null;
  }

  /// Remember that [song] came right after the previous track.
  void noteTransition(String previousId, Song song) {
    if (previousId.isEmpty || previousId == song.id) return;
    final Map<String, int> edges =
        _transitions.putIfAbsent(previousId, () => <String, int>{});
    edges[song.id] = (edges[song.id] ?? 0) + 1;
    _profile = null;
  }

  void noteSkip(Song song) {
    _skipped.add(song.id);
    _affinity.insert(
      0,
      VibeTrack(
        id: song.id,
        title: song.title,
        artist: song.artist,
        weight: -0.7,
      ),
    );
    _bounded();
    _profile = null;
  }

  void noteLike(Song song) {
    _liked.add(song.id);
    _affinity.insert(
      0,
      VibeTrack(
        id: song.id,
        title: song.title,
        artist: song.artist,
        weight: 1.6,
      ),
    );
    _bounded();
    _profile = null;
  }

  /// A like taken back: drop the weight it added.
  void noteUnlike(Song song) {
    _liked.remove(song.id);
    for (int i = 0; i < _affinity.length; i++) {
      final VibeTrack track = _affinity[i];
      if (track.id != song.id || track.weight <= 0) continue;
      _affinity.removeAt(i);
      break;
    }
    _profile = null;
  }

  /// Older sessions (the play history stored on the device) enter with a
  /// lighter weight, so what is playing *now* still leads.
  void seedHistory(Iterable<VibeTrack> history) {
    for (final VibeTrack track in history) {
      if (track.id.isEmpty) continue;
      _affinity.add(
        VibeTrack(
          id: track.id,
          title: track.title,
          artist: track.artist,
          weight: track.weight * 0.6,
        ),
      );
    }
    _bounded();
    _profile = null;
  }

  void seedTransitions(Map<String, Map<String, int>> edges) {
    for (final MapEntry<String, Map<String, int>> entry in edges.entries) {
      final Map<String, int> target =
          _transitions.putIfAbsent(entry.key, () => <String, int>{});
      entry.value.forEach((String id, int count) {
        target[id] = (target[id] ?? 0) + count;
      });
    }
    _profile = null;
  }

  void clear() {
    _affinity.clear();
    _played.clear();
    _transitions.clear();
    _skipped.clear();
    _liked.clear();
    _profile = null;
  }

  void _bounded() {
    if (_affinity.length > _capacity) {
      _affinity.removeRange(_capacity, _affinity.length);
    }
  }

  /// Immutable snapshot used for scoring (cached until something changes).
  VibeProfile get profile => _profile ??= VibeProfile.from(
        history: _affinity,
        playedIds: _played,
        skippedIds: _skipped,
        likedIds: _liked,
        transitions: _transitions,
      );
}

/// A frozen view of the vibe memory: artist weights, title-word weights and
/// the sets needed to filter. Everything is pre-normalised, so scoring a
/// candidate is a handful of map lookups.
class VibeProfile {
  VibeProfile({
    required this.artistWeights,
    required this.tokenWeights,
    required this.playedIds,
    required this.skippedIds,
    required this.likedIds,
    required this.transitions,
  });

  final Map<String, double> artistWeights;
  final Map<String, double> tokenWeights;
  final Set<String> playedIds;
  final Set<String> skippedIds;
  final Set<String> likedIds;
  final Map<String, Map<String, int>> transitions;

  bool get isEmpty =>
      artistWeights.isEmpty && tokenWeights.isEmpty && likedIds.isEmpty;

  factory VibeProfile.from({
    required List<VibeTrack> history,
    required List<String> playedIds,
    required Set<String> skippedIds,
    required Set<String> likedIds,
    required Map<String, Map<String, int>> transitions,
  }) {
    final Map<String, double> artists = <String, double>{};
    final Map<String, double> tokens = <String, double>{};
    // Newest first and decayed, so last night's binge does not outvote today.
    for (int i = 0; i < history.length; i++) {
      final VibeTrack track = history[i];
      final double decay = math.pow(0.97, i).toDouble();
      final double weight = track.weight * decay;
      final String artist = artistKey(track.artist);
      if (artist.isNotEmpty && weight > 0) {
        artists[artist] = (artists[artist] ?? 0) + weight;
      }
      for (final String token in titleTokens(track.title)) {
        tokens[token] = (tokens[token] ?? 0) + weight;
      }
    }
    return VibeProfile(
      artistWeights: artists,
      tokenWeights: tokens,
      playedIds: Set<String>.unmodifiable(playedIds),
      skippedIds: Set<String>.unmodifiable(skippedIds),
      likedIds: Set<String>.unmodifiable(likedIds),
      transitions: transitions,
    );
  }

  double get artistCeiling {
    double top = 0;
    for (final double w in artistWeights.values) {
      if (w > top) top = w;
    }
    return top;
  }

  /// How much this candidate's artist is part of the current vibe (0…1).
  double artistAffinity(String artist) {
    final double ceiling = artistCeiling;
    if (ceiling <= 0) return 0;
    final String key = artistKey(artist);
    if (key.isEmpty) return 0;
    final double exact = artistWeights[key] ?? 0;
    if (exact > 0) return (exact / ceiling).clamp(0.0, 1.0);
    // "Arijit Singh, Shreya Ghoshal" should still match "Arijit Singh".
    double best = 0;
    for (final String other in _artistMentions(artist)) {
      final double hit = artistWeights[other] ?? 0;
      if (hit > best) best = hit;
    }
    return (best / ceiling).clamp(0.0, 1.0);
  }

  /// How much of this candidate's title the listener has been enjoying
  /// (0…1) — the word-overlap side of an embedding, without the model.
  double titleAffinity(String title) {
    if (tokenWeights.isEmpty) return 0;
    final Set<String> tokens = titleTokens(title);
    if (tokens.isEmpty) return 0;
    double hits = 0;
    for (final String token in tokens) {
      hits += tokenWeights[token] ?? 0;
    }
    if (hits <= 0) return 0;
    return (hits / tokens.length / 2.2).clamp(0.0, 1.0);
  }

  /// Session-graph boost: did this exact track follow the anchor before?
  double transitionAffinity(String anchorId, String candidateId) {
    final Map<String, int>? edges = transitions[anchorId];
    if (edges == null) return 0;
    final int count = edges[candidateId] ?? 0;
    if (count <= 0) return 0;
    return math.min(1.0, 0.5 + 0.25 * (count - 1));
  }
}

/// Ranks a pool of candidates the way a listener hears a good queue: first
/// what matches the vibe, then each following track close to the one before
/// it — never a lurch from a 3-minute ghazal into a 7-minute club remix.
class VibeRanker {
  const VibeRanker._();

  // Weights. Artist + title carry the identity; the session graph is the
  // strongest single signal when it exists, because it is *this* listener.
  static const double artistWeight = 1.05;
  static const double titleWeight = 0.55;

  /// The session graph is the strongest single signal there is, because it is
  /// literally what *this* listener did last time.
  static const double transitionWeight = 1.6;

  /// A candidate that has already been heard this session is not banned — it
  /// only has to be clearly better than something new.
  static const double playedPenalty = 0.6;

  /// Vibe smoothness: how much two tracks may differ before the sequence feels
  /// wrong (duration is the audio-feature proxy we can honestly compute).
  static const double jumpPenalty = 0.45;

  static List<Song> rank(
    Song anchor,
    List<Song> pool, {
    required VibeProfile profile,
    Set<String> excludedIds = const <String>{},
    int limit = 20,
  }) {
    final List<Song> candidates = <Song>[];
    final List<Song> seen = <Song>[anchor];
    for (final Song song in pool) {
      if (song.id.isEmpty ||
          song.id == anchor.id ||
          excludedIds.contains(song.id) ||
          profile.skippedIds.contains(song.id)) {
        continue;
      }
      if (seen.any((Song other) => sameRecording(other, song))) continue;
      candidates.add(song);
      seen.add(song);
    }
    if (candidates.isEmpty) return <Song>[];

    final Map<String, double> scores = <String, double>{
      for (final Song song in candidates) song.id: score(anchor, song, profile),
    };

    // Greedy sequencing with a proximity term, so the queue flows instead of
    // jumping between unrelated worlds.
    final List<Song> ordered = <Song>[];
    Song previous = anchor;
    final List<Song> remaining = List<Song>.of(candidates);
    while (remaining.isNotEmpty && ordered.length < limit) {
      int bestIndex = 0;
      double bestScore = double.negativeInfinity;
      for (int i = 0; i < remaining.length; i++) {
        final Song song = remaining[i];
        final double value =
            scores[song.id]! - jumpPenalty * proximityCost(previous, song);
        if (value > bestScore) {
          bestScore = value;
          bestIndex = i;
        }
      }
      final Song pick = remaining.removeAt(bestIndex);
      ordered.add(pick);
      previous = pick;
    }
    return ordered;
  }

  /// Raw vibe match for one candidate (higher is better, may be negative).
  static double score(Song anchor, Song candidate, VibeProfile profile) {
    double value = 0;
    value += artistWeight * profile.artistAffinity(candidate.artist);
    value += titleWeight * profile.titleAffinity(candidate.title);
    value += transitionWeight *
        profile.transitionAffinity(anchor.id, candidate.id);
    if (profile.likedIds.contains(candidate.id)) value += 0.6;
    if (profile.playedIds.contains(candidate.id)) value -= playedPenalty;
    // A track from the artist that is playing right now is always welcome.
    if (artistKey(candidate.artist).isNotEmpty &&
        artistKey(candidate.artist) == artistKey(anchor.artist)) {
      value += 0.35;
    }
    return value;
  }

  /// 0 (same feel) … 1 (a jarring jump). Duration is compared as a ratio, so a
  /// 2-minute short and a 12-minute mix do not sit next to each other.
  static double proximityCost(Song a, Song b) {
    final int da = a.duration?.inSeconds ?? 0;
    final int db = b.duration?.inSeconds ?? 0;
    if (da <= 0 || db <= 0) return 0.15;
    final double ratio = da > db ? da / db : db / da;
    // 1.0 → same length · 1.5 → ~50% longer · 2.5+ → different worlds.
    final double lengthCost = ((ratio - 1.0) / 1.5).clamp(0.0, 1.0);
    // Shared words/artist pull the opposite way (they feel adjacent).
    final bool sameArtist =
        artistKey(a.artist).isNotEmpty && artistKey(a.artist) == artistKey(b.artist);
    final Set<String> ta = titleTokens(a.title);
    final Set<String> tb = titleTokens(b.title);
    double shared = 0;
    if (ta.isNotEmpty && tb.isNotEmpty) {
      final int common = ta.intersection(tb).length;
      shared = common / math.max(ta.length, tb.length);
    }
    double cost = lengthCost - (sameArtist ? 0.35 : 0) - 0.25 * shared;
    return cost.clamp(0.0, 1.0);
  }
}

// ------------------------------------------------------------------- text
/// Words that say nothing about a *song* — they only say where it came from.
const Set<String> _titleStopWords = <String>{
  'official', 'video', 'videos', 'audio', 'song', 'songs',
  'full', 'hd', '4k', 'lyrics', 'lyric', 'lyrical',
  'version', 'mix', 'remix', 'remastered', 'live', 'slowed',
  'reverb', 'sped', 'speed', 'nightcore', 'cover', 'karaoke',
  'instrumental', 'feat', 'ft', 'with', 'and', 'the',
  'a', 'an', 'of', 'to', 'in', 'on',
  'for', 'from', 'music', 'mv', 'visualizer', 'out',
  'now', 'new', 'latest', 'best', 'top', 'hits',
  'hit', 'unplugged', 'acoustic', 'extended', 'edit', 'original',
  'motion', 'poster', 'teaser', 'trailer', 'jukebox', 'playlist',
  'album', 'single', 'records', 'record', 'productions', 'studios',
  'studio', 'entertainment', 'presenting', 'presented', 'exclusive', 'blockbuster',
  'trending', 'viral', 'hq', 'quality', 'ifallmusic',
};

/// `"Kesariya | Brahmastra | Arijit Singh"` → `{kesariya, brahmastra, arijit,
/// singh}` — the words a person would use to describe the song.
Set<String> titleTokens(String title) {
  final String cleaned = title
      .toLowerCase()
      .replaceAll(RegExp(r'\([^)]*\)|\[[^\]]*\]'), ' ')
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', ' ', unicode: true), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  final Set<String> out = <String>{};
  for (final String word in cleaned.split(' ')) {
    if (word.length < 3) continue;
    if (_titleStopWords.contains(word)) continue;
    if (RegExp(r'^\d+$').hasMatch(word)) continue;
    out.add(word);
  }
  return out;
}

/// The primary artist of a row, normalised: `"Arijit Singh, Shreya Ghoshal"` →
/// `"arijit singh"`, `"T-Series"` → `"t series"`.
String artistKey(String artist) {
  final String primary = artist
      .split(RegExp(r'[,&]|\bfeat\.?\b|\bft\.?\b|\bwith\b', caseSensitive: false))
      .first
      .toLowerCase()
      .replaceAll('"', '')
      .replaceAll(RegExp(r'\s*-\s*topic$'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{N}\s]+', ' ', unicode: true))
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return primary;
}

/// Every artist named in a row (the primary one plus the collaborators).
Iterable<String> _artistMentions(String artist) sync* {
  for (final String part in artist.split(
    RegExp(r'[,&/]|\bfeat\.?\b|\bft\.?\b', caseSensitive: false),
  )) {
    final String key = artistKey(part);
    if (key.isNotEmpty) yield key;
  }
}
