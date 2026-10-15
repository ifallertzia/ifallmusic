import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

import 'recommendation_store.dart';
import 'update_reminders.dart';

/// Re-ranks the on-device cache every 6 hours. Does not touch playback.
@pragma('vm:entry-point')
void saxifyRecommendationDispatcher() {
  Workmanager().executeTask((String task, Map<String, dynamic>? input) async {
    try {
      WidgetsFlutterBinding.ensureInitialized();
      if (task == 'checkAppUpdate') {
        return await UpdateReminders.backgroundCheck();
      }
      final RecommendationStore store = RecommendationStore();
      await store.open();
      await store.touchCache();
      return true;
    } catch (_) {
      return false;
    }
  });
}

Future<void> registerRecommendationRefresh() async {
  await Workmanager().initialize(saxifyRecommendationDispatcher);
  await registerUpdateReminders();
  await Workmanager().registerPeriodicTask(
    'saxify-reco',
    'refreshRecommendations',
    frequency: const Duration(hours: 6),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

Future<void> registerUpdateReminders() async {
  await Workmanager().registerPeriodicTask(
    'sidify-update-check', 'checkAppUpdate',
    frequency: const Duration(hours: 6),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
