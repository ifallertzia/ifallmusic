import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/nerd_stats.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../widgets/song_menu.dart';
import '../widgets/sidify_widgets.dart';
import 'equalizer_page.dart';

/// The player's capsule sheet (the site's PlaybackSheet): speed, sleep
/// timer, crossfade and friends, plus the path to the equalizer and the
/// "stats for nerds". Everything here drives the same engine settings the
/// old interface used — nothing about playback changes.
Future<void> showPlaybackSheet(BuildContext context) {
  return showSidifySheet(
    context,
    title: 'Playback',
    child: const _PlaybackSheetBody(),
  );
}

class _PlaybackSheetBody extends StatelessWidget {
  const _PlaybackSheetBody();

  @override
  Widget build(BuildContext context) {
    final PlaybackService playback = context.watch<PlaybackService>();
    final SettingsService settings = context.watch<SettingsService>();
    final SidifyTokens t = context.sidify;
    final Duration? sleep = playback.sleepRemaining;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _row(
            context,
            Icons.speed_rounded,
            'Speed',
            trailing: Wrap(
              spacing: 6,
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
          _row(
            context,
            Icons.bedtime_rounded,
            sleep != null
                ? 'Sleep timer · ${sleep.inMinutes + 1} min left'
                : 'Sleep timer',
            trailing: Wrap(
              spacing: 6,
              children: <Widget>[
                if (sleep != null)
                  _miniChip(context, 'Off', false, playback.cancelSleepTimer)
                else
                  for (final int m in <int>[15, 30, 45, 60])
                    _miniChip(
                      context,
                      '$m',
                      false,
                      () => playback.startSleepTimer(Duration(minutes: m)),
                    ),
              ],
            ),
          ),
          _row(
            context,
            Icons.blur_linear_rounded,
            'Crossfade · ${settings.crossfadeSeconds == 0 ? 'Off' : '${settings.crossfadeSeconds}s'}',
            trailing: SizedBox(
              width: 130,
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
          _row(
            context,
            Icons.all_inclusive_rounded,
            'AutoPlay',
            subtitle: 'Similar music lines up before the queue ends',
            trailing: SidifySwitch(
              value: settings.autoplay,
              label: 'AutoPlay',
              onChanged: settings.setAutoplay,
            ),
          ),
          _row(
            context,
            Icons.graphic_eq_rounded,
            'Volume normalization',
            trailing: SidifySwitch(
              value: playback.normalizeVolume,
              label: 'Volume normalization',
              onChanged: playback.setNormalizeVolume,
            ),
          ),
          _row(
            context,
            Icons.content_cut_rounded,
            'Skip silence',
            trailing: SidifySwitch(
              value: settings.skipSilence,
              label: 'Skip silence',
              onChanged: (bool v) async {
                await settings.setSkipSilence(v);
                await playback.setSkipSilence(v);
              },
            ),
          ),
          Divider(
            height: 24,
            thickness: 0.5,
            color: t.hairline,
            indent: 20,
            endIndent: 20,
          ),
          _row(
            context,
            Icons.equalizer_rounded,
            'Equalizer',
            subtitle: settings.equalizerEnabled
                ? settings.equalizerProfileName
                : 'Off',
            chevron: true,
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const EqualizerPage(),
                  settings: const RouteSettings(name: 'sidify/equalizer'),
                ),
              );
            },
          ),
          _row(
            context,
            Icons.query_stats_rounded,
            'Stats for nerds',
            chevron: true,
            onTap: () {
              Navigator.of(context).pop();
              showSidifySheet(
                context,
                title: 'Stats for nerds',
                child: const _NerdStatsBody(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _row(
    BuildContext context,
    IconData icon,
    String title, {
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
    bool chevron = false,
  }) {
    final SidifyTokens t = context.sidify;
    final Widget row = Container(
      constraints: const BoxConstraints(minHeight: 52),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 19, color: t.text),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: TextStyle(fontSize: 15.5, color: t.text),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12.5, color: t.text2),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing,
          if (chevron)
            Icon(Icons.chevron_right_rounded, size: 18, color: t.text3),
        ],
      ),
    );
    if (onTap == null) return row;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: row),
    );
  }

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

  SliderThemeData _sliderTheme(SidifyTokens t) => SliderThemeData(
        trackHeight: 4,
        activeTrackColor: t.text,
        inactiveTrackColor: t.fill3,
        thumbColor: t.text,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      );
}

/// What the engine is actually doing, in the site's "stats for nerds" spirit.
/// Only neutral facts are shown — codec, bitrate, format — never a provider.
class _NerdStatsBody extends StatelessWidget {
  const _NerdStatsBody();

  @override
  Widget build(BuildContext context) {
    final NerdStats s = context.watch<PlaybackService>().nerdStats;
    final SidifyTokens t = context.sidify;
    Widget stat(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 120,
                child: Text(k, style: TextStyle(fontSize: 13.5, color: t.text2)),
              ),
              Expanded(
                child: Text(
                  v,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: t.text,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
    return SingleChildScrollView(
      padding: const EdgeInsets.only(top: 8, bottom: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          stat('Engine', 'Sidify'),
          stat('Stream', s.bufferLine.isEmpty || s.bufferLine == '—'
              ? '—'
              : s.bufferLine),
          stat('Format', s.formatLine),
          stat('Progress', s.progressLine),
          stat('Speed', '${s.speed}×'),
          stat('Volume', '${(s.volume * 100).round()}%'),
          stat('Normalization', s.normalized ? 'On' : 'Off'),
          stat('Crossfade', s.crossfadeSeconds == 0
              ? 'Off'
              : '${s.crossfadeSeconds}s'),
          stat('Skip silence', s.skipSilence ? 'On' : 'Off'),
          stat('Platform', s.platformLine),
        ],
      ),
    );
  }
}
