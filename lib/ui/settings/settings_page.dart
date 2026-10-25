import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/branding.dart';
import '../../config/foss_build.dart';
import '../../core/models/playlist.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/library_service.dart';
import '../../core/services/listen_together_service.dart';
import '../../core/services/music_download_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/playlist_sync_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../library/downloads_page.dart';
import '../library/lyrics_finder_page.dart';
import '../library/replay_page.dart';
import '../player/equalizer_page.dart';
import '../shell/sidify_shell_controller.dart';
import '../widgets/sidify_widgets.dart';
import 'backup_sheet.dart';
import 'diagnostics_page.dart';
import 'update_dialog.dart';

/// Settings, grouped the site's way — Profile, Appearance, Playback, Sound,
/// Lyrics, Listen Together, Downloads & storage, Data, Privacy, About —
/// each row driving the same engine settings it always did.
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final LibraryService library = context.watch<LibraryService>();
    final PlaybackService playback = context.watch<PlaybackService>();
    final MusicDownloadService downloads = context.watch<MusicDownloadService>();
    final JamService jam = context.watch<JamService>();
    final SidifyTokens t = context.sidify;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Settings', style: SidifyText.titleM(t.text)),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 190),
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          // ---------------------------------------------------------- Profile
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            child: Row(
              children: <Widget>[
                const SidifyLogoMark(size: 56),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        settings.displayName.isEmpty
                            ? 'Sidify listener'
                            : settings.displayName,
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: t.text,
                        ),
                      ),
                      Text(
                        settings.email,
                        style: TextStyle(fontSize: 13.5, color: t.text2),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SidifyGroup(
            children: <Widget>[
              SidifyGroupRow(
                icon: Icons.person_rounded,
                title: 'Display name',
                subtitle: settings.displayName.isEmpty
                    ? 'Not set'
                    : settings.displayName,
                chevron: true,
                onTap: () => _editText(
                  context,
                  title: 'Display name',
                  initial: settings.displayName,
                  onSave: settings.setDisplayName,
                ),
              ),
              SidifyGroupRow(
                icon: Icons.mail_rounded,
                title: 'Email',
                subtitle: settings.email,
                chevron: true,
                onTap: () => _editText(
                  context,
                  title: 'Email',
                  initial: settings.email,
                  onSave: settings.setEmail,
                ),
              ),
            ],
          ),

          // ------------------------------------------------------- Appearance
          SidifyGroup(
            header: 'Appearance',
            footer: 'Colour from the artwork tints the player, the page '
                'backdrop and album headers.',
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
              SidifyGroupRow(
                icon: Icons.palette_rounded,
                title: 'Colour from artwork',
                trailing: SidifySwitch(
                  value: settings.dynamicColor,
                  label: 'Colour from artwork',
                  onChanged: settings.setDynamicColor,
                ),
              ),
              SidifyGroupRow(
                icon: Icons.motion_photos_off_rounded,
                title: 'Reduce motion',
                subtitle: 'No artwork breathing or drifting colours',
                trailing: SidifySwitch(
                  value: settings.reduceMotion,
                  label: 'Reduce motion',
                  onChanged: settings.setReduceMotion,
                ),
              ),
              SidifyGroupRow(
                icon: Icons.blur_on_rounded,
                title: 'Liquid glass',
                subtitle: 'Frosted tab bar and mini player',
                trailing: SidifySwitch(
                  value: settings.liquidGlass,
                  label: 'Liquid glass',
                  onChanged: settings.setLiquidGlass,
                ),
              ),
            ],
          ),

          // --------------------------------------------------------- Playback
          SidifyGroup(
            header: 'Playback',
            children: <Widget>[
              SidifyGroupRow(
                icon: Icons.all_inclusive_rounded,
                title: 'AutoPlay',
                subtitle: 'When the queue ends, keep similar music playing',
                trailing: SidifySwitch(
                  value: settings.autoplay,
                  label: 'AutoPlay',
                  onChanged: settings.setAutoplay,
                ),
              ),
              SidifyGroupRow(
                icon: Icons.skip_next_rounded,
                title: 'Gapless playback',
                subtitle: 'Preload the next song',
                trailing: SidifySwitch(
                  value: settings.gapless,
                  label: 'Gapless playback',
                  onChanged: settings.setGapless,
                ),
              ),
              SidifyGroupRow(
                icon: Icons.blur_linear_rounded,
                title: settings.crossfadeSeconds == 0
                    ? 'Crossfade · Off'
                    : 'Crossfade · ${settings.crossfadeSeconds}s',
                subtitle: 'Blend the end of each song into the next',
                trailing: SizedBox(
                  width: 120,
                  child: SliderTheme(
                    data: _sliderTheme(t),
                    child: Slider(
                      value: settings.crossfadeSeconds.toDouble(),
                      min: 0,
                      max: 12,
                      divisions: 12,
                      onChanged: (double v) =>
                          playback.setCrossfadeSeconds(v.round()),
                    ),
                  ),
                ),
              ),
              SidifyGroupRow(
                icon: Icons.history_rounded,
                title: 'Resume where you left off',
                trailing: SidifySwitch(
                  value: settings.rememberPosition,
                  label: 'Resume where you left off',
                  onChanged: settings.setRememberPosition,
                ),
              ),
              SidifyGroupRow(
                icon: Icons.speed_rounded,
                // No "Speed" word: the icon is the whole label, so the rate
                // chips get the row to themselves instead of fighting the word
                // for one line on a narrow phone — the same call the Playback
                // sheet already makes.
                title: '',
                trailing: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: <Widget>[
                    for (final double v in <double>[0.75, 1, 1.25, 1.5, 2])
                      _miniChip(
                        context,
                        v == 1 ? '1×' : '${v}×',
                        playback.speed == v,
                        () => playback.setSpeed(v),
                      ),
                  ],
                ),
              ),
            ],
          ),

          // ------------------------------------------------------------ Sound
          SidifyGroup(
            header: 'Sound',
            children: <Widget>[
              // Streaming quality · Wi-Fi / Mobile are gone for good — those
              // rows drove nothing and only crowded this group.
              SidifyGroupRow(
                icon: Icons.volume_up_rounded,
                title: 'Volume normalization',
                subtitle: 'Even out loudness between songs',
                trailing: SidifySwitch(
                  value: playback.normalizeVolume,
                  label: 'Volume normalization',
                  onChanged: playback.setNormalizeVolume,
                ),
              ),
              SidifyGroupRow(
                icon: Icons.equalizer_rounded,
                title: 'Equalizer',
                subtitle: settings.equalizerEnabled
                    ? settings.equalizerProfileName
                    : 'Off',
                chevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EqualizerPage(),
                    settings: const RouteSettings(name: 'sidify/equalizer'),
                  ),
                ),
              ),
            ],
          ),

          // ----------------------------------------------------------- Lyrics
          SidifyGroup(
            header: 'Lyrics',
            footer: 'Timed lyrics light up line by line. Sidify finds the '
                'words automatically — nothing to configure.',
            children: <Widget>[
              SidifyGroupRow(
                icon: Icons.lyrics_rounded,
                title: 'Lyrics finder',
                subtitle: 'Look up the words to any song',
                chevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LyricsFinderPage(),
                    settings: const RouteSettings(name: 'sidify/lyrics-finder'),
                  ),
                ),
              ),
              SidifyGroupRow(
                icon: Icons.translate_rounded,
                title: 'Romanize lyrics',
                subtitle: 'Show non-Latin scripts in Latin letters',
                trailing: SidifySwitch(
                  value: settings.lyricsRomanize,
                  label: 'Romanize lyrics',
                  onChanged: settings.setLyricsRomanize,
                ),
              ),
              SidifyGroupRow(
                icon: Icons.language_rounded,
                title: 'Translate lyrics into',
                trailing: SidifyChips(
                  small: true,
                  value: settings.lyricsTranslateTo,
                  options: const <(String, String)>[
                    ('', 'Off'),
                    ('en', 'English'),
                    ('hi', 'Hindi'),
                  ],
                  onChanged: settings.setLyricsTranslateTo,
                ),
              ),
            ],
          ),

          // --------------------------------------------------- Listen Together
          SidifyGroup(
            header: 'Listen Together',
            footer: 'Your display name is what others see in a room. Rooms '
                'close by themselves once everyone has left.',
            children: <Widget>[
              SidifyGroupRow(
                icon: Icons.people_rounded,
                title: jam.inRoom
                    ? 'In room ${jam.code ?? ''}'
                    : 'Not in a room',
                subtitle: jam.inRoom
                    ? (jam.isReconnecting
                        ? 'Reconnecting…'
                        : '${jam.members.length} listening')
                    : 'Start one or join with a code',
                chevron: true,
                onTap: () {
                  Navigator.of(context).pop();
                  context.read<SidifyShellController>().goTogether();
                },
              ),
              if (jam.inRoom)
                SidifyGroupRow(
                  icon: Icons.logout_rounded,
                  title: 'Leave the room',
                  danger: true,
                  onTap: () => jam.leave(),
                ),
            ],
          ),

          // ---------------------------------------------- Downloads & storage
          SidifyGroup(
            header: 'Downloads & storage',
            children: <Widget>[
              SidifyGroupRow(
                icon: Icons.download_rounded,
                title: 'Your downloads',
                subtitle:
                    '${downloads.downloaded.length} saved · ${downloads.jobs.where((j) => j.phase == MusicDownloadPhase.running || j.phase == MusicDownloadPhase.idle).length} active',
                chevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DownloadsPage(),
                    settings: const RouteSettings(name: 'sidify/downloads'),
                  ),
                ),
              ),
              SidifyGroupRow(
                icon: Icons.favorite_rounded,
                title: 'Download songs you love',
                subtitle: 'Every new like becomes available offline',
                trailing: SidifySwitch(
                  value: settings.autoDownloadLikes,
                  label: 'Download songs you love',
                  onChanged: settings.setAutoDownloadLikes,
                ),
              ),
              SidifyGroupRow(
                icon: Icons.cached_rounded,
                title: 'Clear playback cache',
                subtitle: 'Removes temporary streamed-song cache only',
                onTap: () async {
                  await playback.clearPlaybackCache();
                  showAppNotice('Playback cache cleared');
                },
              ),
            ],
          ),

          // ------------------------------------------------------------- Data
          SidifyGroup(
            header: 'Library & data',
            children: <Widget>[
              SidifyGroupRow(
                icon: Icons.backup_rounded,
                title: 'Backup library',
                subtitle: 'Copy JSON, or paste a backup to merge or replace',
                chevron: true,
                onTap: () => showBackupSheet(context),
              ),
              SidifyGroupRow(
                icon: Icons.qr_code_2_rounded,
                title: 'Generate playlist code',
                subtitle: 'Copy a code that restores all your playlists',
                onTap: () async {
                  showAppNotice('Generating code…');
                  final String? code =
                      await PlaylistSyncService.shareAllPlaylists(
                    library.playlists
                        .map((p) => p.toJson())
                        .toList(),
                  );
                  if (code != null) {
                    await settings.setLastPlaylistCode(code);
                    showAppNotice('Playlist code copied');
                  } else {
                    showAppNotice('Could not generate a code');
                  }
                },
              ),
              SidifyGroupRow(
                icon: Icons.download_for_offline_rounded,
                title: 'Import playlist code',
                subtitle: 'Paste a code to restore playlists',
                chevron: true,
                onTap: () => _importCode(context),
              ),
              SidifyGroupRow(
                icon: Icons.bar_chart_rounded,
                title: 'Your Replay',
                subtitle: 'Minutes, top songs and top artists',
                chevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const ReplayPage(),
                    settings: const RouteSettings(name: 'sidify/replay'),
                  ),
                ),
              ),
            ],
          ),

          // ---------------------------------------------------------- Privacy
          SidifyGroup(
            header: 'Privacy',
            children: <Widget>[
              SidifyGroupRow(
                icon: Icons.manage_search_rounded,
                title: 'Clear search history',
                onTap: () async {
                  await library.clearSearchHistory();
                  showAppNotice('Search history cleared');
                },
              ),
              SidifyGroupRow(
                icon: Icons.history_rounded,
                title: 'Clear listening history',
                onTap: () async {
                  await library.clearHistory();
                  showAppNotice('Listening history cleared');
                },
              ),
              SidifyGroupRow(
                icon: Icons.insights_rounded,
                title: 'Keep on-device listening stats',
                subtitle: 'Feeds Replay and your recommendations',
                trailing: SidifySwitch(
                  value: settings.statsOptIn,
                  label: 'Keep on-device listening stats',
                  onChanged: settings.setStatsOptIn,
                ),
              ),
              SidifyGroupRow(
                icon: Icons.restart_alt_rounded,
                title: 'Reset all settings',
                subtitle: 'Library, downloads and history stay untouched',
                danger: true,
                onTap: () async {
                  await settings.resetAll();
                  showAppNotice('Settings reset');
                },
              ),
            ],
          ),

          // ------------------------------------------------------------ About
          SidifyGroup(
            header: 'About',
            children: <Widget>[
              SidifyGroupRow(
                title: 'Sidify ${SidifyBranding.fullVersionLabel}',
                subtitle: '${SidifyBranding.tagline} · ${SidifyBranding.author}',
                trailing: const SidifyLogoMark(size: 30),
              ),
              SidifyGroupRow(
                icon: Icons.language_rounded,
                title: 'Website & latest download',
                subtitle: SidifyBranding.latestDownloadMessage,
                chevron: true,
                onTap: () => launchUrl(
                  Uri.parse(SidifyBranding.websiteUrl),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              if (FossBuild.githubUpdaterEnabled)
                SidifyGroupRow(
                  icon: Icons.system_update_rounded,
                  title: 'Check for updates',
                  subtitle: 'Install the newest Sidify over this app',
                  chevron: true,
                  onTap: () => showUpdateDialog(context),
                ),
              SidifyGroupRow(
                icon: Icons.bug_report_rounded,
                title: 'Diagnostics',
                subtitle: 'Boot log, playback errors and device info',
                chevron: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const DiagnosticsPage(),
                    settings: const RouteSettings(name: 'sidify/diagnostics'),
                  ),
                ),
              ),
            ],
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Sidify · ${SidifyBranding.tagline}',
                style: TextStyle(fontSize: 12, color: t.text3),
              ),
            ),
          ),
        ],
      ),
    );
  }

  SliderThemeData _sliderTheme(SidifyTokens t) => SliderThemeData(
        trackHeight: 4,
        activeTrackColor: t.text,
        inactiveTrackColor: t.fill3,
        thumbColor: t.text,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      );

  Widget _miniChip(
    BuildContext context,
    String label,
    bool on,
    VoidCallback onTap,
  ) {
    final SidifyTokens t = context.sidify;
    return Material(
      color: on ? t.primary : t.fill2,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: on ? t.onPrimary : t.text,
            ),
          ),
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
    final SidifyTokens t = context.sidify;
    final String? value = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: t.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text(title, style: SidifyText.title(t.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: t.text),
          onSubmitted: (String v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: t.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('Save', style: TextStyle(color: t.text)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value != null) await onSave(value);
  }

  Future<void> _importCode(BuildContext context) async {
    final TextEditingController controller = TextEditingController();
    final SidifyTokens t = context.sidify;
    final String? code = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        backgroundColor: t.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('Import playlist code', style: SidifyText.title(t.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: t.text),
          decoration: InputDecoration(
            hintText: 'Paste the code',
            hintStyle: TextStyle(color: t.text2),
          ),
          onSubmitted: (String v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: t.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('Import', style: TextStyle(color: t.text)),
          ),
        ],
      ),
    );
    controller.dispose();
    if (code == null || code.trim().isEmpty || !context.mounted) return;
    final Map<String, dynamic>? payload =
        await PlaylistSyncService.fetchAll(code.trim());
    if (payload == null) {
      showAppNotice('That code did not answer');
      return;
    }
    final List<Playlist> incoming =
        PlaylistSyncService.playlistsFromPayload(payload);
    await context.read<LibraryService>().mergePlaylists(incoming);
    showAppNotice('Playlists restored');
  }
}
