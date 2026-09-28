import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

class InnertubeResolver {
  InnertubeResolver({
    http.Client? client,
    PoTokenResolver poTokenResolver = const NullPoTokenResolver(),
    Duration perClientTimeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client(),
       _poTokenResolver = poTokenResolver,
       _perClientTimeout = perClientTimeout;

  static final Uri _playerEndpoint = Uri.parse(
    'https://www.youtube.com/youtubei/v1/player?prettyPrint=false',
  );

  final http.Client _client;
  final PoTokenResolver _poTokenResolver;
  final Duration _perClientTimeout;
  final Map<int, int> _probeFailuresByItag = <int, int>{};
  final Set<int> _blacklistedItags = <int>{};

  static const List<_InnertubeClient> _clients = <_InnertubeClient>[
    _InnertubeClient(
      clientName: 'ANDROID_TESTSUITE',
      clientVersion: '1.9.31',
      userAgent:
          'com.google.android.youtube.testsuite/1.9.31 (Linux; U; Android 14; en_US; SM-S928B Build/UP1A.231005.007)',
      platform: 'MOBILE',
      osName: 'Android',
      osVersion: '14',
    ),
    _InnertubeClient(
      clientName: 'ANDROID_VR',
      clientVersion: '1.74.31',
      clientId: 28,
      userAgent:
          'com.google.android.apps.youtube.vr.oculus/1.74.31 (Linux; U; Android 14; eureka-user Build/SQ3A.220605.009.A1) gzip',
      platform: 'MOBILE',
      osName: 'Android',
      osVersion: '14',
    ),
    _InnertubeClient(
      clientName: 'VISION_OS',
      clientVersion: '1.1.2',
      clientId: 113,
      userAgent:
          'com.google.ios.youtube/1.1.2 (VisionPro1,1; U; CPU OS 1_1 like Mac OS X; en_US)',
      platform: 'MOBILE',
      osName: 'iOS',
      osVersion: '1.1',
    ),
    _InnertubeClient(
      clientName: 'ANDROID_EMBEDDED_PLAYER',
      clientVersion: '1.2.2',
      clientId: 55,
      userAgent:
          'com.google.android.youtube.embedded.player/1.2.2 (Linux; U; Android 14; en_US; SM-S928B Build/UP1A.231005.007)',
      platform: 'MOBILE',
      osName: 'Android',
      osVersion: '14',
    ),
    _InnertubeClient(
      clientName: 'ANDROID_MUSIC',
      clientVersion: '7.07.51',
      userAgent:
          'com.google.android.apps.youtube.music/7.07.51 (Linux; U; Android 14; en_US; SM-S928B Build/UP1A.231005.007)',
      platform: 'MOBILE',
      osName: 'Android',
      osVersion: '14',
    ),
    _InnertubeClient(
      clientName: 'TVHTML5_SIMPLY_EMBEDDED_PLAYER',
      clientVersion: '2.0',
      clientId: 85,
      userAgent:
          'Mozilla/5.0 (PlayStation; PlayStation 4/12.02) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15',
      platform: 'TV',
      embed: true,
    ),
  ];

  Future<InnertubeResolvedStream> resolve(
    VideoId videoId, {
    bool preferDownload = false,
    bool validate = true,
    Set<String> skipClients = const <String>{},
  }) async {
    Object? lastError;
    for (final _InnertubeClient client in _clients) {
      if (skipClients.contains(client.clientName)) continue;
      try {
        final Map<String, dynamic> body = await _body(client, videoId.value);
        final String? poToken = await _poTokenResolver.get(videoId.value);
        if (poToken != null && poToken.isNotEmpty) {
          body['serviceIntegrityDimensions'] = <String, String>{
            'poToken': poToken,
          };
        }
        final Map<String, String> headers = <String, String>{
          'Content-Type': 'application/json',
          'User-Agent': client.userAgent,
          'X-YouTube-Client-Name':
              client.clientId?.toString() ?? client.clientName,
          'X-YouTube-Client-Version': client.clientVersion,
          'Origin': 'https://music.youtube.com',
          'Referer': 'https://music.youtube.com/',
          if (poToken != null && poToken.isNotEmpty) 'X-YouTube-Po-Token': poToken,
        };
        final http.Response response = await _client
            .post(_playerEndpoint, headers: headers, body: jsonEncode(body))
            .timeout(_perClientTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw HttpException('HTTP ${response.statusCode}');
        }
        final Object? decoded = jsonDecode(response.body);
        if (decoded is! Map) throw const FormatException('Invalid player JSON');
        final Map<String, dynamic> json = decoded.cast<String, dynamic>();
        final Object? playability = json['playabilityStatus'];
        final String status = playability is Map
            ? playability['status']?.toString() ?? 'UNKNOWN'
            : 'UNKNOWN';
        if (status != 'OK') {
          throw StateError('playabilityStatus=$status');
        }
        final List<InnertubeResolvedStream> candidates = _formats(
          json,
          client.clientName,
          preferDownload: preferDownload,
        );
        for (final InnertubeResolvedStream stream in candidates) {
          if (_blacklistedItags.contains(stream.itag)) continue;
          if (!validate || await _probe(stream.url, stream.itag)) {
            debugPrint('[innertube:${client.clientName}] using itag ${stream.itag}');
            return stream;
          }
        }
        throw StateError('No directly playable audio URL');
      } catch (e) {
        lastError = e;
        debugPrint('[innertube:${client.clientName}] failed: $e');
      }
    }
    throw StateError(
      'Innertube could not resolve a playable stream${lastError == null ? '' : ': $lastError'}',
    );
  }

  Future<Map<String, dynamic>> _body(_InnertubeClient client, String videoId) async {
    final Map<String, dynamic> clientJson = <String, dynamic>{
      'clientName': client.clientName,
      'clientVersion': client.clientVersion,
      'gl': 'US',
      'hl': 'en',
      'platform': client.platform,
      if (client.osName != null) 'osName': client.osName,
      if (client.osVersion != null) 'osVersion': client.osVersion,
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
        bitrate: _asInt(map['bitrate']) == 0 ? _asInt(map['averageBitrate']) : _asInt(map['bitrate']),
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

  Future<bool> _probe(Uri url, int itag) async {
    final HttpClient httpClient = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      final HttpClientRequest request = await httpClient.headUrl(url);
      final HttpClientResponse response =
          await request.close().timeout(const Duration(seconds: 8));
      await response.drain<void>().timeout(const Duration(seconds: 8));
      if (response.statusCode == HttpStatus.ok ||
          response.statusCode == HttpStatus.partialContent) {
        return true;
      }
      _noteProbeFailure(itag);
      return false;
    } catch (_) {
      _noteProbeFailure(itag);
      return false;
    } finally {
      httpClient.close(force: true);
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
    required this.userAgent,
    required this.platform,
    this.clientId,
    this.osName,
    this.osVersion,
    this.embed = false,
  });

  final String clientName;
  final String clientVersion;
  final int? clientId;
  final String userAgent;
  final String platform;
  final String? osName;
  final String? osVersion;
  final bool embed;
}
