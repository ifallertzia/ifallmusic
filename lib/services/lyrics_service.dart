import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/branding.dart';
import 'lrc_parser.dart';
import 'lyrics_query.dart';

export 'lrc_parser.dart';
export 'lyrics_query.dart';

enum LyricsStatus { found, notFound, unavailable }

class LyricsResult {
  const LyricsResult({
    this.plain = '',
    this.lines = const [],
    this.source = '',
    this.instrumental = false,
    this.status = LyricsStatus.found,
  });
  final String plain, source;
  final List<LyricLine> lines;
  final bool instrumental;
  final LyricsStatus status;
  bool get synced => usableSync(lines);
  factory LyricsResult.fromRecord(Map<String, dynamic> record) {
    final parsed = parseLrc(record['syncedLyrics'] as String? ?? '');
    final plain = (record['plainLyrics'] as String? ?? '').trim();
    return LyricsResult(
      plain: plain.isNotEmpty ? plain : parsed.map((l) => l.text).join('\n'),
      lines: usableSync(parsed) ? parsed : [],
      source: 'LRCLIB',
      instrumental: record['instrumental'] == true,
    );
  }
  Map<String, dynamic> toJson() => {
    'plain': plain,
    'lines': lines.map((l) => l.toJson()).toList(),
    'source': source,
    'instrumental': instrumental,
    'status': status.name,
  };
  factory LyricsResult.fromJson(Map<String, dynamic> json) => LyricsResult(
    plain: json['plain'] as String? ?? '',
    source: json['source'] as String? ?? '',
    instrumental: json['instrumental'] == true,
    status: json['status'] == 'notFound'
        ? LyricsStatus.notFound
        : LyricsStatus.found,
    lines: (json['lines'] as List? ?? []).take(1200).map((l) {
      var text = l['text'] as String;
      if (text.length > 500) text = text.substring(0, 500);
      return LyricLine(l['ms'] as int, text);
    }).toList(),
  );
}

class LyricsService {
  LyricsService({Dio? dio, this.persist = true}) : _dio = dio ?? Dio();
  static final instance = LyricsService();
  final Dio _dio;
  final bool persist;
  final _memory = <String, ({DateTime at, LyricsResult result})>{};
  Future<LyricsResult> find({
    required String title,
    String artist = '',
    int durationSecs = 0,
    String? videoId,
    bool refresh = false,
    CancelToken? cancelToken,
  }) async {
    final key =
        videoId ?? '${normalize(title)}|${normalize(artist)}|$durationSecs';
    final storageKey = 'ifall.lyrics.$key';
    SharedPreferences? prefs;
    if (persist) {
      try {
        prefs = await SharedPreferences.getInstance();
      } catch (_) {}
    }
    var cached = _memory[key];
    if (cached == null && prefs != null) {
      try {
        final json =
            jsonDecode(prefs.getString(storageKey) ?? '')
                as Map<String, dynamic>;
        cached = (
          at: DateTime.fromMillisecondsSinceEpoch(json['at'] as int),
          result: LyricsResult.fromJson(json['result'] as Map<String, dynamic>),
        );
      } catch (_) {}
    }
    if (!refresh &&
        cached != null &&
        DateTime.now().difference(cached.at) <
            (cached.result.status == LyricsStatus.notFound
                ? const Duration(hours: 1)
                : const Duration(days: 7)))
      return cached.result;
    bool outage = false;
    Future<dynamic> get(String url, [Map<String, dynamic>? query]) async {
      final token = CancelToken();
      // A separate token per request lets a timeout abort its own connection.
      cancelToken?.whenCancel.then((_) => token.cancel('lookup cancelled'));
      if (cancelToken?.isCancelled == true) return null;
      try {
        final data =
            (await _dio
                    .get<dynamic>(
                      url,
                      queryParameters: query,
                      cancelToken: token,
                      options: Options(
                        sendTimeout: const Duration(seconds: 4),
                        receiveTimeout: const Duration(seconds: 4),
                        headers: {
                          'Accept': 'application/json',
                          'User-Agent':
                              'IfallMusic/${IfallBranding.versionLabel} (https://github.com/ifallertzia/Saxify-v1)',
                        },
                      ),
                    )
                    .timeout(
                      const Duration(seconds: 4),
                      onTimeout: () {
                        token.cancel('timeout');
                        throw Exception('timeout');
                      },
                    ))
                .data;
        if (url.endsWith('/search') ? data is! List : data is! Map) {
          throw const FormatException('Invalid lyrics response');
        }
        return data;
      } on DioException catch (e) {
        if (e.response?.statusCode != 404) outage = true;
      } catch (_) {
        outage = true;
      }
      return null;
    }

    final variants = queryVariants(title: title, artist: artist);
    if (variants.isEmpty)
      return const LyricsResult(status: LyricsStatus.notFound);
    LyricsResult? result;
    final exact = await Future.wait(
      variants.map(
        (q) => get('https://lrclib.net/api/get', {
          'track_name': q.title,
          'artist_name': q.artist,
          if (durationSecs > 0) 'duration': durationSecs,
        }),
      ),
    );
    for (final r in exact) {
      if (r is Map<String, dynamic>) {
        final hit = LyricsResult.fromRecord(r);
        if (hit.instrumental || hit.plain.isNotEmpty) {
          result = hit;
          break;
        }
      }
    }
    if (result == null && cancelToken?.isCancelled != true) {
      final searched = await Future.wait(
        variants
            .map((q) => q.title)
            .toSet()
            .map(
              (t) => get('https://lrclib.net/api/search', {'track_name': t}),
            ),
      );
      final records = searched
          .whereType<List>()
          .expand((l) => l)
          .whereType<Map<String, dynamic>>()
          .toList();
      final match = rankLyrics(records, variants, durationSecs);
      if (match != null) result = LyricsResult.fromRecord(match);
    }
    if (result == null && cancelToken?.isCancelled != true) {
      final plain = await Future.wait(
        variants
            .where((q) => q.artist.isNotEmpty)
            .map(
              (q) => get(
                'https://api.lyrics.ovh/v1/${Uri.encodeComponent(q.artist)}/${Uri.encodeComponent(q.title)}',
              ),
            ),
      );
      for (final r in plain) {
        if (r is Map &&
            r['lyrics'] is String &&
            (r['lyrics'] as String).trim().isNotEmpty) {
          result = LyricsResult(
            plain: (r['lyrics'] as String).trim(),
            source: 'lyrics.ovh',
          );
          break;
        }
      }
    }
    result ??= LyricsResult(
      status: outage ? LyricsStatus.unavailable : LyricsStatus.notFound,
    );
    if (result.status != LyricsStatus.unavailable &&
        cancelToken?.isCancelled != true) {
      final at = DateTime.now();
      if (_memory.length >= 100) _memory.remove(_memory.keys.first);
      _memory[key] = (at: at, result: result);
      if (prefs != null) {
        try {
          final keys = prefs
              .getKeys()
              .where((k) => k.startsWith('ifall.lyrics.'))
              .toList();
          if (keys.length >= 100 && !keys.contains(storageKey))
            await prefs.remove(keys.first);
          await prefs.setString(
            storageKey,
            jsonEncode({
              'at': at.millisecondsSinceEpoch,
              'result': result.toJson(),
            }),
          );
        } catch (_) {
          /* Cache storage must not hide fetched lyrics. */
        }
      }
    }
    return result;
  }
}
