import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/foss_build.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/settings_service.dart';
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(Icons.dark_mode_rounded, size: 19, color: t.text2),
                        const SizedBox(width: 10),
                        Text('Theme', style: SidifyText.label(t.text)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    SidifyChips(
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
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SidifyGroup(
            header: 'App',
            children: <Widget>[
              SidifyGroupRow(
                icon: Icons.lock_outline_rounded,
                title: 'Password',
                chevron: true,
                onTap: () => _showPasswordDialog(context),
              ),
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

bool _matchesUnlockPassphrase(String value) {
  const List<int> expectedCodeUnits = <int>[119, 97, 116, 101, 114];
  final List<int> actualCodeUnits = value.codeUnits;
  if (actualCodeUnits.length != expectedCodeUnits.length) return false;
  for (int i = 0; i < expectedCodeUnits.length; i++) {
    if (actualCodeUnits[i] != expectedCodeUnits[i]) return false;
  }
  return true;
}

Future<void> _showPasswordDialog(BuildContext context) async {
  final TextEditingController controller = TextEditingController();
  final String? entered = await showDialog<String>(
    context: context,
    builder: (BuildContext dialogContext) => AlertDialog(
      title: const Text('Password'),
      content: TextField(
        controller: controller,
        autofocus: true,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        textInputAction: TextInputAction.done,
        onSubmitted: (String value) =>
            Navigator.of(dialogContext).pop(value),
        decoration: const InputDecoration(labelText: 'Password'),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(controller.text),
          child: const Text('Continue'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (entered == null || !context.mounted) return;

  final SettingsService settings = context.read<SettingsService>();
  if (_matchesUnlockPassphrase(entered)) {
    await settings.setAdultContentUnlocked(true);
    if (context.mounted) showAppNotice('Adult content unlocked');
  } else {
    showAppNotice('Incorrect password');
  }
}
