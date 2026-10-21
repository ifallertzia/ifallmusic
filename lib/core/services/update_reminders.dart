import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../config/foss_build.dart';
import 'app_notifications.dart';
import 'update_service.dart';

/// Android schedules checks approximately every six hours (battery/Doze may
/// defer them). Never downloads an APK without the listener's confirmation.
///
/// Posts go through [AppNotifications]: the plugin has one method channel for
/// the whole process, and a second instance here would take the download
/// notifications' taps with it.
class UpdateReminders {
  static const int _id = 7401;
  static const String _lastKey = 'sidify.update.last_notice';
  static const String _versionKey = 'sidify.update.notice_version';

  /// The payload this reminder is recognised by when it is tapped.
  static const String payload = 'app-update';

  static Future<bool> initialize({VoidCallback? onTap}) async {
    if (!FossBuild.githubUpdaterEnabled) return false;
    if (!AppNotifications.supported) return false;
    if (onTap != null) {
      AppNotifications.route(payload, (NotificationResponse _) => onTap());
    }
    await AppNotifications.ensureInitialized();
    final NotificationAppLaunchDetails? launch =
        await AppNotifications.plugin.getNotificationAppLaunchDetails();
    return launch?.didNotificationLaunchApp ?? false;
  }

  static Future<void> notify(UpdateInfo info) async {
    if (!FossBuild.githubUpdaterEnabled) return;
    if (!AppNotifications.supported) return;
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final String version = info.latestLabel;
    final int now = DateTime.now().millisecondsSinceEpoch;
    if (prefs.getString(_versionKey) == version &&
        now - (prefs.getInt(_lastKey) ?? 0) <
            const Duration(hours: 6).inMilliseconds) return;
    await AppNotifications.show(
      _id,
      'New app available',
      'Sidify $version — Update now',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'sidify_updates',
          'App updates',
          channelDescription: 'Reminders when a newer Sidify is available',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          autoCancel: true,
        ),
      ),
      payload: payload,
    );
    await prefs.setString(_versionKey, version);
    await prefs.setInt(_lastKey, now);
  }

  static Future<bool> backgroundCheck() async {
    if (!FossBuild.githubUpdaterEnabled) return false;
    final UpdateService service = UpdateService();
    try {
      await initialize();
      final UpdateInfo? info = await service.check();
      if (info == null) return false;
      if (info.hasUpdate && info.downloadable) {
        await notify(info);
      } else if (!info.hasUpdate) {
        await AppNotifications.cancel(_id);
      }
      return true;
    } catch (_) {
      return false;
    } finally {
      service.dispose();
    }
  }
}
