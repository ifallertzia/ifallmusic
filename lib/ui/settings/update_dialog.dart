import 'package:flutter/material.dart';

import '../../config/branding.dart';
import '../../core/services/update_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../widgets/sidify_widgets.dart';

/// Check for updates, and install the new build in place when there is one.
/// The APK it installs is signed with the same release key as always, so it
/// lands over the current app with no conflict (see docs/RELEASE_SIGNING.md).
Future<void> showUpdateDialog(BuildContext context) async {
  final SidifyTokens t = context.sidify;
  final UpdateService service = UpdateService();
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext dialogContext) => AlertDialog(
      backgroundColor: t.raised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      content: Row(
        children: <Widget>[
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: t.text2),
          ),
          const SizedBox(width: 14),
          Text('Checking for updates…', style: TextStyle(color: t.text)),
        ],
      ),
    ),
  );
  UpdateInfo? info;
  try {
    info = await service.check();
  } catch (_) {
    info = null;
  }
  if (!context.mounted) return;
  Navigator.of(context).pop();
  if (info == null) {
    return showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: t.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Could not check', style: SidifyText.title(t.text)),
        content: Text(
          'The update check did not answer. You can always get the latest '
          'Sidify app from ${SidifyBranding.websiteUrl.replaceAll('https://', '')}.',
          style: TextStyle(color: t.text2),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Close', style: TextStyle(color: t.text)),
          ),
        ],
      ),
    );
  }
  return showDialog<void>(
    context: context,
    builder: (BuildContext dialogContext) =>
        _UpdateDialog(service: service, info: info!),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.service, required this.info});

  final UpdateService service;
  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  double _progress = -1;
  String? _error;

  Future<void> _download() async {
    final String? url = widget.info.apkUrl;
    if (url == null) return;
    setState(() {
      _progress = 0;
      _error = null;
    });
    try {
      final String path = await widget.service.downloadApk(
        url,
        onProgress: (double fraction, int _) {
          if (mounted) setState(() => _progress = fraction);
        },
      );
      await widget.service.install(path);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = -1;
          _error = 'Download failed. Check the connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final UpdateInfo info = widget.info;
    return AlertDialog(
      backgroundColor: t.raised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Row(
        children: <Widget>[
          const SidifyLogoMark(size: 34),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              info.hasUpdate ? 'Update available' : 'You are up to date',
              style: SidifyText.title(t.text),
            ),
          ),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            info.hasUpdate
                ? 'Sidify ${info.latestLabel} is ready'
                    '${info.sizeLabel.isNotEmpty ? ' · ${info.sizeLabel}' : ''}. '
                    'It installs over this app — your library, settings and '
                    'downloads stay put.'
                : 'Sidify ${info.currentLabel} is the latest build.',
            style: TextStyle(fontSize: 14, height: 1.45, color: t.text2),
          ),
          if (info.hasUpdate && info.notes.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              info.notes,
              style: TextStyle(fontSize: 13, height: 1.45, color: t.text2),
            ),
          ],
          if (_progress >= 0) ...<Widget>[
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 5,
                backgroundColor: t.fill2,
                color: t.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Downloading… ${(_progress * 100).round()}%',
              style: TextStyle(fontSize: 12.5, color: t.text2),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(fontSize: 13, color: t.danger)),
          ],
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _progress >= 0
              ? null
              : () => Navigator.of(context).pop(),
          child: Text(
            info.hasUpdate ? 'Later' : 'Close',
            style: TextStyle(color: t.text2),
          ),
        ),
        if (info.hasUpdate && info.downloadable)
          TextButton(
            onPressed: _progress >= 0 ? null : _download,
            child: Text(
              _progress >= 0 ? 'Downloading…' : 'Download & install',
              style: TextStyle(color: t.text, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}
