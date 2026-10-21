import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/sidify_theme.dart';
import '../models/movie_models.dart';
import '../services/movie_library_service.dart';
import 'local_videos_page.dart';
import 'movie_detail_page.dart';
import 'movie_downloads_page.dart';
import 'movie_settings_page.dart';
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
            // Music is one tap away in the floating bar (the music note),
            // so the movies headers keep only their own actions.
            IconButton(
              tooltip: 'Settings',
              onPressed: () => openMovieSettingsPage(context),
              icon: Icon(Icons.settings_rounded, color: t.text),
            ),
          ]),
          const SizedBox(height: 16),
          _entryTile(
            context,
            t,
            icon: Icons.download_rounded,
            title: 'Downloads',
            subtitle: 'Movies and episodes saved by the app',
            onTap: () => openMovieDownloadsPage(context),
          ),
          const SizedBox(height: 10),
          _entryTile(
            context,
            t,
            icon: Icons.smartphone_rounded,
            title: 'On this device',
            subtitle: 'Play videos already saved on this phone',
            onTap: () => openLocalVideosPage(context),
          ),
          const SizedBox(height: 24),
          _section(context, t, 'Watchlist', library.watchlist, library: library),
          const SizedBox(height: 24),
          _section(context, t, 'Recently watched', library.history),
        ],
      ),
    );
  }

  Widget _entryTile(
    BuildContext context,
    SidifyTokens t, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: t.raised,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.edge),
          ),
          child: Row(children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: t.brand.withValues(alpha: .14),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, color: t.brand, size: 23),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: SidifyText.titleM(t.text)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: SidifyText.caption(t.text2)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: t.text3),
          ]),
        ),
      ),
    );
  }

  Widget _section(
    BuildContext context,
    SidifyTokens t,
    String title,
    List<MoviePost> posts, {
    MovieLibraryService? library,
  }) {
    final bool isWatchlist = library != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
      Text(title, style: SidifyText.section(t.text)),
      const SizedBox(height: 10),
      if (posts.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text(
            isWatchlist
                ? 'Saved movies and series will appear here.'
                : 'Your viewing history will appear here.',
            style: SidifyText.bodyS(t.text2),
          ),
        )
      else
        for (final MoviePost post in posts)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: SizedBox(
              width: 48,
              child: MoviePosterImage(
                imageUrl: post.imageUrl,
                fallbackUrl: post.fallbackImageUrl,
                borderRadius: BorderRadius.circular(7),
              ),
            ),
            title: Text(
              post.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SidifyText.body(t.text),
            ),
            subtitle: Text(post.badge, style: SidifyText.caption(t.text2)),
            trailing: isWatchlist
                ? IconButton(
                    tooltip: 'Remove from watchlist',
                    onPressed: () => library.toggleWatchlist(post),
                    icon: Icon(Icons.bookmark_remove_rounded, color: t.text2, size: 20),
                  )
                : Icon(Icons.chevron_right_rounded, color: t.text3),
            onTap: () => openMovieDetailPage(context, post),
          ),
    ]);
  }
}
