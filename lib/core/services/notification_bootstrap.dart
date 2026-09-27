import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import 'media_notification_handler.dart';

/// Lock-screen / Bluetooth controls via the app-owned audio_service handler.
///
/// Init is optional. If it fails, the existing [AudioPlayer] path still works.
class NotificationBootstrap {
  NotificationBootstrap._();

  static bool active = false;
  static MediaNotificationHandler? handler;
  static bool _asked = false;

  static Future<bool> init() async {
    if (active) return true;
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return false;
    try {
      handler = await AudioService.init<MediaNotificationHandler>(
        builder: MediaNotificationHandler.new,
        config: const AudioServiceConfig(
          androidNotificationChannelId: 'com.saxify.app.playback.v2',
          androidNotificationChannelName: 'IfallMusic playback',
          androidNotificationChannelDescription:
              'Playback, queue and favourite controls',
          androidNotificationOngoing: true,
          androidStopForegroundOnPause: false,
          androidNotificationIcon: 'drawable/ic_notification_music',
        ),
      );
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      active = true;
      return true;
    } catch (e) {
      debugPrint('[IfallMusic][Notify] init skipped: $e');
      active = false;
      return false;
    }
  }

  /// Android 13+. Denied permission still leaves in-app playback working.
  static Future<void> requestOnFirstPlay() async {
    if (_asked || kIsWeb || !Platform.isAndroid) return;
    _asked = true;
    try {
      final PermissionStatus status = await Permission.notification.status;
      if (status.isGranted || status.isLimited) return;
      await Permission.notification.request();
    } catch (e) {
      debugPrint('[IfallMusic][Notify] permission: $e');
    }
  }
}
