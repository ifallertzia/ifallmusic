import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/sidify_theme.dart';
import '../../ui/shell/sidify_shell_controller.dart';
import '../../ui/search/search_page.dart';
import 'movies_home_page.dart';

class SearchHubPage extends StatelessWidget {
  const SearchHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final SidifyShellController shell = context.watch<SidifyShellController>();
    if (shell.hasModeChoice) {
      return shell.isMoviesMode ? const MoviesHomePage() : const SearchPage();
    }
    return SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 32, 22, 24),
            shrinkWrap: true,
            children: <Widget>[
              Text('Choose your Sidify', style: SidifyText.display(t.text)),
              const SizedBox(height: 8),
              Text('Choose a space to open. You can switch any time.', style: SidifyText.bodyS(t.text2)),
              const SizedBox(height: 28),
              _ModeCard(
                key: const ValueKey<String>('search-choice-music'),
                icon: Icons.music_note_rounded,
                title: 'Sidify Music',
                subtitle: 'Songs, albums, artists and your music library',
                color: t.brand,
                onTap: () => shell.chooseMode(movies: false),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                key: const ValueKey<String>('search-choice-movies'),
                icon: Icons.movie_creation_rounded,
                title: 'Sidify Movies',
                subtitle: 'Movies, series, watchlist and downloads',
                color: const Color(0xFFDA4967),
                onTap: () => shell.chooseMode(movies: true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({super.key, required this.icon, required this.title, required this.subtitle, required this.color, required this.onTap});

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return Material(
      color: t.raised,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(20), border: Border.all(color: t.edge)),
          child: Row(children: <Widget>[
            Container(width: 54, height: 54, decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(16)), child: Icon(icon, color: color, size: 28)),
            const SizedBox(width: 16),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
              Text(title, style: SidifyText.section(t.text)),
              const SizedBox(height: 4),
              Text(subtitle, style: SidifyText.bodyS(t.text2)),
            ])),
            Icon(Icons.chevron_right_rounded, color: t.text2),
          ]),
        ),
      ),
    );
  }
}
