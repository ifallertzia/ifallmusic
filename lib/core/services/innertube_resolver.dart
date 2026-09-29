import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// Future hook for YouTube proof-of-origin tokens.
///
/// The default resolver returns null; callers may provide an implementation later
/// without changing the playback pipeline.
abstract class PoTokenResolver {
  Future<String?> get(String videoId);
}

class NullPoTokenResolver implements PoTokenResolver {
  const NullPoTokenResolver();

  @override
  Future<String?> get(String videoId) async => null;
}

class InnertubeResolvedStream {
  const InnertubeResolvedStream({
    required this.url,
    required this.itag,
    required this.bitrate,
    required this.mimeType,
    required this.clientName,
    this.contentLength,
    this.audioOnly = true,
  });

  final Uri url;
  final int itag;
  final int bitrate;
  final String mimeType;
  final String clientName;
  final int? contentLength;
  final bool audioOnly;
}

/// Outcome of the HEAD probe that pre-validates a stream URL.
enum _ProbeOutcome {
  /// Server answered 200/206 — the URL is safe to hand to the player.
  confirmed,

  /// Definitively dead (400/403/404/410) — try the next candidate.
  rejected,

  /// Anything else (405, 429, 5xx, timeouts, socket errors): not proven
  /// dead, so the player's own GET request makes the final call.
  inconclusive,
}

class InnertubeResolver {
  InnertubeResolver({
    http.Client? client,
    PoTokenResolver poTokenResolver = const NullPoTokenResolver(),
    Duration perClientTimeout = const Duration(seconds: 6),
    String? gl,
    String? hl,
  }) : _client = client ?? http.Client(),
       _poTokenResolver = poTokenResolver,
       _perClientTimeout = perClientTimeout,
       // Same locale rules as YoutubeService so search and playback agree
       // on which videos are region-available.
       _gl = gl ?? _defaultCountry(),
       _hl = hl ?? _defaultLanguage();

  static String _defaultCountry() {
    try {
      final String code =
          (PlatformDispatcher.instance.locale.countryCode ?? '').trim();
      return code.isEmpty ? 'IN' : code;
    } catch (_) {
      // Test shells / early startup may not expose a locale.
      return 'IN';
    }
  }

  static String _defaultLanguage() {
    try {
      final String code = PlatformDispatcher.instance.locale.languageCode;
      return (code.isEmpty || code == 'und') ? 'en' : code;
    } catch (_) {
      return 'en';
    }
  }

  static final Uri _playerEndpoint = Uri.parse(
    'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
  );

  /// How many stream URLs we HEAD-probe per client before giving up. Keeps a
  /// slow/unreachable CDN from eating the whole resolution budget.
  static const int _maxProbesPerClient = 6;

  /// Codes that mean "this URL is dead", as opposed to transient conditions.
  static const Set<int> _rejectedCodes = <int>{400, 403, 404, 410};

  final http.Client _client;
  final PoTokenResolver _poTokenResolver;
  final Duration _perClientTimeout;
  final String _gl;
  final String _hl;
  final Map<int, int> _probeFailuresByItag = <int, int>{};
  final Set<int> _blacklistedItags = <int>{};

  /// Client roster, ordered by real-world success (2026-09).
  ///
  /// Every entry is copied verbatim from yt-dlp's `INNERTUBE_CLIENTS`
  /// (`yt_dlp/extractor/youtube/_base.py`, current) except
  /// TVHTML5_SIMPLY_EMBEDDED_PLAYER, which is kept as a last resort.
  /// Why this order:
  ///  * `VISIONOS` is yt-dlp's default lead client — its stream URLs play in
  ///    full without a proof-of-origin token (verified against live YouTube
  ///    on 2026-09-26), and it never triggers the SABR-only path.
  ///  * `TVHTML5` serves direct URLs tokenless for most formats.
  ///  * `ANDROID`/`IOS` are `REQUIRE_JS_PLAYER: False` and always answer,
  ///    so they make dependable mid-tier fallbacks.
  ///  * `ANDROID_VR` formats have been 403-ing since 2026.08.17 — kept only
  ///    as a cheap late fallback in case enforcement eases.
  ///
  /// Removed after live probing (2026-09-29):
  ///  * `TVHTML5_SIMPLY_EMBEDDED_PLAYER` — hard ERROR: "YouTube is no longer
  ///    supported in this application or device" (this was the error surface
  ///    in the 2.3.5 field report).
  ///  * `ANDROID_TESTSUITE` (404), `VISION_OS` (400 — not a real client name),
  ///    `ANDROID_MUSIC`, `ANDROID_EMBEDDED_PLAYER`.
  ///
  /// Deliberately absent: `WEB`/`MWEB`/`tv_simply` (withhold direct URLs
  /// without a PO token — we have no token source) and every client whose
  /// `X-YouTube-Client-Name` would be non-numeric.
  static const List<_InnertubeClient> _clients = <_InnertubeClient>[
    _InnertubeClient(
      clientName: 'VISIONOS',
      clientVersion: '1.02',
      clientId: 101,
      userAgent:
          'Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15',
      deviceMake: 'Apple',
      deviceModel: 'RealityDevice17,1',
      osName: 'visionOS',
      osVersion: '26.5.23O471',
    ),
    _InnertubeClient(
      clientName: 'TVHTML5',
      clientVersion: '7.20260707.07.00',
      clientId: 7,
      userAgent:
          'Mozilla/5.0 (ChromiumStylePlatform) Cobalt/25.lts.30.1034943-gold (unlike Gecko), Unknown_TV_Unknown_0/Unknown (Unknown, Unknown)',
    ),
    _InnertubeClient(
      clientName: 'ANDROID',
      clientVersion: '21.26.364',
      clientId: 3,
      userAgent:
          'com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip',
      androidSdkVersion: 30,
      osName: 'Android',
      osVersion: '11',
    ),
    _InnertubeClient(
      clientName: 'IOS',
      clientVersion: '21.26.4',
      clientId: 5,
      userAgent:
          'com.google.ios.youtube/21.26.4 (iPhone16,2; U; CPU iOS 18_3_2 like Mac OS X;)',
      deviceMake: 'Apple',
      deviceModel: 'iPhone16,2',
      osName: 'iPhone',
      osVersion: '18.3.2.22D82',
    ),
    _InnertubeClient(
      clientName: 'ANDROID_VR',
      clientVersion: '1.65.10',
      clientId: 28,
      userAgent:
          'com.google.android.apps.youtube.vr.oculus/1.65.10 (Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      deviceMake: 'Oculus',
      deviceModel: 'Quest 3',
      androidSdkVersion: 32,
      osName: 'Android',
      osVersion: '12L',
    ),
  ];

  Future<InnertubeResolvedStream> resolve(
    VideoId videoId, {
    bool preferDownload = false,
    bool validate = true,
    Set<String> skipClients = const <String>{},
  }) async {
    final List<String> failures = <String>[];
    for (final _InnertubeClient client in _clients) {
      if (skipClients.contains(client.clientName)) continue;
      try {
        final String? poToken = await _poTokenResolver.get(videoId.value);
        ({Map<String, dynamic> json, String? headerVisitor}) result =
            await _post(client, videoId, poToken: poToken);
        Map<String, dynamic> json = result.json;
        String status = _statusOf(json);

        // Bot check: anonymous requests are answered LOGIN_REQUIRED until the
        // visitorData we just received is echoed back. Retry the same client
        // once with it before rotating (proven pattern, vibecast 2026-09).
        if (status == 'LOGIN_REQUIRED') {
          final String? visitorData = _visitorDataOf(
            json,
            result.headerVisitor,
          );
          if (visitorData != null && visitorData.isNotEmpty) {
            result = await _post(
              client,
              videoId,
              poToken: poToken,
              visitorData: visitorData,
            );
            json = result.json;
            status = _statusOf(json);
          }
        }

        if (status != 'OK') {
          final String reason = _playabilityReason(json);
          failures.add(
            '${client.clientName}=$status${reason.isEmpty ? '' : ' ($reason)'}',
          );
          debugPrint(
            '[innertube:${client.clientName}] playability $status $reason',
          );
          continue;
        }

        final List<InnertubeResolvedStream> candidates = _formats(
          json,
          client.clientName,
          preferDownload: preferDownload,
        );
        int probed = 0;
        for (final InnertubeResolvedStream stream in candidates) {
          if (_blacklistedItags.contains(stream.itag)) continue;
          if (!validate) return stream;
          if (probed >= _maxProbesPerClient) break;
          probed++;
          final _ProbeOutcome outcome = await _probe(stream.url, stream.itag);
          if (outcome == _ProbeOutcome.rejected) {
            debugPrint(
              '[innertube:${client.clientName}] itag ${stream.itag} dead, '
              'trying next stream',
            );
            continue;
          }
          // confirmed, or not proven dead (HEAD blocked, transient 5xx/429,
          // network hiccup...): hand the URL to the player instead of
          // burning the rest of the time budget.
          debugPrint(
            '[innertube:${client.clientName}] itag ${stream.itag} '
            '${outcome == _ProbeOutcome.confirmed ? 'confirmed' : 'unconfirmed, using it anyway'}',
          );
          return stream;
        }
        failures.add(
          candidates.isEmpty
              ? '${client.clientName}=OK-no-direct-url'
              : '${client.clientName}=urls-rejected',
        );
      } catch (e) {
        final String detail = e.toString();
        failures.add(
          '${client.clientName}=${detail.length > 200 ? '${detail.substring(0, 200)}…' : detail}',
        );
        debugPrint('[innertube:${client.clientName}] failed: $e');
      }
    }
    throw StateError(
      'Innertube could not resolve a playable stream: '
      '${failures.join(' | ')}',
    );
  }

  Future<({Map<String, dynamic> json, String? headerVisitor})> _post(
    _InnertubeClient client,
    VideoId videoId, {
    String? poToken,
    String? visitorData,
  }) async {
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': client.userAgent,
      // Always the numeric client id — YouTube treats non-numeric values
      // as malformed (YtMusicService sends '67' and works in production).
      'X-YouTube-Client-Name': client.clientId.toString(),
      'X-YouTube-Client-Version': client.clientVersion,
      if (visitorData != null && visitorData.isNotEmpty)
        'X-Goog-Visitor-Id': visitorData,
      if (poToken != null && poToken.isNotEmpty)
        'X-YouTube-Po-Token': poToken,
    };
    final http.Response response = await _client
        .post(
          _playerEndpoint,
          headers: headers,
          body: jsonEncode(_body(client, videoId.value, visitorData, poToken)),
        )
        .timeout(_perClientTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP ${response.statusCode}');
    }
    final Object? decoded = jsonDecode(response.body);
    if (decoded is! Map) throw const FormatException('Invalid player JSON');
    final Map<String, dynamic> json = decoded.cast<String, dynamic>();
    // Header first, body second — either can carry the bot-check challenge
    // that must be echoed on the retry.
    return (
      json: json,
      headerVisitor: response.headers['x-goog-visitor-id'],
    );
  }

  String _statusOf(Map<String, dynamic> json) {
    final Object? playability = json['playabilityStatus'];
    if (playability is! Map) return 'UNKNOWN';
    return playability['status']?.toString() ?? 'UNKNOWN';
  }

  String _playabilityReason(Map<String, dynamic> json) {
    final Object? playability = json['playabilityStatus'];
    if (playability is! Map) return '';
    final Object? reason = playability['reason'];
    final String text = _richText(reason);
    if (text.isNotEmpty) return text;
    final Object? messages = playability['messages'];
    if (messages is List && messages.isNotEmpty) {
      return messages.first.toString();
    }
    return '';
  }

  String _richText(Object? value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is Map) {
      final Object? simple = value['simpleText'];
      if (simple != null) return simple.toString();
      final Object? runs = value['runs'];
      if (runs is List) {
        return runs
            .map((Object? run) =>
                run is Map ? run['text']?.toString() ?? '' : '')
            .join();
      }
    }
    return '';
  }

  String? _visitorDataOf(Map<String, dynamic> json, String? headerVisitor) {
    if (headerVisitor != null && headerVisitor.isNotEmpty) {
      return headerVisitor;
    }
    final Object? context = json['responseContext'];
    if (context is Map) {
      final Object? data = context['visitorData'];
      if (data is String && data.isNotEmpty) return data;
    }
    final Object? top = json['visitorData'];
    if (top is String && top.isNotEmpty) return top;
    return null;
  }

  Map<String, dynamic> _body(
    _InnertubeClient client,
    String videoId,
    String? visitorData,
    String? poToken,
  ) {
    final Map<String, dynamic> clientJson = <String, dynamic>{
      'clientName': client.clientName,
      'clientVersion': client.clientVersion,
      'hl': _hl,
      'gl': _gl,
      if (client.userAgent.isNotEmpty) 'userAgent': client.userAgent,
      if (client.deviceMake != null) 'deviceMake': client.deviceMake,
      if (client.deviceModel != null) 'deviceModel': client.deviceModel,
      if (client.androidSdkVersion != null)
        'androidSdkVersion': client.androidSdkVersion,
      if (client.osName != null) 'osName': client.osName,
      if (client.osVersion != null) 'osVersion': client.osVersion,
      if (visitorData != null && visitorData.isNotEmpty)
        'visitorData': visitorData,
    };
    return <String, dynamic>{
      'context': <String, dynamic>{
        'client': clientJson,
        if (client.embed)
          'thirdParty': <String, String>{
            'embedUrl': 'https://www.youtube.com/watch?v=$videoId',
          },
      },
      'videoId': videoId,
      // Lets otherwise-acceptable music through region/kid gates.
      'contentCheckOk': true,
      'racyCheckOk': true,
      if (poToken != null && poToken.isNotEmpty)
        'serviceIntegrityDimensions': <String, String>{'poToken': poToken},
    };
  }

  List<InnertubeResolvedStream> _formats(
    Map<String, dynamic> json,
    String clientName, {
    required bool preferDownload,
  }) {
    final Object? streaming = json['streamingData'];
    if (streaming is! Map) return <InnertubeResolvedStream>[];
    final List<InnertubeResolvedStream> audio = _readFormats(
      streaming['adaptiveFormats'],
      clientName,
      audioOnlyOnly: true,
    );
    final List<InnertubeResolvedStream> muxed = _readFormats(
      streaming['formats'],
      clientName,
      audioOnlyOnly: false,
    );
    audio.sort((InnertubeResolvedStream a, InnertubeResolvedStream b) {
      if (preferDownload) {
        final int a140 = a.itag == 140 ? 1 : 0;
        final int b140 = b.itag == 140 ? 1 : 0;
        if (a140 != b140) return b140.compareTo(a140);
        final int aLen = a.contentLength == null ? 0 : 1;
        final int bLen = b.contentLength == null ? 0 : 1;
        if (aLen != bLen) return bLen.compareTo(aLen);
      }
      return b.bitrate.compareTo(a.bitrate);
    });
    muxed.sort((InnertubeResolvedStream a, InnertubeResolvedStream b) =>
        b.bitrate.compareTo(a.bitrate));
    return <InnertubeResolvedStream>[...audio, ...muxed];
  }

  List<InnertubeResolvedStream> _readFormats(
    Object? raw,
    String clientName, {
    required bool audioOnlyOnly,
  }) {
    if (raw is! List) return <InnertubeResolvedStream>[];
    final List<InnertubeResolvedStream> out = <InnertubeResolvedStream>[];
    for (final Object? item in raw) {
      if (item is! Map) continue;
      final Map map = item;
      if (map['signatureCipher'] != null || map['cipher'] != null) {
        // Deliberately do not block rotation on ciphered clients. The selected
        // mobile clients usually provide direct URLs; legacy explode remains the
        // decipher-capable fallback.
        continue;
      }
      final String? rawUrl = map['url']?.toString();
      if (rawUrl == null || rawUrl.isEmpty) continue;
      final Uri? url = Uri.tryParse(rawUrl);
      if (url == null || !url.hasScheme) continue;
      final int itag = _asInt(map['itag']);
      final String mime = map['mimeType']?.toString() ?? '';
      final bool audioOnly = mime.startsWith('audio/') ||
          const <int>{140, 141, 139, 249, 250, 251}.contains(itag);
      if (audioOnlyOnly && !audioOnly) continue;
      out.add(InnertubeResolvedStream(
        url: url,
        itag: itag,
        bitrate: _asInt(map['bitrate']) == 0
            ? _asInt(map['averageBitrate'])
            : _asInt(map['bitrate']),
        mimeType: mime,
        clientName: clientName,
        contentLength: _asNullableInt(map['contentLength']),
        audioOnly: audioOnly,
      ));
    }
    return out;
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  int? _asNullableInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.round();
    return int.tryParse(value.toString());
  }

  Future<_ProbeOutcome> _probe(Uri url, int itag) async {
    try {
      final http.Response response = await _client
          .head(url)
          .timeout(const Duration(seconds: 4));
      final int code = response.statusCode;
      if (code == HttpStatus.ok || code == HttpStatus.partialContent) {
        return _ProbeOutcome.confirmed;
      }
      if (_rejectedCodes.contains(code)) {
        _noteProbeFailure(itag);
        return _ProbeOutcome.rejected;
      }
      // 405 (HEAD unsupported), 429, 5xx... not proof of a dead URL.
      return _ProbeOutcome.inconclusive;
    } on Exception catch (e) {
      // Timeouts/socket errors say something about the network, never the
      // URL — no blacklist strike, and do not keep probing the same host.
      debugPrint('[innertube] probe inconclusive for itag $itag: $e');
      return _ProbeOutcome.inconclusive;
    }
  }

  void _noteProbeFailure(int itag) {
    final int failures = (_probeFailuresByItag[itag] ?? 0) + 1;
    _probeFailuresByItag[itag] = failures;
    if (failures >= 2) _blacklistedItags.add(itag);
  }

  void close() => _client.close();
}

class _InnertubeClient {
  const _InnertubeClient({
    required this.clientName,
    required this.clientVersion,
    required this.clientId,
    required this.userAgent,
    this.deviceMake,
    this.deviceModel,
    this.androidSdkVersion,
    this.osName,
    this.osVersion,
    this.embed = false,
  });

  final String clientName;
  final String clientVersion;

  /// Numeric Innertube client id — always sent as `X-YouTube-Client-Name`.

  final int clientId;
  final String userAgent;
  final String? deviceMake;
  final String? deviceModel;
  final int? androidSdkVersion;
  final String? osName;
  final String? osVersion;
  final bool embed;
}
