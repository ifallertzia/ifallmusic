import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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

/// Binary response of an HTTP Range request.
class MovieRangeResponse {
  const MovieRangeResponse({
    required this.statusCode,
    required this.bytes,
    required this.headers,
    required this.effectiveUrl,
  });

  final int statusCode;
  final Uint8List bytes;
  final Map<String, String> headers;
  final String effectiveUrl;

  String? header(String name) {
    final String lower = name.toLowerCase();
    for (final MapEntry<String, String> entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  /// Total size of the full remote file parsed from
  /// `Content-Range: bytes <start>-<end>/<total>`, or -1 when unavailable.
  int get totalSize {
    final String? range = header('content-range');
    if (range == null) return -1;
    final RegExpMatch? m = RegExp(r'/(\d+)\s*$').firstMatch(range.trim());
    if (m == null) return -1;
    return int.tryParse(m.group(1)!) ?? -1;
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

  /// Fetches bytes `[start, end]` (inclusive) of a remote binary file.
  /// `end == null` fetches through the end of the file. A server that
  /// ignores the Range header answers 200 with the whole file — callers
  /// must treat anything other than 206 as "range unsupported".
  Future<MovieRangeResponse> getRange(
    String url, {
    Map<String, String> headers = const <String, String>{},
    required int start,
    int? end,
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

  @override
  Future<MovieRangeResponse> getRange(
    String url, {
    Map<String, String> headers = const <String, String>{},
    required int start,
    int? end,
  }) async {
    final Response<List<int>> res = await _dio.get<List<int>>(
      url,
      options: Options(
        headers: <String, String>{
          ...headers,
          'Range': end == null ? 'bytes=$start-' : 'bytes=$start-$end',
          // Range offsets are only meaningful on the identity encoding.
          'Accept-Encoding': 'identity',
        },
        followRedirects: true,
        maxRedirects: 5,
        responseType: ResponseType.bytes,
        receiveTimeout: const Duration(seconds: 60),
        validateStatus: (int? s) => s != null && s < 500,
      ),
    );
    return MovieRangeResponse(
      statusCode: res.statusCode ?? 0,
      bytes: Uint8List.fromList(res.data ?? const <int>[]),
      headers: _flattenHeaders(res.headers),
      effectiveUrl: res.realUri.toString(),
    );
  }

  /// Fetches a small binary resource — a poster — with the same reach as the
  /// catalog pages themselves.
  ///
  /// Posters are normally loaded by the image cache through the system
  /// resolver, which is exactly what fails on networks that poison DNS for the
  /// catalog's hosts: the page arrives (through the DNS-over-HTTPS fallback
  /// here) while every thumbnail on it stays blank. This goes direct first and
  /// then over DNS-over-HTTPS, with a browser User-Agent, and only returns
  /// bytes that really are an image — an ISP block page answered with 200 is
  /// not mistaken for one.
  Future<Uint8List?> getBytes(
    String url, {
    Map<String, String> headers = const <String, String>{},
    int maxBytes = 8 * 1024 * 1024,
  }) async {
    final Uri? uri = Uri.tryParse(url.trim());
    if (uri == null ||
        !(uri.scheme == 'http' || uri.scheme == 'https') ||
        uri.host.isEmpty) {
      return null;
    }
    try {
      final Response<List<int>> res = await _dio.get<List<int>>(
        uri.toString(),
        options: Options(
          headers: headers,
          followRedirects: true,
          maxRedirects: 5,
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 20),
          validateStatus: (int? s) => s != null && s < 600,
        ),
      );
      final int status = res.statusCode ?? 0;
      final List<int> data = res.data ?? const <int>[];
      if (status >= 200 &&
          status < 300 &&
          data.length <= maxBytes &&
          looksLikeImage(data)) {
        return data is Uint8List ? data : Uint8List.fromList(data);
      }
    } on DioException catch (_) {
      // Fall through to DNS-over-HTTPS below.
    } catch (_) {
      return null;
    }
    return _bytesOverDoh(uri, headers: headers, maxBytes: maxBytes);
  }

  /// True when [data] starts like a JPEG, PNG, GIF, WebP, BMP or AVIF/HEIF.
  static bool looksLikeImage(List<int> data) {
    if (data.length < 12) return false;
    bool starts(List<int> magic, [int offset = 0]) {
      for (int i = 0; i < magic.length; i++) {
        if (data[offset + i] != magic[i]) return false;
      }
      return true;
    }

    if (starts(const <int>[0xFF, 0xD8, 0xFF])) return true; // JPEG
    if (starts(const <int>[0x89, 0x50, 0x4E, 0x47])) return true; // PNG
    if (starts(const <int>[0x47, 0x49, 0x46, 0x38])) return true; // GIF
    if (starts(const <int>[0x42, 0x4D])) return true; // BMP
    if (starts(const <int>[0x52, 0x49, 0x46, 0x46]) &&
        starts(const <int>[0x57, 0x45, 0x42, 0x50], 8)) {
      return true; // WebP
    }
    if (starts(const <int>[0x66, 0x74, 0x79, 0x70], 4)) return true; // AVIF
    return false;
  }

  Future<Uint8List?> _bytesOverDoh(
    Uri uri, {
    required Map<String, String> headers,
    required int maxBytes,
  }) async {
    final InternetAddress? addr = await _resolveViaDoh(uri.host);
    if (addr == null) return null;

    HttpClient? client;
    try {
      final int port =
          uri.hasPort ? uri.port : (uri.scheme == 'https' ? 443 : 80);
      client = HttpClient(context: SecurityContext.defaultContext)
        ..connectionTimeout = const Duration(seconds: 10)
        ..connectionFactory =
            (Uri target, String? proxyHost, int? proxyPort) async {
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
              return ConnectionTask.fromSocket(
                Future<Socket>.value(secure),
                () {
                  secure.destroy();
                },
              );
            }
            return ConnectionTask.fromSocket(Future<Socket>.value(sock), () {
              sock.destroy();
            });
          }
          return Socket.startConnect(target.host, target.port);
        };

      final HttpClientRequest req = await client.getUrl(uri);
      req.followRedirects = true;
      req.maxRedirects = 5;
      req.headers.set('User-Agent', browserUserAgent);
      headers.forEach(req.headers.set);
      final HttpClientResponse resp =
          await req.close().timeout(const Duration(seconds: 20));
      if (resp.statusCode < 200 || resp.statusCode >= 300) {
        await resp.drain<void>().timeout(const Duration(seconds: 5));
        return null;
      }
      final BytesBuilder builder = BytesBuilder(copy: false);
      await for (final List<int> chunk
          in resp.timeout(const Duration(seconds: 20))) {
        builder.add(chunk);
        if (builder.length > maxBytes) return null;
      }
      final Uint8List bytes = builder.takeBytes();
      return looksLikeImage(bytes) ? bytes : null;
    } catch (_) {
      return null;
    } finally {
      client?.close(force: true);
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
