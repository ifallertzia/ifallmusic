import 'package:flutter/material.dart';
import '../../config/branding.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/saxify_theme.dart';

/// App diagnostics — deliberately short and human readable.
///
/// The old build let you point the app at a remote downloader backend and then
/// reported on it here. That whole section is gone: nothing in IfallMusic
/// depends on a server, so there is nothing to poll.
class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key, required this.safeMode});

  final bool safeMode;

  @override
  Widget build(BuildContext context) {
    return AuroraBackdrop(
      intensity: 0.65,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(title: const Text('Diagnostics')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 60),
          children: <Widget>[
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Icon(Icons.info_outline_rounded, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${IfallBranding.appName} ${IfallBranding.fullVersionLabel}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    safeMode
                        ? 'Safe mode is on — heavy startup steps were skipped. Playback still works.'
                        : 'Everything is running normally.',
                    style: const TextStyle(
                      color: SaxifyColors.textMuted,
                      fontSize: 12.5,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Audio', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  _Row(
                    label: '8D audio',
                    value: 'Coming soon',
                  ),
                  const SizedBox(height: 6),
                  _Row(
                    label: 'Download folder',
                    value: 'Download/${IfallBranding.downloadFolderName}',
                  ),
                  const SizedBox(height: 6),
                  const _Row(label: 'Downloads', value: 'On-device · no backend'),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GlassPanel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('Branding', style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Text(
                    'Logo ${IfallBranding.logoWidth.toInt()}×${IfallBranding.logoHeight.toInt()} '
                    '${IfallBranding.logoFormat}\n${IfallBranding.logoAsset}',
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: SaxifyColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 12.5, color: SaxifyColors.textSecondary),
          ),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Text(
            value,
            maxLines: 2,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
