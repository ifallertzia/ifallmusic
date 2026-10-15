# Update reminders and waveform QA

## Behavior
- Search subscribes to the same session mood-cover catalog as Explore and starts loading it even when Explore has not been visited. Failed image requests retain colored tiles.
- One second after the first frame, a silent release check begins. A confirmed, downloadable newer build opens the existing Update now / Later dialog. Network latency can delay the offer beyond one second. No update or a failed check produces no automatic error dialog.
- Foreground checks/resume checks are throttled to six hours. A shared dialog guard prevents automatic/manual offers stacking.
- Android WorkManager checks approximately every six hours with a network constraint. Doze, force-stop and manufacturer battery restrictions can delay/prevent work. Notification permission is required for system notifications; the in-app offer works without it.
- Notifications use one replaceable ID and a persisted six-hour per-release cooldown. Tapping opens the app; a fresh check offers the update. Newer version/build detection and APK install flow remain unchanged.
- Wave phase is decorative (not FFT/audio amplitude sampling). Playhead/labels remain driven by real position/duration. Pausing, buffering, reduced motion and disabled tickers stop phase animation. No playback engine or volume controls changed.

## Validation
This workspace has no Flutter/Dart SDK. Added tests have not been executed here.

Run in a Flutter-enabled environment:
```
flutter pub get
flutter analyze
flutter test test/waveform_seek_bar_test.dart test/automatic_update_dialog_test.dart test/update_version_compare_test.dart
flutter build apk --debug
```

Device checks:
1. Open Search before Explore: tile images progressively appear, taps still open the correct mood.
2. Use an older installed version: launch offer, Later, manual check, Update now/download/install. Verify offline/current-version launches stay quiet.
3. Allow notifications; background the app through a scheduled check, tap the update notification, verify one dialog. Repeat with notification permission denied.
4. Seek at 0%, middle, end; drag/cancel, pause/resume, buffering, unknown duration, rapid track changes, different artwork, reduced-motion setting.
5. Profile waveform in release/profile mode on a 60 Hz device; verify frame budget and unchanged volume interaction.
