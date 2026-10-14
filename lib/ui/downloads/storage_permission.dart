import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/native_bridge.dart';
import '../../core/theme/ifall_ui.dart';

/// English, short, and honest. Deny means stream-only — the app keeps going.
class StoragePermission {
  const StoragePermission._();

  static Future<bool> ensure(BuildContext context) async {
    if (!Platform.isAndroid) return true;
    final int sdk = await NativeBridge.sdkInt();
    // Android 10+ writes our own files through MediaStore. No storage prompt.
    if (sdk >= 29 || sdk == 0) return true;

    final PermissionStatus current = await Permission.storage.status;
    if (current.isGranted) return true;

    if (!context.mounted) return false;
    final bool? allow = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialog) => AlertDialog(
        title: const Text('Storage Permission Needed'),
        content: const Text(
          'To save songs to your Downloads folder, IfallMusic needs storage access.\n\n'
          'If you allow, songs save to /Download/IfallMusic/.\n'
          'If you deny, you can still stream, but nothing is saved.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Not now'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Allow'),
          ),
        ],
      ),
    );
    if (!context.mounted) return false;
    if (allow != true) {
      _denied(context);
      return false;
    }
    final PermissionStatus status = await Permission.storage.request();
    if (!status.isGranted) {
      if (context.mounted) _denied(context);
      return false;
    }
    return true;
  }

  static void _denied(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Storage denied. You can still stream. Nothing will be saved.'),
        backgroundColor: IfallTokens.surfaceAlt,
      ),
    );
  }
}
