import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/native_bridge.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/glass.dart';
import '../../core/theme/saxify_accents.dart';
import '../../core/theme/saxify_theme.dart';
import '../widgets/neon.dart';
import '../widgets/search_fab.dart';

/// Studio equalizer with saved user presets.
///
/// Bands bind to the running Android player session, and selected settings
/// persist across tracks and app restarts.
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
  List<Map<String, dynamic>> _savedPresets = <Map<String, dynamic>>[];

  static const List<String> _custom = <String>[
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
      _savedPresets = settings.equalizerCustomPresets;
      final List<int> savedLevels = settings.equalizerLevels;
      _enabled = settings.equalizerEnabled;
      _preset = settings.equalizerProfileName == 'Original audio'
          ? null
          : settings.equalizerProfileName;
      _levels = info == null ? <int>[] : List<int>.from(info.levels);
      if (savedLevels.length == info?.bands) _levels = savedLevels;
    });
    if (info != null && info.supported && settings.equalizerEnabled) {
      final List<int> savedLevels = settings.equalizerLevels;
      for (int i = 0; i < savedLevels.length && i < info.bands; i++) {
        await NativeBridge.eqSetBand(i, savedLevels[i]);
      }
      await NativeBridge.eqSetEnabled(true);
    } else if (info != null && info.supported) {
      await NativeBridge.eqSetEnabled(false);
    }
  }

  Future<void> _applyPreset(String name) async {
    final EqualizerInfo? info = _info;
    if (info == null) return;
    Map<String, dynamic>? saved;
    for (final Map<String, dynamic> item in _savedPresets) {
      if (item['name'] == name) {
        saved = item;
        break;
      }
    }
    final List<int> next = saved?['levels'] is List
        ? (saved!['levels'] as List).map((Object? v) => v is num ? v.round() : 0).toList()
        : _curve(name, info);
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

  Future<void> _saveCustomPreset() async {
    final TextEditingController controller = TextEditingController();
    final String? name = await showDialog<String>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Save equalizer preset'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 24,
          decoration: const InputDecoration(labelText: 'Preset name'),
          onSubmitted: (String value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(controller.text), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    final String clean = name?.trim() ?? '';
    if (clean.isEmpty || !mounted || _levels.isEmpty) return;
    final SettingsService settings = context.read<SettingsService>();
    await settings.saveEqualizerCustomPreset(clean, _levels);
    await NativeBridge.eqSetEnabled(true);
    await settings.setEqualizerProfile(name: clean, levels: _levels, enabled: true);
    if (!mounted) return;
    setState(() {
      _preset = clean;
      _enabled = true;
      _savedPresets = settings.equalizerCustomPresets;
    });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved "$clean"')));
  }

  List<int> _curve(String name, EqualizerInfo info) {
    final int n = info.bands;
    final int min = info.minLevel;
    final int max = info.maxLevel;
    int clamp(double unit) {
      final double span = (max - min).toDouble();
      final int value = (min + span * unit).round();
      if (value < min) return min;
      if (value > max) return max;
      return value;
    }

    return List<int>.generate(n, (int i) {
      final double t = n == 1 ? 0.5 : i / (n - 1);
      switch (name) {
        case 'Bass Boost':
          return clamp(t < 0.35 ? 0.85 : 0.40);
        case 'Vocal':
          return clamp(t > 0.3 && t < 0.7 ? 0.82 : 0.42);
        case 'Rock':
          return clamp(t < 0.25 || t > 0.75 ? 0.8 : 0.45);
        case 'Pop':
          return clamp(0.55 + (t - 0.5).abs() * 0.4);
        case 'Flat':
        default:
          return 0.clamp(min, max);
      }
    });
  }

  @override
  void dispose() {
    // Leave the effect attached so playback keeps the curve after this page closes.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.read<SettingsService>();
    return AuroraBackdrop(
      intensity: 0.5,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          title: const Text('Equalizer'),
          actions: const <Widget>[SaxifySearchButton()],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 180),
          children: <Widget>[
            // ------------------------------------------------ bands
            const SectionHeader(
              title: 'Studio equalizer',
              subtitle: 'Bound to the live player session',
              padding: EdgeInsets.fromLTRB(4, 6, 4, 10),
            ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_unsupported)
              const EmptyState(
                icon: Icons.graphic_eq_rounded,
                title: 'Equalizer unavailable',
                message:
                    'This device does not expose an audio session equalizer. Playback is unchanged.',
              )
            else ...<Widget>[
              GlassPanel(
                radius: SaxifyTheme.radiusMd,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Enable equalizer'),
                      subtitle: const Text(
                        'Connected to the current player session',
                        style: TextStyle(color: SaxifyColors.textMuted, fontSize: 12),
                      ),
                      value: _enabled,
                      onChanged: (bool v) async {
                        await NativeBridge.eqSetEnabled(v);
                        if (!mounted) return;
                        setState(() => _enabled = v);
                        await settings.setEqualizerProfile(
                          name: v ? (_preset ?? 'Custom') : 'Original audio',
                          levels: _levels,
                          enabled: v,
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Presets',
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final String name in <String>[
                          ..._custom,
                          ...?_info?.presets.where((String p) => !_custom.contains(p)),
                        ..._savedPresets.map((Map<String, dynamic> p) => p['name'].toString()),
                        ])
                          ChoiceChip(
                            label: Text(name),
                            selected: _preset == name,
                            onSelected: (_) => _applyPreset(name),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _levels.isEmpty ? null : _saveCustomPreset,
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Save current preset'),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < (_info?.bands ?? 0); i++)
                _BandSlider(
                  index: i,
                  centerHz: (_info!.centersMilliHz.length > i
                          ? _info!.centersMilliHz[i]
                          : 0) /
                      1000,
                  min: _info!.minLevel,
                  max: _info!.maxLevel,
                  value: _levels.length > i ? _levels[i] : 0,
                  enabled: _enabled,
                  onChanged: (int level) async {
                    setState(() {
                      _preset = null;
                      if (_levels.length > i) _levels[i] = level;
                    });
                    await NativeBridge.eqSetBand(i, level);
                    if (!mounted) return;
                    await settings.setEqualizerProfile(
                      name: 'Custom',
                      levels: _levels,
                      enabled: _enabled,
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BandSlider extends StatelessWidget {
  const _BandSlider({
    required this.index,
    required this.centerHz,
    required this.min,
    required this.max,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  final int index;
  final num centerHz;
  final int min;
  final int max;
  final int value;
  final bool enabled;
  final ValueChanged<int> onChanged;

  String get _label {
    if (centerHz >= 1000) return '${(centerHz / 1000).toStringAsFixed(1)} kHz';
    if (centerHz <= 0) return 'Band ${index + 1}';
    return '${centerHz.round()} Hz';
  }

  @override
  Widget build(BuildContext context) {
    final SaxifyAccent accent = context.accent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _label,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: SaxifyColors.textSecondary,
                  ),
                ),
              ),
              Text(
                '${value > 0 ? '+' : ''}${(value / 100).toStringAsFixed(1)} dB',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accent.primary,
                ),
              ),
            ],
          ),
          Slider(
            min: min.toDouble(),
            max: max.toDouble(),
            value: value.clamp(min, max).toDouble(),
            onChanged: enabled ? (double v) => onChanged(v.round()) : null,
          ),
        ],
      ),
    );
  }
}
