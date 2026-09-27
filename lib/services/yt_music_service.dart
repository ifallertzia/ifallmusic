import 'package:dio/dio.dart';

import 'yt_music_parser.dart';

class YtMusicService {
  YtMusicService({Dio? dio, this.gl = 'IN', this.hl = 'en'})
    : _dio = dio ?? Dio();
  final Dio _dio;
  final String gl, hl;
  static const songsFilter = 'EgWKAQIIAWoMEA4QChADEAQQCRAF';
  static const videosFilter = 'EgWKAQIQAWoMEA4QChADEAQQCRAF';
  static const albumsFilter = 'EgWKAQIYAWoMEA4QChADEAQQCRAF';
  static const artistsFilter = 'EgWKAQIgAWoMEA4QChADEAQQCRAF';
  static const version = '1.20250219.01.00';
  final _cache = <String, ({DateTime at, MusicSearchResult result})>{};
  final _inflight = <String, Future<MusicSearchResult>>{};
  static String sanitize(String q) {
    final s = q.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), '').trim();
    return s.length > 120 ? s.substring(0, 120) : s;
  }

  Future<Map<String, dynamic>> request(
    String endpoint,
    Map<String, dynamic> body, {
    CancelToken? cancelToken,
    String? continuation,
  }) async {
    final token = cancelToken ?? CancelToken();
    final response = await _dio
        .post<Map<String, dynamic>>(
          'https://music.youtube.com/youtubei/v1/$endpoint',
          queryParameters: {
            'prettyPrint': 'false',
            if (continuation != null) ...{
              'ctoken': continuation,
              'continuation': continuation,
              'type': 'next',
            },
          },
          data: {
            'context': {
              'client': {
                'clientName': 'WEB_REMIX',
                'clientVersion': version,
                'hl': hl,
                'gl': gl,
              },
            },
            ...body,
          },
          cancelToken: token,
          options: Options(
            sendTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 8),
            headers: {
              'Content-Type': 'application/json',
              'Origin': 'https://music.youtube.com',
              'Referer': 'https://music.youtube.com/',
              'X-YouTube-Client-Name': '67',
              'X-YouTube-Client-Version': version,
              'User-Agent':
                  'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36',
            },
          ),
        )
        .timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            token.cancel('timeout');
            throw DioException(
              requestOptions: RequestOptions(),
              type: DioExceptionType.receiveTimeout,
            );
          },
        );
    if (response.data == null || response.data!.containsKey('error'))
      throw const FormatException('Empty YTM response');
    return response.data!;
  }

  Future<MusicSearchResult> search(
    String query, {
    String? filter,
    CancelToken? cancelToken,
    String? continuation,
  }) async {
    final q = sanitize(query);
    final key = '$q|$filter|$gl|$hl|$continuation';
    final cached = _cache[key];
    if (cached != null &&
        DateTime.now().difference(cached.at) < const Duration(minutes: 10))
      return cached.result;
    // UI-owned cancel tokens must not cancel another consumer's shared request.
    if (cancelToken == null && _inflight.containsKey(key))
      return _inflight[key]!;
    final operation = () async {
      final result = parseMusicSearch(
        await request(
          'search',
          {'query': q, if (filter != null) 'params': filter},
          cancelToken: cancelToken,
          continuation: continuation,
        ),
      );
      if (_cache.length >= 100) _cache.remove(_cache.keys.first);
      _cache[key] = (at: DateTime.now(), result: result);
      return result;
    }();
    if (cancelToken == null) _inflight[key] = operation;
    try {
      return await operation;
    } finally {
      if (cancelToken == null) _inflight.remove(key);
    }
  }

  Future<String?> playlistId(String browseId) async {
    if (browseId.startsWith('OLAK5uy')) return browseId;
    if (browseId.startsWith('VL')) return browseId.substring(2);
    final json = await request('browse', {'browseId': browseId});
    final url =
        json['microformat']?['microformatDataRenderer']?['urlCanonical']
            as String?;
    return url == null ? null : Uri.tryParse(url)?.queryParameters['list'];
  }

  void close() => _dio.close(force: true);
}
