import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/services/update_service.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../widgets/neon.dart';
import '../widgets/saxify_logo.dart';

/// Runs an update check and, if a newer release exists, shows the
/// "Update available" dialog with in-app download + install.
Future<void> checkAndPromptUpdate(BuildContext context, {bool silent = true}) async {
  final UpdateService service = UpdateService();
  try {
    final UpdateInfo? info = await service.check();
    if (!context.mounted) return;
    if (info == null) {
      if (!silent) _toast(context, 'Could not reach the update server');
      return;
    }
    if (!info.hasUpdate) {
      if (!silent) _toast(context, 'You are on the latest version');
      return;
    }
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext c) => _UpdateDialog(info: info),
    );
  } finally {
    service.dispose();
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

enum _Phase { idle, downloading, done, error }

/// Clean, short changelog shown in the in-app update dialog — only the items
/// that matter to the listener. The full release body on GitHub is intentionally
/// not shown here so the dialog stays focused.
const String _kShortChangelog =
    '• Lyrics support added\n'
    '• Important bug fixes';

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  final UpdateService _service = UpdateService();
  _Phase _phase = _Phase.idle;
  double _progress = 0;
  String? _error;

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final String? url = widget.info.apkUrl;
    if (url == null) return;
    setState(() {
      _phase = _Phase.downloading;
      _progress = 0;
      _error = null;
    });
    try {
      final String path = await _service.downloadApk(
        url,
        onProgress: (double fraction, int bytes) {
          if (!mounted) return;
          setState(() => _progress = fraction);
        },
      );
      if (!mounted) return;
      setState(() => _phase = _Phase.done);
      await _service.install(path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.error;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final UpdateInfo info = widget.info;

    return Dialog(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const SaxifyLogo(size: 40),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('Update available',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(
                        '${info.currentVersion} → ${info.latestVersion}'
                        '${info.sizeLabel.isNotEmpty ? ' · ${info.sizeLabel}' : ''}',
                        style: const TextStyle(
                            fontSize: 12.5, color: SaxifyColors.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SaxifyColors.surfaceAlt,
                borderRadius: BorderRadius.circular(SaxifyTheme.radiusSm),
                border: Border.all(color: SaxifyColors.border),
              ),
              child: Text(
                _kShortChangelog,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.55,
                  color: SaxifyColors.textSecondary,
                ),
              ),
            ),
            const SizedBox(height: 18),
            if (_phase == _Phase.downloading) ...<Widget>[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                'Downloading… ${(_progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                    fontSize: 12, color: SaxifyColors.textMuted),
              ),
            ] else if (_phase == _Phase.error) ...<Widget>[
              Text(
                'Download failed: $_error',
                style: const TextStyle(
                    fontSize: 12, color: SaxifyColors.danger),
              ),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: NeonButton(
                      label: 'Retry',
                      compact: true,
                      onPressed: _start,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NeonButton(
                      label: 'Cancel',
                      filled: false,
                      compact: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ] else ...<Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: NeonButton(
                      label: info.downloadable ? 'Update now' : 'Not available',
                      icon: Icons.system_update_rounded,
                      compact: true,
                      onPressed: info.downloadable ? _start : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: NeonButton(
                      label: 'Later',
                      filled: false,
                      compact: true,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
              if (!info.downloadable) ...<Widget>[
                const SizedBox(height: 10),
                const Text(
                  'This release has no APK attached yet. Attach '
                  '"app-release.apk" to the GitHub release to enable in-app '
                  'install.',
                  style: TextStyle(
                      fontSize: 11.5, color: SaxifyColors.textMuted),
                ),
              ],
            ],
            if (_phase == _Phase.done) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                'APK downloaded — the installer should now open.\n\n'
                'If you see "App not installed / package conflicts", that '
                'means the old app was signed with a different key. '
                'Uninstall the old IfallMusic (your library can be backed '
                'up from Settings > Backup library) and install again.',
                style: TextStyle(fontSize: 11.5, height: 1.45, color: accent.primary),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
