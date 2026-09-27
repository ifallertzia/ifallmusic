import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'native_bridge.dart';
import 'settings_service.dart';

/// ---------------------------------------------------------------------------
/// IfallMusic real-time spatial (8D) audio processor — Flutter control layer.
///
/// ## What "8D audio" actually is
/// 1. **Orbit / auto-pan** — a low-frequency oscillator (0.05–0.5 Hz) drives the
///    stereo field left ↔ right. Slow = the sound walks around your head.
/// 2. **Depth** — the side channels are widened while the centre is pulled back,
///    which is what makes it feel like the music is *around* you instead of in
///    your ears.
/// 3. **Reverb** — a short synthetic tail (early reflections + comb/feedback
///    delay) places the source in a room so the panning is audible.
///
/// ## How the layers fit together
/// ```
///   UI (Equalizer ▸ 8D templates)   ← sliders, presets, live LFO visual
///            │
///   SpatialAudioService (this file) ← presets, persistence, LFO maths
///            │
///   NativeBridge  →  SaxifyBridge.kt `spatial*` methods
///            │
///   Android: Virtualizer + EnvironmentalReverb on the live audio session
///            + SpatialAudioProcessor.kt (sample-accurate LFO panner/reverb,
///              the engine used when the player is driven by Oboe/Media3)
/// ```
///
/// The Dart side owns the *musical* parameters; the native side owns the
/// sample loop. Both stay in sync through [NativeBridge.spatialApply].
/// ---------------------------------------------------------------------------

/// One ready-made 8D template shown in the equalizer page.
@immutable
class SpatialPreset {
  const SpatialPreset({
    required this.id,
    required this.label,
    required this.description,
    required this.rotationHz,
    required this.depth,
    required this.reverb,
    required this.width,
  });

  final String id;
  final String label;
  final String description;

  /// Orbit speed. 0.08 Hz ≈ one full circle every 12 s.
  final double rotationHz;

  /// 0 = mono-ish centre, 1 = full left/right orbit.
  final double depth;

  /// 0 = dry, 1 = big hall.
  final double reverb;

  /// Stereo widening of the non-oscillating part of the signal.
  final double width;

  bool get isOff => id == SpatialPresets.offId;
}

/// The templates. Ordered from "just a hint of space" to "full orbit".
class SpatialPresets {
  const SpatialPresets._();

  static const String offId = 'off';

  static const SpatialPreset off = SpatialPreset(
    id: offId,
    label: 'Off',
    description: 'Normal stereo — no spatial processing',
    rotationHz: 0,
    depth: 0,
    reverb: 0,
    width: 0,
  );

  static const SpatialPreset orbit = SpatialPreset(
    id: '8d-orbit',
    label: '8D Orbit',
    description: 'Sound slowly circles your head — the classic 8D',
    rotationHz: 0.12,
    depth: 0.9,
    reverb: 0.30,
    width: 0.35,
  );

  static const SpatialPreset swift = SpatialPreset(
    id: '8d-swift',
    label: '8D Swift',
    description: 'A faster orbit for club and EDM tracks',
    rotationHz: 0.26,
    depth: 0.8,
    reverb: 0.18,
    width: 0.30,
  );

  static const SpatialPreset cinematic = SpatialPreset(
    id: '8d-cinematic',
    label: '8D Cinematic',
    description: 'Wide, deep and reverberant — like a film score',
    rotationHz: 0.07,
    depth: 0.75,
    reverb: 0.70,
    width: 0.55,
  );

  static const SpatialPreset dreamy = SpatialPreset(
    id: '8d-dreamy',
    label: '8D Dreamy',
    description: 'Slow drift with a long, soft tail — lofi and ambient',
    rotationHz: 0.05,
    depth: 0.6,
    reverb: 0.85,
    width: 0.45,
  );

  static const SpatialPreset focus = SpatialPreset(
    id: '8d-focus',
    label: '8D Focus',
    description: 'Barely moving but very wide — great for study sessions',
    rotationHz: 0.03,
    depth: 0.45,
    reverb: 0.25,
    width: 0.75,
  );

  static const SpatialPreset club = SpatialPreset(
    id: '8d-club',
    label: '8D Club',
    description: 'Fast orbit plus a tight room — party mode',
    rotationHz: 0.34,
    depth: 1.0,
    reverb: 0.22,
    width: 0.25,
  );

  static const List<SpatialPreset> all = <SpatialPreset>[
    off,
    orbit,
    swift,
    cinematic,
    dreamy,
    focus,
    club,
  ];

  static SpatialPreset byId(String? id) {
    for (final SpatialPreset preset in all) {
      if (preset.id == id) return preset;
    }
    return off;
  }
}

/// Live 8D state for the whole app.
class SpatialAudioService extends ChangeNotifier {
  SpatialAudioService(this._settings) {
    _preset = SpatialPresets.byId(_settings.spatialPresetId);
    _depth = _settings.spatialDepth.clamp(0.0, 1.0);
    _rotationHz = _settings.spatialRotationHz.clamp(0.0, 0.6);
    _reverb = _settings.spatialReverb.clamp(0.0, 1.0);
    if (_preset.isOff) _enabled = false;
    _push();
  }

  final SettingsService _settings;

  late SpatialPreset _preset;
  late double _depth;
  late double _rotationHz;
  late double _reverb;
  bool _enabled = false;
  Timer? _visualTicker;
  double _phase = 0;

  SpatialPreset get preset => _preset;
  bool get enabled => _enabled && !_preset.isOff;
  double get depth => _depth;
  double get rotationHz => _rotationHz;
  double get reverb => _reverb;
  double get width => _preset.width;

  /// True while the sliders were moved away from the template values.
  bool get customised =>
      (_depth - _preset.depth).abs() > 0.01 ||
      (_rotationHz - _preset.rotationHz).abs() > 0.01 ||
      (_reverb - _preset.reverb).abs() > 0.01;

  // ---------------------------------------------------------------- LFO maths
  /// One full orbit takes `1 / rotationHz` seconds.
  Duration get orbitPeriod => Duration(
        milliseconds: rotationHz <= 0 ? 0 : (1000 / rotationHz).round(),
      );

  /// Current pan position, -1 (hard left) … +1 (hard right).
  double get pan => enabled ? math.sin(_phase) * _depth : 0;

  /// Current left/right gains — used by the UI meter and by the native engine
  /// (equal-power law so the perceived loudness stays constant while orbiting).
  (double left, double right) get gains {
    final double p = pan.clamp(-1.0, 1.0);
    final double angle = (p + 1) * (math.pi / 4); // 0 … π/2
    return (math.cos(angle), math.sin(angle));
  }

  /// Emits ~30×/s while the engine runs so the UI can draw the orbit.
  Stream<double> orbitStream() async* {
    if (!enabled) {
      yield 0;
      return;
    }
    final int stepMs =
        (1000 * (1 / (rotationHz <= 0 ? 0.1 : rotationHz)) / 48).round().clamp(16, 120);
    while (enabled) {
      await Future<void>.delayed(Duration(milliseconds: stepMs));
      yield pan;
    }
  }

  // ------------------------------------------------------------------ control
  Future<void> applyPreset(SpatialPreset preset) async {
    _preset = preset;
    _depth = preset.depth;
    _rotationHz = preset.rotationHz;
    _reverb = preset.reverb;
    _enabled = !preset.isOff;
    _phase = 0;
    await _settings.setSpatialPresetId(preset.id);
    await _settings.setSpatialDepth(_depth);
    await _settings.setSpatialRotationHz(_rotationHz);
    await _settings.setSpatialReverb(_reverb);
    _restartTicker();
    notifyListeners();
    await _push();
  }

  Future<void> setEnabled(bool value) async {
    _enabled = value;
    _restartTicker();
    notifyListeners();
    await _push();
  }

  Future<void> setDepth(double value) async {
    _depth = value.clamp(0.0, 1.0);
    await _settings.setSpatialDepth(_depth);
    notifyListeners();
    await _push();
  }

  Future<void> setRotationHz(double value) async {
    _rotationHz = value.clamp(0.0, 0.6);
    await _settings.setSpatialRotationHz(_rotationHz);
    _restartTicker();
    notifyListeners();
    await _push();
  }

  Future<void> setReverb(double value) async {
    _reverb = value.clamp(0.0, 1.0);
    await _settings.setSpatialReverb(_reverb);
    notifyListeners();
    await _push();
  }

  void _restartTicker() {
    _visualTicker?.cancel();
    if (!enabled) return;
    final int tickMs = orbitPeriod.inMilliseconds == 0
        ? 60
        : (orbitPeriod.inMilliseconds / 48).round().clamp(16, 120);
    final double delta = (2 * math.pi) * (tickMs / 1000) * _rotationHz;
    _visualTicker = Timer.periodic(Duration(milliseconds: tickMs), (_) {
      _phase = (_phase + delta) % (2 * math.pi);
      notifyListeners();
    });
  }

  Future<void> _push() async {
    try {
      if (!enabled) {
        await NativeBridge.spatialDisable();
        return;
      }
      await NativeBridge.spatialApply(
        rotationHz: _rotationHz,
        depth: _depth,
        reverb: _reverb,
        width: _preset.width,
      );
    } catch (e) {
      debugPrint('[IfallMusic][Spatial] native apply skipped: $e');
    }
  }

  @override
  void dispose() {
    _visualTicker?.cancel();
    super.dispose();
  }
}
