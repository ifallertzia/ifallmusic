import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/playlist_sync_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/ifall_ui.dart';

Future<void> sharePlaylistCode(BuildContext context, Playlist playlist) async {
  final TextEditingController name = TextEditingController(text: playlist.name);
  final String? title = await showDialog<String>(
    context: context,
    builder: (BuildContext dialog) => AlertDialog(
      title: Text('Generate code', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
      content: TextField(
        controller: name,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Playlist name'),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(dialog, name.text), child: const Text('Generate')),
      ],
    ),
  );
  if (title == null || !context.mounted) return;
  final String? code = await PlaylistSyncService.shareSinglePlaylist(
    title.trim().isEmpty ? playlist.name : title.trim(),
    playlist.songs.map((Song s) => s.toJson()).toList(),
  );
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(code == null
          ? 'Could not create a code. Check your connection.'
          : 'Code clipboard mein save ho gaya hai!'),
    ),
  );
}

Future<void> shareAllPlaylistCodes(BuildContext context) async {
  final LibraryService library = context.read<LibraryService>();
  final TextEditingController name = TextEditingController(text: 'My IfallMusic library');
  final String? title = await showDialog<String>(
    context: context,
    builder: (BuildContext dialog) => AlertDialog(
      title: Text('Generate all', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
      content: TextField(controller: name, decoration: const InputDecoration(hintText: 'Backup name')),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.pop(dialog), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(dialog, name.text), child: const Text('Generate')),
      ],
    ),
  );
  if (title == null || !context.mounted) return;
  final String? code = await PlaylistSyncService.shareAllPlaylists(
    library.playlists.map((Playlist p) => p.toJson()).toList(),
    title: title.trim().isEmpty ? 'IfallMusic library' : title.trim(),
  );
  if (!context.mounted) return;
  if (code != null) {
    await context.read<SettingsService>().setLastPlaylistCode(code);
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(code == null
          ? 'Could not create a code. Check your connection.'
          : 'Code clipboard mein save ho gaya hai!'),
    ),
  );
}

Future<void> showImportCodeSheet(BuildContext context) async {
  final TextEditingController code = TextEditingController();
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: IfallTokens.surface,
    builder: (BuildContext sheet) {
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.viewInsetsOf(sheet).bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text('Import playlist code', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Cloud playlist codes are separate from local library JSON. Full-library restore needs the Render route GET /playlist/all/:code; a single-playlist code uses GET /playlist/:code. Generating codes needs POST /playlist and POST /playlist/all.',
              style: TextStyle(fontSize: 12, color: IfallTokens.textMuted),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final ClipboardData? data = await Clipboard.getData('text/plain');
                  final String text = data?.text?.trim() ?? '';
                  if (text.isNotEmpty) code.text = text;
                },
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('Paste code'),
              ),
            ),
            TextField(
              controller: code,
              decoration: const InputDecoration(hintText: 'Playlist code'),
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: () async {
                final LibraryService library = sheet.read<LibraryService>();
                final String id = code.text.trim();
                Map<String, dynamic>? payload = await PlaylistSyncService.fetchAll(id);
                payload ??= await PlaylistSyncService.fetchPlaylist(id);
                if (!sheet.mounted) return;
                if (payload == null) {
                  ScaffoldMessenger.of(sheet).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Could not fetch the code. The Render backend must provide GET /playlist/all/:code for a full-library code and GET /playlist/:code for single-playlist codes.',
                      ),
                    ),
                  );
                  return;
                }
                final List<Playlist> imported = PlaylistSyncService.playlistsFromPayload(payload);
                if (imported.isEmpty) {
                  ScaffoldMessenger.of(sheet).showSnackBar(
                    const SnackBar(content: Text('That code did not contain any playlists.')),
                  );
                  return;
                }
                await library.mergePlaylists(imported);
                if (!sheet.mounted) return;
                Navigator.of(sheet).pop();
                ScaffoldMessenger.of(sheet).showSnackBar(
                  const SnackBar(content: Text('Playlists restore ho gayi!')),
                );
              },
              child: const Text('Fetch'),
            ),
          ],
        ),
      );
    },
  );
}
