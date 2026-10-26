import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../movies/ui/movie_downloads_page.dart';
import '../../movies/ui/movie_library_page.dart';
import '../../movies/ui/movies_explore_page.dart';
import '../../movies/ui/movies_home_page.dart';
import '../../movies/ui/search_hub_page.dart';
import '../../core/services/listen_together_service.dart';
import '../rooms/room_chat_panel.dart';
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
            ? _moviesBody(shell)
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
        floatingActionButton: _RoomChatLauncher(visible: !shell.isMoviesMode),
      ),
    );
  }

  Widget _moviesBody(SidifyShellController shell) {
    switch (shell.tab) {
      case SidifyTab.explore:
        return const MoviesExplorePage();
      case SidifyTab.search:
        // Direct movie search: same catalog page with the search field
        // focused, remounted per search request so the field regains focus.
        return MoviesHomePage(
          key: ValueKey<int>(shell.searchNonce),
          autofocusSearch: true,
          initialQuery: shell.searchQuery,
        );
      case SidifyTab.library:
        return const MovieLibraryPage();
      case SidifyTab.downloads:
        return const MovieDownloadsPage(embedded: true);
      case SidifyTab.together:
        return const _WatchTogetherSoonPage();
      case SidifyTab.home:
        return const MoviesHomePage();
    }
  }
}

class _WatchTogetherSoonPage extends StatelessWidget {
  const _WatchTogetherSoonPage();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: Text('Watch Together — Coming soon')),
      );
}


class _RoomChatLauncher extends StatelessWidget {
  const _RoomChatLauncher({required this.visible});
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final JamService jam = context.watch<JamService>();
    if (!visible || !jam.isConnected) return const SizedBox.shrink();
    return FloatingActionButton(
      heroTag: 'room-chat-launcher',
      backgroundColor: const Color(0xFFE5484D),
      foregroundColor: Colors.white,
      tooltip: 'Open room chat',
      onPressed: () => showDialog<void>(
        context: context,
        builder: (BuildContext dialogContext) => Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 28),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: RoomChatPanel(height: MediaQuery.sizeOf(dialogContext).height * .72),
          ),
        ),
      ),
      child: const Icon(Icons.chat_rounded),
    );
  }
}
