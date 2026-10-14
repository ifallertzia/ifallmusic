import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../widgets/saxify_logo.dart';
import 'diagnostics_page.dart';
import '../player/player_sheets.dart';
import '../stats/listening_stats_page.dart';

import '../../config/branding.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/library_service.dart';
import '../../core/services/listen_together_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/presence_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/youtube_service.dart';
import '../../services/lyrics_service.dart';
import '../../core/theme/ifall_ui.dart';
import '../../core/theme/theme_controller.dart';
import '../../core/utils/format.dart';
import '../downloads/storage_permission.dart';
import '../player/equalizer_page.dart';
import '../rooms/listen_together_page.dart';
import '../shell/ifall_shell.dart';
import '../shell/shell_controller.dart';
import 'background_guide_sheet.dart';
import 'backup_sheet.dart';
import 'playlist_sync_sheet.dart';
import 'update_dialog.dart';
import '../../core/theme/glass.dart';
import '../widgets/neon.dart';

/// One-line text prompt shared by the account pages. Kept at file scope so
/// Last.fm, ListenBrainz, Spotify and Discord can all reach it.
Future<String?> _prompt(
    BuildContext context, {
    required String title,
    required String initial,
    bool obscure = false,
    String? hint,
  }) {
    final TextEditingController controller =
        TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: obscure,
          decoration: InputDecoration(hintText: hint ?? title),
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

/// The language choices offered in Settings. `system` follows the phone.
const List<(String, String)> appLanguages = <(String, String)>[
  ('system', 'System'),
  ('en', 'English'),
  ('hi', 'हिन्दी'),
  ('bn', 'বাংলা'),
  ('ta', 'தமிழ்'),
  ('te', 'తెలుగు'),
  ('mr', 'मराठी'),
  ('gu', 'ગુજરાતી'),
  ('kn', 'ಕನ್ನಡ'),
  ('ml', 'മലയാളം'),
  ('pa', 'ਪੰਜਾਬੀ'),
  ('ur', 'اردو'),
  ('es', 'Español'),
  ('fr', 'Français'),
  ('de', 'Deutsch'),
  ('pt', 'Português'),
  ('ja', '日本語'),
  ('ko', '한국어'),
  ('ar', 'العربية'),
];

String languageLabel(String code) => appLanguages
    .firstWhere(
      ((String, String) e) => e.$1 == code,
      orElse: () => ('system', 'System'),
    )
    .$2;

String themeModeLabel(ThemeMode mode) => switch (mode) {
      ThemeMode.system => 'System',
      ThemeMode.light => 'Light',
      ThemeMode.dark => 'Dark',
    };

/// **Settings** — one grouped list, every panel a row that opens its own page.
///
/// The look follows the same rules as the rest of the app: heavy tight titles,
/// hairline separators, frosted groups on true black.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final LibraryService library = context.watch<LibraryService>();
    final PlaybackService playback = context.watch<PlaybackService>();
    final JamService jam = context.watch<JamService>();
    final IfallPalette c = IfallPalette.of(context);

    final int activeDownloads = 0;

    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: EdgeInsets.only(bottom: IfallInsets.bottom),
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 10),
              child: Text('Settings', style: IfallText.display(c.onSurface)),
            ),
            // ------------------------------------------------------ account
            IfallGroup(
              title: 'Account & profile',
              children: <Widget>[
                IfallRow(
                  icon: Icons.person_outline_rounded,
                  title: 'Display name',
                  subtitle: 'Shown across your dashboard',
                  value: settings.displayName,
                  onTap: () => _editText(
                    context,
                    title: 'Display name',
                    initial: settings.displayName,
                    onSave: settings.setDisplayName,
                  ),
                ),
                IfallRow(
                  icon: Icons.upload_file_rounded,
                  title: 'Backup library',
                  subtitle: 'Copy JSON, or paste a backup to merge or replace',
                  onTap: () => showBackupSheet(context, library),
                ),
                IfallRow(
                  icon: Icons.cloud_upload_outlined,
                  title: 'Generate all playlist codes',
                  subtitle: 'Copies a cloud code to the clipboard',
                  onTap: () => shareAllPlaylistCodes(context),
                ),
                IfallRow(
                  icon: Icons.cloud_download_outlined,
                  title: 'Import playlist code',
                  subtitle: 'Paste a code to restore playlists',
                  onTap: () => showImportCodeSheet(context),
                ),
              ],
            ),

            // ---------------------------------------------------- listening
            IfallGroup(
              title: 'Listening',
              children: <Widget>[
                IfallRow(
                  icon: Icons.surround_sound_rounded,
                  title: 'Listen Together',
                  subtitle: jam.isConnected
                      ? 'In room ${jam.code ?? ''}'
                      : 'Open a room and play in sync with friends',
                  value: jam.isConnected ? 'Live' : 'Off',
                  onTap: () => openListenTogether(context),
                ),
                IfallRow(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Equalizer',
                  subtitle: 'Bands, presets and your saved custom presets',
                  value: settings.equalizerEnabled
                      ? settings.equalizerProfileName
                      : 'Original audio',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext c2) => const EqualizerPage(),
                    ),
                  ),
                ),
                IfallRow(
                  icon: Icons.bedtime_rounded,
                  title: 'Sleep timer',
                  subtitle: 'Playback pauses when the timer ends',
                  value: playback.sleepRemaining == null
                      ? 'Off'
                      : Fmt.clock(playback.sleepRemaining!),
                  onTap: () => showSleepTimerSheet(context),
                ),
                IfallRow(
                  icon: Icons.insights_rounded,
                  title: 'Listening stats',
                  subtitle: 'Your Replay: top artists, songs and minutes',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext c2) => const ListeningStatsPage(),
                    ),
                  ),
                ),
              ],
            ),

            // --------------------------------------------------- appearance
            IfallGroup(
              title: 'Appearance',
              children: <Widget>[
                IfallRow(
                  icon: Icons.palette_outlined,
                  title: 'Theme & colour',
                  subtitle: themeModeLabel(settings.themeMode),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext c2) =>
                          const AppearanceSettingsPage(),
                    ),
                  ),
                ),
                IfallRow(
                  icon: Icons.translate_rounded,
                  title: 'Language',
                  value: languageLabel(settings.language),
                  onTap: () => showLanguageSheet(context),
                ),
                IfallRow(
                  icon: Icons.lyrics_outlined,
                  title: 'Lyrics providers',
                  subtitle: '${settings.lyricsProviders.length} sources enabled',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext c2) => const LyricsSettingsPage(),
                    ),
                  ),
                ),
              ],
            ),

            // ----------------------------------------------------- playback
            IfallGroup(
              title: 'Playback & audio',
              children: <Widget>[
                IfallRow(
                  icon: Icons.play_circle_outline_rounded,
                  title: 'Playback',
                  subtitle: 'Quality, gapless, crossfade, speed, silence',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext c2) =>
                          const PlaybackSettingsPage(),
                    ),
                  ),
                ),
                IfallRow(
                  icon: Icons.hub_outlined,
                  title: 'Sources',
                  subtitle: 'The stream resolvers IfallMusic may fall back to',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext c2) => const SourcesSettingsPage(),
                    ),
                  ),
                ),
                IfallRow(
                  icon: Icons.headphones_battery_rounded,
                  title: 'Background playback guide',
                  subtitle: 'Keep the music going with the screen off',
                  onTap: () => showBackgroundGuideSheet(context),
                ),
              ],
            ),

            // -------------------------------------------------- connections
            IfallGroup(
              title: 'Connections',
              children: <Widget>[
                IfallRow(
                  icon: Icons.link_rounded,
                  title: 'Accounts & scrobbling',
                  subtitle: 'Last.fm, ListenBrainz, Spotify import',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext c2) => const AccountsSettingsPage(),
                    ),
                  ),
                ),
                IfallRow(
                  icon: Icons.discord_rounded,
                  title: 'Discord Rich Presence',
                  value: settings.discordEnabled ? 'On' : 'Off',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext c2) => const DiscordSettingsPage(),
                    ),
                  ),
                ),
                IfallRow(
                  icon: Icons.dns_outlined,
                  title: 'Listen Together server',
                  subtitle: settings.jamServer.isEmpty
                      ? 'Not set'
                      : settings.jamServer,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext c2) => const JamServerPage(),
                    ),
                  ),
                ),
              ],
            ),

            // ------------------------------------------------------ storage
            IfallGroup(
              title: 'Downloads & storage',
              children: <Widget>[
                IfallRow(
                  icon: Icons.download_done_rounded,
                  title: 'Your Downloads',
                  subtitle: 'Songs saved offline, with delete and progress',
                  value: '$activeDownloads active',
                  onTap: () {
                    Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
                    context.read<ShellController>().goDownloads();
                  },
                ),
                IfallRow(
                  icon: Icons.folder_outlined,
                  title: 'Storage permission',
                  subtitle:
                      'Save a public copy in Download/${IfallBranding.downloadFolderName}',
                  onTap: () => StoragePermission.ensure(context),
                ),
                IfallRow(
                  icon: Icons.cached_rounded,
                  title: 'Offline cache size',
                  value: settings.offlineCacheSizeLabel,
                  onTap: () => showCacheSizeSheet(context),
                ),
                IfallRow(
                  icon: Icons.delete_sweep_outlined,
                  title: 'Clear playback cache',
                  subtitle: 'Removes temporary streamed-song cache only',
                  trailing: FutureBuilder<int>(
                    future: context.read<PlaybackService>().playbackCacheBytes(),
                    builder:
                        (BuildContext context, AsyncSnapshot<int> snapshot) =>
                            Text(
                      snapshot.hasData ? Fmt.bytes(snapshot.data!) : '…',
                      style: IfallText.caption(c.onSurfaceVariant),
                    ),
                  ),
                  onTap: () async {
                    await context.read<PlaybackService>().clearPlaybackCache();
                    if (context.mounted) {
                      showAppNotice('Playback cache cleared');
                    }
                  },
                ),
                IfallRow(
                  icon: Icons.search_off_rounded,
                  title: 'Clear search memory',
                  subtitle: 'Forgets remembered searches so they run again',
                  onTap: () async {
                    context.read<YoutubeService>().clearSearchCache();
                    if (context.mounted) showAppNotice('Search memory cleared');
                  },
                ),
              ],
            ),

            // ------------------------------------------------------ privacy
            IfallGroup(
              title: 'Privacy',
              children: <Widget>[
                IfallRow(
                  icon: Icons.search_off_rounded,
                  title: 'Clear search history',
                  subtitle: 'Removes your recent search terms',
                  onTap: () async {
                    await library.clearSearchHistory();
                    if (context.mounted) showAppNotice('Search history cleared');
                  },
                ),
                IfallRow(
                  icon: Icons.cleaning_services_outlined,
                  title: 'Clear listening history',
                  subtitle: 'Deletes recently played from this device',
                  onTap: () async {
                    await library.clearHistory();
                    await settings.forgetPositions();
                    if (context.mounted) {
                      showAppNotice('Listening history cleared');
                    }
                  },
                ),
                IfallRow(
                  icon: Icons.analytics_outlined,
                  title: 'Keep on-device listening stats',
                  subtitle: 'Feeds Replay and your recommendations',
                  trailing: Switch.adaptive(
                    value: settings.statsOptIn,
                    activeColor: c.accent,
                    onChanged: settings.setStatsOptIn,
                  ),
                  onTap: () => settings.setStatsOptIn(!settings.statsOptIn),
                ),
              ],
            ),

            // -------------------------------------------------------- about
            IfallGroup(
              title: 'About & support',
              children: <Widget>[
                IfallRow(
                  icon: Icons.language_rounded,
                  title: 'Website & latest app download',
                  subtitle: IfallBranding.latestDownloadMessage,
                  trailing: Icon(
                    Icons.open_in_new_rounded,
                    size: 18,
                    color: c.onSurfaceVariant,
                  ),
                  onTap: () => launchUrl(
                    Uri.parse(IfallBranding.websiteUrl),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                IfallRow(
                  icon: Icons.system_update_rounded,
                  title: 'Check for updates',
                  subtitle:
                      'Downloads and installs the newest build in-app (${IfallBranding.fullVersionLabel})',
                  onTap: () => checkAndPromptUpdate(context, silent: false),
                ),
                IfallRow(
                  icon: Icons.bug_report_outlined,
                  title: 'Diagnostics',
                  subtitle: 'Boot log, playback errors and device info',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext c2) => DiagnosticsPage(
                        safeMode: context.read<bool>(),
                      ),
                    ),
                  ),
                ),
                IfallRow(
                  icon: Icons.info_outline_rounded,
                  title: 'About ${IfallBranding.appName}',
                  subtitle: '${IfallBranding.tagline} · ${IfallBranding.author}',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (BuildContext c2) => const AboutSettingsPage(),
                    ),
                  ),
                ),
              ],
            ),

            IfallGroup(
              children: <Widget>[
                IfallRow(
                  icon: Icons.restart_alt_rounded,
                  title: 'Reset all settings',
                  subtitle: 'Your library, downloads and history are untouched',
                  danger: true,
                  onTap: () => _confirmReset(context),
                ),
              ],
            ),
            const SizedBox(height: 12),
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
    final TextEditingController controller =
        TextEditingController(text: initial);
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
    if (value != null && value.trim().isNotEmpty) {
      await onSave(value.trim());
    }
  }

  Future<void> _confirmReset(BuildContext context) async {
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Reset all settings?'),
        content: const Text(
          'Theme, playback, downloads and appearance go back to their defaults. '
          'Your liked songs, playlists, history and downloads stay on this device.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await context.read<SettingsService>().resetAll();
    if (context.mounted) showAppNotice('Settings reset');
  }
}

// ---------------------------------------------------------------- appearance

/// Theme, colour and the performance switches.
class AppearanceSettingsPage extends StatelessWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final ThemeController theme = context.watch<ThemeController>();
    final IfallPalette c = IfallPalette.of(context);

    return _SettingsScaffold(
      title: 'Appearance',
      children: <Widget>[
        IfallGroup(
          title: 'Theme',
          footer:
              'System follows your phone. Light is rolling out across the app — '
              'where a panel has not been repainted yet it keeps the dark look.',
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: IfallSegmented<ThemeMode>(
                value: settings.themeMode,
                options: const <ThemeMode>[
                  ThemeMode.system,
                  ThemeMode.dark,
                  ThemeMode.light,
                ],
                labelBuilder: themeModeLabel,
                onChanged: theme.setThemeMode,
              ),
            ),
          ],
        ),
        IfallGroup(
          title: 'Colour',
          children: <Widget>[
            IfallSwitchRow(
              icon: Icons.format_paint_rounded,
              title: 'Paint the accent across the app',
              subtitle: 'Off keeps the neutral black look',
              value: theme.accentAcrossApp,
              onChanged: theme.setAccentAcrossApp,
            ),
          ],
        ),
        const IfallGroup(title: 'Accent', children: <Widget>[_ThemePanel()]),
        IfallGroup(
          title: 'Effects',
          children: <Widget>[
            IfallSwitchRow(
              icon: Icons.blur_on_rounded,
              title: 'Liquid glass',
              subtitle: 'Frosted blur behind the floating bars and sheets',
              value: settings.liquidGlass,
              onChanged: theme.setLiquidGlass,
            ),
            IfallSwitchRow(
              icon: Icons.speed_rounded,
              title: 'High performance mode',
              subtitle: 'Drops heavy blur and shader work on slower phones',
              value: settings.highPerformance,
              onChanged: settings.setHighPerformance,
            ),
            IfallSwitchRow(
              icon: Icons.visibility_outlined,
              title: 'Keep the screen awake',
              subtitle: 'While the player is open',
              value: settings.keepScreenAwake,
              onChanged: settings.setKeepScreenAwake,
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
          child: Text(
            'Accent: ${theme.accent.label}',
            style: IfallText.caption(c.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

/// One setting page's chrome: back arrow, title, scrolling body.
class _SettingsScaffold extends StatelessWidget {
  const _SettingsScaffold({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 6, 12, 2),
              child: Row(
                children: <Widget>[
                  const BackButton(),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IfallText.title(c.onSurface),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------ playback

/// Quality, transitions, speed and silence.
class PlaybackSettingsPage extends StatelessWidget {
  const PlaybackSettingsPage({super.key});

  static const List<String> qualityChoices = <String>['low', 'medium', 'high'];

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final PlaybackService playback = context.read<PlaybackService>();

    return _SettingsScaffold(
      title: 'Playback',
      children: <Widget>[
        IfallGroup(
          title: 'Audio quality',
          footer:
              'A separate ceiling for Wi-Fi and mobile data, so a commute does '
              'not quietly burn through a data plan.',
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                'Wi-Fi',
                style: IfallText.caption(
                  IfallPalette.of(context).onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: IfallSegmented<String>(
                value: settings.qualityWifi,
                options: qualityChoices,
                labelBuilder: (String v) => v.toUpperCase(),
                onChanged: settings.setQualityWifi,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: Text(
                'Mobile data',
                style: IfallText.caption(
                  IfallPalette.of(context).onSurfaceVariant,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: IfallSegmented<String>(
                value: settings.qualityMobile,
                options: qualityChoices,
                labelBuilder: (String v) => v.toUpperCase(),
                onChanged: settings.setQualityMobile,
              ),
            ),
          ],
        ),
        IfallGroup(
          title: 'Transitions',
          children: <Widget>[
            IfallSwitchRow(
              icon: Icons.bolt_rounded,
              title: 'Gapless playback',
              subtitle: 'Preloads the next track for seamless transitions',
              value: settings.gapless,
              onChanged: settings.setGapless,
            ),
            IfallSliderRow(
              icon: Icons.compare_arrows_rounded,
              title: 'Crossfade',
              subtitle:
                  'Blends the end of one track into the start of the next',
              value: settings.crossfadeSeconds.toDouble(),
              min: 0,
              max: 12,
              divisions: 12,
              format: (double v) =>
                  v == 0 ? 'Off' : '${v.round()}s',
              onChanged: (double v) async {
                await settings.setCrossfadeSeconds(v.round());
                if (context.mounted) {
                  await playback.setCrossfadeSeconds(v.round());
                }
              },
            ),
            IfallSwitchRow(
              icon: Icons.auto_awesome_rounded,
              title: 'Automix (beta)',
              subtitle:
                  'DJ-style beat-matched tempo stretch between two tracks',
              value: settings.automix,
              onChanged: (bool v) async {
                await settings.setAutomix(v);
                if (context.mounted) await playback.setAutomix(v);
              },
            ),
            IfallSwitchRow(
              icon: Icons.autorenew_rounded,
              title: 'Autoplay',
              subtitle: 'Keep similar music flowing when your queue ends',
              value: settings.autoplay,
              onChanged: settings.setAutoplay,
            ),
          ],
        ),
        IfallGroup(
          title: 'Speed & silence',
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
              child: IfallSegmented<double>(
                value: settings.playbackSpeed,
                options: const <double>[0.5, 0.75, 1.0, 1.25, 1.5, 2.0],
                labelBuilder: (double v) => v == 1.0 ? '1x' : '${v}x',
                onChanged: (double v) async {
                  await settings.setPlaybackSpeed(v);
                  if (context.mounted) await playback.setSpeed(v);
                },
              ),
            ),
            IfallSwitchRow(
              icon: Icons.content_cut_rounded,
              title: 'Skip silence',
              subtitle: 'Best-effort silence skipping on supported devices',
              value: settings.skipSilence,
              onChanged: playback.setSkipSilence,
            ),
            IfallSwitchRow(
              icon: Icons.volume_down_rounded,
              title: 'Normalize volume',
              subtitle: 'Evens out loudness between tracks',
              value: settings.normalizeVolume,
              onChanged: settings.setNormalizeVolume,
            ),
          ],
        ),
        IfallGroup(
          title: 'Resume & resolver',
          children: <Widget>[
            IfallSwitchRow(
              icon: Icons.history_rounded,
              title: 'Remember playback position',
              subtitle: 'Resume exactly where you left off',
              value: settings.rememberPosition,
              onChanged: settings.setRememberPosition,
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Stream resolver',
                    style: IfallText.body(IfallPalette.of(context).onSurface),
                  ),
                  const SizedBox(height: 8),
                  IfallSegmented<StreamResolverMode>(
                    value: settings.streamResolverMode,
                    options: StreamResolverMode.values,
                    labelBuilder: (StreamResolverMode m) => switch (m) {
                      StreamResolverMode.smart => 'Smart',
                      StreamResolverMode.innertubeOnly => 'Innertube',
                      StreamResolverMode.legacyOnly => 'Legacy',
                    },
                    onChanged: settings.setStreamResolverMode,
                  ),
                ],
              ),
            ),
          ],
        ),
        IfallGroup(
          title: 'Sleep timer',
          children: <Widget>[
            IfallSwitchRow(
              icon: Icons.bedtime_rounded,
              title: 'Stop after this track',
              subtitle: 'Instead of counting down',
              value: settings.sleepEndOfTrack,
              onChanged: settings.setSleepEndOfTrack,
            ),
            IfallRow(
              icon: Icons.timer_outlined,
              title: 'Countdown length',
              value: '${settings.sleepMinutes} min',
              onTap: () => showSleepTimerSheet(context),
            ),
          ],
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- sources

/// The stream sources the resolver is allowed to fall back to.
class SourcesSettingsPage extends StatelessWidget {
  const SourcesSettingsPage({super.key});

  /// The built-in resolvers. The first two are IfallMusic's own dual engine.
  static const List<(String, String, String, IconData)> builtIn =
      <(String, String, String, IconData)>[
    (
      'Innertube',
      'Primary',
      'Posts straight to YouTube’s on-device player endpoint and rotates '
          'through the Android, VR, VisionOS, embedded, Music and TV clients.',
      Icons.stream_rounded,
    ),
    (
      'Legacy resolver',
      'Fallback',
      'youtube_explode_dart with the androidSdkless → ios → androidVr order, '
          'probe timeouts and per-itag blacklisting.',
      Icons.history_toggle_off_rounded,
    ),
    (
      'On-device files',
      'Local',
      'Audio already on the phone, served from MediaStore without touching '
          'the network.',
      Icons.sd_card_rounded,
    ),
    (
      'Downloads',
      'Offline',
      'Tracks saved by IfallMusic, played straight from storage.',
      Icons.download_done_rounded,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final IfallPalette c = IfallPalette.of(context);
    final List<Map<String, dynamic>> extra = settings.extraSources;

    return _SettingsScaffold(
      title: 'Sources',
      children: <Widget>[
        IfallGroup(
          title: 'Built in',
          footer:
              'Smart mode tries Innertube first and falls back to the legacy '
              'resolver. Switching the resolver in Playback pins one of them.',
          children: <Widget>[
            for (final (String name, String kind, String note, IconData icon)
                in builtIn)
              IfallRow(
                icon: icon,
                title: name,
                subtitle: note,
                value: kind,
              ),
          ],
        ),
        IfallGroup(
          title: 'Extra source modules',
          footer: extra.isEmpty
              ? 'A module is a small JSON endpoint that answers with a stream '
                  'URL for a video id. Add one to widen the fallback chain — '
                  'IfallMusic still resolves everything else on the device.'
              : 'Modules are consulted last, after both built-in resolvers.',
          children: <Widget>[
            for (int i = 0; i < extra.length; i++)
              IfallRow(
                icon: Icons.extension_rounded,
                title: extra[i]['name']?.toString() ?? 'Module',
                subtitle: extra[i]['url']?.toString() ?? '',
                value: extra[i]['enabled'] == true ? 'On' : 'Off',
                onTap: () => _editModule(context, index: i),
              ),
            IfallRow(
              icon: Icons.add_rounded,
              title: 'Add a source module',
              onTap: () => _editModule(context),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text(
            'Nothing here is ever uploaded: every source is contacted from '
            'this device, in the order shown.',
            style: IfallText.caption(c.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  Future<void> _editModule(BuildContext context, {int? index}) async {
    final SettingsService settings = context.read<SettingsService>();
    final List<Map<String, dynamic>> modules = settings.extraSources;
    final Map<String, dynamic>? existing =
        index != null && index < modules.length ? modules[index] : null;
    final TextEditingController name =
        TextEditingController(text: existing?['name']?.toString() ?? '');
    final TextEditingController url =
        TextEditingController(text: existing?['url']?.toString() ?? '');
    bool enabled = existing?['enabled'] != false;

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => AlertDialog(
          title: Text(existing == null ? 'Add source module' : 'Edit module'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: url,
                decoration: const InputDecoration(labelText: 'Endpoint URL'),
              ),
              const SizedBox(height: 6),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enabled'),
                value: enabled,
                onChanged: (bool v) => setState(() => enabled = v),
              ),
            ],
          ),
          actions: <Widget>[
            if (existing != null)
              TextButton(
                onPressed: () {
                  modules.removeAt(index!);
                  settings.setExtraSources(modules);
                  Navigator.of(dialogContext).pop(false);
                },
                child: const Text('Delete'),
              ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final Map<String, dynamic> entry = <String, dynamic>{
      'name': name.text.trim().isEmpty ? 'Module' : name.text.trim(),
      'url': url.text.trim(),
      'enabled': enabled,
    };
    if (index != null && index < modules.length) {
      modules[index] = entry;
    } else {
      modules.add(entry);
    }
    await settings.setExtraSources(modules);
  }
}

// ------------------------------------------------------------------ accounts

/// Scrobbling and account-linked imports.
class AccountsSettingsPage extends StatelessWidget {
  const AccountsSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final PresenceService presence = context.watch<PresenceService>();
    final IfallPalette c = IfallPalette.of(context);

    return _SettingsScaffold(
      title: 'Accounts',
      children: <Widget>[
        IfallGroup(
          title: 'Last.fm',
          children: <Widget>[
            IfallSwitchRow(
              icon: Icons.album_rounded,
              title: 'Scrobble to Last.fm',
              subtitle: settings.lastFmUser.isEmpty
                  ? 'Connect your account'
                  : 'Signed in as ${settings.lastFmUser}',
              value: settings.lastFmEnabled,
              onChanged: (bool v) async {
                if (!v) {
                  await settings.setLastFmEnabled(false);
                  return;
                }
                if (!context.mounted) return;
                final String? user = await _prompt(
                  context,
                  title: 'Last.fm username',
                  initial: settings.lastFmUser,
                );
                if (user == null) return;
                await settings.setLastFmUser(user);
                await settings.setLastFmEnabled(true);
                if (context.mounted) {
                  showAppNotice(
                    'Last.fm scrobbling on. Approve IfallMusic on last.fm if asked.',
                  );
                }
              },
            ),
            if (settings.lastFmEnabled)
              IfallRow(
                icon: Icons.link_off_rounded,
                title: 'Disconnect Last.fm',
                onTap: () async {
                  await settings.setLastFmEnabled(false);
                  await settings.setLastFmSession('');
                  await settings.setLastFmUser('');
                },
              ),
          ],
        ),
        IfallGroup(
          title: 'Status',
          footer: presence.queuedScrobbles == 0
              ? null
              : '${presence.queuedScrobbles} scrobble(s) are waiting for a connection and retry on the next track.',
          children: <Widget>[
            IfallRow(
              icon: Icons.sync_alt_rounded,
              title: 'Last activity',
              value: presence.status,
            ),
          ],
        ),
        IfallGroup(
          title: 'ListenBrainz',
          children: <Widget>[
            IfallRow(
              icon: Icons.vpn_key_outlined,
              title: 'ListenBrainz token',
              subtitle: settings.listenBrainzToken.isEmpty
                  ? 'Paste your user token'
                  : 'Token saved',
              value: settings.listenBrainzEnabled ? 'On' : 'Off',
              onTap: () async {
                final String? token = await _prompt(
                  context,
                  title: 'ListenBrainz token',
                  initial: settings.listenBrainzToken,
                  obscure: true,
                );
                if (token == null) return;
                await settings.setListenBrainzToken(token);
                await settings.setListenBrainzEnabled(token.isNotEmpty);
              },
            ),
          ],
        ),
        IfallGroup(
          title: 'Scrobbling rules',
          children: <Widget>[
            IfallSliderRow(
              icon: Icons.timeline_rounded,
              title: 'Scrobble at',
              subtitle: 'How far into a track a scrobble fires',
              value: settings.scrobblePercent.toDouble(),
              min: 10,
              max: 95,
              divisions: 17,
              format: (double v) => '${v.round()}%',
              onChanged: (double v) => settings.setScrobblePercent(v.round()),
            ),
          ],
        ),
        IfallGroup(
          title: 'Spotify',
          footer:
              'Import is manual: IfallMusic matches your Spotify playlists '
              'against what it can play and rebuilds them locally.',
          children: <Widget>[
            IfallRow(
              icon: Icons.playlist_add_rounded,
              title: 'Import playlists from Spotify',
              subtitle: 'Paste a public playlist link',
              onTap: () async {
                final String? link = await _prompt(
                  context,
                  title: 'Spotify playlist link',
                  initial: '',
                );
                if (link == null || link.isEmpty) return;
                if (!context.mounted) return;
                showAppNotice(
                  'Import is coming to this build — the link was noted.',
                );
              },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
          child: Text(
            'Scrobbling sends the track, artist and timestamp and nothing else. '
            'It happens from this device, only while a track is playing.',
            style: IfallText.caption(c.onSurfaceVariant),
          ),
        ),
      ],
    );
  }

  }
}

// ------------------------------------------------------------------- discord

/// Discord Rich Presence.
class DiscordSettingsPage extends StatelessWidget {
  const DiscordSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();

    return _SettingsScaffold(
      title: 'Discord',
      children: <Widget>[
        IfallGroup(
          title: 'Rich Presence',
          footer:
              'Shows the track, artist and progress on your Discord profile '
              'while IfallMusic is playing.',
          children: <Widget>[
            IfallSwitchRow(
              icon: Icons.discord_rounded,
              title: 'Enable Discord presence',
              value: settings.discordEnabled,
              onChanged: settings.setDiscordEnabled,
            ),
            IfallRow(
              icon: Icons.hub_outlined,
              title: 'Presence relay',
              subtitle: settings.discordRelay.isEmpty
                  ? 'Not set — Discord needs a relay on a device it can reach'
                  : settings.discordRelay,
              onTap: () async {
                final String? relay = await _prompt(
                  context,
                  title: 'Presence relay URL',
                  initial: settings.discordRelay,
                  hint: 'https://my-relay.example.com/presence',
                );
                if (relay == null) return;
                await settings.setDiscordRelay(relay);
              },
            ),
            IfallRow(
              icon: Icons.edit_outlined,
              title: 'Custom status line',
              subtitle: settings.discordDetails.isEmpty
                  ? 'Shows the album by default'
                  : settings.discordDetails,
              onTap: () async {
                final TextEditingController controller =
                    TextEditingController(text: settings.discordDetails);
                final String? value = await showDialog<String>(
                  context: context,
                  builder: (BuildContext dialogContext) => AlertDialog(
                    title: const Text('Custom status line'),
                    content: TextField(
                      controller: controller,
                      autofocus: true,
                      onSubmitted: (String v) =>
                          Navigator.of(dialogContext).pop(v),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.of(dialogContext).pop(controller.text),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
                if (value == null) return;
                await settings.setDiscordDetails(value);
              },
            ),
          ],
        ),
      ],
    );
  }
}

// -------------------------------------------------------------------- lyrics

/// Which lyrics providers the finder may ask, and in what order.
class LyricsSettingsPage extends StatelessWidget {
  const LyricsSettingsPage({super.key});

  /// Persists the choice and repoints the live lookup chain, so the next
  /// search uses the new order without restarting the app.
  void _setProviders(SettingsService settings, String provider, bool on) {
    final List<String> next = List<String>.from(settings.lyricsProviders);
    if (on) {
      if (!next.contains(provider)) next.add(provider);
    } else {
      next.remove(provider);
    }
    settings.setLyricsProviders(next);
    LyricsService.instance.providers = next;
  }

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();

    return _SettingsScaffold(
      title: 'Lyrics',
      children: <Widget>[
        IfallGroup(
          title: 'Providers',
          footer: 'Tried top to bottom. The first one with a hit wins.',
          children: <Widget>[
            for (final String provider in LyricsProviders.all)
              IfallRow(
                icon: Icons.lyrics_outlined,
                title: provider,
                subtitle: LyricsProviders.note(provider),
                trailing: Switch.adaptive(
                  value: settings.lyricsProviders.contains(provider),
                  activeColor: IfallPalette.of(context).accent,
                  onChanged: (bool on) => _setProviders(settings, provider, on),
                ),
                onTap: () => _setProviders(
                  settings,
                  provider,
                  !settings.lyricsProviders.contains(provider),
                ),
              ),
          ],
        ),
        IfallGroup(
          title: 'Display',
          children: <Widget>[
            IfallSwitchRow(
              icon: Icons.translate_rounded,
              title: 'Transliterate to latin script',
              subtitle: 'Romanizes non-latin lyrics when a provider has it',
              value: settings.lyricsRomanize,
              onChanged: settings.setLyricsRomanize,
            ),
            IfallRow(
              icon: Icons.g_translate_rounded,
              title: 'Translate lyrics into',
              value: settings.lyricsTranslateTo.isEmpty
                  ? 'Off'
                  : settings.lyricsTranslateTo,
              onTap: () => showTranslationSheet(context),
            ),
          ],
        ),
      ],
    );
  }
}

/// Picks the translation target language.
void showTranslationSheet(BuildContext context) {
  const List<String> targets = <String>[
    '',
    'English',
    'Hindi',
    'Spanish',
    'French',
    'German',
    'Portuguese',
    'Japanese',
    'Korean',
    'Arabic',
  ];
  showIfallSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => IfallSheet(
      title: 'Translate lyrics into',
      child: Consumer<SettingsService>(
        builder: (BuildContext context, SettingsService settings, _) => Column(
          children: <Widget>[
            for (final String target in targets)
              RadioListTile<String>(
                value: target,
                groupValue: settings.lyricsTranslateTo,
                title: Text(target.isEmpty ? 'Off' : target),
                onChanged: (String? v) {
                  settings.setLyricsTranslateTo(v ?? '');
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Picks the app language.
void showLanguageSheet(BuildContext context) {
  showIfallSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => IfallSheet(
      title: 'Language',
      subtitle: 'System follows your phone',
      child: Consumer<SettingsService>(
        builder: (BuildContext context, SettingsService settings, _) => Column(
          children: <Widget>[
            for (final (String code, String label) in appLanguages)
              RadioListTile<String>(
                value: code,
                groupValue: settings.language,
                title: Text(label),
                onChanged: (String? v) {
                  settings.setLanguage(v ?? 'system');
                  Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

/// Picks the offline cache ceiling.
void showCacheSizeSheet(BuildContext context) {
  const List<String> choices = <String>[
    '512MB',
    '1GB',
    '2GB',
    '4GB',
    'Unlimited',
  ];
  showIfallSheet<void>(
    context: context,
    builder: (BuildContext sheetContext) => IfallSheet(
      title: 'Offline cache size',
      subtitle: 'Smart playback cache; downloads stay separate',
      child: Consumer<SettingsService>(
        builder: (BuildContext context, SettingsService settings, _) => Column(
          children: <Widget>[
            for (final String choice in choices)
              RadioListTile<String>(
                value: choice,
                groupValue: settings.offlineCacheSizeLabel,
                title: Text(choice),
                onChanged: (String? v) async {
                  await settings.setOfflineCacheSizeLabel(v ?? '2GB');
                  if (context.mounted) {
                    await context.read<PlaybackService>().prunePlaybackCache();
                  }
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
              ),
          ],
        ),
      ),
    ),
  );
}

// ---------------------------------------------------------------- jam server

/// Where the Listen Together rooms live.
class JamServerPage extends StatefulWidget {
  const JamServerPage({super.key});

  @override
  State<JamServerPage> createState() => _JamServerPageState();
}

class _JamServerPageState extends State<JamServerPage> {
  late final TextEditingController _server;
  late final TextEditingController _name;

  @override
  void initState() {
    super.initState();
    final SettingsService settings = context.read<SettingsService>();
    _server = TextEditingController(text: settings.jamServer);
    _name = TextEditingController(text: settings.jamDisplayName);
  }

  @override
  void dispose() {
    _server.dispose();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: <Widget>[
            Row(
              children: <Widget>[
                const BackButton(),
                Expanded(
                  child: Text(
                    'Listen Together server',
                    style: IfallText.title(c.onSurface),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            IfallGroup(
              title: 'Server address',
              footer:
                  'The party server is a tiny Go service — its source is in '
                  '`backend/` in this repository, deployable to Render or any '
                  'small VPS. Rooms are in-memory and hold no library data.',
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: TextField(
                    controller: _server,
                    style: IfallText.body(c.onSurface),
                    decoration: InputDecoration(
                      hintText: JamService.placeholderServer,
                      hintStyle: IfallText.body(c.onSurfaceVariant),
                      filled: true,
                      fillColor: c.glass,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(IfallUI.rMd),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            IfallGroup(
              title: 'Your name in a room',
              footer: 'Defaults to your profile name when left empty.',
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                  child: TextField(
                    controller: _name,
                    style: IfallText.body(c.onSurface),
                    decoration: InputDecoration(
                      hintText: 'Listener',
                      hintStyle: IfallText.body(c.onSurfaceVariant),
                      filled: true,
                      fillColor: c.glass,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(IfallUI.rMd),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FilledButton(
              onPressed: () async {
                await context.read<SettingsService>().setJamServer(_server.text);
                await context
                    .read<SettingsService>()
                    .setJamDisplayName(_name.text);
                if (mounted) showAppNotice('Saved');
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

// --------------------------------------------------------------------- about

/// Version, credits and the support links.
class AboutSettingsPage extends StatelessWidget {
  const AboutSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
          children: <Widget>[
            Row(
              children: <Widget>[
                const BackButton(),
                Expanded(
                  child: Text('About', style: IfallText.title(c.onSurface)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Center(child: _AboutCard()),
            const SizedBox(height: 8),
            const _ContactSection(),
            const _MadeWithLoveFooter(),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Theme, accent and about widgets — kept from the previous Settings screen so
// the colour editor, the swatch grid and the support card behave exactly as
// before.
// ---------------------------------------------------------------------------

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
                            color: IfallTokens.textMuted,
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
                      : 'Clean black look; only song-quality text changes colour',
                  style: const TextStyle(
                    fontSize: 12,
                    color: IfallTokens.textMuted,
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
                    color: IfallTokens.textMuted,
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
                          color: IfallTokens.textMuted,
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
              color: IfallTokens.textFaint,
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
            color: IfallTokens.textSecondary,
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
              color: IfallTokens.textMuted,
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
                        color: IfallTokens.textMuted,
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
              color: IfallTokens.textSecondary,
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
                        color: IfallTokens.textSecondary,
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
                        color: IfallTokens.textMuted,
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
                      color: IfallTokens.textSecondary,
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
                    color: IfallTokens.textSecondary,
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
            style: const TextStyle(fontSize: 12, color: IfallTokens.textMuted),
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
              color: IfallTokens.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}

/// A contact / support row. The subtitle and trailing slot were dropped when
/// the About page moved to [IfallRow]; nothing passes them any more.
class _SettingTile extends StatelessWidget {
  const _SettingTile({
    required this.icon,
    required this.title,
    this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GlassListTile(
      onTap: onTap,
      leading: _TileIcon(icon),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: IfallTokens.textFaint,
      ),
      child: _TileText(title: title, subtitle: null),
    );
  }
}

