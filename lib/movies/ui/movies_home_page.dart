import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/sidify_theme.dart';
import '../models/movie_models.dart';
import '../services/eon_movies_service.dart';
import 'movie_detail_page.dart';
import 'movie_ui_widgets.dart';

/// Movies & Series browse + search hub:
/// - Top search bar (`GET /?action=search&page=<n>&name=<query>`)
/// - Recommended movies & series automatically loaded beneath (`GET /?page=<n>`)
/// - Category chips (`Bollywood`, `Hollywood`, `South Indian`, `Web Series`, `Anime`)
/// - Header shortcut to [MovieDownloadsPage] with live active badge.
class MoviesHomePage extends StatefulWidget {
  const MoviesHomePage({super.key, this.onBackToChooser});

  final VoidCallback? onBackToChooser;

  @override
  State<MoviesHomePage> createState() => _MoviesHomePageState();
}

class _MoviesHomePageState extends State<MoviesHomePage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  MovieCategory _category = MovieCategory.recommended;
  String _activeQuery = '';
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<MoviePost> _posts = <MoviePost>[];
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _fetchFirstPage();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String raw) {
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 420), () {
      final String trimmed = raw.trim();
      if (trimmed == _activeQuery) return;
      _activeQuery = trimmed;
      _fetchFirstPage();
    });
  }

  void _submitSearch(String raw) {
    _debounce?.cancel();
    _activeQuery = raw.trim();
    _fetchFirstPage();
  }

  void _clearSearch() {
    _debounce?.cancel();
    _searchController.clear();
    if (_activeQuery.isEmpty) {
      setState(() {});
      return;
    }
    _activeQuery = '';
    _fetchFirstPage();
  }

  Future<void> _fetchFirstPage() async {
    final int token = ++_requestToken;
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
      _hasMore = true;
    });

    try {
      final EonMoviesService svc = context.read<EonMoviesService>();
      final List<MoviePost> results = _activeQuery.isNotEmpty
          ? await svc.searchPosts(query: _activeQuery, page: 1)
          : await svc.fetchPosts(category: _category, page: 1);

      if (!mounted || token != _requestToken) return;
      setState(() {
        _posts = results;
        _hasMore = results.length >= 20;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _error = e.toString();
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
      final List<MoviePost> more = _activeQuery.isNotEmpty
          ? await svc.searchPosts(query: _activeQuery, page: nextPage)
          : await svc.fetchPosts(category: _category, page: nextPage);

      if (!mounted || token != _requestToken) return;
      final Set<String> existingLinks =
          _posts.map((MoviePost p) => p.link).toSet();
      final List<MoviePost> merged = <MoviePost>[
        ..._posts,
        for (final MoviePost p in more)
          if (!existingLinks.contains(p.link)) p,
      ];
      setState(() {
        _posts = merged;
        _page = nextPage;
        _hasMore = more.length >= 20;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final double width = MediaQuery.sizeOf(context).width;
    final int crossAxisCount = width >= 900 ? 5 : (width >= 600 ? 4 : 3);

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
                        if (widget.onBackToChooser != null) ...<Widget>[
                          Material(
                            color: t.raised,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: widget.onBackToChooser,
                              child: Padding(
                                padding: const EdgeInsets.all(9),
                                child: Icon(
                                  Icons.arrow_back_ios_new_rounded,
                                  size: 16,
                                  color: t.text,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                        ],
                        Expanded(
                          child: Text(
                            'Movies & Series',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SidifyText.headline(t.text),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const MovieDownloadsActionButton(),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Top Search Input Bar
                    Container(
                      decoration: BoxDecoration(
                        color: t.raised,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: t.edge),
                      ),
                      child: TextField(
                        controller: _searchController,
                        textInputAction: TextInputAction.search,
                        style: SidifyText.body(t.text),
                        onChanged: _onSearchChanged,
                        onSubmitted: _submitSearch,
                        decoration: InputDecoration(
                          hintText: 'Search movies, web series, anime...',
                          hintStyle: SidifyText.bodyS(t.text2),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            color: t.text2,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: _clearSearch,
                                  icon: Icon(
                                    Icons.cancel_rounded,
                                    color: t.text2,
                                    size: 19,
                                  ),
                                )
                              : null,
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 13,
                          ),
                        ),
                      ),
                    ),
                    if (_activeQuery.isEmpty) ...<Widget>[
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 36,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: MovieCategory.values.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 8),
                          itemBuilder: (BuildContext context, int i) {
                            final MovieCategory cat = MovieCategory.values[i];
                            final bool selected = _category == cat;
                            return GestureDetector(
                              onTap: () {
                                if (_category == cat) return;
                                setState(() => _category = cat);
                                _fetchFirstPage();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: selected ? t.primary : t.raised,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: selected ? t.primary : t.edge,
                                  ),
                                ),
                                child: Text(
                                  cat.label,
                                  style: SidifyText.label(
                                    selected ? t.onPrimary : t.text,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Text(
                      _activeQuery.isNotEmpty
                          ? 'Search Results for "$_activeQuery"'
                          : '${_category.label} Movies & Series',
                      style: SidifyText.title(t.text),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (_loading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: t.brand),
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
                      Icon(Icons.wifi_off_rounded, size: 46, color: t.danger),
                      const SizedBox(height: 12),
                      Text(
                        'Unable to reach movies catalog',
                        style: SidifyText.titleM(t.text),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _error!,
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
            else if (_posts.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Text(
                      'No movies or series matched your search.',
                      textAlign: TextAlign.center,
                      style: SidifyText.bodyS(t.text2),
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
                      final MoviePost post = _posts[index];
                      return _MovieGridCard(post: post);
                    },
                    childCount: _posts.length,
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
}

class _MovieGridCard extends StatelessWidget {
  const _MovieGridCard({required this.post});

  final MoviePost post;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return GestureDetector(
      onTap: () => openMovieDetailPage(context, post),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                MoviePosterImage(
                  imageUrl: post.imageUrl,
                  fallbackUrl: post.fallbackImageUrl,
                  borderRadius: BorderRadius.circular(12),
                ),
                if (post.badge.isNotEmpty || post.isSeries)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: post.isSeries ? t.brand : t.scrim,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        post.isSeries ? 'SERIES' : 'MOVIE',
                        style: const TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            post.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SidifyText.label(t.text),
          ),
          if (post.subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2),
            Text(
              post.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SidifyText.caption(t.text2),
            ),
          ],
        ],
      ),
    );
  }
}
