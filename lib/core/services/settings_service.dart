import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';


/// Everything the Settings screen owns, persisted with shared_preferences.
///
/// Keys are stable strings so the store survives renames of the Dart fields.
enum StreamResolverMode { smart, innertubeOnly, legacyOnly }

class SettingsService extends ChangeNotifier {
  SettingsService(this._prefs);

  final SharedPreferences _prefs;

  // ---------------------------------------------------------------- keys
  static const String kDisplayName = 'saxify.display_name';
  static const String kEmail = 'saxify.email';
  static const String kAccentId = 'saxify.accent_id';
  static const String kAccentAcrossApp = 'saxify.accent_across_app';
  static const String kAutoRotateTheme = 'saxify.auto_rotate_theme';
  static const String kRotateSeconds = 'saxify.rotate_seconds';
  static const String kQualityWifi = 'saxify.quality_wifi';
  static const String kQualityMobile = 'saxify.quality_mobile';
  static const String kGapless = 'saxify.gapless';
  static const String kAutoplay = 'saxify.autoplay';
  static const String kRememberPosition = 'saxify.remember_position';
  static const String kPlaybackSpeed = 'saxify.playback_speed';
  static const String kExplicitFilter = 'saxify.explicit_filter';
  static const String kLastPositions = 'saxify.last_positions';
  static const String kCustomAccentPrimary = 'saxify.custom_accent_primary';
  static const String kCustomAccentSecondary = 'saxify.custom_accent_secondary';
  static const String kSpatialPreset = 'saxify.spatial_preset';
  static const String kSpatialDepth = 'saxify.spatial_depth';
  static const String kSpatialSpeed = 'saxify.spatial_speed';
  static const String kSpatialReverb = 'saxify.spatial_reverb';
  static const String kLastPlaylistCode = 'saxify.last_playlist_code';
  static const String kAutoPlaylistSync = 'saxify.auto_playlist_sync';
  static const String kMaxDownloadHistory = 'saxify.max_download_history';
  static const String kEqualizerProfile = 'saxify.equalizer_profile.v1';
  static const String kEqualizerCustomPresets = 'saxify.equalizer_custom_presets.v1';
  static const String kStreamResolverMode = 'saxify.stream_resolver_mode.v1';
  static const String kOfflineCacheSize = 'saxify.offline_cache_size.v1';
  static const String kPersistentQueue = 'saxify.persistent_queue.v1';
  static const String kSkipSilence = 'saxify.skip_silence.v1';

  // ---------------------------------------------------------------- account
  String get displayName => _prefs.getString(kDisplayName)?.trim() ?? '';
  Future<void> setDisplayName(String v) =>
      _prefs.setString(kDisplayName, v.trim()).then((_) => notifyListeners());

  String get email => _prefs.getString(kEmail) ?? 'dastaanenajdik@gmail.com';
  Future<void> setEmail(String v) =>
      _prefs.setString(kEmail, v).then((_) => notifyListeners());

  // ---------------------------------------------------------------- theme
  String get accentId => _prefs.getString(kAccentId) ?? 'violet-pulse';
  Future<void> setAccentId(String v) =>
      _prefs.setString(kAccentId, v).then((_) => notifyListeners());

  /// When off, the app keeps its neutral black appearance while the small
  /// song-quality label still follows the selected / rotating colour.
  bool get accentAcrossApp =>
      _prefs.getBool(kAccentAcrossApp) ??
      (_prefs.getString(kAccentId) == 'custom-mix');
  Future<void> setAccentAcrossApp(bool value) => _prefs
      .setBool(kAccentAcrossApp, value)
      .then((_) => notifyListeners());

  int? get customAccentPrimary => _prefs.getInt(kCustomAccentPrimary);
  int? get customAccentSecondary => _prefs.getInt(kCustomAccentSecondary);

  Future<void> setCustomAccent({required int primary, required int secondary}) async {
    await _prefs.setInt(kCustomAccentPrimary, primary);
    await _prefs.setInt(kCustomAccentSecondary, secondary);
    notifyListeners();
  }

  bool get autoRotateTheme => _prefs.getBool(kAutoRotateTheme) ?? true;
  Future<void> setAutoRotateTheme(bool v) =>
      _prefs.setBool(kAutoRotateTheme, v).then((_) => notifyListeners());

  /// Rotation cadence in seconds. 150s == 2.5 minutes, right in the middle of
  /// the "every 2–3 minutes" the app promises.
  int get rotateSeconds => _prefs.getInt(kRotateSeconds) ?? 150;
  Future<void> setRotateSeconds(int v) =>
      _prefs.setInt(kRotateSeconds, v).then((_) => notifyListeners());

  // ---------------------------------------------------------------- audio
  String get qualityWifi => _prefs.getString(kQualityWifi) ?? 'high';
  Future<void> setQualityWifi(String v) =>
      _prefs.setString(kQualityWifi, v).then((_) => notifyListeners());

  String get qualityMobile => _prefs.getString(kQualityMobile) ?? 'medium';
  Future<void> setQualityMobile(String v) =>
      _prefs.setString(kQualityMobile, v).then((_) => notifyListeners());

  bool get gapless => _prefs.getBool(kGapless) ?? true;
  Future<void> setGapless(bool v) =>
      _prefs.setBool(kGapless, v).then((_) => notifyListeners());

  bool get autoplay => _prefs.getBool(kAutoplay) ?? true;
  Future<void> setAutoplay(bool v) =>
      _prefs.setBool(kAutoplay, v).then((_) => notifyListeners());

  bool get rememberPosition => _prefs.getBool(kRememberPosition) ?? true;
  Future<void> setRememberPosition(bool v) =>
      _prefs.setBool(kRememberPosition, v).then((_) => notifyListeners());

  double get playbackSpeed => _prefs.getDouble(kPlaybackSpeed) ?? 1.0;
  Future<void> setPlaybackSpeed(double v) =>
      _prefs.setDouble(kPlaybackSpeed, v).then((_) => notifyListeners());

  StreamResolverMode get streamResolverMode {
    final String raw = _prefs.getString(kStreamResolverMode) ?? 'smart';
    return StreamResolverMode.values.firstWhere(
      (StreamResolverMode mode) => mode.name == raw,
      orElse: () => StreamResolverMode.smart,
    );
  }

  String get streamResolverLabel => switch (streamResolverMode) {
    StreamResolverMode.smart => 'Smart',
    StreamResolverMode.innertubeOnly => 'Innertube only',
    StreamResolverMode.legacyOnly => 'Legacy only',
  };

  Future<void> setStreamResolverMode(StreamResolverMode mode) => _prefs
      .setString(kStreamResolverMode, mode.name)
      .then((_) => notifyListeners());

  int? get offlineCacheSizeBytes {
    final String raw = _prefs.getString(kOfflineCacheSize) ?? '2GB';
    return switch (raw) {
      '512MB' => 512 * 1024 * 1024,
      '1GB' => 1024 * 1024 * 1024,
      '2GB' => 2 * 1024 * 1024 * 1024,
      '4GB' => 4 * 1024 * 1024 * 1024,
      'Unlimited' => null,
      _ => 2 * 1024 * 1024 * 1024,
    };
  }

  String get offlineCacheSizeLabel => _prefs.getString(kOfflineCacheSize) ?? '2GB';
  Future<void> setOfflineCacheSizeLabel(String label) => _prefs
      .setString(kOfflineCacheSize, label)
      .then((_) => notifyListeners());

  bool get skipSilence => _prefs.getBool(kSkipSilence) ?? false;
  Future<void> setSkipSilence(bool v) =>
      _prefs.setBool(kSkipSilence, v).then((_) => notifyListeners());

  bool get explicitFilter => _prefs.getBool(kExplicitFilter) ?? false;
  Future<void> setExplicitFilter(bool v) =>
      _prefs.setBool(kExplicitFilter, v).then((_) => notifyListeners());

  // ------------------------------------------------- resume-where-you-left
  Map<String, dynamic> _positions() {
    final String? raw = _prefs.getString(kLastPositions);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  /// Where the listener stopped, or null when resuming would be pointless.
  Duration? resumePositionFor(String songId) {
    if (!rememberPosition) return null;
    final Object? ms = _positions()[songId];
    final int value = ms is int ? ms : 0;
    if (value < 5000) return null; // don't resume a barely-started track
    return Duration(milliseconds: value);
  }

  Future<void> saveResumePosition(String songId, Duration position) async {
    final Map<String, dynamic> map = _positions();
    map[songId] = position.inMilliseconds;
    final List<String> keys = map.keys.toList();
    // Keep only the 40 most recent entries so the blob stays small.
    if (keys.length > 40) {
      for (final String k in keys.sublist(0, keys.length - 40)) {
        map.remove(k);
      }
    }
    await _prefs.setString(kLastPositions, jsonEncode(map));
  }

  Future<void> forgetPositions() => _prefs.remove(kLastPositions);

  Map<String, dynamic>? get persistentQueue {
    final String? raw = _prefs.getString(kPersistentQueue);
    if (raw == null || raw.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> savePersistentQueue(Map<String, dynamic> value) async {
    await _prefs.setString(kPersistentQueue, jsonEncode(value));
  }

  Future<void> clearPersistentQueue() => _prefs.remove(kPersistentQueue);

  // ------------------------------------------------------- playlist codes
  String? get lastPlaylistCode => _prefs.getString(kLastPlaylistCode);

  Future<void> setLastPlaylistCode(String code) =>
      _prefs.setString(kLastPlaylistCode, code).then((_) => notifyListeners());

  bool get autoPlaylistSync => _prefs.getBool(kAutoPlaylistSync) ?? true;

  Future<void> setAutoPlaylistSync(bool value) =>
      _prefs.setBool(kAutoPlaylistSync, value).then((_) => notifyListeners());

  int get maxDownloadHistory => _prefs.getInt(kMaxDownloadHistory) ?? 120;

  // ---------------------------------------------------------- equalizer
  Map<String, dynamic> get equalizerProfile {
    final String? raw = _prefs.getString(kEqualizerProfile);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      final Object? decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> setEqualizerProfile({
    required String name,
    required List<int> levels,
    required bool enabled,
  }) async {
    await _prefs.setString(kEqualizerProfile, jsonEncode(<String, Object>{
      'name': name,
      'levels': levels,
      'enabled': enabled,
    }));
    notifyListeners();
  }

  List<Map<String, dynamic>> get equalizerCustomPresets {
    final String? raw = _prefs.getString(kEqualizerCustomPresets);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded.whereType<Map>().map((Map item) => item.cast<String, dynamic>()).toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> saveEqualizerCustomPreset(String name, List<int> levels) async {
    final List<Map<String, dynamic>> presets = equalizerCustomPresets;
    presets.removeWhere((Map<String, dynamic> p) =>
        (p['name']?.toString().toLowerCase() ?? '') == name.trim().toLowerCase());
    presets.add(<String, dynamic>{'name': name.trim(), 'levels': levels});
    await _prefs.setString(kEqualizerCustomPresets, jsonEncode(presets));
    notifyListeners();
  }

  Future<void> deleteEqualizerCustomPreset(String name) async {
    final List<Map<String, dynamic>> presets = equalizerCustomPresets;
    presets.removeWhere((Map<String, dynamic> p) => p['name'] == name);
    await _prefs.setString(kEqualizerCustomPresets, jsonEncode(presets));
    notifyListeners();
  }

  bool get equalizerEnabled => equalizerProfile['enabled'] == true;
  String get equalizerProfileName => equalizerProfile['name']?.toString() ?? 'Original audio';
  List<int> get equalizerLevels {
    final Object? raw = equalizerProfile['levels'];
    return raw is List ? raw.map((Object? value) => value is num ? value.round() : 0).toList() : <int>[];
  }

  // ----------------------------------------------------- spatial audio (8D)
  String get spatialPresetId => _prefs.getString(kSpatialPreset) ?? 'off';

  Future<void> setSpatialPresetId(String id) =>
      _prefs.setString(kSpatialPreset, id).then((_) => notifyListeners());

  double get spatialDepth => _prefs.getDouble(kSpatialDepth) ?? 0.85;
  Future<void> setSpatialDepth(double v) =>
      _prefs.setDouble(kSpatialDepth, v).then((_) => notifyListeners());

  double get spatialRotationHz => _prefs.getDouble(kSpatialSpeed) ?? 0.18;
  Future<void> setSpatialRotationHz(double v) =>
      _prefs.setDouble(kSpatialSpeed, v).then((_) => notifyListeners());

  double get spatialReverb => _prefs.getDouble(kSpatialReverb) ?? 0.35;
  Future<void> setSpatialReverb(double v) =>
      _prefs.setDouble(kSpatialReverb, v).then((_) => notifyListeners());

  Future<void> resetAll() async {
    await _prefs.clear();
    notifyListeners();
  }
}
