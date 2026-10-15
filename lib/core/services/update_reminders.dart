import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'update_service.dart';

/// Android schedules checks approximately every six hours (battery/Doze may
/// defer them). Never downloads an APK without the listener's confirmation.
class UpdateReminders {
  static final _notifications = FlutterLocalNotificationsPlugin();
  static const _id = 7401;
  static const _lastKey = 'sidify.update.last_notice';
  static const _versionKey = 'sidify.update.notice_version';

  static Future<bool> initialize({VoidCallback? onTap}) async {
    if (kIsWeb || !Platform.isAndroid) return false;
    await _notifications.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification_music'),
      ),
      onDidReceiveNotificationResponse: (_) => onTap?.call(),
    );
    final launch = await _notifications.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp ?? false;
  }

  static Future<void> notify(UpdateInfo info) async {
    if (kIsWeb || !Platform.isAndroid) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final version = info.latestLabel;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (prefs.getString(_versionKey) == version &&
        now - (prefs.getInt(_lastKey) ?? 0) < const Duration(hours: 6).inMilliseconds) return;
    await _notifications.show(
      _id, 'New app available', 'Sidify $version — Update now',
      const NotificationDetails(android: AndroidNotificationDetails(
        'sidify_updates', 'App updates',
        channelDescription: 'Reminders when a newer Sidify is available',
        importance: Importance.defaultImportance,
        priority: Priority.defaultPriority,
        autoCancel: true,
      )),
      payload: 'app-update',
    );
    await prefs.setString(_versionKey, version);
    await prefs.setInt(_lastKey, now);
  }

  static Future<bool> backgroundCheck() async {
    final service = UpdateService();
    try {
      await initialize();
      final info = await service.check();
      if (info == null) return false;
      if (info.hasUpdate && info.downloadable) {
        await notify(info);
      } else if (!info.hasUpdate) {
        await _notifications.cancel(_id);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      service.dispose();
    }
  }
}
