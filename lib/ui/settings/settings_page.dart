import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/branding.dart';
import '../../core/services/library_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/format.dart';
import '../downloads/storage_permission.dart';
import '../player/equalizer_page.dart';
import '../shell/shell_controller.dart';
import '../widgets/neon.dart';
import '../widgets/saxify_logo.dart';
import 'background_guide_sheet.dart';
import 'backup_sheet.dart';
import 'playlist_sync_sheet.dart';
import 'update_dialog.dart';

/// `1.0` renders as `1x`, `1.25` as `1.25x` — so the chip matches a choice.
String _speedLabel(double speed) =>
    speed == speed.roundToDouble() ? '${speed.toInt()}x' : '${speed}x';

/// Settings — the same panels as before, rebuilt in liquid glass on black.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final LibraryService library = context.watch<LibraryService>();

    return AuroraBackdrop(
      intensity: 0.45,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          slivers: <Widget>[
            SliverAppBar(
              pinned: true,
              backgroundColor: Colors.transparent,
              title: Text(
                'Settings',
                style: SaxifyTheme.appleFont(
                  size: 22,
                  weight: FontWeight.w800,
                  letterSpacing: -0.6,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 210),
              sliver: SliverList(
                delegate: SliverChildListDelegate(<Widget>[
                  // ------------------------------------------------ Account
                  const _PanelHeader(
                    title: 'Account & Profile',
                    subtitle: 'Your identity and library portability',
                  ),
                  _SettingTile(
                    icon: Icons.person_outline_rounded,
                    title: 'Display name',
                    subtitle: 'Shown across your dashboard',
                    trailing: Text(
                      settings.displayName,
                      style: const TextStyle(
                        fontSize: 13,
                        color: SaxifyColors.textSecondary,
                      ),
                    ),
                    onTap: () => _editText(
                      context,
                      title: 'Display name',
                      initial: settings.displayName,
                      onSave: settings.setDisplayName,
                    ),
                  ),
                  _SettingTile(
                    icon: Icons.upload_file_rounded,
                    title: 'Backup library',
                    subtitle:
                        'Copy JSON, or paste a backup to merge or replace',
                    onTap: () => showBackupSheet(context, library),
                  ),
                  _SettingTile(
                    icon: Icons.cloud_upload_outlined,
                    title: 'Generate all playlist codes',
                    subtitle: 'Copies a cloud code to the clipboard',
                    onTap: () => shareAllPlaylistCodes(context),
                  ),
                  _SettingTile(
                    icon: Icons.cloud_download_outlined,
                    title: 'Import playlist code',
                    subtitle: 'Paste a code to restore playlists',
                    onTap: () => showImportCodeSheet(context),
                  ),

                  // ------------------------------------------------ Appearance
                  const _PanelHeader(
                    title: 'Appearance & Theme',
                    subtitle: 'Pick a colour, or build your own mix',
                  ),
                  const _ThemePanel(),

                  // ------------------------------------------------ Effects
                  const _PanelHeader(
                    title: 'Audio & Effects',
                    subtitle: 'Shape and save your sound preferences',
                  ),
                  _SettingTile(
                    icon: Icons.graphic_eq_rounded,
                    title: 'Studio equalizer',
                    subtitle: 'Bands, built-in presets and your saved custom presets',
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const EqualizerPage(),
                      ),
                    ),
                  ),
                  const _SettingTile(
                    icon: Icons.surround_sound_rounded,
                    title: '8D Audio',
                    subtitle: 'Coming soon — we are crafting a more immersive listening experience',
                  ),

                  // ------------------------------------------------ Playback
                  const _PanelHeader(
                    title: 'Playback',
                    subtitle:
                        'Gapless handoff and auto-next',
                  ),
                  _SwitchTile(
                    icon: Icons.bolt_rounded,
                    title: 'Gapless playback',
                    subtitle:
                        'Preloads the next track for seamless transitions',
                    value: settings.gapless,
                    onChanged: settings.setGapless,
                  ),
                  _SwitchTile(
                    icon: Icons.autorenew_rounded,
                    title: 'Autoplay',
                    subtitle:
                        'Keep similar music flowing when your queue ends — playback never stops',
                    value: settings.autoplay,
                    onChanged: settings.setAutoplay,
                  ),
                  _SwitchTile(
                    icon: Icons.history_rounded,
                    title: 'Remember playback position',
                    subtitle: 'Resume exactly where you left off',
                    value: settings.rememberPosition,
                    onChanged: settings.setRememberPosition,
                  ),
                  _ChoiceTile(
                    icon: Icons.speed_rounded,
                    title: 'Playback speed',
                    subtitle: 'Applied instantly to the current track',
                    choices: const <String>['0.75x', '1x', '1.25x', '1.5x'],
                    value: _speedLabel(settings.playbackSpeed),
                    onChanged: (String v) async {
                      final double speed = double.parse(v.replaceAll('x', ''));
                      await settings.setPlaybackSpeed(speed);
                      if (context.mounted) {
                        await context.read<PlaybackService>().setSpeed(speed);
                      }
                    },
                  ),
                  _SwitchTile(
                    icon: Icons.content_cut_rounded,
                    title: 'Skip silence',
                    subtitle: 'Best-effort just_audio silence skipping on supported devices',
                    value: settings.skipSilence,
                    onChanged: (bool enabled) =>
                        context.read<PlaybackService>().setSkipSilence(enabled),
                  ),
                  _ChoiceTile(
                    icon: Icons.route_rounded,
                    title: 'Stream resolver',
                    subtitle: 'Ifall server 1 uses Innertube first, then legacy fallback',
                    choices: const <String>['Ifall server 1 (smart)', 'Ifall server 2', 'Ifall server 3'],
                    value: settings.streamResolverLabel,
                    onChanged: (String v) => settings.setStreamResolverMode(
                      switch (v) {
                        'Ifall server 2' => StreamResolverMode.innertubeOnly,
                        'Ifall server 3' => StreamResolverMode.legacyOnly,
                        _ => StreamResolverMode.smart,
                      },
                    ),
                  ),

                  // ------------------------------------------------ Storage
                  const _PanelHeader(
                    title: 'Downloads & Storage',
                    subtitle: 'Everything is saved on this phone — no backend',
                  ),
                  _SettingTile(
                    icon: Icons.download_done_rounded,
                    title: 'Your Downloads',
                    subtitle: 'Songs saved offline, with delete and progress',
                    onTap: () {
                      Navigator.of(
                        context,
                      ).popUntil((Route<dynamic> r) => r.isFirst);
                      context.read<ShellController>().goDownloads();
                    },
                  ),
                  _SettingTile(
                    icon: Icons.folder_outlined,
                    title: 'Storage permission',
                    subtitle:
                        'Save a public copy in Download/${IfallBranding.downloadFolderName}',
                    onTap: () => StoragePermission.ensure(context),
                  ),
                  _ChoiceTile(
                    icon: Icons.cached_rounded,
                    title: 'Offline cache size',
                    subtitle: 'Smart playback cache; downloads stay separate',
                    choices: const <String>['512MB', '1GB', '2GB', '4GB', 'Unlimited'],
                    value: settings.offlineCacheSizeLabel,
                    onChanged: (String label) async {
                      await settings.setOfflineCacheSizeLabel(label);
                      if (context.mounted) {
                        await context.read<PlaybackService>().prunePlaybackCache();
                      }
                    },
                  ),
                  _SettingTile(
                    icon: Icons.delete_sweep_outlined,
                    title: 'Clear playback cache',
                    subtitle: 'Removes temporary streamed-song cache only',
                    trailing: FutureBuilder<int>(
                      future: context.read<PlaybackService>().playbackCacheBytes(),
                      builder: (BuildContext context, AsyncSnapshot<int> snap) => Text(
                        snap.hasData ? Fmt.bytes(snap.data!) : '…',
                        style: const TextStyle(
                          fontSize: 13,
                          color: SaxifyColors.textSecondary,
                        ),
                      ),
                    ),
                    onTap: () async {
                      await context.read<PlaybackService>().clearPlaybackCache();
                      if (context.mounted) _toast(context, 'Playback cache cleared');
                    },
                  ),

                  // ------------------------------------------------ System
                  const _PanelHeader(
                    title: 'System & Device',
                    subtitle: 'How IfallMusic talks to your phone',
                  ),
                  _SettingTile(
                    icon: Icons.headphones_battery_rounded,
                    title: 'Instructions to play in background',
                    subtitle: 'Keep the music going with the screen off',
                    onTap: () => showBackgroundGuideSheet(context),
                  ),
                  _SettingTile(
                    icon: Icons.bedtime_rounded,
                    title: 'Sleep timer',
                    subtitle: 'Pause playback automatically',
                    trailing: Text(
                      context.watch<PlaybackService>().sleepRemaining == null
                          ? 'Off'
                          : Fmt.clock(
                              context.read<PlaybackService>().sleepRemaining!,
                            ),
                      style: const TextStyle(
                        fontSize: 13,
                        color: SaxifyColors.textSecondary,
                      ),
                    ),
                    onTap: () => _sleepSheet(context),
                  ),

                  // ------------------------------------------------ Privacy
                  const _PanelHeader(
                    title: 'Privacy & Storage',
                    subtitle: 'Control what IfallMusic remembers',
                  ),
                  _SettingTile(
                    icon: Icons.search_off_rounded,
                    title: 'Clear search history',
                    subtitle: 'Removes your recent search terms',
                    onTap: () async {
                      await library.clearSearchHistory();
                      if (context.mounted)
                        _toast(context, 'Search history cleared');
                    },
                  ),
                  _SettingTile(
                    icon: Icons.cleaning_services_outlined,
                    title: 'Clear listening history',
                    subtitle: 'Deletes recently played from this device',
                    onTap: () async {
                      await library.clearHistory();
                      await settings.forgetPositions();
                      if (context.mounted)
                        _toast(context, 'Listening history cleared');
                    },
                  ),

                  // ------------------------------------------------ About
                  const _PanelHeader(
                    title: 'About & Support',
                    subtitle: 'Version info, help and credits',
                  ),
                  _SettingTile(
                    icon: Icons.language_rounded,
                    title: 'Website & latest app download',
                    subtitle: IfallBranding.latestDownloadMessage,
                    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                    onTap: () => launchUrl(
                      Uri.parse(IfallBranding.websiteUrl),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                  _SettingTile(
                    icon: Icons.system_update_rounded,
                    title: 'Check for updates',
                    subtitle: 'Downloads and installs the newest build in-app',
                    onTap: () => checkAndPromptUpdate(context, silent: false),
                  ),
                  const _AboutCard(),
                  const _MadeWithLoveFooter(),

                  // ------------------------------------------------ Contact
                  const _ContactSection(),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editText(
    BuildContext context, {
    required String title,
    required String initial,
    required Future<void> Function(String) onSave,
  }) async {
    final TextEditingController controller = TextEditingController(
      text: initial,
    );
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: title),
          onSubmitted: (String v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (value != null && value.trim().isNotEmpty) await onSave(value.trim());
  }

  void _sleepSheet(BuildContext context) {
    final PlaybackService playback = context.read<PlaybackService>();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext sheetContext) => GlassSheet(
        title: 'Sleep timer',
        subtitle: 'Playback pauses when the timer ends',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final int m in <int>[15, 30, 45, 60, 90])
              ListTile(
                title: Text('$m minutes'),
                onTap: () {
                  playback.startSleepTimer(Duration(minutes: m));
                  Navigator.of(sheetContext).pop();
                },
              ),
            ListTile(
              title: const Text(
                'Turn off',
                style: TextStyle(color: SaxifyColors.danger),
              ),
              onTap: () {
                playback.cancelSleepTimer();
                Navigator.of(sheetContext).pop();
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

// ------------------------------------------------------------------ reporting
Future<void> _showReportDialog(BuildContext context) async {
  final TextEditingController details = TextEditingController();
  const List<String> categories = <String>[
    'Playback / background',
    'Search / song results',
    'Downloads',
    'UI / layout',
    'Suggestion',
  ];
  const List<(String, String)> examples = <(String, String)>[
    ('Song stopped', 'A song stopped while IfallMusic was in the background.'),
    ('Wrong results', 'Search or a mood showed non-song / unrelated results.'),
    ('Download failed', 'A download did not start or did not finish.'),
    ('UI overlap', 'Some buttons or text overlap on my phone.'),
    ('Suggestion', 'I would like to suggest this feature: '),
  ];
  String category = categories.first;

  String? action;
  String reportText = '';
  try {
    action = await showDialog<String>(
      context: context,
      builder: (BuildContext dialog) => StatefulBuilder(
        builder: (BuildContext dialog, StateSetter setDialogState) => AlertDialog(
          title: const Text('Contact / Report'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  'Choose an example below or write your own. Send opens Gmail or your email app with a ready-to-send draft (normal spaces, no "+" signs).',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: SaxifyColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'What is this about?',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final String item in categories)
                      ChoiceChip(
                        label: Text(
                          item,
                          style: const TextStyle(fontSize: 11.5),
                        ),
                        selected: category == item,
                        onSelected: (_) =>
                            setDialogState(() => category = item),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    for (final (String, String) example in examples)
                      ActionChip(
                        label: Text(
                          example.$1,
                          style: const TextStyle(fontSize: 11),
                        ),
                        onPressed: () {
                          setDialogState(() {
                            details.text = example.$2;
                            details.selection = TextSelection.collapsed(
                              offset: details.text.length,
                            );
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: details,
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Details or your suggestion',
                    hintText:
                        'What happened? Phone model is helpful, but optional.',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialog).pop(),
              child: const Text('Cancel'),
            ),
            TextButton.icon(
              onPressed: () => Navigator.of(dialog).pop('send'),
              icon: const Icon(Icons.send_rounded, size: 17),
              label: const Text('Open email'),
            ),
          ],
        ),
      ),
    );
    reportText = details.text;
  } finally {
    details.dispose();
  }

  if (action == 'send' && context.mounted) {
    await _launchSupportEmail(context, category, reportText);
  }
}

/// Opens the listener's mail app with a properly encoded draft.
///
/// The old build used `Uri(queryParameters: …)`, which form-encodes spaces as
/// `+` — that is why every word arrived with a plus sign. A `mailto:` URI wants
/// **percent-encoding** (`%20`), so the query is built by hand here and spaces
/// stay spaces in Gmail, Outlook and every other client.
Future<void> _launchSupportEmail(
  BuildContext context,
  String category,
  String details,
) async {
  final String subject = '${IfallBranding.appName} feedback: $category';
  final String body = <String>[
    'Hi ${IfallBranding.appName} team,',
    '',
    'Topic: $category',
    '',
    details.trim().isEmpty
        ? 'Please describe the issue or suggestion here.'
        : details.trim(),
    '',
    'Phone model / Android version (optional):',
  ].join('\r\n');

  Uri mailtoUri(String address) => Uri(
    scheme: 'mailto',
    path: address,
    query:
        'subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}',
  );

  bool opened = false;
  try {
    opened = await launchUrl(
      mailtoUri(IfallBranding.contactEmail),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {}

  if (!opened) {
    // Gmail web composer fallback — same doc, same readable spaces.
    final Uri gmail = Uri.https('mail.google.com', '/mail/', <String, String>{
      'view': 'cm',
      'fs': '1',
      'to': IfallBranding.contactEmail,
      'su': subject,
      'body': body,
    });
    try {
      opened = await launchUrl(gmail, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        opened
            ? 'Email draft opened. Review it and press Send.'
            : 'Could not open an email app. Install Gmail or another mail app and try again.',
      ),
    ),
  );
}

// --------------------------------------------------------------------- theme
class _ThemePanel extends StatefulWidget {
  const _ThemePanel();

  @override
  State<_ThemePanel> createState() => _ThemePanelState();
}

class _ThemePanelState extends State<_ThemePanel> {
  Timer? _ticker;
  bool _mixerOpen = false;
  bool _coloursOpen = false;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeController theme = context.watch<ThemeController>();
    final SaxifyAccent accent = theme.paletteAccent;

    return Column(
      children: <Widget>[
        GlassPanel(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(
                          'Accent colour',
                          style: SaxifyTheme.appleFont(
                            size: 15,
                            weight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${accent.label} · Choose where colour appears',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: SaxifyColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SaxifyLogo(size: 42, accent: accent),
                ],
              ),
              const SizedBox(height: 12),
              GlassButton(
                label: _coloursOpen
                    ? 'Hide accent colours'
                    : 'Choose accent colour',
                icon: _coloursOpen ? Icons.expand_less : Icons.palette_outlined,
                filled: false,
                expand: true,
                compact: true,
                onPressed: () => setState(() => _coloursOpen = !_coloursOpen),
              ),
              if (_coloursOpen)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final option in SaxifyAccents.all)
                        _AccentSwatch(
                          accent: option,
                          width: 32,
                          selected: theme.selectedId == option.id,
                          onTap: () => theme.pin(option.id),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              GlassButton(
                label: _mixerOpen ? 'Hide colour mixer' : 'Build your own mix',
                icon: _mixerOpen
                    ? Icons.expand_less_rounded
                    : Icons.palette_outlined,
                filled: false,
                expand: true,
                compact: true,
                onPressed: () => setState(() => _mixerOpen = !_mixerOpen),
              ),
              if (_mixerOpen)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: _AccentMixer(),
                ),
              const SizedBox(height: 6),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: theme.accentAcrossApp,
                onChanged: theme.setAccentAcrossApp,
                title: const Text(
                  'Use colour across the app',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  theme.accentAcrossApp
                      ? 'The selected colour styles buttons, controls and highlights'
                      : 'Off by default · clean black look; only song-quality text changes colour',
                  style: const TextStyle(
                    fontSize: 12,
                    color: SaxifyColors.textMuted,
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: theme.autoRotate,
                onChanged: theme.setAutoRotate,
                title: const Text(
                  'Auto-rotate colour',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  theme.autoRotate
                      ? 'Changes every ${theme.rotateInterval.inMinutes > 0 ? '${theme.rotateInterval.inMinutes} min' : '${theme.rotateInterval.inSeconds}s'} · next in ${theme.secondsUntilNextSwitch()}s'
                      : 'Choose a colour above to keep it fixed',
                  style: const TextStyle(
                    fontSize: 12,
                    color: SaxifyColors.textMuted,
                  ),
                ),
              ),
              if (theme.autoRotate)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: <Widget>[
                    for (final Duration d in <Duration>[
                      const Duration(minutes: 1),
                      const Duration(minutes: 2),
                      const Duration(seconds: 150),
                      const Duration(minutes: 3),
                      const Duration(minutes: 5),
                    ])
                      ChoiceChip(
                        label: Text(
                          d.inSeconds == 150 ? '2.5 min' : '${d.inMinutes} min',
                        ),
                        selected: d.inSeconds == theme.rotateInterval.inSeconds,
                        onSelected: (_) => theme.setRotateInterval(d),
                        labelStyle: const TextStyle(fontSize: 11.5),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AccentSwatch extends StatelessWidget {
  const _AccentSwatch({
    required this.accent,
    required this.selected,
    required this.onTap,
    required this.width,
  });

  final SaxifyAccent accent;
  final bool selected;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: accent.label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: width,
                height: width,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(width / 2),
                  gradient: accent.gradient,
                  border: Border.all(
                    color: selected
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.18),
                    width: selected ? 2.2 : 1,
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accent.primary.withValues(
                        alpha: selected ? 0.55 : 0.22,
                      ),
                      blurRadius: selected ? 18 : 10,
                      spreadRadius: -3,
                    ),
                  ],
                ),
                child: selected
                    ? Icon(
                        Icons.check_rounded,
                        size: width * 0.5,
                        color: accent.onAccent,
                      )
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// RGB mixer — the listener builds their own accent and the whole app follows.
class _AccentMixer extends StatefulWidget {
  const _AccentMixer();

  @override
  State<_AccentMixer> createState() => _AccentMixerState();
}

class _AccentMixerState extends State<_AccentMixer> {
  late Color _primary;
  late Color _deep;

  @override
  void initState() {
    super.initState();
    final ThemeController theme = context.read<ThemeController>();
    _primary = theme.paletteAccent.primary;
    _deep = theme.paletteAccent.secondary;
  }

  void _randomise() {
    final math.Random random = math.Random();
    setState(() {
      _primary = HSVColor.fromAHSV(
        1,
        random.nextDouble() * 360,
        0.55 + random.nextDouble() * 0.35,
        0.72 + random.nextDouble() * 0.25,
      ).toColor();
      _deep = HSVColor.fromAHSV(
        1,
        random.nextDouble() * 360,
        0.6 + random.nextDouble() * 0.35,
        0.35 + random.nextDouble() * 0.25,
      ).toColor();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeController theme = context.read<ThemeController>();
    final SaxifyAccent preview = SaxifyAccent.custom(_primary, _deep);

    return GlassPanel(
      radius: SaxifyTheme.radiusMd,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  gradient: preview.gradient,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Your colour mix',
                      style: SaxifyTheme.appleFont(
                        size: 14,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${preview.primaryHex}  →  ${preview.secondaryHex}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: SaxifyColors.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Surprise me',
                onPressed: _randomise,
                icon: const Icon(Icons.casino_outlined, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _RgbSliders(
            label: 'Main colour',
            color: _primary,
            onChanged: (Color c) => setState(() => _primary = c),
          ),
          _RgbSliders(
            label: 'Deep colour',
            color: _deep,
            onChanged: (Color c) => setState(() => _deep = c),
          ),
          const SizedBox(height: 6),
          Row(
            children: <Widget>[
              Expanded(
                child: GlassButton(
                  label: 'Apply to app',
                  icon: Icons.brush_rounded,
                  compact: true,
                  onPressed: () => theme.defineCustom(_primary, _deep),
                ),
              ),
              const SizedBox(width: 10),
              GlassButton(
                label: 'Reset',
                icon: Icons.restart_alt_rounded,
                filled: false,
                compact: true,
                onPressed: () {
                  setState(() {
                    _primary = SaxifyAccents.violetPulse.primary;
                    _deep = SaxifyAccents.violetPulse.secondary;
                  });
                  theme.pin(SaxifyAccents.violetPulse.id);
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Slide red, green and blue to mix any colour. The whole app — buttons, '
            'glows, equalizer and the heart in the footer — follows immediately.',
            style: TextStyle(
              fontSize: 11,
              height: 1.45,
              color: SaxifyColors.textFaint,
            ),
          ),
        ],
      ),
    );
  }
}

class _RgbSliders extends StatelessWidget {
  const _RgbSliders({
    required this.label,
    required this.color,
    required this.onChanged,
  });

  final String label;
  final Color color;
  final ValueChanged<Color> onChanged;

  int _c(double v) => (v * 255).round().clamp(0, 255);

  @override
  Widget build(BuildContext context) {
    final int r = _c(color.r);
    final int g = _c(color.g);
    final int b = _c(color.b);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SizedBox(height: 6),
        Text(
          '$label · R$r G$g B$b',
          style: const TextStyle(
            fontSize: 11.5,
            color: SaxifyColors.textSecondary,
          ),
        ),
        _Channel(
          label: 'R',
          value: r,
          tint: const Color(0xFFFF5A5A),
          onChanged: (int v) => onChanged(Color.fromARGB(255, v, g, b)),
        ),
        _Channel(
          label: 'G',
          value: g,
          tint: const Color(0xFF4ADE80),
          onChanged: (int v) => onChanged(Color.fromARGB(255, r, v, b)),
        ),
        _Channel(
          label: 'B',
          value: b,
          tint: const Color(0xFF60A5FA),
          onChanged: (int v) => onChanged(Color.fromARGB(255, r, g, v)),
        ),
      ],
    );
  }
}

class _Channel extends StatelessWidget {
  const _Channel({
    required this.label,
    required this.value,
    required this.tint,
    required this.onChanged,
  });

  final String label;
  final int value;
  final Color tint;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        SizedBox(
          width: 16,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: tint,
            ),
          ),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: tint,
              thumbColor: Colors.white,
              overlayColor: tint.withValues(alpha: 0.18),
            ),
            child: Slider(
              min: 0,
              max: 255,
              value: value.toDouble(),
              onChanged: (double v) => onChanged(v.round()),
            ),
          ),
        ),
        SizedBox(
          width: 34,
          child: Text(
            '$value',
            textAlign: TextAlign.end,
            style: const TextStyle(
              fontSize: 11.5,
              color: SaxifyColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _AboutCard extends StatefulWidget {
  const _AboutCard();

  @override
  State<_AboutCard> createState() => _AboutCardState();
}

class _AboutCardState extends State<_AboutCard> {
  /// The real version and build number of the *installed* APK, read from the
  /// platform rather than from a compile-time constant. This is what lets a
  /// user confirm at a glance that they are on the new build — the build number
  /// is also what Android compares when deciding an APK is an update.
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final PackageInfo info = await PackageInfo.fromPlatform();
      if (mounted) setState(() => _packageInfo = info);
    } catch (_) {
      // Fall back to the compile-time label below.
    }
  }

  /// `2.4.0 (build 13)` from the platform, or the branding constant until it
  /// has loaded (or if the platform call failed).
  String get _versionText {
    final PackageInfo? info = _packageInfo;
    if (info == null) return IfallBranding.fullVersionLabel;
    final String build = info.buildNumber;
    return build.isEmpty ? info.version : '${info.version} (build $build)';
  }

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return GlassPanel(
      glow: true,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const SaxifyLogo(size: 42),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    GradientText(
                      IfallBranding.appName,
                      style: SaxifyTheme.appleFont(
                        size: 18,
                        weight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      IfallBranding.tagline,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: SaxifyColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Text(
            'IfallMusic is a clean, premium music experience: search and play any '
            'song, save it for offline listening, shape the sound with the studio '
            'equalizer presets, and let the whole app change colour '
            'with you — on a deep black canvas made for colour.',
            style: TextStyle(
              fontSize: 12.5,
              height: 1.55,
              color: SaxifyColors.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _FeatureChip('Search songs easily'),
              _FeatureChip('Discover artists'),
              _FeatureChip('Background playback'),
              _FeatureChip('Offline downloads'),
              _FeatureChip('Playlists'),
              _FeatureChip('Liquid glass UI'),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Text(
                      'App version',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: SaxifyColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'IfallMusic · $_versionText',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${IfallBranding.packageName} · updates install in place',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: SaxifyColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: () => showAboutDialog(
                  context: context,
                  applicationName: IfallBranding.appName,
                  applicationVersion: _versionText,
                  applicationIcon: const SaxifyLogo(size: 46),
                  children: const <Widget>[
                    Text(
                      'IfallMusic streams audio from the ifallertzia server. '
                      'All artwork and metadata belong to their respective owners. '
                      'IfallMusic is not affiliated with, or endorsed by, any '
                      'third-party streaming service.',
                      style: TextStyle(fontSize: 12.5, height: 1.5),
                    ),
                  ],
                ),
                child: Text(
                  'Legal',
                  style: TextStyle(color: accent.primary, fontSize: 12.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// The contact row lives on its own, at the very bottom of Settings, and simply
/// says what it is — no extra explanation text.
class _ContactSection extends StatelessWidget {
  const _ContactSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _PanelHeader(
          title: 'Contact',
          subtitle: 'Reach out, report a problem or send feedback',
        ),
        _SettingTile(
          icon: Icons.mail_outline_rounded,
          title: 'Contact / Report / Feedback',
          onTap: () => _showReportDialog(context),
        ),
      ],
    );
  }
}

/// "Made with ❤️ by Siddharth ifallertzia" — the heart keeps changing colour
/// with the app's appearance, exactly like the reference site.
class _MadeWithLoveFooter extends StatefulWidget {
  const _MadeWithLoveFooter();

  @override
  State<_MadeWithLoveFooter> createState() => _MadeWithLoveFooterState();
}

class _MadeWithLoveFooterState extends State<_MadeWithLoveFooter>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 8),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    final List<SaxifyAccent> palette = SaxifyAccents.all;
    final int index = palette.indexWhere((SaxifyAccent a) => a.id == accent.id);

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 26, 4, 8),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, _) {
          // Rotates the heart through the current accent and the next colours so
          // it is always in sync with whatever theme the app is wearing.
          final double t = _controller.value;
          final SaxifyAccent from = index >= 0 ? palette[index] : accent;
          final SaxifyAccent to =
              palette[(math.max(index, 0) + 1) % palette.length];
          final Color heart = Color.lerp(
            from.primary,
            t < 0.5 ? to.primary : from.secondary,
            Curves.easeInOut.transform(t < 0.5 ? t * 2 : (1 - t) * 2),
          )!;

          return Column(
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  Text(
                    'Made with ',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: SaxifyColors.textSecondary,
                      shadows: <Shadow>[
                        Shadow(
                          color: heart.withValues(alpha: 0.35),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                  ),
                  Transform.scale(
                    scale: 1 + 0.06 * math.sin(t * math.pi * 2),
                    child: Icon(Icons.favorite_rounded, size: 15, color: heart),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'by ${IfallBranding.author}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                  color: heart,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  const _FeatureChip(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassTag(label);
  }
}

// --------------------------------------------------------------------- tiles
class _PanelHeader extends StatelessWidget {
  const _PanelHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: SaxifyTheme.appleFont(
              size: 18,
              weight: FontWeight.w700,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: SaxifyColors.textMuted),
          ),
        ],
      ),
    );
  }
}

/// Shared leading icon badge for the setting rows.
class _TileIcon extends StatelessWidget {
  const _TileIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: accent.primary.withValues(alpha: 0.20),
        border: Border.all(color: accent.primary.withValues(alpha: 0.32)),
      ),
      child: Icon(icon, size: 19, color: accent.primary),
    );
  }
}

class _TileText extends StatelessWidget {
  const _TileText({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...<Widget>[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              color: SaxifyColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassListTile(
      onTap: onTap,
      leading: _TileIcon(icon),
      trailing:
          trailing ??
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: SaxifyColors.textFaint,
          ),
      child: _TileText(title: title, subtitle: subtitle),
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassListTile(
      leading: _TileIcon(icon),
      trailing: Switch(value: value, onChanged: onChanged),
      child: _TileText(title: title, subtitle: subtitle),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.choices,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final List<String> choices;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return Padding(
      // A small gap so stacked cards never touch each other.
      padding: const EdgeInsets.only(bottom: 8),
      child: GlassPanel(
        radius: SaxifyTheme.radiusMd,
        padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                _TileIcon(icon),
                const SizedBox(width: 12),
                Expanded(
                  child: _TileText(title: title, subtitle: subtitle),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                for (final String choice in choices)
                  ChoiceChip(
                    label: Text(choice.toUpperCase()),
                    selected: choice == value,
                    onSelected: (_) => onChanged(choice),
                    labelStyle: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: choice == value
                          ? accent.primary
                          : SaxifyColors.textMuted,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
