import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/sidify_theme.dart';
import '../../ui/search/search_page.dart';
import '../../ui/shell/sidify_shell_controller.dart';
import 'movie_ui_widgets.dart';
import 'movies_home_page.dart';

/// Search entry hub displayed when the user taps the Search tab:
/// - Offers two clear choices: **Music** and **Movies & Series**.
/// - Choosing **Music** opens the untouched existing [SearchPage].
/// - Choosing **Movies & Series** opens [MoviesHomePage].
class SearchHubPage extends StatelessWidget {
  const SearchHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SidifyShellController shell = context.watch<SidifyShellController>();
    final SidifyTokens t = context.sidify;

    switch (shell.searchMode) {
      case SearchMode.music:
        return Column(
          children: <Widget>[
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: <Widget>[
                    _modeSwitchPill(
                      t,
                      icon: Icons.arrow_back_ios_new_rounded,
                      label: 'Search Options',
                      onTap: () => shell.setSearchMode(SearchMode.chooser),
                    ),
                    const Spacer(),
                    _modeSwitchPill(
                      t,
                      icon: Icons.movie_creation_outlined,
                      label: 'Movies & Series',
                      onTap: () => shell.setSearchMode(SearchMode.movies),
                    ),
                  ],
                ),
              ),
            ),
            const Expanded(child: _MusicSearchHost()),
          ],
        );

      case SearchMode.movies:
        return MoviesHomePage(
          onBackToChooser: () => shell.setSearchMode(SearchMode.chooser),
        );

      case SearchMode.chooser:
        return SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 190),
            physics: const BouncingScrollPhysics(),
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text('Search', style: SidifyText.display(t.text)),
                  ),
                  const MovieDownloadsActionButton(),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Choose what you want to explore today',
                style: SidifyText.bodyS(t.text2),
              ),
              const SizedBox(height: 24),
              _SearchChoiceCard(
                key: const ValueKey<String>('search-choice-music'),
                icon: Icons.music_note_rounded,
                accentColor: t.brand,
                title: 'Music',
                subtitle:
                    'Songs, albums, artists, playlists & lossless streaming',
                badgeText: 'AUDIO STREAMING',
                onTap: () => shell.setSearchMode(SearchMode.music),
              ),
              const SizedBox(height: 16),
              _SearchChoiceCard(
                key: const ValueKey<String>('search-choice-movies'),
                icon: Icons.movie_filter_rounded,
                accentColor: const Color(0xFF0A84FF),
                title: 'Movies & Series',
                subtitle:
                    'Search HD / 4K movies & web series with multi-language downloads',
                badgeText: 'MOVIES • WEB SERIES • DOWNLOADS',
                onTap: () => shell.setSearchMode(SearchMode.movies),
              ),
            ],
          ),
        );
    }
  }

  Widget _modeSwitchPill(
    SidifyTokens t, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Material(
      color: t.raised,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: t.edge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 14, color: t.text),
              const SizedBox(width: 6),
              Text(label, style: SidifyText.caption(t.text)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MusicSearchHost extends StatelessWidget {
  const _MusicSearchHost();

  @override
  Widget build(BuildContext context) {
    return MediaQuery.removePadding(
      context: context,
      removeTop: true,
      child: const SearchPage(),
    );
  }
}

class _SearchChoiceCard extends StatelessWidget {
  const _SearchChoiceCard({
    super.key,
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.onTap,
  });

  final IconData icon;
  final Color accentColor;
  final String title;
  final String subtitle;
  final String badgeText;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: accentColor.withValues(alpha: 0.35)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                accentColor.withValues(alpha: t.isDark ? 0.22 : 0.12),
                t.raised,
              ],
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Icon(icon, size: 30, color: accentColor),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      badgeText,
                      style: SidifyText.eyebrow(accentColor),
                    ),
                    const SizedBox(height: 5),
                    Text(title, style: SidifyText.section(t.text)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: SidifyText.bodyS(t.text2)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_ios_rounded,
                size: 16,
                color: t.text2,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
