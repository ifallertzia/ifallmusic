import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/saxify_accents.dart';


/// Everything the Settings screen owns, persisted with shared_preferences.
///
/// Keys are stable strings so the store survives renames of the Dart fields.
enum StreamResolverMode { smart, innertubeOnly, legacyOnly }

/// The lyrics providers IfallMusic knows how to ask, in the order they are
/// tried. The list is user-editable from Settings → Lyrics.
class LyricsProviders {
  const LyricsProviders._();

  static const String lrclib = 'LRCLIB';
  static const String lrcRed = 'lrc.red';
  static const String musixmatch = 'Musixmatch';
  static const String genius = 'Genius';
  static const String kugou = 'KuGou';
  static const String megalobiz = 'Megalobiz';
  static const String embedded = 'Embedded';

  /// The plain-text provider that has always been the last rung. It is not a
  /// user choice — it is what runs when everything above it came back empty.
  static const String plainFallback = 'lyrics.ovh';

  static const List<String> all = <String>[
    lrclib,
    lrcRed,
    musixmatch,
    genius,
    kugou,
    megalobiz,
    embedded,
  ];

  static const List<String> defaultOrder = <String>[
    lrclib,
    lrcRed,
    musixmatch,
    genius,
  ];

  static String note(String provider) => switch (provider) {
    lrclib => 'Open, community-contributed synced lyrics.',
    lrcRed => 'Aggregated word-level timing (lrc.red).',
    musixmatch => 'Large catalogue, mostly line-synced.',
    genius => 'Plain lyrics plus annotations — no timing.',
    kugou => 'Strong for Chinese and Japanese releases.',
    megalobiz => 'Hand-timed community lines.',
    embedded => 'Lyrics carried inside the downloaded file.',
    _ => '',
  };
}

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
  /// One-shot migration flag: moves an existing install onto the Spotify Green
  /// default look (accent painted across the whole app).
  static const String kGreenDefaultApplied = 'saxify.green_default.v1';

  // ------------------------------------------------- BitChord-parity knobs
  static const String kThemeMode = 'ifall.theme_mode.v1';
  static const String kLiquidGlass = 'ifall.liquid_glass.v1';
  static const String kCrossfade = 'ifall.crossfade_seconds.v1';
  static const String kAutomix = 'ifall.automix.v1';
  static const String kNormalizeVolume = 'ifall.normalize_volume.v1';
  static const String kSilenceSkipping = 'ifall.silence_skipping.v1';
  static const String kSleepEndOfTrack = 'ifall.sleep_end_of_track.v1';
  static const String kSleepMinutes = 'ifall.sleep_minutes.v1';
  static const String kJamServer = 'ifall.jam_server.v1';
  static const String kJamDisplayName = 'ifall.jam_display_name.v1';
  static const String kJamLastCode = 'ifall.jam_last_code.v1';
  static const String kDiscordEnabled = 'ifall.discord_enabled.v1';
  static const String kDiscordDetails = 'ifall.discord_details.v1';
  static const String kDiscordRelay = 'ifall.discord_relay.v1';
  static const String kLastFmSession = 'ifall.lastfm_session.v1';
  static const String kLastFmUser = 'ifall.lastfm_user.v1';
  static const String kLastFmEnabled = 'ifall.lastfm_enabled.v1';
  static const String kListenBrainzToken = 'ifall.listenbrainz_token.v1';
  static const String kListenBrainzEnabled = 'ifall.listenbrainz_enabled.v1';
  static const String kScrobblePercent = 'ifall.scrobble_percent.v1';
  static const String kExtraSources = 'ifall.extra_sources.v1';
  static const String kLyricsProviders = 'ifall.lyrics_providers.v1';
  static const String kLyricsRomanize = 'ifall.lyrics_romanize.v1';
  static const String kLyricsTranslate = 'ifall.lyrics_translate.v1';
  static const String kStatsOptIn = 'ifall.stats_opt_in.v1';
  static const String kLanguage = 'ifall.language.v1';
  static const String kHighPerformance = 'ifall.high_performance.v1';
  static const String kKeepScreenAwake = 'ifall.keep_screen_awake.v1';
  static const String kAutoDownloadLikes = 'ifall.auto_download_likes.v1';

  // ------------------------------------------------------ Sidify shell (UI)
  // Preferences the Sidify interface owns: artwork-tinted surfaces, reduced
  // motion, how the Library lays its playlists out, and which playlists are
  // pinned to the top. Additive only — no existing key changes meaning.
  static const String kDynamicColor = 'sidify.dynamic_color.v1';
  static const String kReduceMotion = 'sidify.reduce_motion.v1';
  static const String kLibraryLayout = 'sidify.library_layout.v1';
  static const String kPinnedPlaylists = 'sidify.pinned_playlists.v1';

  // ---------------------------------------------------------------- account
  String get displayName => _prefs.getString(kDisplayName)?.trim() ?? '';
  Future<void> setDisplayName(String v) =>
      _prefs.setString(kDisplayName, v.trim()).then((_) => notifyListeners());

  String get email => _prefs.getString(kEmail) ?? 'dastaanenajdik@gmail.com';
  Future<void> setEmail(String v) =>
      _prefs.setString(kEmail, v).then((_) => notifyListeners());

  // ---------------------------------------------------------------- theme
  /// Spotify Green is the house look now — a fresh install (and any install
  /// migrating onto this build) wears it everywhere.
  static const String defaultAccentId = 'neon-green';

  String get accentId => _prefs.getString(kAccentId) ?? defaultAccentId;
  Future<void> setAccentId(String v) =>
      _prefs.setString(kAccentId, v).then((_) => notifyListeners());

  /// When off, the app keeps its neutral black appearance while the small
  /// song-quality label still follows the selected / rotating colour. It is on
  /// by default now, so the accent really is painted across the whole app.
  bool get accentAcrossApp =>
      _prefs.getBool(kAccentAcrossApp) ??
      (_prefs.getString(kAccentId) == SaxifyAccent.customAccentId ||
          _prefs.getString(kAccentId) == null ||
          _prefs.getString(kAccentId) == defaultAccentId);
  Future<void> setAccentAcrossApp(bool value) => _prefs
      .setBool(kAccentAcrossApp, value)
      .then((_) => notifyListeners());

  /// Runs once per install: anyone arriving from an older build lands on the
  /// Spotify Green default instead of keeping a stale palette pick.
  Future<void> applyGreenDefault() async {
    if (_prefs.getBool(kGreenDefaultApplied) ?? false) return;
    await _prefs.setBool(kGreenDefaultApplied, true);
    await _prefs.setString(kAccentId, defaultAccentId);
    await _prefs.setBool(kAccentAcrossApp, true);
    await _prefs.setBool(kAutoRotateTheme, false);
    notifyListeners();
  }

  int? get customAccentPrimary => _prefs.getInt(kCustomAccentPrimary);
  int? get customAccentSecondary => _prefs.getInt(kCustomAccentSecondary);

  Future<void> setCustomAccent({required int primary, required int secondary}) async {
    await _prefs.setInt(kCustomAccentPrimary, primary);
    await _prefs.setInt(kCustomAccentSecondary, secondary);
    notifyListeners();
  }

  /// Rotation is opt-in now: the app stays on the Spotify Green default until
  /// the listener asks for the palette to cycle on its own.
  bool get autoRotateTheme => _prefs.getBool(kAutoRotateTheme) ?? false;
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

  /// The bitrate ceiling (kbps) the per-network quality settings imply for
  /// [networkType] ('wifi' / 'mobile' / anything else, from
  /// `NativeBridge.networkType`). `null` means "no ceiling" — 'high', and
  /// the default for unknown transports, because a failed network probe must
  /// never silently downgrade anyone's audio. Downloads ignore this: a file
  /// outlives the connection it was fetched on.
  int? qualityCapKbps(String networkType) {
    final String quality =
        networkType == 'mobile' ? qualityMobile : qualityWifi;
    return switch (quality) {
      'low' => 96,
      'medium' => 160,
      _ => null,
    };
  }

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

  // --------------------------------------------------- appearance / display
  /// `system` follows the phone, `light` and `dark` pin it.
  String get themeModeRaw => _prefs.getString(kThemeMode) ?? 'dark';
  ThemeMode get themeMode => switch (themeModeRaw) {
    'system' => ThemeMode.system,
    'light' => ThemeMode.light,
    _ => ThemeMode.dark,
  };
  Future<void> setThemeMode(ThemeMode mode) => _prefs
      .setString(kThemeMode, mode.name)
      .then((_) => notifyListeners());

  // ---------------------------------------------------------- Sidify shell
  /// Colour sampled from the playing artwork tints the player backdrop, the
  /// page ambience and collection headers.
  bool get dynamicColor => _prefs.getBool(kDynamicColor) ?? true;
  Future<void> setDynamicColor(bool v) =>
      _prefs.setBool(kDynamicColor, v).then((_) => notifyListeners());

  /// Calms the interface down: no artwork breathing, no drifting colours.
  bool get reduceMotion => _prefs.getBool(kReduceMotion) ?? false;
  Future<void> setReduceMotion(bool v) =>
      _prefs.setBool(kReduceMotion, v).then((_) => notifyListeners());

  /// How the Library shows playlists: `grid` or `list`.
  String get libraryLayout => _prefs.getString(kLibraryLayout) ?? 'grid';
  Future<void> setLibraryLayout(String v) =>
      _prefs.setString(kLibraryLayout, v).then((_) => notifyListeners());

  /// Playlists pinned to the top of the Library, most recent pin first.
  List<String> get pinnedPlaylists =>
      _prefs.getStringList(kPinnedPlaylists) ?? const <String>[];
  Future<void> setPinnedPlaylists(List<String> v) => _prefs
      .setStringList(kPinnedPlaylists, v)
      .then((_) => notifyListeners());

  /// The frosted-glass treatment. It is cheap on modern phones but a costly
  /// backdrop filter on old ones, so it can be switched off from Settings.
  bool get liquidGlass => _prefs.getBool(kLiquidGlass) ?? true;
  Future<void> setLiquidGlass(bool v) =>
      _prefs.setBool(kLiquidGlass, v).then((_) => notifyListeners());

  /// Drop frame-heavy effects (large blurs, backdrop shaders) on weak devices.
  bool get highPerformance => _prefs.getBool(kHighPerformance) ?? false;
  Future<void> setHighPerformance(bool v) =>
      _prefs.setBool(kHighPerformance, v).then((_) => notifyListeners());

  bool get keepScreenAwake => _prefs.getBool(kKeepScreenAwake) ?? false;
  Future<void> setKeepScreenAwake(bool v) =>
      _prefs.setBool(kKeepScreenAwake, v).then((_) => notifyListeners());

  /// BCP-47-ish tag chosen in Settings → Language. `system` follows the phone.
  String get language => _prefs.getString(kLanguage) ?? 'system';
  Future<void> setLanguage(String v) =>
      _prefs.setString(kLanguage, v).then((_) => notifyListeners());

  // ---------------------------------------------------------- transitions
  /// True crossfade length in seconds, 0–12. Zero means "no crossfade", which
  /// is the gapless behaviour IfallMusic has always shipped.
  int get crossfadeSeconds => _prefs.getInt(kCrossfade) ?? 0;
  Future<void> setCrossfadeSeconds(int v) => _prefs
      .setInt(kCrossfade, v.clamp(0, 12))
      .then((_) => notifyListeners());

  /// DJ-style transitions: beat-matched tempo stretch between two tracks.
  bool get automix => _prefs.getBool(kAutomix) ?? false;
  Future<void> setAutomix(bool v) =>
      _prefs.setBool(kAutomix, v).then((_) => notifyListeners());

  /// Loudness normalisation (ReplayGain-style trim on the stream).
  bool get normalizeVolume => _prefs.getBool(kNormalizeVolume) ?? true;
  Future<void> setNormalizeVolume(bool v) =>
      _prefs.setBool(kNormalizeVolume, v).then((_) => notifyListeners());

  /// Skip the quiet lead-in/lead-out of a track (separate from crossfade).
  bool get silenceSkipping => _prefs.getBool(kSilenceSkipping) ?? false;
  Future<void> setSilenceSkipping(bool v) =>
      _prefs.setBool(kSilenceSkipping, v).then((_) => notifyListeners());

  // ------------------------------------------------------------ sleep timer
  /// Minutes for the last-used fixed sleep timer preset.
  int get sleepMinutes => _prefs.getInt(kSleepMinutes) ?? 30;
  Future<void> setSleepMinutes(int v) => _prefs
      .setInt(kSleepMinutes, v.clamp(1, 720))
      .then((_) => notifyListeners());

  /// "Stop after this track" instead of a countdown.
  bool get sleepEndOfTrack => _prefs.getBool(kSleepEndOfTrack) ?? false;
  Future<void> setSleepEndOfTrack(bool v) =>
      _prefs.setBool(kSleepEndOfTrack, v).then((_) => notifyListeners());

  // ------------------------------------------------------- listen together
  /// Base address of the party server. Empty means "ask for one on first use".
  String get jamServer => _prefs.getString(kJamServer) ?? '';
  Future<void> setJamServer(String v) =>
      _prefs.setString(kJamServer, v.trim()).then((_) => notifyListeners());

  /// Name shown to the other people in the room. Defaults to the profile name.
  String get jamDisplayName => _prefs.getString(kJamDisplayName) ?? '';
  Future<void> setJamDisplayName(String v) => _prefs
      .setString(kJamDisplayName, v.trim())
      .then((_) => notifyListeners());

  String? get jamLastCode => _prefs.getString(kJamLastCode);
  Future<void> setJamLastCode(String? v) async {
    if (v == null) {
      await _prefs.remove(kJamLastCode);
    } else {
      await _prefs.setString(kJamLastCode, v);
    }
    notifyListeners();
  }

  // ------------------------------------------------------ presence & social
  bool get discordEnabled => _prefs.getBool(kDiscordEnabled) ?? false;
  Future<void> setDiscordEnabled(bool v) =>
      _prefs.setBool(kDiscordEnabled, v).then((_) => notifyListeners());

  /// Optional second line under the track in Discord.
  String get discordDetails => _prefs.getString(kDiscordDetails) ?? '';
  Future<void> setDiscordDetails(String v) =>
      _prefs.setString(kDiscordDetails, v.trim()).then((_) => notifyListeners());

  /// Where Rich Presence is POSTed. Discord's own transport is a local IPC
  /// socket that a phone cannot open, so presence goes through a relay the
  /// listener runs. Empty means presence is off.
  String get discordRelay => _prefs.getString(kDiscordRelay) ?? '';
  Future<void> setDiscordRelay(String v) =>
      _prefs.setString(kDiscordRelay, v.trim()).then((_) => notifyListeners());

  bool get lastFmEnabled => _prefs.getBool(kLastFmEnabled) ?? false;
  Future<void> setLastFmEnabled(bool v) =>
      _prefs.setBool(kLastFmEnabled, v).then((_) => notifyListeners());

  String get lastFmUser => _prefs.getString(kLastFmUser) ?? '';
  Future<void> setLastFmUser(String v) =>
      _prefs.setString(kLastFmUser, v.trim()).then((_) => notifyListeners());

  /// Last.fm session key, returned after the listener approves the token.
  String get lastFmSession => _prefs.getString(kLastFmSession) ?? '';
  Future<void> setLastFmSession(String v) =>
      _prefs.setString(kLastFmSession, v.trim()).then((_) => notifyListeners());

  bool get listenBrainzEnabled =>
      _prefs.getBool(kListenBrainzEnabled) ?? false;
  Future<void> setListenBrainzEnabled(bool v) => _prefs
      .setBool(kListenBrainzEnabled, v)
      .then((_) => notifyListeners());

  String get listenBrainzToken => _prefs.getString(kListenBrainzToken) ?? '';
  Future<void> setListenBrainzToken(String v) => _prefs
      .setString(kListenBrainzToken, v.trim())
      .then((_) => notifyListeners());

  /// How far into a track a scrobble fires (Last.fm's own rule is 50 %).
  int get scrobblePercent => _prefs.getInt(kScrobblePercent) ?? 50;
  Future<void> setScrobblePercent(int v) => _prefs
      .setInt(kScrobblePercent, v.clamp(10, 95))
      .then((_) => notifyListeners());

  // ------------------------------------------------------------- fallback
  /// Extra module/stream sources the resolver may fall back to, persisted as a
  /// JSON list of `{name, kind, url, enabled}`.
  List<Map<String, dynamic>> get extraSources {
    final String? raw = _prefs.getString(kExtraSources);
    if (raw == null || raw.isEmpty) return <Map<String, dynamic>>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return <Map<String, dynamic>>[];
      return decoded
          .whereType<Map>()
          .map((Map item) => item.cast<String, dynamic>())
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> setExtraSources(List<Map<String, dynamic>> value) => _prefs
      .setString(kExtraSources, jsonEncode(value))
      .then((_) => notifyListeners());

  /// Which lyrics providers the finder is allowed to ask, in order.
  List<String> get lyricsProviders {
    final String? raw = _prefs.getString(kLyricsProviders);
    if (raw == null || raw.isEmpty) return LyricsProviders.defaultOrder;
    return raw
        .split(',')
        .map((String s) => s.trim())
        .where((String s) => s.isNotEmpty)
        .toList();
  }

  Future<void> setLyricsProviders(List<String> value) => _prefs
      .setString(kLyricsProviders, value.join(','))
      .then((_) => notifyListeners());

  /// Transliterates non-latin lyrics into latin script when a provider has it.
  bool get lyricsRomanize => _prefs.getBool(kLyricsRomanize) ?? false;
  Future<void> setLyricsRomanize(bool v) =>
      _prefs.setBool(kLyricsRomanize, v).then((_) => notifyListeners());

  /// Target language for translated lyrics; empty disables translation.
  String get lyricsTranslateTo => _prefs.getString(kLyricsTranslate) ?? '';
  Future<void> setLyricsTranslateTo(String v) => _prefs
      .setString(kLyricsTranslate, v.trim())
      .then((_) => notifyListeners());

  // ------------------------------------------------------------- telemetry
  /// Keeps the on-device listening history that powers Replay and the
  /// recommendation engine. Off means history is still shown in the app but
  /// nothing is written to the stats store.
  bool get statsOptIn => _prefs.getBool(kStatsOptIn) ?? true;
  Future<void> setStatsOptIn(bool v) =>
      _prefs.setBool(kStatsOptIn, v).then((_) => notifyListeners());

  bool get autoDownloadLikes => _prefs.getBool(kAutoDownloadLikes) ?? false;
  Future<void> setAutoDownloadLikes(bool v) =>
      _prefs.setBool(kAutoDownloadLikes, v).then((_) => notifyListeners());

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

  /// Every key this service owns.
  ///
  /// A settings reset used to call `prefs.clear()`. That file is shared with
  /// the library, the playlists, the history and the downloads — all stored
  /// under the same `saxify.` prefix — so one "reset" tap wiped an entire
  /// collection. Only the keys listed here are ever removed.
  static const List<String> ownedKeys = <String>[
    'saxify.accent_across_app',
    'saxify.accent_id',
    'saxify.auto_playlist_sync',
    'saxify.auto_rotate_theme',
    'saxify.autoplay',
    'saxify.custom_accent_primary',
    'saxify.custom_accent_secondary',
    'saxify.display_name',
    'saxify.email',
    'saxify.equalizer_custom_presets.v1',
    'saxify.equalizer_profile.v1',
    'saxify.explicit_filter',
    'saxify.gapless',
    'saxify.green_default.v1',
    'saxify.last_playlist_code',
    'saxify.last_positions',
    'saxify.max_download_history',
    'saxify.offline_cache_size.v1',
    'saxify.persistent_queue.v1',
    'saxify.playback_speed',
    'saxify.quality_mobile',
    'saxify.quality_wifi',
    'saxify.remember_position',
    'saxify.rotate_seconds',
    'saxify.skip_silence.v1',
    'saxify.spatial_depth',
    'saxify.spatial_preset',
    'saxify.spatial_reverb',
    'saxify.spatial_speed',
    'saxify.stream_resolver_mode.v1',
    // ------------------------------------------------------ Sidify shell UI
    'sidify.dynamic_color.v1',
    'sidify.library_layout.v1',
    'sidify.pinned_playlists.v1',
    'sidify.reduce_motion.v1',
    // --------------------------------------------- BitChord-parity settings
    'ifall.automix.v1',
    'ifall.auto_download_likes.v1',
    'ifall.crossfade_seconds.v1',
    'ifall.discord_details.v1',
    'ifall.discord_enabled.v1',
    'ifall.discord_relay.v1',
    'ifall.extra_sources.v1',
    'ifall.high_performance.v1',
    'ifall.jam_display_name.v1',
    'ifall.jam_last_code.v1',
    'ifall.jam_server.v1',
    'ifall.keep_screen_awake.v1',
    'ifall.language.v1',
    'ifall.lastfm_enabled.v1',
    'ifall.lastfm_session.v1',
    'ifall.lastfm_user.v1',
    'ifall.listenbrainz_enabled.v1',
    'ifall.listenbrainz_token.v1',
    'ifall.liquid_glass.v1',
    'ifall.lyrics_providers.v1',
    'ifall.lyrics_romanize.v1',
    'ifall.lyrics_translate.v1',
    'ifall.normalize_volume.v1',
    'ifall.scrobble_percent.v1',
    'ifall.silence_skipping.v1',
    'ifall.sleep_end_of_track.v1',
    'ifall.sleep_minutes.v1',
    'ifall.stats_opt_in.v1',
    'ifall.theme_mode.v1',
  ];

  Future<void> resetAll() async {
    for (final String key in ownedKeys) {
      await _prefs.remove(key);
    }
    notifyListeners();
  }
}
