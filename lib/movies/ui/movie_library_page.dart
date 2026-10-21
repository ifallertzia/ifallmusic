import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/sidify_theme.dart';
import '../models/movie_models.dart';
import '../services/movie_library_service.dart';
import 'movie_detail_page.dart';
import 'movie_downloads_page.dart';
import 'movie_ui_widgets.dart';

class MovieLibraryPage extends StatelessWidget {
  const MovieLibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final MovieLibraryService library = context.watch<MovieLibraryService>();
    return SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 150),
        children: <Widget>[
          Row(children: <Widget>[
            Expanded(child: Text('Library', style: SidifyText.display(t.text))),
            IconButton(
              tooltip: 'Movie downloads',
              onPressed: () => openMovieDownloadsPage(context),
              icon: Icon(Icons.download_rounded, color: t.text),
            ),
          ]),
          const SizedBox(height: 16),
          _section(context, t, 'Watchlist', library.watchlist),
          const SizedBox(height: 24),
          _section(context, t, 'Recently watched', library.history),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, SidifyTokens t, String title, List<MoviePost> posts) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text(title, style: SidifyText.section(t.text)),
      const SizedBox(height: 10),
      if (posts.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(title == 'Watchlist' ? 'Saved movies and series will appear here.' : 'Your viewing history will appear here.', style: SidifyText.bodyS(t.text2)),
        )
      else
        for (final MoviePost post in posts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(width: 48, child: MoviePosterImage(imageUrl: post.imageUrl, fallbackUrl: post.fallbackImageUrl, borderRadius: BorderRadius.circular(7))),
            title: Text(post.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: SidifyText.body(t.text)),
            subtitle: Text(post.badge, style: SidifyText.caption(t.text2)),
            trailing: Icon(Icons.chevron_right_rounded, color: t.text3),
            onTap: () => openMovieDetailPage(context, post),
          ),
    ]);
  }
}
