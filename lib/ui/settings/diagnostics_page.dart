import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/branding.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/boot_log.dart';
import '../../core/services/native_bridge.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../widgets/sidify_widgets.dart';

/// Diagnostics: what the app is running, the last playback error, and the
/// boot log — the page to open when something misbehaves. Copyable, so a
/// report can be pasted anywhere.
class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  String _log = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final String log = await BootLog.tail();
    if (!mounted) return;
    setState(() {
      _log = log;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final PlaybackService playback = context.watch<PlaybackService>();
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Diagnostics', style: SidifyText.titleM(t.text)),
        actions: <Widget>[
          IconButton(
            icon: Icon(Icons.copy_rounded, size: 19, color: t.text),
            tooltip: 'Copy report',
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: 'Sidify diagnostics\n$_log'),
              );
              showAppNotice('Diagnostics copied');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 60),
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          SidifyGroup(
            header: 'App',
            children: <Widget>[
              _row(context, 'App', 'Sidify ${SidifyBranding.fullVersionLabel}'),
              _row(context, 'Package', SidifyBranding.packageName),
              _row(context, 'Platform',
                  '${Platform.operatingSystem} ${Platform.operatingSystemVersion.split(' ').take(2).join(' ')}'),
              _row(
                context,
                'Downloads',
                'On-device · saved in the app',
              ),
            ],
          ),
          SidifyGroup(
            header: 'Playback',
            children: <Widget>[
              _row(
                context,
                'Now playing',
                playback.current?.title ?? 'Nothing',
              ),
              _row(
                context,
                'State',
                playback.isPlaying
                    ? 'Playing'
                    : playback.isLoading
                        ? 'Loading'
                        : 'Paused',
              ),
              _row(
                context,
                'Last error',
                playback.lastError?.body ?? 'None',
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'BOOT LOG',
              style: SidifyText.eyebrow(t.text2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: t.raised.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _loading
                    ? 'Loading…'
                    : (_log.isEmpty ? 'The boot log is empty.' : _log),
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.5,
                  color: t.text2,
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SidifyButton(
              label: 'Repair local cache',
              variant: SidifyButtonVariant.secondary,
              onTap: () async {
                await NativeBridge.repairLocalCache();
                showAppNotice('Cache repaired');
                _load();
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final SidifyTokens t = context.sidify;
    return Container(
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(fontSize: 13.5, color: t.text2),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(fontSize: 13.5, color: t.text),
            ),
          ),
        ],
      ),
    );
  }
}
