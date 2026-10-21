import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/foss_build.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/sidify_theme.dart';
import '../../ui/settings/update_dialog.dart';
import '../../ui/shell/sidify_shell_controller.dart';
import '../../ui/widgets/sidify_widgets.dart';

void openMovieSettingsPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const MovieSettingsPage(),
      settings: const RouteSettings(name: 'sidify/movie-settings'),
    ),
  );
}

/// Movies-mode settings. Uses the app's existing (single) theme system and
/// update flow — no parallel movie-only theme or updater is created.
class MovieSettingsPage extends StatelessWidget {
  const MovieSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final SettingsService settings = context.watch<SettingsService>();
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: t.text, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Settings', style: SidifyText.title(t.text)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 190),
        children: <Widget>[
          SidifyGroup(
            header: 'Appearance',
            footer: 'Theme applies across Music and Movies.',
            children: <Widget>[
              SidifyGroupRow(
                icon: Icons.dark_mode_rounded,
                title: 'Theme',
                trailing: SidifyChips(
                  small: true,
                  value: settings.themeModeRaw,
                  options: const <(String, String)>[
                    ('dark', 'Dark'),
                    ('light', 'Light'),
                    ('system', 'Auto'),
                  ],
                  onChanged: (String v) => settings.setThemeMode(
                    v == 'light'
                        ? ThemeMode.light
                        : v == 'system'
                            ? ThemeMode.system
                            : ThemeMode.dark,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Accent colour', style: SidifyText.label(t.text)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: <Widget>[
                        for (final SaxifyAccent accent in SaxifyAccents.presets)
                          _AccentSwatch(
                            accent: accent,
                            selected: settings.accentId == accent.id,
                            onTap: () => settings.setAccentId(accent.id),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SidifyGroup(
            header: 'App',
            children: <Widget>[
              if (FossBuild.githubUpdaterEnabled)
                SidifyGroupRow(
                  icon: Icons.system_update_rounded,
                  title: 'Check for update',
                  subtitle: 'Download and install the latest version',
                  chevron: true,
                  onTap: () => showUpdateDialog(context),
                ),
              SidifyGroupRow(
                icon: Icons.music_note_rounded,
                title: 'Switch to Music',
                chevron: true,
                onTap: () {
                  Navigator.of(context).maybePop();
                  context.read<SidifyShellController>().switchMode();
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final SaxifyAccent accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return Tooltip(
      message: accent.label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: accent.gradient,
            border: Border.all(
              color: selected ? t.text : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? const Icon(Icons.check_rounded, size: 18, color: Colors.white)
              : null,
        ),
      ),
    );
  }
}
