import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../../core/utils/format.dart';
import 'artwork.dart';
import '../../core/theme/ifall_ui.dart';

/// "Add to playlist" sheet: pick an existing playlist or create a new one.
Future<void> showAddToPlaylistSheet(BuildContext context, Song song) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => _AddToPlaylistSheet(song: song),
  );
}

class _AddToPlaylistSheet extends StatelessWidget {
  const _AddToPlaylistSheet({required this.song});

  final Song song;

  Future<void> _promptCreate(BuildContext context, LibraryService library) async {
    final TextEditingController controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text('New playlist',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (String v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) return;
    final Playlist playlist = await library.createPlaylist(name);
    await library.addToPlaylist(playlist.id, song);
    if (!context.mounted) return;
    Navigator.of(context).pop();
    _toast(context, 'Added to "${playlist.name}"');
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final SaxifyAccent accent = context.accent;

    return DraggableScrollableSheet(
      initialChildSize: 0.62,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder: (BuildContext context, ScrollController scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: IfallTokens.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(SaxifyTheme.radiusLg)),
          ),
          child: Column(
            children: <Widget>[
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: IfallTokens.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Row(
                  children: <Widget>[
                    Artwork(url: song.thumbnailUrl, size: 46, radius: 8),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text('Add to playlist',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Text(
                            '${song.title} · ${Fmt.duration(song.duration)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12, color: IfallTokens.textMuted),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 22),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  children: <Widget>[
                    ListTile(
                      leading: Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          gradient: accent.gradient,
                        ),
                        child: const Icon(Icons.add_rounded, color: Colors.black),
                      ),
                      title: const Text('Create new playlist',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: const Text('Start a fresh collection',
                          style: TextStyle(
                              fontSize: 12, color: IfallTokens.textMuted)),
                      onTap: () => _promptCreate(context, library),
                    ),
                    if (library.playlists.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: IfallEmpty(
                          icon: Icons.queue_music_rounded,
                          compact: true,
                          message:
                              'No playlists yet — create your first one and it will show up here.',
                        ),
                      )
                    else
                      for (final Playlist playlist in library.playlists)
                        ListTile(
                          leading: Artwork(
                              url: playlist.artwork,
                              size: 42,
                              radius: 10,
                              fallbackIcon: Icons.queue_music_rounded),
                          title: Text(playlist.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${playlist.count} songs',
                              style: const TextStyle(
                                  fontSize: 12, color: IfallTokens.textMuted)),
                          trailing: playlist.songs
                                  .any((Song s) => s.id == song.id)
                              ? Icon(Icons.check_circle_rounded,
                                  color: accent.primary, size: 20)
                              : const Icon(Icons.add_circle_outline_rounded,
                                  color: IfallTokens.textFaint, size: 20),
                          onTap: () async {
                            final bool added =
                                await library.addToPlaylist(playlist.id, song);
                            if (!context.mounted) return;
                            Navigator.of(context).pop();
                            _toast(
                              context,
                              added
                                  ? 'Added to "${playlist.name}"'
                                  : 'Already in "${playlist.name}"',
                            );
                          },
                        ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
