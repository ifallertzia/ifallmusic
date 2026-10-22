import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/app_feedback.dart';
import '../../core/theme/sidify_theme.dart';
import '../models/movie_models.dart';
import '../services/eon_movies_service.dart';
import '../services/movie_download_service.dart';
import '../services/movie_library_service.dart';
import 'movie_downloads_page.dart';
import 'movie_player_page.dart';
import 'movie_ui_widgets.dart';

void openMovieDetailPage(BuildContext context, MoviePost post) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => MovieDetailPage(initialPost: post),
      settings: const RouteSettings(name: 'sidify/movie-detail'),
    ),
  );
}

class MovieDetailPage extends StatefulWidget {
  const MovieDetailPage({super.key, required this.initialPost});

  final MoviePost initialPost;

  @override
  State<MovieDetailPage> createState() => _MovieDetailPageState();
}

class _MovieDetailPageState extends State<MovieDetailPage> {
  MovieDetail? _detail;
  String? _error;
  bool _loading = true;
  String _selectedSeason = '';
  final Set<String> _loadingGroupIds = <String>{};
  final Set<String> _collapsedGroupIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  MoviePost get _currentPost {
    final MovieDetail? detail = _detail;
    if (detail == null) return widget.initialPost;
    return MoviePost(
      title: detail.title,
      link: detail.webUrl,
      imageUrl: detail.posterUrl.isNotEmpty ? detail.posterUrl : widget.initialPost.imageUrl,
      fallbackImageUrl: detail.fallbackPosterUrl,
      badge: detail.isSeries ? 'Series' : 'Movie',
      subtitle: detail.year,
    );
  }

  Future<void> _load() async {
    final MovieLibraryService? library = context.read<MovieLibraryService?>();
    if (library != null) unawaited(library.recordOpened(widget.initialPost));
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final EonMoviesService svc = context.read<EonMoviesService>();
      final MovieDetail detail = await svc.fetchDetail(widget.initialPost.link);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Check your connection and try again.';
        _loading = false;
      });
    }
  }

  Future<MovieEpisodeGroup?> _ensureGroupLoaded(MovieEpisodeGroup group) async {
    if (group.isLoaded) return group;
    final MovieDetail? current = _detail;
    if (current == null) return null;
    if (_loadingGroupIds.contains(group.id)) return null;
    setState(() => _loadingGroupIds.add(group.id));

    try {
      final EonMoviesService svc = context.read<EonMoviesService>();
      final MovieEpisodeGroup loaded = await svc.expandEpisodeGroup(group);
      if (!mounted) return null;
      final MovieDetail latest = _detail ?? current;
      MovieEpisodeGroup replaceLoaded(MovieEpisodeGroup g) {
        if (g.id == group.id) return loaded;
        if (g.nestedGroups.isEmpty) return g;
        return g.copyWith(
          nestedGroups: g.nestedGroups.map(replaceLoaded).toList(),
        );
      }

      final List<MovieEpisodeGroup> updated =
          latest.episodeGroups.map(replaceLoaded).toList();
      setState(() {
        _loadingGroupIds.remove(group.id);
        _collapsedGroupIds.remove(group.id);
        _detail = MovieDetail(
          title: latest.title,
          cleanTitle: latest.cleanTitle,
          type: latest.type,
          webUrl: latest.webUrl,
          year: latest.year,
          releaseDate: latest.releaseDate,
          backdropUrl: latest.backdropUrl,
          fallbackBackdropUrl: latest.fallbackBackdropUrl,
          posterUrl: latest.posterUrl,
          fallbackPosterUrl: latest.fallbackPosterUrl,
          languages: latest.languages,
          languageList: latest.languageList,
          genres: latest.genres,
          director: latest.director,
          qualityBadges: latest.qualityBadges,
          synopsis: latest.synopsis,
          defaultSeasonLabel: latest.defaultSeasonLabel,
          directQualities: latest.directQualities,
          episodeGroups: updated,
          relatedPosts: latest.relatedPosts,
        );
      });
      return loaded;
    } catch (_) {
      if (!mounted) return null;
      setState(() => _loadingGroupIds.remove(group.id));
      showAppNotice(
        'Could not load episodes right now. Please try again.',
        duration: const Duration(seconds: 2),
      );
      return null;
    }
  }

  Future<void> _toggleGroup(MovieEpisodeGroup group) async {
    if (!group.isLoaded) {
      await _ensureGroupLoaded(group);
      return;
    }
    setState(() {
      if (_collapsedGroupIds.contains(group.id)) {
        _collapsedGroupIds.remove(group.id);
      } else {
        _collapsedGroupIds.add(group.id);
      }
    });
  }

  /// The one sentence a person should read when a title cannot be streamed.
  String _offlineLine(String title) =>
      'Cannot play $title online but you can still download it and play offline.';

  void _playQualities(MovieDetail detail, List<MovieQualityLink> qualities) {
    // Playback starts on the *best* stream available, then the player walks
    // down the list itself if that one is dead.
    final MovieQualityLink? best = highestPlayableQuality(qualities);
    if (best == null) {
      showAppNotice(
        _offlineLine(
          detail.cleanTitle.isNotEmpty ? detail.cleanTitle : detail.title,
        ),
        duration: const Duration(seconds: 4),
      );
      return;
    }
    openOnlineMoviePlayer(
      context,
      detail: detail,
      quality: best,
      allQualities: playableQualitiesBestFirst(qualities),
    );
  }

  void _downloadQualities(
    MovieDetail detail,
    List<MovieQualityLink> qualities, {
    required String heading,
  }) {
    final List<MovieQualityLink> zipQualities = qualities
        .where((MovieQualityLink q) => q.isZipPack)
        .toList();
    final bool zipOnly = zipQualities.isNotEmpty &&
        highestPlayableQuality(qualities) == null;
    if (zipOnly) {
      showSeriesDownloadDialog(
        context,
        detail: detail,
        packQualities: zipQualities,
      );
    } else {
      showMovieDownloadQualityDialog(
        context,
        detail: detail,
        qualities: qualities,
        heading: heading,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final MovieDetail? detail = _detail;

    return Scaffold(
      backgroundColor: t.bg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: <Widget>[
          SliverAppBar(
            expandedHeight: 270,
            pinned: true,
            backgroundColor: t.bg,
            surfaceTintColor: Colors.transparent,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: Material(
                color: t.scrim,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
            actions: <Widget>[
              Builder(
                builder: (BuildContext context) {
                  final MovieLibraryService? library = context.watch<MovieLibraryService?>();
                  if (library == null) return const SizedBox.shrink();
                  final bool saved = library.contains(_currentPost);
                  return IconButton(
                    tooltip: saved ? 'Remove from watchlist' : 'Add to watchlist',
                    onPressed: () => library.toggleWatchlist(_currentPost),
                    icon: Icon(saved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded, color: Colors.white),
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: MovieDownloadsActionButton(),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  MoviePosterImage(
                    imageUrl: detail?.backdropUrl.isNotEmpty == true
                        ? detail!.backdropUrl
                        : widget.initialPost.imageUrl,
                    fallbackUrl: detail?.fallbackBackdropUrl.isNotEmpty == true
                        ? detail!.fallbackBackdropUrl
                        : widget.initialPost.fallbackImageUrl,
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          t.bg.withValues(alpha: 0.25),
                          t.bg.withValues(alpha: 0.72),
                          t.bg,
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 12,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: <Widget>[
                        SizedBox(
                          width: 96,
                          height: 138,
                          child: MoviePosterImage(
                            imageUrl: detail?.posterUrl.isNotEmpty == true
                                ? detail!.posterUrl
                                : widget.initialPost.imageUrl,
                            fallbackUrl:
                                detail?.fallbackPosterUrl.isNotEmpty == true
                                    ? detail!.fallbackPosterUrl
                                    : widget.initialPost.fallbackImageUrl,
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: <Widget>[
                                  _badge(
                                    t,
                                    (detail?.isSeries ??
                                            widget.initialPost.isSeries)
                                        ? 'SERIES'
                                        : 'MOVIE',
                                    highlight: true,
                                  ),
                                  if ((detail?.year ?? '').isNotEmpty)
                                    _badge(t, detail!.year),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Text(
                                detail?.title ?? widget.initialPost.title,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: SidifyText.title(t.text),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_loading)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    CircularProgressIndicator(color: t.brand),
                    const SizedBox(height: 14),
                    Text(
                      'Loading details…',
                      style: SidifyText.bodyS(t.text2),
                    ),
                  ],
                ),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Icon(Icons.cloud_off_rounded, size: 46, color: t.danger),
                    const SizedBox(height: 12),
                    Text(
                      'Could not load title details',
                      style: SidifyText.titleM(t.text),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: SidifyText.caption(t.text2),
                    ),
                    const SizedBox(height: 18),
                    ElevatedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (detail != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 48),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  _buildDetailBody(context, t, detail),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildDetailBody(
    BuildContext context,
    SidifyTokens t,
    MovieDetail detail,
  ) {
    final List<Widget> widgets = <Widget>[];

    // Prominent Audio / Download Languages banner
    widgets.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: t.raised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.edge),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: t.brand.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.translate_rounded,
                size: 18,
                color: t.brand,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Download Audio Languages',
                    style: SidifyText.caption(t.text2),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    detail.languages.isNotEmpty
                        ? detail.languages
                        : 'Original Audio',
                    style: SidifyText.titleM(t.text),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (detail.genres.isNotEmpty || detail.releaseDate.isNotEmpty) {
      widgets.add(const SizedBox(height: 12));
      widgets.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            if (detail.releaseDate.isNotEmpty) _badge(t, detail.releaseDate),
            for (final String genre in detail.genres) _badge(t, genre),
          ],
        ),
      );
    }

    if (detail.synopsis.isNotEmpty) {
      widgets.add(const SizedBox(height: 14));
      widgets.add(
        Text(
          detail.synopsis,
          style: SidifyText.bodyS(t.text2),
        ),
      );
    }

    widgets.add(const SizedBox(height: 18));
    widgets.add(_buildActionsRow(context, t, detail));
    widgets.add(_ActiveDownloadsStrip(detail: detail));
    widgets.add(const SizedBox(height: 22));

    if (detail.episodeGroups.isNotEmpty) {
      final List<String> seasons = detail.episodeGroups
          .map((MovieEpisodeGroup g) => g.seasonLabel)
          .where((String s) => s.isNotEmpty)
          .toSet()
          .toList();

      widgets.add(
        Text(
          'Seasons & Episodes',
          style: SidifyText.section(t.text),
        ),
      );
      widgets.add(const SizedBox(height: 4));
      widgets.add(
        Text(
          detail.languages.isNotEmpty
              ? 'Languages: ${detail.languages}'
              : 'Choose a season and episode',
          style: SidifyText.caption(t.text2),
        ),
      );

      if (seasons.length > 1) {
        widgets.add(const SizedBox(height: 12));
        widgets.add(
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _seasonChip(t, label: 'All Seasons', value: ''),
              for (final String s in seasons) _seasonChip(t, label: s, value: s),
            ],
          ),
        );
      }

      widgets.add(const SizedBox(height: 14));

      final Iterable<MovieEpisodeGroup> visibleGroups = _selectedSeason.isEmpty
          ? detail.episodeGroups
          : detail.episodeGroups.where(
              (MovieEpisodeGroup g) => g.seasonLabel == _selectedSeason,
            );

      for (final MovieEpisodeGroup group in visibleGroups) {
        widgets.add(_buildEpisodeGroupCard(t, detail, group));
      }
    } else if (detail.directQualities.isEmpty) {
      widgets.add(
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.raised,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            'No watch or download links are listed for this title right now.',
            style: SidifyText.bodyS(t.text2),
          ),
        ),
      );
    }

    if (detail.relatedPosts.isNotEmpty) {
      widgets.add(const SizedBox(height: 24));
      widgets.add(
        Text('Recommended For You', style: SidifyText.section(t.text)),
      );
      widgets.add(const SizedBox(height: 12));
      widgets.add(
        SizedBox(
          height: 215,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: detail.relatedPosts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (BuildContext context, int i) {
              final MoviePost post = detail.relatedPosts[i];
              return GestureDetector(
                onTap: () => openMovieDetailPage(context, post),
                child: SizedBox(
                  width: 122,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: MoviePosterImage(
                          imageUrl: post.imageUrl,
                          fallbackUrl: post.fallbackImageUrl,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        post.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SidifyText.label(t.text),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    return widgets;
  }

  Widget _buildActionsRow(
    BuildContext context,
    SidifyTokens t,
    MovieDetail detail,
  ) {
    final bool isMovieLike =
        detail.episodeGroups.isEmpty && detail.directQualities.isNotEmpty;
    final MovieQualityLink? best =
        isMovieLike ? highestPlayableQuality(detail.directQualities) : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Nothing streamable: say it first, then offer the download right
        // underneath it — that is the way to watch this title at all.
        if (isMovieLike && best == null) ...<Widget>[
          Text(
            _offlineLine(
              detail.cleanTitle.isNotEmpty ? detail.cleanTitle : detail.title,
            ),
            style: SidifyText.bodyS(t.text2),
          ),
          const SizedBox(height: 12),
        ],
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            if (isMovieLike && best != null)
              _primaryButton(
                t,
                icon: Icons.play_arrow_rounded,
                label: 'Try beta',
                filled: true,
                onTap: () => _playQualities(detail, detail.directQualities),
              ),
            if (isMovieLike)
              _primaryButton(
                t,
                icon: Icons.download_rounded,
                label: 'Download',
                filled: best == null,
                onTap: () => _downloadQualities(
                  detail,
                  detail.directQualities,
                  heading: 'Download',
                ),
              ),
            Builder(
              builder: (BuildContext context) {
                final MovieLibraryService? library =
                    context.watch<MovieLibraryService?>();
                if (library == null) return const SizedBox.shrink();
                final bool saved = library.contains(_currentPost);
                return _primaryButton(
                  t,
                  icon: saved
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  label: saved ? 'In Watchlist' : 'Watchlist',
                  filled: false,
                  onTap: () => library.toggleWatchlist(_currentPost),
                );
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _primaryButton(
    SidifyTokens t, {
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: filled ? t.brand : t.raised,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: filled
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: t.edge),
                ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 19, color: filled ? Colors.white : t.text),
              const SizedBox(width: 7),
              Text(
                label,
                style: SidifyText.label(filled ? Colors.white : t.text),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEpisodeGroupCard(
    SidifyTokens t,
    MovieDetail detail,
    MovieEpisodeGroup group,
  ) {
    final bool loading = _loadingGroupIds.contains(group.id);
    final bool expanded =
        group.isLoaded && !_collapsedGroupIds.contains(group.id);
    final String langs =
        group.languages.isNotEmpty ? group.languages : detail.languages;
    final bool hasNested = group.nestedGroups.isNotEmpty;
    final bool isContainer = hasNested || !group.isLoaded;
    final MovieQualityLink? best =
        group.isLoaded ? highestPlayableQuality(group.qualities) : null;
    final bool zipOnly = group.isLoaded &&
        best == null &&
        group.qualities.any((MovieQualityLink q) => q.isZipPack);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: <Widget>[
                Icon(
                  group.isCompletePack || zipOnly
                      ? Icons.folder_zip_rounded
                      : Icons.movie_filter_rounded,
                  size: 20,
                  color: t.brand,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        group.fullHeading,
                        style: SidifyText.titleM(t.text),
                      ),
                      if (zipOnly) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          _offlineLine(group.fullHeading),
                          style: SidifyText.caption(t.text2),
                        ),
                      ] else if (langs.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          'Audio: $langs',
                          style: SidifyText.caption(t.text2),
                        ),
                      ],
                      if (group.isLoaded &&
                          !hasNested &&
                          group.qualities.isEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          'No links available',
                          style: SidifyText.caption(t.text2),
                        ),
                      ],
                    ],
                  ),
                ),
                if (loading)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.brand,
                    ),
                  )
                else if (isContainer)
                  IconButton(
                    tooltip: expanded ? 'Collapse' : 'Show episodes',
                    onPressed: () => _toggleGroup(group),
                    icon: Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: t.text2,
                    ),
                  )
                else ...<Widget>[
                  if (best != null)
                    _groupActionButton(
                      t,
                      icon: Icons.play_arrow_rounded,
                      label: 'Try beta',
                      filled: true,
                      onTap: () => _playQualities(detail, group.qualities),
                    ),
                  if (group.qualities.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    _groupActionButton(
                      t,
                      icon: Icons.download_rounded,
                      label: 'Download',
                      filled: best == null,
                      onTap: () => _downloadQualities(
                        detail,
                        group.qualities,
                        heading: group.fullHeading,
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),
          if (hasNested && expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final MovieEpisodeGroup sub in group.nestedGroups)
                    _buildEpisodeGroupCard(t, detail, sub),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _groupActionButton(
    SidifyTokens t, {
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: filled ? t.brand : t.raised,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          decoration: filled
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: t.edge),
                ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 16, color: filled ? Colors.white : t.text),
              const SizedBox(width: 5),
              Text(
                label,
                style: SidifyText.label(filled ? Colors.white : t.text),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _seasonChip(
    SidifyTokens t, {
    required String label,
    required String value,
  }) {
    final bool selected = _selectedSeason == value;
    return GestureDetector(
      onTap: () => setState(() => _selectedSeason = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? t.primary : t.raised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? t.primary : t.edge),
        ),
        child: Text(
          label,
          style: SidifyText.label(selected ? t.onPrimary : t.text),
        ),
      ),
    );
  }

  Widget _badge(SidifyTokens t, String label, {bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: highlight ? t.brand : t.raised,
        borderRadius: BorderRadius.circular(8),
        border: highlight ? null : Border.all(color: t.edge),
      ),
      child: Text(
        label,
        style: SidifyText.caption(highlight ? Colors.white : t.text2),
      ),
    );
  }
}

/// Compact live progress for this title's active/paused downloads, shown
/// under the detail actions. Tapping opens the Downloads manager.
class _ActiveDownloadsStrip extends StatelessWidget {
  const _ActiveDownloadsStrip({required this.detail});

  final MovieDetail detail;

  @override
  Widget build(BuildContext context) {
    final MovieDownloadService? service =
        context.watch<MovieDownloadService?>();
    if (service == null) return const SizedBox.shrink();
    final String title =
        detail.cleanTitle.isNotEmpty ? detail.cleanTitle : detail.title;
    final List<MovieDownloadItem> mine = service.items
        .where((MovieDownloadItem e) =>
            e.movieTitle == title &&
            (e.isActive || e.status == MovieDownloadStatus.paused))
        .toList();
    if (mine.isEmpty) return const SizedBox.shrink();
    final SidifyTokens t = context.sidify;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Material(
        color: t.raised,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => openMovieDownloadsPage(context),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.edge),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final MovieDownloadItem item in mine) ...<Widget>[
                  Row(
                    children: <Widget>[
                      Icon(Icons.downloading_rounded, size: 17, color: t.brand),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.subtitleSummary.isNotEmpty
                              ? item.subtitleSummary
                              : item.qualityLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SidifyText.bodyS(t.text),
                        ),
                      ),
                      Text(
                        item.status == MovieDownloadStatus.resolving
                            ? 'Connecting…'
                            : item.status == MovieDownloadStatus.paused
                                ? 'Paused'
                                : '${(item.progress * 100).toStringAsFixed(0)}%',
                        style: SidifyText.label(t.brand),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: item.status == MovieDownloadStatus.resolving
                          ? null
                          : item.progress,
                      minHeight: 5,
                      backgroundColor: t.fill2,
                      valueColor: AlwaysStoppedAnimation<Color>(t.brand),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                Text(
                  'Open Downloads to manage',
                  style: SidifyText.caption(t.text2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
