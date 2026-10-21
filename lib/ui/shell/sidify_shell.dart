import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../movies/models/movie_models.dart';
import '../../movies/ui/movie_library_page.dart';
import '../../movies/ui/movies_home_page.dart';
import '../../movies/ui/search_hub_page.dart';
import '../explore/explore_page.dart';
import '../home/home_page.dart';
import '../library/library_page.dart';
import '../rooms/listen_together_page.dart';
import '../search/search_page.dart';
import 'sidify_shell_controller.dart';

class SidifyShell extends StatelessWidget {
  const SidifyShell({super.key});

  @override
  Widget build(BuildContext context) {
    final SidifyShellController shell = context.watch<SidifyShellController>();
    if (!shell.ready || !shell.hasModeChoice) {
      return const Scaffold(body: SearchHubPage());
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (!didPop && !shell.back()) SystemNavigator.pop();
      },
      child: Scaffold(
        body: shell.isMoviesMode
            ? shell.tab == SidifyTab.library
                ? const MovieLibraryPage()
                : shell.tab == SidifyTab.together
                    ? const _WatchTogetherSoonPage()
                    : MoviesHomePage(
                        initialCategory: shell.tab == SidifyTab.explore
                            ? MovieCategory.bollywood
                            : MovieCategory.recommended,
                      )
            : IndexedStack(
                index: shell.index,
                children: const <Widget>[
                  HomePage(),
                  ExplorePage(),
                  SearchPage(),
                  LibraryPage(),
                  ListenTogetherPage(),
                ],
              ),
      ),
    );
  }
}

class _WatchTogetherSoonPage extends StatelessWidget {
  const _WatchTogetherSoonPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Watch Together — Coming soon')),
      );
}
