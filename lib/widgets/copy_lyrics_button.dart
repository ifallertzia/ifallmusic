import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CopyLyricsButton extends StatefulWidget {
  const CopyLyricsButton({
    super.key,
    required this.plain,
    this.iconOnly = false,
  });
  final String plain;
  final bool iconOnly;
  @override
  State<CopyLyricsButton> createState() => _CopyLyricsButtonState();
}

class _CopyLyricsButtonState extends State<CopyLyricsButton> {
  bool _copied = false;
  Timer? _reset;
  Future<void> _copy() async {
    try {
      await Clipboard.setData(ClipboardData(text: widget.plain));
      if (!mounted) return;
      setState(() => _copied = true);
      _reset = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _copied = false);
      });
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Couldn't copy — select the lyrics manually."),
          ),
        );
    }
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Copy lyrics',
    child: widget.iconOnly
        ? IconButton(
            tooltip: _copied ? 'Copied' : 'Copy',
            onPressed: _copied ? null : _copy,
            icon: Icon(_copied ? Icons.check : Icons.content_copy),
          )
        : OutlinedButton.icon(
            onPressed: _copied || widget.plain.isEmpty ? null : _copy,
            icon: Icon(_copied ? Icons.check : Icons.content_copy, size: 16),
            label: Text(_copied ? 'Copied' : 'Copy'),
          ),
  );
}
