import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/sidify_theme.dart';
import '../models/movie_models.dart';
import '../services/eon_movies_service.dart';
import '../services/movie_library_service.dart';
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
        _error = 'Sorry yr, phir se try kr (ya internet connection check kr)';
        _loading = false;
      });
    }
  }

  Future<void> _toggleOrExpandGroup(MovieEpisodeGroup group) async {
    final MovieDetail? current = _detail;
    if (current == null) return;

    if (group.isLoaded) {
      setState(() {
        if (_collapsedGroupIds.contains(group.id)) {
          _collapsedGroupIds.remove(group.id);
        } else {
          _collapsedGroupIds.add(group.id);
        }
      });
      return;
    }

    if (_loadingGroupIds.contains(group.id)) return;
    setState(() => _loadingGroupIds.add(group.id));

    try {
      final EonMoviesService svc = context.read<EonMoviesService>();
      final MovieEpisodeGroup loaded = await svc.expandEpisodeGroup(group);
      if (!mounted) return;
      final List<MovieEpisodeGroup> updated = current.episodeGroups
          .map((MovieEpisodeGroup g) => g.id == group.id ? loaded : g)
          .toList();
      setState(() {
        _loadingGroupIds.remove(group.id);
        _collapsedGroupIds.remove(group.id);
        _detail = MovieDetail(
          title: current.title,
          cleanTitle: current.cleanTitle,
          type: current.type,
          webUrl: current.webUrl,
          year: current.year,
          releaseDate: current.releaseDate,
          backdropUrl: current.backdropUrl,
          fallbackBackdropUrl: current.fallbackBackdropUrl,
          posterUrl: current.posterUrl,
          fallbackPosterUrl: current.fallbackPosterUrl,
          languages: current.languages,
          languageList: current.languageList,
          genres: current.genres,
          director: current.director,
          qualityBadges: current.qualityBadges,
          synopsis: current.synopsis,
          defaultSeasonLabel: current.defaultSeasonLabel,
          directQualities: current.directQualities,
          episodeGroups: updated,
          relatedPosts: current.relatedPosts,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingGroupIds.remove(group.id));
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
                      'Loading download qualities & languages...',
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
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 190),
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

    widgets.add(const SizedBox(height: 22));

    if (!detail.isSeries && detail.directQualities.isNotEmpty) {
      widgets.add(
        Text(
          'Download Qualities',
          style: SidifyText.section(t.text),
        ),
      );
      widgets.add(const SizedBox(height: 4));
      widgets.add(
        Text(
          detail.languages.isNotEmpty
              ? 'Select resolution to start direct download (${detail.languages})'
              : 'Select resolution to start direct download',
          style: SidifyText.caption(t.text2),
        ),
      );
      widgets.add(const SizedBox(height: 12));
      for (final MovieQualityLink q in detail.directQualities) {
        widgets.add(
          MovieQualityDownloadTile(
            detail: detail,
            quality: q,
            allQualities: detail.directQualities,
          ),
        );
      }
    } else if (detail.episodeGroups.isNotEmpty) {
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
              ? 'Quality-wise downloads • Languages: ${detail.languages}'
              : 'Choose season / episode and quality below',
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
    } else if (detail.directQualities.isNotEmpty) {
      widgets.add(Text('Download Options', style: SidifyText.section(t.text)));
      widgets.add(const SizedBox(height: 12));
      for (final MovieQualityLink q in detail.directQualities) {
        widgets.add(
          MovieQualityDownloadTile(
            detail: detail,
            quality: q,
            allQualities: detail.directQualities,
          ),
        );
      }
    } else {
      widgets.add(
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.raised,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text(
            'No download links listed for this title right now.',
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

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _toggleOrExpandGroup(group),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: <Widget>[
                  Icon(
                    group.isCompletePack
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
                        if (langs.isNotEmpty) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(
                            'Audio: $langs',
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
                  else
                    Icon(
                      expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      color: t.text2,
                    ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  for (final MovieQualityLink q in group.qualities)
                    MovieQualityDownloadTile(
                      detail: detail,
                      quality: q,
                      allQualities: group.qualities,
                    ),
                  for (final MovieEpisodeGroup sub in group.nestedGroups)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Padding(
                            padding: const EdgeInsets.only(
                              left: 4,
                              bottom: 8,
                            ),
                            child: Text(
                              sub.fullHeading,
                              style: SidifyText.label(t.text),
                            ),
                          ),
                          for (final MovieQualityLink nq in sub.qualities)
                            MovieQualityDownloadTile(
                              detail: detail,
                              quality: nq,
                              allQualities: sub.qualities,
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
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
