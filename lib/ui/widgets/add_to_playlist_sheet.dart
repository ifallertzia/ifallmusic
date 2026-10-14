import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/library_service.dart';
import '../../core/theme/sidify_theme.dart';
import 'sidify_widgets.dart';
import 'song_menu.dart';

/// "Add to playlist…" — create a new playlist or add to an existing one;
/// playlists that already hold the song are marked.
Future<void> showAddToPlaylistSheet(BuildContext context, Song song) {
  return showSidifySheet(
    context,
    title: 'Add to playlist',
    subtitle: song.title,
    child: Consumer<LibraryService>(
      builder: (BuildContext context, LibraryService library, _) {
        final SidifyTokens t = context.sidify;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () async {
                    final String? name = await _askName(context);
                    if (name == null || name.trim().isEmpty) return;
                    if (!context.mounted) return;
                    final Playlist p = await library.createPlaylist(name.trim());
                    await library.addToPlaylist(p.id, song);
                    if (context.mounted) Navigator.of(context).pop();
                    showAppNotice('Added to $name');
                  },
                  child: Container(
                    height: 56,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      children: <Widget>[
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            border: Border.all(color: t.fill3, width: 1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(Icons.add_rounded, size: 20, color: t.text2),
                        ),
                        const SizedBox(width: 12),
                        Text('New playlist',
                            style: TextStyle(fontSize: 16, color: t.text)),
                      ],
                    ),
                  ),
                ),
              ),
              for (final Playlist p in library.playlists)
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () async {
                      final bool added = await library.addToPlaylist(p.id, song);
                      if (context.mounted) Navigator.of(context).pop();
                      showAppNotice(
                        added ? 'Added to ${p.name}' : 'Already in ${p.name}',
                      );
                    },
                    child: Container(
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: <Widget>[
                          Artwork(
                            url: p.songs.isEmpty ? '' : p.songs.first.thumbnailUrl,
                            size: 40,
                            radius: 8,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  p.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 16, color: t.text),
                                ),
                                Text(
                                  '${p.count} song${p.count == 1 ? '' : 's'}',
                                  style: TextStyle(fontSize: 12.5, color: t.text2),
                                ),
                              ],
                            ),
                          ),
                          if (p.songs.any((Song s) => s.id == song.id))
                            Icon(Icons.check_rounded, size: 18, color: t.playing),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    ),
  );
}

/// Create-playlist dialog (also used by the Library's "New playlist").
Future<String?> askPlaylistName(BuildContext context, {String title = 'New playlist'}) =>
    _askName(context, title: title);

Future<String?> _askName(BuildContext context, {String title = 'New playlist'}) {
  final TextEditingController controller = TextEditingController();
  final SidifyTokens t = context.sidify;
  return showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) {
      return AlertDialog(
        backgroundColor: t.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: SidifyText.title(t.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: t.text),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: t.text2),
            filled: true,
            fillColor: t.fill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: t.edge, width: 0.5),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: t.edge, width: 0.5),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: t.text2, width: 1),
            ),
          ),
          onSubmitted: (String v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: t.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('Create', style: TextStyle(color: t.text)),
          ),
        ],
      );
    },
  );
}
