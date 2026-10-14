import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../config/branding.dart';
import '../models/song.dart';
import 'playback_service.dart';
import 'settings_service.dart';

/// The scrobbling + Rich Presence companion.
///
/// Three independent outputs, each switched on from Settings:
///
/// * **Last.fm** — `track.updateNowPlaying` on start, `track.scrobble` once the
///   listener is [SettingsService.scrobblePercent] of the way in.
/// * **ListenBrainz** — `POST /1/submit-listens`, `single` on start and, at the
///   same threshold, an `import` listen so replays do not double-count.
/// * **Discord Rich Presence** — pushed through a relay the listener owns.
///
/// Every network call is fire-and-forget and wrapped: a scrobbler that is down
/// never touches playback. Failures queue in memory and are retried on the
/// next track, so a night of listening on the metro still lands on Last.fm.
class PresenceService extends ChangeNotifier {
  PresenceService({required this.settings, Dio? dio})
      : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 6)));

  final SettingsService settings;
  final Dio _dio;

  StreamSubscription<Song>? _sub;
  Timer? _tick;
  Song? _current;
  bool _scrobbled = false;
  final List<_PendingScrobble> _retry = <_PendingScrobble>[];
  String _status = 'Idle';

  /// Last human-readable outcome, surfaced in Settings → Accounts.
  String get status => _status;
  int get queuedScrobbles => _retry.length;

  /// Last.fm hands out API keys per application; ship yours with
  /// `--dart-define=IFALL_LASTFM_KEY=…`. Without one, Last.fm stays off and the
  /// other two outputs are unaffected.
  static const String lastFmApiKey =
      String.fromEnvironment('IFALL_LASTFM_KEY', defaultValue: '');
  static const String lastFmSharedSecret =
      String.fromEnvironment('IFALL_LASTFM_SECRET', defaultValue: '');

  static const String listenBrainzBase = 'https://api.listenbrainz.org';

  bool get lastFmReady =>
      lastFmApiKey.isNotEmpty && lastFmSharedSecret.isNotEmpty;

  /// Starts mirroring [playback] to whatever outputs are enabled.
  void attach(PlaybackService playback) {
    _sub?.cancel();
    _sub = playback.trackStream.listen(_onTrack);
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      final Song? song = playback.current;
      if (song == null) return;
      final Duration position = playback.position;
      final Duration total = playback.duration;
      if (total <= Duration.zero) return;
      if (position.inMilliseconds / total.inMilliseconds * 100 >=
          settings.scrobblePercent) {
        _fire(song, scrobble: true);
      } else {
        _fire(song, scrobble: false);
      }
    });
  }

  void _onTrack(Song song) {
    _current = song;
    _scrobbled = false;
    _fire(song, scrobble: false);
    _flushRetry();
  }

  void _fire(Song song, {required bool scrobble}) {
    if (scrobble) {
      if (_scrobbled) return;
      _scrobbled = true;
    }
    if (settings.lastFmEnabled) unawaited(_lastFm(song, scrobble: scrobble));
    if (settings.listenBrainzEnabled) {
      unawaited(_listenBrainz(song, scrobble: scrobble));
    }
    if (settings.discordEnabled) unawaited(_discord(song));
  }

  // ------------------------------------------------------------------ Last.fm

  Future<void> _lastFm(Song song, {required bool scrobble}) async {
    if (!lastFmReady || settings.lastFmSession.isEmpty) return;
    final Map<String, String> params = <String, String>{
      'method': scrobble ? 'track.scrobble' : 'track.updateNowPlaying',
      'api_key': lastFmApiKey,
      'sk': settings.lastFmSession,
      'artist': song.artist,
      'track': song.title,
      if (song.album != null) 'album': song.album!,
      if (scrobble)
        'timestamp': '${DateTime.now().millisecondsSinceEpoch ~/ 1000}',
    };
    params['api_sig'] = _lastFmSignature(params);
    params['format'] = 'json';

    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        'https://ws.audioscrobbler.com/2.0/',
        data: params,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );
      _setStatus(response.statusCode == 200
          ? 'Last.fm ${scrobble ? 'scrobbled' : 'now playing'} · ${song.title}'
          : 'Last.fm rejected the scrobble (${response.statusCode})');
      if (response.statusCode != 200 && scrobble) _queue(song);
    } catch (e) {
      if (scrobble) _queue(song);
      _setStatus('Last.fm unreachable — queued');
      debugPrint('last.fm: $e');
    }
  }

  /// Last.fm's signature: every parameter except `format`, sorted by name,
  /// concatenated with the shared secret, then MD5.
  static String _lastFmSignature(Map<String, String> params) {
    final List<String> keys = params.keys.toList()..sort();
    final StringBuffer buffer = StringBuffer();
    for (final String key in keys) {
      if (key == 'format' || key == 'callback') continue;
      buffer.write(key);
      buffer.write(params[key]);
    }
    buffer.write(lastFmSharedSecret);
    return md5(utf8.encode(buffer.toString()));
  }

  // ------------------------------------------------------------ ListenBrainz

  Future<void> _listenBrainz(Song song, {required bool scrobble}) async {
    final String token = settings.listenBrainzToken;
    if (token.isEmpty) return;
    final Map<String, dynamic> body = <String, dynamic>{
      'listen_type': scrobble ? 'single' : 'playing_now',
      'payload': <Map<String, dynamic>>[
        <String, dynamic>{
          if (scrobble)
            'listened_at': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          'track_metadata': <String, dynamic>{
            'artist_name': song.artist,
            'track_name': song.title,
            if (song.album != null) 'release_name': song.album!,
            'additional_info': <String, dynamic>{
              'media_player': IfallBranding.appName,
              'submission_client': IfallBranding.appName,
              if (song.id.isNotEmpty) 'origin_url': song.id,
            },
          },
        },
      ],
    };
    try {
      final Response<dynamic> response = await _dio.post<dynamic>(
        '$listenBrainzBase/1/submit-listens',
        data: body,
        options: Options(
          headers: <String, String>{
            'Authorization': 'Token $token',
            'Content-Type': 'application/json',
          },
        ),
      );
      _setStatus(response.statusCode == 200
          ? 'ListenBrainz ${scrobble ? 'submitted' : 'playing now'}'
          : 'ListenBrainz rejected the listen (${response.statusCode})');
      if (response.statusCode != 200 && scrobble) _queue(song);
    } catch (e) {
      if (scrobble) _queue(song);
      _setStatus('ListenBrainz unreachable — queued');
      debugPrint('listenbrainz: $e');
    }
  }

  // ----------------------------------------------------------------- Discord

  /// Rich Presence is pushed through a relay the listener runs (Discord's own
  /// RPC transport is a local IPC socket, which a phone cannot reach directly).
  /// The relay receives one JSON object and forwards it to Discord.
  Future<void> _discord(Song song) async {
    final String relay = settings.discordRelay;
    if (relay.isEmpty) return;
    final Duration total = song.duration ?? Duration.zero;
    final Map<String, dynamic> payload = <String, dynamic>{
      'type': 2,
      'details': song.title,
      'state': song.artist,
      'assets': <String, dynamic>{
        'large_image': song.thumbnailUrl,
        'large_text': song.album ?? song.artist,
      },
      if (settings.discordDetails.isNotEmpty)
        'party_status': settings.discordDetails,
      if (total > Duration.zero)
        'timestamps': <String, dynamic>{
          'start': DateTime.now().millisecondsSinceEpoch,
          'end': DateTime.now().millisecondsSinceEpoch + total.inMilliseconds,
        },
    };
    try {
      await _dio.post<dynamic>(
        relay,
        data: payload,
        options: Options(
          headers: <String, String>{'Content-Type': 'application/json'},
        ),
      );
      _setStatus('Discord presence updated');
    } catch (e) {
      _setStatus('Discord relay unreachable');
      debugPrint('discord: $e');
    }
  }

  // ------------------------------------------------------------------- queue

  void _queue(Song song) {
    if (_retry.length >= 50) _retry.removeAt(0);
    _retry.add(_PendingScrobble(song, DateTime.now()));
    notifyListeners();
  }

  /// Retries the backlog, dropping anything older than a day — Last.fm refuses
  /// scrobbles that far in the past.
  Future<void> _flushRetry() async {
    if (_retry.isEmpty) return;
    final List<_PendingScrobble> pending = List<_PendingScrobble>.from(_retry);
    _retry.clear();
    notifyListeners();
    for (final _PendingScrobble item in pending) {
      if (DateTime.now().difference(item.at) > const Duration(days: 1)) continue;
      if (settings.lastFmEnabled) await _lastFm(item.song, scrobble: true);
      if (settings.listenBrainzEnabled) {
        await _listenBrainz(item.song, scrobble: true);
      }
    }
  }

  void _setStatus(String value) {
    _status = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _tick?.cancel();
    super.dispose();
  }
}

class _PendingScrobble {
  const _PendingScrobble(this.song, this.at);

  final Song song;
  final DateTime at;
}

/// MD5 over [bytes]. Last.fm's signature scheme predates every nicer hash and
/// is fixed by its API, so it is computed inline rather than pulled in as a
/// dependency.
String md5(List<int> bytes) {
  // RFC 1321 — the 64-entry sine table.
  const List<int> shift = <int>[
    7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, //
    5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, //
    4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, //
    6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
  ];
  final List<int> sine = List<int>.generate(64, (int i) {
    final double v = (1 << 32) * _absSin(i + 1);
    return v.floor() & 0xFFFFFFFF;
  });

  // Pad to a multiple of 64 bytes: 0x80, zeros, then the 64-bit length.
  final int bitLength = bytes.length * 8;
  final List<int> padded = List<int>.from(bytes)..add(0x80);
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  for (int i = 0; i < 8; i++) {
    padded.add((bitLength >> (8 * i)) & 0xFF);
  }

  int a0 = 0x67452301;
  int b0 = 0xefcdab89;
  int c0 = 0x98badcfe;
  int d0 = 0x10325476;

  int rotl(int x, int n) => ((x << n) | (x >>> (32 - n))) & 0xFFFFFFFF;

  for (int offset = 0; offset < padded.length; offset += 64) {
    final List<int> m = List<int>.generate(16, (int j) {
      int v = 0;
      for (int k = 0; k < 4; k++) {
        v |= padded[offset + j * 4 + k] << (8 * k);
      }
      return v;
    });
    int a = a0;
    int b = b0;
    int c = c0;
    int d = d0;
    for (int i = 0; i < 64; i++) {
      int f;
      int g;
      if (i < 16) {
        f = (b & c) | (~b & d);
        g = i;
      } else if (i < 32) {
        f = (d & b) | (~d & c);
        g = (5 * i + 1) % 16;
      } else if (i < 48) {
        f = b ^ c ^ d;
        g = (3 * i + 5) % 16;
      } else {
        f = c ^ (b | ~d);
        g = (7 * i) % 16;
      }
      f &= 0xFFFFFFFF;
      final int tmp = d;
      d = c;
      c = b;
      final int sum = (a + f + sine[i] + m[g]) & 0xFFFFFFFF;
      b = (b + rotl(sum, shift[i])) & 0xFFFFFFFF;
      a = tmp;
    }
    a0 = (a0 + a) & 0xFFFFFFFF;
    b0 = (b0 + b) & 0xFFFFFFFF;
    c0 = (c0 + c) & 0xFFFFFFFF;
    d0 = (d0 + d) & 0xFFFFFFFF;
  }

  String hex(int v) =>
      v.toRadixString(16).padLeft(8, '0');
  return hex(_swap(a0)) + hex(_swap(b0)) + hex(_swap(c0)) + hex(_swap(d0));
}

/// MD5 words are little-endian on the wire.
int _swap(int v) {
  final int b0 = v & 0xFF;
  final int b1 = (v >> 8) & 0xFF;
  final int b2 = (v >> 16) & 0xFF;
  final int b3 = (v >> 24) & 0xFF;
  return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
}

double _absSin(int i) => math.sin(i).abs();
