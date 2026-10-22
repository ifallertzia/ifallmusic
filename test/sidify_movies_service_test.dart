import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/movies/models/movie_models.dart';
import 'package:ifallmusic/movies/services/movie_http_client.dart';
import 'package:ifallmusic/movies/services/sidify_movies_service.dart';

class ApiTransport implements MovieHttpTransport {
  Object payload = <String, dynamic>{};
  String lastUrl = '';
  String lastBody = '';
  @override
  final streamDio = Dio();
  MovieHttpResponse response(String url) => MovieHttpResponse(statusCode: 200, body: jsonEncode(payload), headers: {}, effectiveUrl: url);
  @override
  Future<MovieHttpResponse> get(String url, {Map<String, String> headers = const {}, bool followRedirects = true}) async {
    lastUrl = url;
    return response(url);
  }
  @override
  Future<MovieHttpResponse> post(String url, {required String body, Map<String, String> headers = const {}}) async {
    lastBody = body;
    return response(url);
  }
  @override
  Future<MovieRangeResponse> getRange(String url, {Map<String, String> headers = const {}, required int start, int? end}) => throw UnimplementedError();
  @override
  void close() => streamDio.close();
}

void main() {
  late ApiTransport transport;
  late SidifyMoviesService service;
  setUp(() {
    transport = ApiTransport();
    service = SidifyMoviesService(transport: transport, apiOrigin: 'https://api.example');
  });
  tearDown(() => transport.close());
  test('search maps Sidify series and avoids duplicate pagination', () async {
    transport.payload = {'items': [{'title': 'Example', 'slug': 'example', 'kind': 'series', 'year': 2026}]};
    final posts = await service.searchPosts(query: 'a & b');
    expect(posts.single.isSeries, isTrue);
    expect(posts.single.link, 'https://api.example/api/media/title/series/example');
    expect(Uri.parse(transport.lastUrl).queryParameters['q'], 'a & b');
    expect(await service.searchPosts(query: 'a', page: 2), isEmpty);
  });
  test('blocked resolver never returns external fallback as media', () async {
    transport.payload = {'status': 'blocked', 'links': [], 'externalFallbackUrl': 'https://mirror.example/captcha'};
    expect(service.resolveDownloadStream(const MovieQualityLink(id: '1', rawLabel: '720p', resolution: '720p', dlUrl: 'https://mirror.example/1'), fallbackTitle: 'Example'), throwsStateError);
  });
  test('resolver uses POST and retains direct candidates only', () async {
    transport.payload = {'status': 'partial', 'links': [{'server': 'Direct', 'url': 'https://files.example/video.mkv', 'delivery': 'download'}, {'server': 'Page', 'url': 'https://mirror.example/page', 'delivery': 'external'}]};
    final resolved = await service.resolveDownloadStream(const MovieQualityLink(id: '1', rawLabel: '720p', resolution: '720p', dlUrl: 'https://mirror.example/1'), fallbackTitle: 'Example');
    expect(resolved.candidates.single.server, 'Direct');
    expect(jsonDecode(transport.lastBody)['url'], 'https://mirror.example/1');
  });
}
