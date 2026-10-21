import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/sidify_theme.dart';
import '../models/movie_models.dart';
import '../services/eon_movies_service.dart';
import '../services/movie_catalog_filters.dart';
import 'movie_detail_page.dart';
import 'movie_settings_page.dart';
import 'movie_ui_widgets.dart';

/// Movies Explore: real catalog browsing on top of the existing movie
/// service. Category is filtered by the source itself; type and year are
/// filtered from the catalog data the source returns; language and genre
/// (which the source only publishes on title pages) are filtered against
/// the actual title details, fetched on demand for the loaded titles.
class MoviesExplorePage extends StatefulWidget {
  const MoviesExplorePage({super.key});

  @override
  State<MoviesExplorePage> createState() => _MoviesExplorePageState();
}

const List<String> _exploreLanguages = <String>[
  'Hindi',
  'English',
  'Tamil',
  'Telugu',
  'Malayalam',
  'Kannada',
  'Punjabi',
  'Bengali',
  'Marathi',
  'Japanese',
  'Korean',
];

const List<String> _exploreGenres = <String>[
  'Action',
  'Adventure',
  'Animation',
  'Comedy',
  'Crime',
  'Drama',
  'Family',
  'Fantasy',
  'Horror',
  'Mystery',
  'Romance',
  'Sci-Fi',
  'Thriller',
  'War',
];

class _MoviesExplorePageState extends State<MoviesExplorePage> {
  MovieCategory _category = MovieCategory.recommended;
  MovieExploreType _type = MovieExploreType.all;
  int? _year;
  String _language = '';
  String _genre = '';

  List<MoviePost> _posts = <MoviePost>[];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _error = false;
  int _requestToken = 0;

  final Map<String, MovieDetail> _details = <String, MovieDetail>{};
  final Set<String> _failedDetails = <String>{};
  bool _enriching = false;
  int _enrichToken = 0;

  bool get _detailFilterActive => _language.isNotEmpty || _genre.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _fetchFirstPage();
  }

  @override
  void dispose() {
    _enrichToken++;
    super.dispose();
  }

  List<MoviePost> get _baseFiltered =>
      filterMoviePosts(_posts, type: _type, year: _year);

  List<MoviePost> get _visiblePosts {
    final List<MoviePost> base = _baseFiltered;
    if (!_detailFilterActive) return base;
    return base.where((MoviePost post) {
      final MovieDetail? detail = _details[post.link];
      return detail != null &&
          movieDetailMatchesExplore(detail, language: _language, genre: _genre);
    }).toList();
  }

  Future<void> _fetchFirstPage() async {
    final int token = ++_requestToken;
    _enrichToken++;
    setState(() {
      _loading = true;
      _error = false;
      _page = 1;
      _hasMore = true;
      _enriching = false;
    });
    try {
      final EonMoviesService svc = context.read<EonMoviesService>();
      final List<MoviePost> results =
          await svc.fetchPosts(category: _category, page: 1);
      if (!mounted || token != _requestToken) return;
      setState(() {
        _posts = results;
        _hasMore = results.length >= 20;
        _loading = false;
      });
      _maybeEnrich();
    } catch (_) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadNextPage() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final int nextPage = _page + 1;
    final int token = _requestToken;
    try {
      final EonMoviesService svc = context.read<EonMoviesService>();
      final List<MoviePost> more =
          await svc.fetchPosts(category: _category, page: nextPage);
      if (!mounted || token != _requestToken) return;
      final Set<String> existing = _posts.map((MoviePost p) => p.link).toSet();
      setState(() {
        _posts = <MoviePost>[
          ..._posts,
          for (final MoviePost p in more)
            if (!existing.contains(p.link)) p,
        ];
        _page = nextPage;
        _hasMore = more.length >= 20;
        _loadingMore = false;
      });
      _maybeEnrich();
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  Future<void> _maybeEnrich() async {
    if (!_detailFilterActive) return;
    final int token = ++_enrichToken;
    final List<MoviePost> pending = _baseFiltered
        .where((MoviePost p) =>
            !_details.containsKey(p.link) && !_failedDetails.contains(p.link))
        .toList();
    if (pending.isEmpty) {
      if (_enriching && mounted) setState(() => _enriching = false);
      return;
    }
    if (mounted) setState(() => _enriching = true);
    final EonMoviesService svc = context.read<EonMoviesService>();
    const int batchSize = 4;
    for (int i = 0; i < pending.length; i += batchSize) {
      if (!mounted || token != _enrichToken) return;
      final List<MoviePost> batch = pending.skip(i).take(batchSize).toList();
      await Future.wait(<Future<void>>[
        for (final MoviePost post in batch)
          () async {
            try {
              final MovieDetail detail =
                  await svc.fetchDetail(post.link, autoExpandLimit: 0);
              _details[post.link] = detail;
            } catch (_) {
              _failedDetails.add(post.link);
            }
          }(),
      ]);
      if (mounted && token == _enrichToken) setState(() {});
    }
    if (mounted && token == _enrichToken) {
      setState(() => _enriching = false);
    }
  }

  void _applyFilters() {
    _enrichToken++;
    setState(() {});
    _maybeEnrich();
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final double width = MediaQuery.sizeOf(context).width;
    final int crossAxisCount = width >= 900 ? 5 : (width >= 600 ? 4 : 3);
    final List<MoviePost> visible = _visiblePosts;
    final List<int> years = moviePostYears(_posts);

    return SafeArea(
      bottom: false,
      child: RefreshIndicator(
        color: t.brand,
        onRefresh: _fetchFirstPage,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: <Widget>[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Explore',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SidifyText.headline(t.text),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Settings',
                          onPressed: () => openMovieSettingsPage(context),
                          icon: Icon(Icons.settings_rounded, color: t.text),
                        ),
                        const MovieDownloadsActionButton(),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _chipRow(t, <Widget>[
                      for (final MovieCategory cat in MovieCategory.values)
                        _chip(
                          t,
                          label: cat.label,
                          selected: _category == cat,
                          onTap: () {
                            if (_category == cat) return;
                            setState(() {
                              _category = cat;
                              _year = null;
                            });
                            _fetchFirstPage();
                          },
                        ),
                    ]),
                    const SizedBox(height: 10),
                    _chipRow(t, <Widget>[
                      _chip(
                        t,
                        label: 'All',
                        selected: _type == MovieExploreType.all,
                        onTap: () {
                          setState(() => _type = MovieExploreType.all);
                          _applyFilters();
                        },
                      ),
                      _chip(
                        t,
                        label: 'Movies',
                        selected: _type == MovieExploreType.movies,
                        onTap: () {
                          setState(() => _type = MovieExploreType.movies);
                          _applyFilters();
                        },
                      ),
                      _chip(
                        t,
                        label: 'Series',
                        selected: _type == MovieExploreType.series,
                        onTap: () {
                          setState(() => _type = MovieExploreType.series);
                          _applyFilters();
                        },
                      ),
                      if (years.isNotEmpty) ...<Widget>[
                        _divider(t),
                        _chip(
                          t,
                          label: 'Any year',
                          selected: _year == null,
                          onTap: () {
                            setState(() => _year = null);
                            _applyFilters();
                          },
                        ),
                        for (final int year in years)
                          _chip(
                            t,
                            label: '$year',
                            selected: _year == year,
                            onTap: () {
                              setState(() => _year = year);
                              _applyFilters();
                            },
                          ),
                      ],
                    ]),
                    const SizedBox(height: 10),
                    _chipRow(t, <Widget>[
                      _chip(
                        t,
                        label: 'Any language',
                        selected: _language.isEmpty,
                        onTap: () {
                          setState(() => _language = '');
                          _applyFilters();
                        },
                      ),
                      for (final String language in _exploreLanguages)
                        _chip(
                          t,
                          label: language,
                          selected: _language == language,
                          onTap: () {
                            setState(() => _language = language);
                            _applyFilters();
                          },
                        ),
                    ]),
                    const SizedBox(height: 10),
                    _chipRow(t, <Widget>[
                      _chip(
                        t,
                        label: 'Any genre',
                        selected: _genre.isEmpty,
                        onTap: () {
                          setState(() => _genre = '');
                          _applyFilters();
                        },
                      ),
                      for (final String genre in _exploreGenres)
                        _chip(
                          t,
                          label: genre,
                          selected: _genre == genre,
                          onTap: () {
                            setState(() => _genre = genre);
                            _applyFilters();
                          },
                        ),
                    ]),
                    const SizedBox(height: 14),
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '${_category.label} • ${visible.length} titles',
                            style: SidifyText.title(t.text),
                          ),
                        ),
                        if (_enriching) ...<Widget>[
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: t.brand,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text('Checking titles…', style: SidifyText.caption(t.text2)),
                        ],
                      ],
                    ),
                    if (_detailFilterActive) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        'Language & genre are checked against each title — load more to check more titles.',
                        style: SidifyText.caption(t.text2),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (_loading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator(color: t.brand)),
              )
            else if (_error)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(Icons.wifi_off_rounded, size: 46, color: t.danger),
                      const SizedBox(height: 12),
                      Text(
                        'Unable to reach movies catalog',
                        style: SidifyText.titleM(t.text),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Check your connection and try again.',
                        textAlign: TextAlign.center,
                        style: SidifyText.caption(t.text2),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        onPressed: _fetchFirstPage,
                        icon: const Icon(Icons.refresh_rounded, size: 18),
                        label: const Text('Try Again'),
                      ),
                    ],
                  ),
                ),
              )
            else if (visible.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          _enriching
                              ? 'Checking titles for your filters…'
                              : 'No titles match these filters yet.',
                          textAlign: TextAlign.center,
                          style: SidifyText.bodyS(t.text2),
                        ),
                        if (_hasMore && !_enriching) ...<Widget>[
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: _loadingMore ? null : _loadNextPage,
                            icon: const Icon(Icons.expand_more_rounded),
                            label: const Text('Load More'),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              )
            else ...<Widget>[
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 11,
                    childAspectRatio: 0.56,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (BuildContext context, int index) {
                      final MoviePost post = visible[index];
                      return MovieGridCard(
                        post: post,
                        onTap: () => openMovieDetailPage(context, post),
                      );
                    },
                    childCount: visible.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 190),
                  child: _hasMore
                      ? Center(
                          child: _loadingMore
                              ? CircularProgressIndicator(color: t.brand)
                              : OutlinedButton.icon(
                                  onPressed: _loadNextPage,
                                  icon: const Icon(Icons.expand_more_rounded),
                                  label: const Text('Load More'),
                                ),
                        )
                      : const SizedBox(height: 8),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chipRow(SidifyTokens t, List<Widget> chips) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int i) => Center(child: chips[i]),
      ),
    );
  }

  Widget _divider(SidifyTokens t) {
    return Container(width: 1, height: 22, color: t.edge);
  }

  Widget _chip(
    SidifyTokens t, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
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
}
