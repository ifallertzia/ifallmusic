import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The one local-notification plugin this app owns.
///
/// `flutter_local_notifications` keeps a single method channel for the whole
/// process, and whichever plugin instance calls `initialize()` last becomes the
/// one that receives taps — a second instance quietly steals them from the
/// first. So there is exactly one instance, one `initialize()`, and everyone
/// who posts a notification registers the payload prefix it wants back.
class AppNotifications {
  AppNotifications._();

  static final FlutterLocalNotificationsPlugin plugin =
      FlutterLocalNotificationsPlugin();

  /// The small icon every notification in the app wears unless it names its
  /// own (`AndroidInitializationSettings` needs a drawable, not a resource id).
  static const String icon = 'ic_notification_music';

  static final Map<String, void Function(NotificationResponse response)>
      _routes = <String, void Function(NotificationResponse response)>{};

  static bool _ready = false;
  static bool _askedPermission = false;
  static Future<void>? _starting;

  /// Notifications are an Android extra here: on every other platform the same
  /// calls are no-ops, so nothing downstream has to guard for the platform.
  static bool get supported => !kIsWeb && Platform.isAndroid;

  static AndroidFlutterLocalNotificationsPlugin? get _android => plugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// Claims taps (and action buttons) on every notification whose payload
  /// starts with [payloadPrefix].
  static void route(
    String payloadPrefix,
    void Function(NotificationResponse response) handler,
  ) {
    _routes[payloadPrefix] = handler;
  }

  static Future<void> ensureInitialized() {
    if (!supported || _ready) return Future<void>.value();
    return _starting ??= _initialize();
  }

  static Future<void> _initialize() async {
    try {
      await plugin.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings(icon),
        ),
        onDidReceiveNotificationResponse: _deliver,
      );
      _ready = true;
    } catch (error) {
      // A notification failure must never take a download or an update check
      // down with it.
      debugPrint('[Sidify][Notifications] init skipped: $error');
    } finally {
      _starting = null;
    }
  }

  static void _deliver(NotificationResponse response) {
    final String payload = response.payload ?? '';
    for (final MapEntry<String, void Function(NotificationResponse)> route
        in _routes.entries) {
      if (payload == route.key || payload.startsWith(route.key)) {
        route.value(response);
        return;
      }
    }
  }

  /// Android 13+. Asked once, at the first notification the app really wants
  /// to show; a denial only costs the notification, never the download.
  static Future<void> requestPermission() async {
    if (!supported || _askedPermission) return;
    _askedPermission = true;
    try {
      await _android?.requestNotificationsPermission();
    } catch (error) {
      debugPrint('[Sidify][Notifications] permission skipped: $error');
    }
  }

  static Future<void> show(
    int id,
    String title,
    String body,
    NotificationDetails details, {
    String? payload,
  }) async {
    if (!supported) return;
    await ensureInitialized();
    if (!_ready) return;
    try {
      await plugin.show(id, title, body, details, payload: payload);
    } catch (error) {
      debugPrint('[Sidify][Notifications] show($id) skipped: $error');
    }
  }

  static Future<void> cancel(int id) async {
    if (!supported || !_ready) return;
    try {
      await plugin.cancel(id);
    } catch (error) {
      debugPrint('[Sidify][Notifications] cancel($id) skipped: $error');
    }
  }

  /// What Android says is in the shade right now.
  ///
  /// The plugin has no "the user swiped this away" callback, but it can answer
  /// this — which is how a dismissed notification can stay dismissed. `null`
  /// means the question could not be asked, which callers must not read as
  /// "nothing is showing".
  static Future<Set<int>?> activeIds() async {
    if (!supported || !_ready) return null;
    final AndroidFlutterLocalNotificationsPlugin? android = _android;
    if (android == null) return null;
    try {
      final List<ActiveNotification> active =
          await android.getActiveNotifications();
      return active
          .map((ActiveNotification n) => n.id)
          .whereType<int>()
          .toSet();
    } catch (error) {
      debugPrint('[Sidify][Notifications] active list skipped: $error');
      return null;
    }
  }
}
