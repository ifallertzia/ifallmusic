import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../movies/ui/search_hub_page.dart';
import '../explore/explore_page.dart';
import '../home/home_page.dart';
import '../library/library_page.dart';
import '../rooms/listen_together_page.dart';
import 'sidify_shell_controller.dart';

/// The window on a phone: five tabs kept alive in an [IndexedStack], with
/// the floating glass tab bar and mini player painted above everything by
/// the dock layer (see `sidify_dock.dart`) so they survive page pushes.
class SidifyShell extends StatelessWidget {
  const SidifyShell({super.key});

  @override
  Widget build(BuildContext context) {
    final SidifyShellController shell =
        context.watch<SidifyShellController>();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (bool didPop, Object? _) {
        if (didPop) return;
        if (shell.tab == SidifyTab.search &&
            shell.searchMode != SearchMode.chooser) {
          shell.setSearchMode(SearchMode.chooser);
          return;
        }
        // Back replays tab visits; only at Home does it leave the app.
        if (!shell.back()) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: IndexedStack(
          index: shell.index,
          children: const <Widget>[
            HomePage(),
            ExplorePage(),
            SearchHubPage(),
            LibraryPage(),
            ListenTogetherPage(),
          ],
        ),
      ),
    );
  }
}
