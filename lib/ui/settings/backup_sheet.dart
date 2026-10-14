import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/services/app_feedback.dart';
import '../../core/services/library_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../widgets/song_menu.dart';
import '../widgets/sidify_widgets.dart';

/// Backup & restore: copy the library out as JSON, or paste one back in
/// (merge or replace). The format is the engine's own and has not changed,
/// so backups from older builds import exactly as before.
Future<void> showBackupSheet(BuildContext context) {
  return showSidifySheet(
    context,
    title: 'Backup library',
    subtitle: 'Liked songs, playlists, history and artists',
    child: const _BackupBody(),
  );
}

class _BackupBody extends StatefulWidget {
  const _BackupBody();

  @override
  State<_BackupBody> createState() => _BackupBodyState();
}

class _BackupBodyState extends State<_BackupBody> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _import(LibraryService library, bool merge) async {
    final String raw = _controller.text;
    final String? error = library.validateBackup(raw);
    if (error != null) {
      showAppNotice(error);
      return;
    }
    final bool ok = await library.importBackup(raw, merge: merge);
    showAppNotice(ok ? 'Library restored' : 'That backup could not be read');
    if (ok && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.read<LibraryService>();
    final SidifyTokens t = context.sidify;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SidifyButton(
            label: 'Copy backup JSON',
            icon: Icons.copy_rounded,
            variant: SidifyButtonVariant.secondary,
            onTap: () async {
              await Clipboard.setData(
                ClipboardData(text: library.exportBackup()),
              );
              showAppNotice('Backup copied');
            },
          ),
          const SizedBox(height: 18),
          Text(
            'Restore from a backup',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.text2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _controller,
            maxLines: 5,
            style: TextStyle(fontSize: 13, color: t.text),
            decoration: InputDecoration(
              hintText: 'Paste a Sidify backup here…',
              hintStyle: TextStyle(color: t.text2),
              filled: true,
              fillColor: t.fill,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: t.edge, width: 0.5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: t.edge, width: 0.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: t.text2, width: 1),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: SidifyButton(
                  label: 'Paste & merge',
                  small: true,
                  variant: SidifyButtonVariant.secondary,
                  onTap: () async {
                    final ClipboardData? data =
                        await Clipboard.getData('text/plain');
                    if (data?.text != null) _controller.text = data!.text!;
                    await _import(library, true);
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SidifyButton(
                  label: 'Replace all',
                  small: true,
                  variant: SidifyButtonVariant.danger,
                  onTap: () => _import(library, false),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
