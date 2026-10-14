import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/library_service.dart';
import '../../core/theme/saxify_theme.dart';
import '../../core/theme/ifall_ui.dart';

/// Copy JSON is the old action. Paste & Import is new, with merge or replace.
Future<void> showBackupSheet(BuildContext context, LibraryService library) async {
  final TextEditingController controller = TextEditingController();
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
            Text('Backup library', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'This is a local library JSON backup, separate from cloud playlist codes. It is copied to your clipboard and imported on this device; IfallMusic does not upload it.',
              style: TextStyle(fontSize: 12, color: IfallTokens.textMuted),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () async {
                  final ClipboardData? data = await Clipboard.getData('text/plain');
                  final String text = data?.text?.trim() ?? '';
                  if (text.isEmpty) return;
                  controller.text = text;
                },
                icon: const Icon(Icons.content_paste_rounded, size: 18),
                label: const Text('Paste from clipboard'),
              ),
            ),
            TextField(
              controller: controller,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(hintText: 'Paste an IfallMusic library JSON'),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: <Widget>[
                TextButton(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: library.exportBackup()));
                    if (!sheet.mounted) return;
                    ScaffoldMessenger.of(sheet).showSnackBar(
                      const SnackBar(content: Text('Library backup copied to clipboard')),
                    );
                  },
                  child: const Text('Copy JSON'),
                ),
                TextButton(
                  onPressed: () => _import(sheet, library, controller.text, merge: true),
                  child: const Text('Merge'),
                ),
                TextButton(
                  onPressed: () => _import(sheet, library, controller.text, merge: false),
                  child: const Text('Replace'),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );
}

Future<void> _import(
  BuildContext context,
  LibraryService library,
  String raw, {
  required bool merge,
}) async {
  final String? error = library.validateBackup(raw);
  if (error != null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error)));
    return;
  }
  final bool ok = await library.importBackup(raw, merge: merge);
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(ok ? 'Library imported' : 'Could not import that backup')),
  );
  if (ok) Navigator.of(context).pop();
}


