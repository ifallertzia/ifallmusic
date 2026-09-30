import 'dart:async';

import 'package:flutter/material.dart';

import '../services/settings_service.dart';
import 'saxify_accents.dart';

/// Owns "which colour is IfallMusic wearing right now".
///
/// Three modes, matching the Appearance panel in Settings:
///  * **auto** — cycles through the palette so the app keeps changing its look
///    on its own (default every 2.5 minutes).
///  * **pinned** — the listener tapped a swatch, so the colour stays put.
///  * **custom** — the listener built their own RGB mix with the colour editor.
class ThemeController extends ChangeNotifier {
  ThemeController(this._settings) {
    _index = SaxifyAccents.indexOfId(_settings.accentId);
    _custom = _readCustom();
    if (_settings.autoRotateTheme) _startTimer();
  }

  final SettingsService _settings;

  int _index = 0;
  Timer? _timer;
  SaxifyAccent? _custom;
  DateTime _lastSwitch = DateTime.now();

  SaxifyAccent? _readCustom() {
    final int? primary = _settings.customAccentPrimary;
    final int? secondary = _settings.customAccentSecondary;
    if (primary == null || secondary == null) return null;
    return SaxifyAccent.custom(Color(primary), Color(secondary));
  }

  bool get usingCustom => _settings.accentId == SaxifyAccent.customAccentId;

  /// Current custom or palette colour. It keeps rotating independently from
  /// the rest of the UI when the listener prefers the neutral black look.
  SaxifyAccent get paletteAccent =>
      usingCustom && _custom != null ? _custom! : SaxifyAccents.all[_index];

  /// Accent used by the shared UI theme. The default is the restrained
  /// graphite look; the user can opt into colour across the whole app.
  SaxifyAccent get accent => _settings.accentAcrossApp
      ? paletteAccent
      : SaxifyAccents.graphite;

  bool get accentAcrossApp => _settings.accentAcrossApp;

  Future<void> setAccentAcrossApp(bool value) async {
    await _settings.setAccentAcrossApp(value);
    notifyListeners();
  }

  /// The palette entry the swatch grid should mark as selected (null when the
  /// listener is on their own mix).
  String? get selectedId => usingCustom ? null : paletteAccent.id;

  int get index => _index;
  bool get autoRotate => _settings.autoRotateTheme;
  Duration get rotateInterval => Duration(seconds: _settings.rotateSeconds);

  /// Seconds until the next automatic switch (used by the Settings countdown).
  int secondsUntilNextSwitch() {
    if (!autoRotate) return 0;
    final Duration elapsed = DateTime.now().difference(_lastSwitch);
    final int remaining = rotateInterval.inSeconds - elapsed.inSeconds;
    return remaining < 0 ? 0 : remaining;
  }

  /// Swatches only show palette colours.
  Future<void> pin(String accentId) async {
    await _stopTimer();
    _index = SaxifyAccents.indexOfId(accentId);
    await _settings.setAccentId(accentId);
    await _settings.setAutoRotateTheme(false);
    notifyListeners();
  }

  /// The listener's own colour mix (RGB editor in Settings).
  Future<void> defineCustom(Color primary, Color secondary) async {
    _custom = SaxifyAccent.custom(primary, secondary);
    await _settings.setCustomAccent(
      primary: _argb(primary),
      secondary: _argb(secondary),
    );
    await _stopTimer();
    await _settings.setAccentId(SaxifyAccent.customAccentId);
    await _settings.setAutoRotateTheme(false);
    await _settings.setAccentAcrossApp(true);
    notifyListeners();
  }

  /// ARGB int without relying on version-specific Color helpers.
  static int _argb(Color color) =>
      (0xFF << 24) |
      ((color.r * 255).round() << 16) |
      ((color.g * 255).round() << 8) |
      (color.b * 255).round();

  Future<void> setAutoRotate(bool value) async {
    await _settings.setAutoRotateTheme(value);
    if (value) {
      if (usingCustom) {
        // An explicit opt-in to rotation returns to the last palette colour;
        // the saved RGB mix remains stored and is not overwritten.
        _index = SaxifyAccents.all.length - 1;
      }
      await _settings.setAccentId(SaxifyAccents.all[_index].id);
      _startTimer();
    } else {
      await _stopTimer();
    }
    notifyListeners();
  }

  Future<void> setRotateInterval(Duration interval) async {
    await _settings.setRotateSeconds(interval.inSeconds);
    if (autoRotate) _startTimer();
    notifyListeners();
  }

  /// Jump to the next colour (also what the auto timer calls).
  Future<void> cycle({bool persist = true}) async {
    if (usingCustom) {
      // Leaving the custom mix for the rotation.
      _index = 0;
      if (persist) await _settings.setAccentId(SaxifyAccents.all.first.id);
      _lastSwitch = DateTime.now();
      notifyListeners();
      return;
    }
    _index = (_index + 1) % SaxifyAccents.all.length;
    _lastSwitch = DateTime.now();
    if (persist) await _settings.setAccentId(paletteAccent.id);
    notifyListeners();
  }

  void _startTimer() {
    _timer?.cancel();
    _lastSwitch = DateTime.now();
    _timer = Timer.periodic(rotateInterval, (_) => cycle());
  }

  Future<void> _stopTimer() async {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
