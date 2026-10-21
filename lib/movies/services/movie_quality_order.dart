import '../models/movie_models.dart';
import 'eon_movies_service.dart';

/// Numeric resolution rank (e.g. `720p` -> 720); unknown labels sort last.
int movieQualityRank(MovieQualityLink quality) {
  return int.tryParse(
        RegExp(r'\d+').firstMatch(quality.resolution)?.group(0) ?? '',
      ) ??
      99999;
}

/// The numeric height alone, with unknown labels treated as "no idea" (0)
/// instead of "enormous". Sorting *down* with [movieQualityRank] would put
/// `WEB-DL` and other unlabelled rows above real 1080p, which is exactly the
/// wrong pick for the first stream to try.
int movieQualityHeight(MovieQualityLink quality) {
  return int.tryParse(
        RegExp(r'\d+').firstMatch(quality.resolution)?.group(0) ?? '',
      ) ??
      0;
}

/// Deduplicated subset of [qualities] the online player can attempt.
List<MovieQualityLink> playableQualitiesOf(List<MovieQualityLink> qualities) {
  final Map<String, MovieQualityLink> byId = <String, MovieQualityLink>{};
  for (final MovieQualityLink item in qualities) {
    if (EonMoviesService.canAttemptOnlinePlayback(item)) {
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
  final List<MovieQualityLink> options =
      playableQualitiesOf(qualities).toList();
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

/// Highest streamable quality — what playback starts on. Every fallback then
/// walks *down* this list, so a dead 1080p mirror lands on 720p, not 480p.
MovieQualityLink? highestPlayableQuality(List<MovieQualityLink> qualities) {
  final List<MovieQualityLink> ordered = playableQualitiesBestFirst(qualities);
  return ordered.isEmpty ? null : ordered.first;
}

/// Lowest streamable quality. Kept as the "is anything streamable here?"
/// probe and for callers that deliberately want the smallest stream.
MovieQualityLink? lowestPlayableQuality(List<MovieQualityLink> qualities) {
  final List<MovieQualityLink> options = playableQualitiesOf(qualities).toList()
    ..sort((MovieQualityLink a, MovieQualityLink b) =>
        movieQualityRank(a).compareTo(movieQualityRank(b)));
  return options.isEmpty ? null : options.first;
}
