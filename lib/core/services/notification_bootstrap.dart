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
          androidNotificationChannelId: 'com.ifallmusic.app.playback.v2',
          androidNotificationChannelName: 'IfallMusic playback',
          androidNotificationChannelDescription:
              'Playback, queue and favourite controls',
          // Keeping the foreground service alive on pause (false) already
          // forces an ongoing notification, so a stray swipe cannot kill a
          // long track. `androidNotificationOngoing: true` is rejected by
          // audio_service unless stopForegroundOnPause is also true, and
          // would only restate what the foreground service does anyway.
          androidNotificationOngoing: false,
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

  /// Phones with aggressive battery optimisation (Xiaomi, Realme, Oppo,
  /// Samsung) kill a long background track after a few minutes. Asking once
  /// moves IfallMusic onto the unrestricted list; OEMs that ignore the
  /// request fall back to the guide sheet in Settings.
  static bool _batteryAsked = false;

  static Future<void> requestBatteryExemption() async {
    if (_batteryAsked || kIsWeb || !Platform.isAndroid) return;
    _batteryAsked = true;
    try {
      if (await Permission.ignoreBatteryOptimizations.isGranted) return;
      await Permission.ignoreBatteryOptimizations.request();
    } catch (e) {
      debugPrint('[IfallMusic][Battery] request skipped: $e');
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
