import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/artist.dart';
import '../../core/models/song.dart';
import '../../core/theme/sidify_theme.dart';
import '../widgets/sidify_widgets.dart';
import '../../core/services/library_service.dart';

/// History: what you played, newest first — from the on-device log.
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final SidifyTokens t = context.sidify;
    final List<HistoryEntry> history = library.history;
    final List<Song> songs =
        history.map((HistoryEntry e) => e.song).toList();

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('History', style: SidifyText.titleM(t.text)),
        actions: <Widget>[
          if (history.isNotEmpty)
            TextButton(
              onPressed: () => library.clearHistory(),
              child: Text('Clear', style: TextStyle(color: t.text2)),
            ),
        ],
      ),
      body: history.isEmpty
          ? const EmptyState(
              icon: Icons.history_rounded,
              title: 'Nothing played yet',
              desc: 'Songs you play will line up here.',
            )
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 190),
              physics: const BouncingScrollPhysics(),
              itemCount: songs.length,
              itemBuilder: (BuildContext context, int i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TrackRow(
                  tracks: songs,
                  index: i,
                  onRemove: () =>
                      library.removeHistoryEntry(songs[i].id),
                ),
              ),
            ),
    );
  }
}
