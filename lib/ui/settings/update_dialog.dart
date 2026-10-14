import 'dart:async';

import 'package:flutter/material.dart';

import '../../config/branding.dart';
import '../../core/services/update_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../widgets/sidify_widgets.dart';

/// Opens the in-app updater: it checks GitHub Releases, and when a newer build
/// is published it offers **Update now** — which downloads the APK with a live
/// percentage and then hands it to the Android installer.
///
/// The APK it installs is signed with the same release key as always, so it
/// lands over the current app with no conflict (see docs/RELEASE_SIGNING.md).
Future<void> showUpdateDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    // One dialog owns the whole flow (check → offer → download → install), so
    // there is no second route to pop and nothing to get out of step.
    barrierDismissible: false,
    builder: (BuildContext dialogContext) =>
        _UpdateDialog(service: UpdateService()),
  );
}

/// Where the updater is in its flow.
enum _Stage {
  checking,
  couldNotCheck,
  upToDate,
  available,
  downloading,
  ready,
  failed,
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.service});

  final UpdateService service;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  /// A 20 MB APK on a slow mobile connection still lands inside this; the cap
  /// exists so a stalled download can never trap the listener in the dialog.
  static const Duration _downloadTimeout = Duration(minutes: 10);

  _Stage _stage = _Stage.checking;
  UpdateInfo? _info;
  String? _apkPath;
  double _progress = 0;
  String _error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  @override
  void dispose() {
    widget.service.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    UpdateInfo? info;
    try {
      info = await widget.service.check();
    } catch (_) {
      info = null;
    }
    if (!mounted) return;
    setState(() {
      _info = info;
      _stage = info == null
          ? _Stage.couldNotCheck
          : info.hasUpdate
              ? _Stage.available
              : _Stage.upToDate;
    });
  }

  /// Downloads the release APK, reporting progress, then opens the installer.
  Future<void> _updateNow() async {
    final String? url = _info?.apkUrl;
    if (url == null) return;
    setState(() {
      _stage = _Stage.downloading;
      _progress = 0;
      _error = '';
    });
    try {
      final String path = await widget.service
          .downloadApk(
            url,
            onProgress: (double fraction, int _) {
              if (mounted) setState(() => _progress = fraction);
            },
          )
          .timeout(_downloadTimeout);
      if (!mounted) return;
      _apkPath = path;
      setState(() => _progress = 1);
      await _install();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = 'The download did not finish. Check the connection and try '
            'again.';
      });
    }
  }

  /// Hands the APK to Android's package installer — the system prompt is what
  /// actually installs it. Kept as its own step so the listener can re-open the
  /// installer if they backed out of the prompt.
  Future<void> _install() async {
    final String? path = _apkPath;
    if (path == null) return;
    if (mounted) setState(() => _stage = _Stage.ready);
    try {
      await widget.service.install(path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _Stage.failed;
        _error = 'Sidify could not open the installer. Try again, and allow '
            '"Install unknown apps" for Sidify if Android asks.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    // Restraint at huge system font scales: the dialog keeps its shape and the
    // buttons stay inside it instead of pushing past the edge.
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.2,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: t.hairline, width: 0.75),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(alpha: t.isDark ? 0.5 : 0.18),
                  blurRadius: 40,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _head(t),
                  Flexible(
                    // Nothing in the dialog can ever be taller than the screen:
                    // long copy scrolls, it does not overflow.
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.only(top: 10),
                      child: _body(t),
                    ),
                  ),
                  _actions(t),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _head(SidifyTokens t) {
    return Row(
      children: <Widget>[
        const SidifyLogoMark(size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            _title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: SidifyText.title(t.text),
          ),
        ),
      ],
    );
  }

  String get _title => switch (_stage) {
        _Stage.checking => 'Checking for updates',
        _Stage.couldNotCheck => 'Could not check',
        _Stage.upToDate => 'You are up to date',
        _Stage.available || _Stage.downloading => 'New app available',
        _Stage.ready => 'Ready to install',
        _Stage.failed => 'Update not installed',
      };

  Widget _body(SidifyTokens t) {
    final UpdateInfo? info = _info;
    final String size = info?.sizeLabel ?? '';
    return switch (_stage) {
      _Stage.checking => Row(
        children: <Widget>[
          SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2, color: t.text2),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Looking for a newer Sidify…',
              style: TextStyle(fontSize: 13.5, height: 1.45, color: t.text2),
            ),
          ),
        ],
      ),
      _Stage.couldNotCheck => _copy(
        t,
        'The update check did not answer. You can always get the latest '
        'Sidify app from '
        '${SidifyBranding.websiteUrl.replaceAll('https://', '')}.',
      ),
      _Stage.upToDate => _copy(
        t,
        'Sidify ${info?.currentLabel ?? ''} is the latest build.',
      ),
      _Stage.available => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            'Sidify ${info?.latestLabel ?? ''}'
            '${size.isNotEmpty ? ' · $size' : ''}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: t.text,
            ),
          ),
          const SizedBox(height: 6),
          _copy(
            t,
            'It installs over this app — your library, settings and downloads '
            'stay put.',
          ),
        ],
      ),
      _Stage.downloading => _downloadReadOut(t, size),
      _Stage.ready => _copy(
        t,
        'The download is finished. Tap Install in the Android prompt that just '
        'opened.',
      ),
      _Stage.failed => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _copy(t, _error),
          if (size.isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            _copy(t, 'Update ${info!.latestLabel} · $size'),
          ],
        ],
      ),
    };
  }

  /// The live download read-out: the percentage counts up while the bar fills.
  Widget _downloadReadOut(SidifyTokens t, String size) {
    // No content-length means no honest fraction — spin instead of lying.
    final bool measured = _progress > 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Text(
              measured ? '${(_progress * 100).round()}%' : '…',
              style: TextStyle(
                fontSize: 26,
                height: 1,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.6,
                color: t.text,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  size.isNotEmpty ? 'of $size' : 'downloading',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: t.text2),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: measured ? _progress : null,
            minHeight: 6,
            backgroundColor: t.fill2,
            color: t.text,
          ),
        ),
        const SizedBox(height: 8),
        _copy(t, 'Keep Sidify open — the installer starts by itself.'),
      ],
    );
  }

  Widget _copy(SidifyTokens t, String text) {
    return Text(
      text,
      style: TextStyle(fontSize: 13.5, height: 1.45, color: t.text2),
    );
  }

  /// Two equal cells, each label scaled down rather than clipped: the buttons
  /// can never leave the dialog, whatever the copy or the font scale.
  Widget _actions(SidifyTokens t) {
    final List<Widget> buttons = switch (_stage) {
      _Stage.checking || _Stage.downloading => <Widget>[],
      _Stage.couldNotCheck || _Stage.upToDate => <Widget>[
          _button(t, label: 'Close', primary: true, onTap: _close),
        ],
      _Stage.available => <Widget>[
          _button(t, label: 'Later', onTap: _close),
          _button(
            t,
            label: 'Update now',
            primary: true,
            onTap: _updateNow,
          ),
        ],
      _Stage.ready => <Widget>[
          _button(t, label: 'Later', onTap: _close),
          _button(t, label: 'Install', primary: true, onTap: _install),
        ],
      _Stage.failed => <Widget>[
          _button(t, label: 'Later', onTap: _close),
          _button(t, label: 'Try again', primary: true, onTap: _updateNow),
        ],
    };
    if (buttons.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < buttons.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 10),
            Expanded(child: buttons[i]),
          ],
        ],
      ),
    );
  }

  Widget _button(
    SidifyTokens t, {
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return Material(
      color: primary ? t.primary : t.fill2,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 44,
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: primary ? t.onPrimary : t.text,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _close() => Navigator.of(context).pop();
}
