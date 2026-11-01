import '../models/movie_models.dart';
import 'movie_source.dart';

/// Numeric resolution rank (e.g. `720p` -> 720); unknown labels sort last.
int movieQualityRank(MovieQualityLink quality) {
  return int.tryParse(
        RegExp(r'\d+').firstMatch(quality.resolution)?.group(0) ?? '',
      ) ??
      99999;
}

/// The numeric height alone, with unknown labels treated as "no idea" (0)
/// instead of "enormous".
int movieQualityHeight(MovieQualityLink quality) {
  return int.tryParse(
        RegExp(r'\d+').firstMatch(quality.resolution)?.group(0) ?? '',
      ) ??
      0;
}

/// Deduplicated subset of [qualities] the online player can attempt.
///
/// The rule lives in [movieQualityCanStreamOnline] so both catalogs (EonMovies
/// and the premium HDHub4U source) behave identically.
List<MovieQualityLink> playableQualitiesOf(List<MovieQualityLink> qualities) {
  final Map<String, MovieQualityLink> byId = <String, MovieQualityLink>{};
  for (final MovieQualityLink item in qualities) {
    if (movieQualityCanStreamOnline(item)) {
      byId.putIfAbsent(item.id, () => item);
    }
  }
  return List<MovieQualityLink>.unmodifiable(byId.values);
}

/// Playable qualities ordered best first: 1080p before 720p before 480p.
/// Ties keep the catalog's own order.
List<MovieQualityLink> playableQualitiesBestFirst(
  List<MovieQualityLink> qualities,
) {
  final List<MovieQualityLink> options = playableQualitiesOf(qualities).toList();
  final List<MovieQualityLink> ordered = <MovieQualityLink>[];
  for (final MovieQualityLink quality in options) {
    int insertAt = ordered.length;
    for (int i = 0; i < ordered.length; i++) {
      if (movieQualityHeight(quality) > movieQualityHeight(ordered[i])) {
        insertAt = i;
        break;
      }
    }
    ordered.insert(insertAt, quality);
  }
  return List<MovieQualityLink>.unmodifiable(ordered);
}

/// Playable qualities ordered smallest first: 360p → 480p → 720p → 1080p.
///
/// This is the order the player walks: playback *starts* on the lightest
/// stream that is likely to open instantly and climbs to the next resolution
/// up when that one is dead. Ties keep the catalog's own order.
List<MovieQualityLink> playableQualitiesLowestFirst(
  List<MovieQualityLink> qualities,
) {
  final List<MovieQualityLink> best = playableQualitiesBestFirst(qualities);
  return List<MovieQualityLink>.unmodifiable(best.reversed.toList());
}

/// Highest streamable quality — the one a download button should save when the
/// person did not pick a specific row.
MovieQualityLink? highestPlayableQuality(List<MovieQualityLink> qualities) {
  final List<MovieQualityLink> ordered = playableQualitiesBestFirst(qualities);
  return ordered.isEmpty ? null : ordered.first;
}

/// Lowest streamable quality — what online playback starts on.
MovieQualityLink? lowestPlayableQuality(List<MovieQualityLink> qualities) {
  final List<MovieQualityLink> ordered = playableQualitiesLowestFirst(qualities);
  return ordered.isEmpty ? null : ordered.first;
}
