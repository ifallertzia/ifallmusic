import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

class MovieHttpResponse {
  const MovieHttpResponse({
    required this.statusCode,
    required this.body,
    required this.headers,
    required this.effectiveUrl,
  });

  final int statusCode;
  final String body;
  final Map<String, String> headers;
  final String effectiveUrl;

  String? header(String name) {
    final String lower = name.toLowerCase();
    for (final MapEntry<String, String> entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }
}

abstract class MovieHttpTransport {
  Future<MovieHttpResponse> get(
    String url, {
    Map<String, String> headers = const <String, String>{},
    bool followRedirects = true,
  });

  Future<MovieHttpResponse> post(
    String url, {
    required String body,
    Map<String, String> headers = const <String, String>{},
  });

  Dio get streamDio;

  void close();
}

/// Production HTTP client with automatic Cloudflare / Google DNS-over-HTTPS
/// fallback when Indian mobile ISPs (Jio / Airtel / Vi) poison DNS lookups.
class DioMovieHttpTransport implements MovieHttpTransport {
  DioMovieHttpTransport() {
    _dio = _buildDio();
  }

  static const String browserUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

  final Map<String, InternetAddress> _dohCache = <String, InternetAddress>{};
  late final Dio _dio;

  @override
  Dio get streamDio => _dio;

  Dio _buildDio() {
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
        headers: const <String, String>{
          'User-Agent': browserUserAgent,
          'Accept':
              'text/html,application/xhtml+xml,application/xml;q=0.9,application/json,*/*;q=0.8',
          'Accept-Language': 'en-IN,en-US;q=0.9,en;q=0.8',
        },
        responseType: ResponseType.plain,
        validateStatus: (int? status) => status != null && status < 500,
      ),
    );

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final HttpClient client = HttpClient();
        client.connectionTimeout = const Duration(seconds: 15);
        client.userAgent = browserUserAgent;
        return client;
      },
    );
    return dio;
  }

  Map<String, String> _flattenHeaders(Headers headers) {
    final Map<String, String> map = <String, String>{};
    headers.forEach((String k, List<String> v) {
      if (v.isNotEmpty) map[k] = v.join(', ');
    });
    return map;
  }

  @override
  Future<MovieHttpResponse> get(
    String url, {
    Map<String, String> headers = const <String, String>{},
    bool followRedirects = true,
  }) async {
    try {
      final Response<String> res = await _dio.get<String>(
        url,
        options: Options(
          headers: headers,
          followRedirects: followRedirects,
          maxRedirects: followRedirects ? 5 : 0,
          responseType: ResponseType.plain,
          validateStatus: (int? s) => s != null && s < 500,
        ),
      );
      return MovieHttpResponse(
        statusCode: res.statusCode ?? 0,
        body: res.data ?? '',
        headers: _flattenHeaders(res.headers),
        effectiveUrl: res.realUri.toString(),
      );
    } on DioException catch (e) {
      if (_isDnsOrConnectionFailure(e)) {
        final MovieHttpResponse? fallback = await _retryOverDoh(
          url,
          method: 'GET',
          headers: headers,
          followRedirects: followRedirects,
        );
        if (fallback != null) return fallback;
      }
      rethrow;
    }
  }

  @override
  Future<MovieHttpResponse> post(
    String url, {
    required String body,
    Map<String, String> headers = const <String, String>{},
  }) async {
    try {
      final Response<String> res = await _dio.post<String>(
        url,
        data: body,
        options: Options(
          headers: headers,
          responseType: ResponseType.plain,
          validateStatus: (int? s) => s != null && s < 500,
        ),
      );
      return MovieHttpResponse(
        statusCode: res.statusCode ?? 0,
        body: res.data ?? '',
        headers: _flattenHeaders(res.headers),
        effectiveUrl: res.realUri.toString(),
      );
    } on DioException catch (e) {
      if (_isDnsOrConnectionFailure(e)) {
        final MovieHttpResponse? fallback = await _retryOverDoh(
          url,
          method: 'POST',
          body: body,
          headers: headers,
          followRedirects: true,
        );
        if (fallback != null) return fallback;
      }
      rethrow;
    }
  }

  bool _isDnsOrConnectionFailure(DioException e) {
    return e.type == DioExceptionType.connectionError ||
        e.type == DioExceptionType.connectionTimeout ||
        e.error is SocketException ||
        e.error is HandshakeException;
  }

  Future<InternetAddress?> _resolveViaDoh(String host) async {
    if (_dohCache.containsKey(host)) return _dohCache[host];
    final List<String> endpoints = <String>[
      'https://1.1.1.1/dns-query?name=${Uri.encodeQueryComponent(host)}&type=A',
      'https://dns.google/resolve?name=${Uri.encodeQueryComponent(host)}&type=A',
    ];

    final HttpClient raw = HttpClient()
      ..connectionTimeout = const Duration(seconds: 6);
    try {
      for (final String endpoint in endpoints) {
        try {
          final HttpClientRequest req = await raw.getUrl(Uri.parse(endpoint));
          req.headers.set('Accept', 'application/dns-json');
          final HttpClientResponse resp = await req.close();
          if (resp.statusCode != 200) continue;
          final String text = await resp.transform(utf8.decoder).join();
          final Object? decoded = jsonDecode(text);
          if (decoded is Map<String, dynamic>) {
            final Object? answers = decoded['Answer'];
            if (answers is List) {
              for (final Object? item in answers) {
                if (item is Map && item['type'] == 1 && item['data'] is String) {
                  final InternetAddress? addr =
                      InternetAddress.tryParse(item['data'] as String);
                  if (addr != null) {
                    _dohCache[host] = addr;
                    return addr;
                  }
                }
              }
            }
          }
        } catch (_) {}
      }
    } finally {
      raw.close(force: true);
    }
    return null;
  }

  Future<MovieHttpResponse?> _retryOverDoh(
    String url, {
    required String method,
    String body = '',
    required Map<String, String> headers,
    required bool followRedirects,
  }) async {
    final Uri uri = Uri.parse(url);
    final InternetAddress? addr = await _resolveViaDoh(uri.host);
    if (addr == null) return null;

    final SecurityContext ctx = SecurityContext.defaultContext;
    HttpClient? customClient;
    try {
      final int port = uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      customClient = HttpClient(context: ctx)
        ..connectionFactory = (Uri target, String? proxyHost, int? proxyPort) async {
          if (target.host == uri.host) {
            final Socket sock = await Socket.connect(
              addr,
              port,
              timeout: const Duration(seconds: 10),
            );
            if (target.scheme == 'https') {
              final SecureSocket secure = await SecureSocket.secure(
                sock,
                host: uri.host,
              );
              return ConnectionTask.fromSocket(Future<Socket>.value(secure), () {
                secure.destroy();
              });
            }
            return ConnectionTask.fromSocket(Future<Socket>.value(sock), () {
              sock.destroy();
            });
          }
          return Socket.startConnect(target.host, target.port);
        };

      final HttpClientRequest req = await customClient.openUrl(method, uri);
      req.followRedirects = followRedirects;
      req.headers.set('User-Agent', browserUserAgent);
      req.headers.set('Host', uri.host);
      headers.forEach(req.headers.set);
      if (body.isNotEmpty) {
        final List<int> bytes = utf8.encode(body);
        req.contentLength = bytes.length;
        req.add(bytes);
      }
      final HttpClientResponse resp = await req.close();
      final String respBody =
          await resp.transform(const Utf8Decoder(allowMalformed: true)).join();
      final Map<String, String> outHeaders = <String, String>{};
      resp.headers.forEach((String k, List<String> v) {
        if (v.isNotEmpty) outHeaders[k] = v.join(', ');
      });
      return MovieHttpResponse(
        statusCode: resp.statusCode,
        body: respBody,
        headers: outHeaders,
        effectiveUrl: url,
      );
    } catch (_) {
      return null;
    } finally {
      customClient?.close(force: false);
    }
  }

  @override
  void close() {
    _dio.close(force: true);
  }
}
