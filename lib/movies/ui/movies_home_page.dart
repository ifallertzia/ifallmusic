import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/settings_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../services/movie_content_filter.dart';
import '../models/movie_models.dart';
import '../models/movie_provider.dart';
import '../services/movies_repository.dart';
import 'movie_detail_page.dart';
import 'movie_settings_page.dart';
import 'movie_ui_widgets.dart';

/// Movies & Series browse + search hub:
/// - Top search bar (`GET /?action=search&page=<n>&name=<query>`)
/// - Recommended movies & series automatically loaded beneath (`GET /?page=<n>`)
/// - Category chips (`Bollywood`, `Hollywood`, `South Indian`, `Web Series`, `Anime`)
/// - Header shortcut to [MovieDownloadsPage] with live active badge.
class MoviesHomePage extends StatefulWidget {
  const MoviesHomePage({
    super.key,
    this.onBackToChooser,
    this.initialCategory = MovieCategory.recommended,
    this.autofocusSearch = false,
    this.initialQuery = '',
    this.initialProvider,
    this.initialPosts,
  });

  final VoidCallback? onBackToChooser;
  final MovieCategory initialCategory;
  final bool autofocusSearch;
  final String initialQuery;
  final MovieProvider? initialProvider;
  final List<MoviePost>? initialPosts;

  @override
  State<MoviesHomePage> createState() => _MoviesHomePageState();
}

class _MoviesHomePageState extends State<MoviesHomePage> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  late MovieCategory _category;
  String _activeQuery = '';
  int _page = 1;
  bool _hasMore = true;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  List<MoviePost> _posts = <MoviePost>[];
  MovieProvider? _selectedSearchProvider;

  /// Latest tiles from the premium HDHub4U catalog, shown as their own rail
  /// above the main grid while browsing (not while searching — search mixes
  /// every catalog into one list instead).
  List<MoviePost> _premiumPosts = <MoviePost>[];

  /// Latest tiles from the Ifallhub-powered catalog, on their own rail right
  /// under the IMAX HD one, every card badged *ifallhub*.
  List<MoviePost> _ifallhubPosts = <MoviePost>[];
  int _requestToken = 0;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _selectedSearchProvider = widget.initialProvider;
    if (widget.initialQuery.trim().isNotEmpty) {
      _activeQuery = widget.initialQuery.trim();
      _searchController.text = _activeQuery;
    }
    if (widget.initialPosts != null) {
      _posts = List<MoviePost>.from(widget.initialPosts!);
      _loading = false;
      _hasMore = _posts.length >= 20;
    } else {
      _fetchFirstPage();
    }
  }

  @override
  void didUpdateWidget(covariant MoviesHomePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialCategory != widget.initialCategory &&
        _activeQuery.isEmpty) {
      _category = widget.initialCategory;
      _fetchFirstPage();
    }
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
      _selectedSearchProvider = null;
      _fetchFirstPage();
    });
  }

  void _submitSearch(String raw) {
    _debounce?.cancel();
    _activeQuery = raw.trim();
    _selectedSearchProvider = null;
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
    _selectedSearchProvider = null;
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
      final MoviesRepository repo = moviesRepositoryOf(context);
      final List<MoviePost> results = _activeQuery.isNotEmpty
          ? await repo.search(query: _activeQuery, page: 1)
          : await repo.fetchPosts(category: _category, page: 1);

      if (!mounted || token != _requestToken) return;
      setState(() {
        _posts = results;
        _hasMore = results.length >= 20;
        _loading = false;
      });
      if (_activeQuery.isEmpty) {
        unawaited(_loadPremium(category: _category, token: token));
      } else if (_premiumPosts.isNotEmpty || _ifallhubPosts.isNotEmpty) {
        setState(() {
          _premiumPosts = <MoviePost>[];
          _ifallhubPosts = <MoviePost>[];
        });
      }
    } catch (e) {
      if (!mounted || token != _requestToken) return;
      setState(() {
        _error = 'Check your connection and try again.';
        _loading = false;
      });
    }
  }

  /// Premium catalog rails. Failure is silent: the main EonMovies grid above
  /// them is what the page is really about.
  Future<void> _loadPremium({
    required MovieCategory category,
    required int token,
  }) async {
    try {
      final MoviesRepository repo = moviesRepositoryOf(context);
      final List<MoviePost> premium =
          await repo.fetchPremiumPosts(category: category, page: 1);
      if (!mounted || token != _requestToken) return;
      setState(() => _premiumPosts = premium);
    } catch (_) {}

    try {
      final MoviesRepository repo = moviesRepositoryOf(context);
      final List<MoviePost> hub =
          await repo.fetchIfallhubPosts(category: category, page: 1);
      if (!mounted || token != _requestToken) return;
      setState(() => _ifallhubPosts = hub);
    } catch (_) {}
  }

  Future<void> _loadNextPage() async {
    if (_loading || _loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    final int nextPage = _page + 1;
    final int token = _requestToken;

    try {
      final MoviesRepository repo = moviesRepositoryOf(context);
      final List<MoviePost> more = _activeQuery.isNotEmpty
          ? await repo.search(query: _activeQuery, page: nextPage)
          : await repo.fetchPosts(category: _category, page: nextPage);

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
    final SettingsService? settings = context.watch<SettingsService?>();
    final bool adultContentUnlocked = settings?.adultContentUnlocked ?? false;
    final List<MoviePost> visiblePosts = filterMoviePosts(
      _posts,
      adultContentUnlocked: adultContentUnlocked,
    );
    final List<MoviePost> visiblePremiumPosts = filterMoviePosts(
      _premiumPosts,
      adultContentUnlocked: adultContentUnlocked,
    );
    final List<MoviePost> visibleIfallhubPosts = filterMoviePosts(
      _ifallhubPosts,
      adultContentUnlocked: adultContentUnlocked,
    );
    final double width = MediaQuery.sizeOf(context).width;
    final int crossAxisCount = width >= 900 ? 5 : (width >= 600 ? 4 : 3);
    final List<MoviePost> displayPosts = _activeQuery.isNotEmpty &&
            _selectedSearchProvider != null
        ? visiblePosts
            .where((MoviePost p) => p.provider == _selectedSearchProvider)
            .toList()
        : visiblePosts;

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
                        if (widget.onBackToChooser != null ||
                            widget.initialProvider != null) ...<Widget>[
                          Material(
                            color: t.raised,
                            shape: const CircleBorder(),
                            child: InkWell(
                              customBorder: const CircleBorder(),
                              onTap: widget.onBackToChooser ??
                                  () => Navigator.of(context).maybePop(),
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
                        const SizedBox(width: 4),
                        // The way back to Music is the round music button in
                        // the floating bar (it replaced Search there), so the
                        // header keeps only this section's own actions.
                        IconButton(
                          tooltip: 'Settings',
                          onPressed: () => openMovieSettingsPage(context),
                          icon: Icon(Icons.settings_rounded, color: t.text),
                        ),
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
                        autofocus: widget.autofocusSearch,
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
                          ? (_selectedSearchProvider == null
                              ? 'Search Results for "$_activeQuery"'
                              : '${_searchServerLabel(_selectedSearchProvider!)} results')
                          : '${_category.label} Movies & Series',
                      style: SidifyText.title(t.text),
                    ),
                    if (_activeQuery.isNotEmpty &&
                        _selectedSearchProvider != null) ...<Widget>[
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () => setState(() => _selectedSearchProvider = null),
                          icon: const Icon(Icons.arrow_back_rounded, size: 17),
                          label: const Text('All servers'),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
            if (visiblePremiumPosts.isNotEmpty && _activeQuery.isEmpty)
              SliverToBoxAdapter(
                child: _CatalogRail(
                  title: 'IMAX HD catalog',
                  posts: visiblePremiumPosts,
                ),
              ),
            if (visibleIfallhubPosts.isNotEmpty && _activeQuery.isEmpty)
              SliverToBoxAdapter(
                child: _CatalogRail(
                  title: 'ifallhub catalog',
                  posts: visibleIfallhubPosts,
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
            else if (_activeQuery.isNotEmpty &&
                _selectedSearchProvider == null &&
                visiblePosts.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 190),
                  child: Column(
                    children: <Widget>[
                      for (final MovieProvider provider in <MovieProvider>[
                        MovieProvider.ifallhub,
                        MovieProvider.hdhub4u,
                        MovieProvider.eonMovies,
                      ])
                        _searchServerRow(t, provider, visiblePosts),
                    ],
                  ),
                ),
              )
            else if (displayPosts.isEmpty)
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
                      final MoviePost post = displayPosts[index];
                      return MovieGridCard(
                        post: post,
                        showTitle: post.provider != MovieProvider.hdhub4u,
                        onTap: () => openMovieDetailPage(context, post),
                      );
                    },
                    childCount: displayPosts.length,
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

  String _searchServerLabel(MovieProvider provider) => switch (provider) {
        MovieProvider.ifallhub => 'Ifallhub server',
        MovieProvider.hdhub4u => 'IMAX HD',
        MovieProvider.eonMovies => 'Sidify server',
      };

  void _openSearchProviderPage(MovieProvider provider) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MoviesHomePage(
          initialQuery: _activeQuery,
          initialProvider: provider,
          initialPosts: _posts,
        ),
      ),
    );
  }

  Widget _searchServerRow(
    SidifyTokens t,
    MovieProvider provider,
    List<MoviePost> visiblePosts,
  ) {
    final List<MoviePost> providerPosts = visiblePosts
        .where((MoviePost post) => post.provider == provider)
        .toList();
    final Color accent = switch (provider) {
      MovieProvider.ifallhub => const Color(0xFF8B6DFF),
      MovieProvider.hdhub4u => const Color(0xFFE2B85A),
      MovieProvider.eonMovies => t.brand,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: t.raised,
        borderRadius: BorderRadius.circular(15),
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () => _openSearchProviderPage(provider),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: t.edge),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.dns_rounded, color: accent, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _searchServerLabel(provider),
                    style: SidifyText.titleM(t.text),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${providerPosts.length} results',
                    style: SidifyText.label(accent),
                  ),
                ),
                const SizedBox(width: 5),
                Icon(Icons.chevron_right_rounded, color: t.text2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal rail of the newest titles of one of the extra catalogs, each
/// card carrying that catalog's own chip (gold *IMAX HD* or violet *ifallhub*).
class _CatalogRail extends StatelessWidget {
  const _CatalogRail({required this.title, required this.posts});

  final String title;
  final List<MoviePost> posts;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SidifyText.title(t.text),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 232,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: posts.length,
            separatorBuilder: (_, __) => const SizedBox(width: 11),
            itemBuilder: (BuildContext context, int index) {
              final MoviePost post = posts[index];
              return GestureDetector(
                onTap: () => openMovieDetailPage(context, post),
                child: SizedBox(
                  width: 124,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: MoviePosterImage(
                          imageUrl: post.imageUrl,
                          fallbackUrl: post.fallbackImageUrl,
                          referer: post.link,
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
                      if (post.subtitle.isNotEmpty) ...<Widget>[
                        const SizedBox(height: 2),
                        Text(
                          post.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: SidifyText.caption(t.text2),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: PremiumProviderBadge(
                          compact: true,
                          provider: post.provider,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}
