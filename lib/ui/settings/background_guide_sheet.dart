import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../widgets/neon.dart';
import '../../core/theme/ifall_ui.dart';

/// "Instructions to play in background" — the guide the web app ships in
/// Settings, rewritten for a real Android app.
Future<void> showBackgroundGuideSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext sheetContext) => const _BackgroundGuideSheet(),
  );
}

class _BackgroundGuideSheet extends StatelessWidget {
  const _BackgroundGuideSheet();

  static const List<(String, String)> _steps = <(String, String)>[
    (
      'Start a song first',
      'Background audio only keeps running once IfallMusic is actually playing '
          'something. Press play, then lock the screen or switch apps.',
    ),
    (
      'Keep the notification visible',
      'Do not swipe IfallMusic away from the notification shade. That is the '
          'service holding the audio session open — dismissing it can stop '
          'playback on some phones.',
    ),
    (
      'Turn off battery optimisation for IfallMusic',
      'Settings → Apps → IfallMusic → Battery → choose “Unrestricted” (or “No '
          'restrictions”). This is the single most common reason music stops '
          'after a few minutes.',
    ),
    (
      'Allow background activity',
      'Settings → Apps → IfallMusic → allow “Background activity” / “Display over '
          'other apps”. Manufacturer skins (MIUI, ColorOS, One UI, OxygenOS) '
          'each have their own switch.',
    ),
    (
      'Lock IfallMusic in Recents',
      'Open Recents, pull the IfallMusic card down and tap the lock icon. The app '
          'will not be killed when you clear recent apps.',
    ),
    (
      'Use wired or Bluetooth audio',
      'Headsets keep the audio route alive and let the OS media controls work '
          'from the lock screen.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (BuildContext context, ScrollController controller) {
        return Container(
          decoration: const BoxDecoration(
            color: IfallTokens.surface,
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(SaxifyTheme.radiusLg)),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
            children: <Widget>[
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: IfallTokens.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: accent.gradient,
                ),
                child: const Icon(Icons.headphones_battery_rounded,
                    color: Colors.black, size: 26),
              ),
              const SizedBox(height: 14),
              Text(
                'Instructions to play in background',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 19, fontWeight: FontWeight.w700, height: 1.2),
              ),
              const SizedBox(height: 6),
              const Text(
                'Keep the music going with the screen off or the app closed.',
                style: TextStyle(fontSize: 12.5, color: IfallTokens.textMuted),
              ),
              const SizedBox(height: 20),
              for (int i = 0; i < _steps.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: 26,
                        height: 26,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: accent.primary.withValues(alpha: 0.16),
                          border: Border.all(
                              color: accent.primary.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: accent.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              _steps[i].$1,
                              style: const TextStyle(
                                  fontSize: 13.5, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _steps[i].$2,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  height: 1.5,
                                  color: IfallTokens.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 6),
              NeonCard(
                background: accent.primary.withValues(alpha: 0.10),
                borderColor: accent.primary.withValues(alpha: 0.30),
                child: Row(
                  children: <Widget>[
                    Icon(Icons.tips_and_updates_outlined,
                        size: 20, color: accent.primary),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Still cutting out? Turn on “Autoplay” and “Gapless '
                        'playback” in Settings — if a stream dies, IfallMusic skips '
                        'to a similar track instead of stopping.',
                        style: TextStyle(fontSize: 12, height: 1.5),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
