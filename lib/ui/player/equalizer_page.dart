import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/native_bridge.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../widgets/sidify_widgets.dart';

/// The equalizer, in the Sidify style: an on/off row, preset chips and one
/// vertical slider per band. Bands bind to the running Android player session
/// (the engine's native bridge) and persist through Settings, exactly as
/// before — only the clothes are new.
class EqualizerPage extends StatefulWidget {
  const EqualizerPage({super.key});

  @override
  State<EqualizerPage> createState() => _EqualizerPageState();
}

class _EqualizerPageState extends State<EqualizerPage> {
  EqualizerInfo? _info;
  bool _enabled = false;
  bool _loading = true;
  bool _unsupported = false;
  List<int> _levels = <int>[];
  String? _preset;

  static const List<String> _builtIn = <String>[
    'Flat',
    'Bass Boost',
    'Vocal',
    'Rock',
    'Pop',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _bind());
  }

  Future<void> _bind() async {
    if (!Platform.isAndroid) {
      setState(() {
        _loading = false;
        _unsupported = true;
      });
      return;
    }
    final PlaybackService playback = context.read<PlaybackService>();
    final SettingsService settings = context.read<SettingsService>();
    int? session = playback.player.androidAudioSessionId;
    if (session == null || session == 0) {
      try {
        session = await playback.player.androidAudioSessionIdStream
            .firstWhere((int? id) => id != null && id != 0)
            .timeout(const Duration(seconds: 4));
      } catch (_) {
        session = null;
      }
    }
    if (session == null) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _unsupported = true;
      });
      return;
    }
    final EqualizerInfo? info = await NativeBridge.eqInit(session);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _info = info;
      _unsupported = info == null || !info.supported;
      _enabled = settings.equalizerEnabled;
      _preset = settings.equalizerProfileName == 'Original audio'
          ? null
          : settings.equalizerProfileName;
      _levels = info == null ? <int>[] : List<int>.from(info.levels);
      final List<int> saved = settings.equalizerLevels;
      if (saved.length == info?.bands) _levels = saved;
    });
    if (info != null && info.supported) {
      if (settings.equalizerEnabled) {
        final List<int> saved = settings.equalizerLevels;
        for (int i = 0; i < saved.length && i < info.bands; i++) {
          await NativeBridge.eqSetBand(i, saved[i]);
        }
        await NativeBridge.eqSetEnabled(true);
      } else {
        await NativeBridge.eqSetEnabled(false);
      }
    }
  }

  Future<void> _applyPreset(String name) async {
    final EqualizerInfo? info = _info;
    if (info == null) return;
    final List<int> next = _curve(name, info);
    for (int i = 0; i < next.length && i < info.bands; i++) {
      await NativeBridge.eqSetBand(i, next[i]);
    }
    await NativeBridge.eqSetEnabled(true);
    if (!mounted) return;
    setState(() {
      _preset = name;
      _levels = next;
      _enabled = true;
    });
    await context.read<SettingsService>().setEqualizerProfile(
          name: name,
          levels: next,
          enabled: true,
        );
  }

  List<int> _curve(String name, EqualizerInfo info) {
    final int n = info.bands;
    final int min = info.minLevel;
    final int max = info.maxLevel;
    int clampUnit(double unit) {
      final double span = (max - min).toDouble();
      final int value = (min + span * unit).round();
      return value.clamp(min, max);
    }

    return List<int>.generate(n, (int i) {
      final double t = n == 1 ? 0.5 : i / (n - 1);
      return switch (name) {
        'Bass Boost' => clampUnit(t < 0.35 ? 0.85 : 0.40),
        'Vocal' => clampUnit(t > 0.3 && t < 0.7 ? 0.82 : 0.42),
        'Rock' => clampUnit(t < 0.25 || t > 0.75 ? 0.8 : 0.45),
        'Pop' => clampUnit(0.55 + (t - 0.5).abs() * 0.4),
        _ => 0.clamp(min, max),
      };
    });
  }

  Future<void> _bandChanged(int band, int level) async {
    final EqualizerInfo? info = _info;
    if (info == null) return;
    setState(() {
      _levels[band] = level;
      _preset = null;
    });
    await NativeBridge.eqSetBand(band, level);
    if (_enabled) {
      await context.read<SettingsService>().setEqualizerProfile(
            name: 'Custom',
            levels: List<int>.of(_levels),
            enabled: true,
          );
    }
  }

  Future<void> _setEnabled(bool v) async {
    setState(() => _enabled = v);
    await NativeBridge.eqSetEnabled(v);
    await context.read<SettingsService>().setEqualizerProfile(
          name: _preset ?? 'Custom',
          levels: List<int>.of(_levels),
          enabled: v,
        );
  }

  String _freq(int milliHz) {
    final double hz = milliHz / 1000;
    if (hz >= 1000) return '${(hz / 1000).toStringAsFixed(hz >= 10000 ? 0 : 1)}k';
    return '${hz.round()}';
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final EqualizerInfo? info = _info;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Equalizer', style: SidifyText.titleM(t.text)),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: t.text2))
          : _unsupported || info == null
              ? EmptyState(
                  icon: Icons.equalizer_rounded,
                  title: 'Equalizer unavailable',
                  desc: 'Play a song first, then come back — the equalizer '
                      'attaches to the playing audio.',
                )
              : ListView(
                  padding: const EdgeInsets.only(top: 8, bottom: 190),
                  children: <Widget>[
                    SidifyGroup(
                      children: <Widget>[
                        SidifyGroupRow(
                          icon: Icons.equalizer_rounded,
                          title: 'Equalizer',
                          subtitle: _preset ?? 'Custom curve',
                          trailing: SidifySwitch(
                            value: _enabled,
                            label: 'Equalizer',
                            onChanged: _setEnabled,
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: <Widget>[
                          for (final String name in _builtIn)
                            _presetChip(name),
                        ],
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: <Widget>[
                          for (int i = 0; i < info.bands; i++)
                            Expanded(child: _bandSlider(info, i)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        'Levels are in decibels, bound to the device\'s audio '
                        'session. The curve is restored automatically on the '
                        'next song.',
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.45,
                          color: t.text2,
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _presetChip(String name) {
    final SidifyTokens t = context.sidify;
    final bool on = _preset == name && _enabled;
    return Material(
      color: on ? t.primary : t.fill,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: () => _applyPreset(name),
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: on ? t.onPrimary : t.text,
            ),
          ),
        ),
      ),
    );
  }

  Widget _bandSlider(EqualizerInfo info, int band) {
    final SidifyTokens t = context.sidify;
    final int level = band < _levels.length ? _levels[band] : 0;
    final double db = level / 100;
    final int center = band < info.centersMilliHz.length
        ? info.centersMilliHz[band]
        : 0;
    return Opacity(
      opacity: _enabled ? 1 : 0.45,
      child: Column(
        children: <Widget>[
          Text(
            '${db >= 0 ? '+' : ''}${db.toStringAsFixed(1)}',
            style: TextStyle(fontSize: 11, color: t.text2),
          ),
          SizedBox(
            height: 190,
            child: RotatedBox(
              quarterTurns: 3,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4,
                  activeTrackColor: t.text,
                  inactiveTrackColor: t.fill3,
                  thumbColor: t.text,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 14),
                ),
                child: Slider(
                  value: level.toDouble(),
                  min: info.minLevel.toDouble(),
                  max: info.maxLevel.toDouble(),
                  onChanged: _enabled
                      ? (double v) => _bandChanged(band, v.round())
                      : null,
                ),
              ),
            ),
          ),
          Text(
            center > 0 ? _freq(center) : '—',
            style: TextStyle(fontSize: 11.5, color: t.text2),
          ),
        ],
      ),
    );
  }
}
