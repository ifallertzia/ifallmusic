import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/branding.dart';
import '../core/services/settings_service.dart';
import 'lrc_parser.dart';
import 'lyrics_query.dart';
import 'lyrics_translator.dart';

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

/// Multi-provider lyrics lookup.
///
/// The chain is ordered by [LyricsProviders] and is **additive only**: the
/// providers IfallMusic has always used (LRCLIB, then lyrics.ovh) stay first
/// and last, and every extra source is tried strictly in between as another
/// fallback rung. Any provider that answers with a 404, a timeout or a shape
/// we do not understand is skipped silently — a broken rung can never make
/// lyrics worse than they were.
class LyricsService {
  LyricsService({
    Dio? dio,
    this.persist = true,
    List<String>? providers,
  })  : _dio = dio ?? Dio(),
        providers = providers ?? List<String>.of(LyricsProviders.defaultOrder);
  static final instance = LyricsService();
  final Dio _dio;
  final bool persist;

  /// The rungs, in the order they are tried.
  List<String> providers;

  final _memory = <String, ({DateTime at, LyricsResult result})>{};

  /// Settings → Lyrics → "Translate lyrics into", synced at boot and when
  /// the sheet changes it. Empty means translation is off. Only the lookup
  /// result is translated — the on-device cache always keeps the original
  /// words, so turning translation off is instant and free.
  static String translateTarget = '';

  Future<LyricsResult> find({
    required String title,
    String artist = '',
    int durationSecs = 0,
    String? videoId,
    bool refresh = false,
    CancelToken? cancelToken,
    List<String>? useProviders,
  }) async {
    final LyricsResult raw = await _find(
      title: title,
      artist: artist,
      durationSecs: durationSecs,
      videoId: videoId,
      refresh: refresh,
      cancelToken: cancelToken,
      useProviders: useProviders,
    );
    if (translateTarget.isEmpty) return raw;
    return LyricsTranslator.translate(raw, translateTarget);
  }

  Future<LyricsResult> _find({
    required String title,
    String artist = '',
    int durationSecs = 0,
    String? videoId,
    bool refresh = false,
    CancelToken? cancelToken,
    List<String>? useProviders,
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
                        responseType:
                            url.endsWith('.lrc') ||
                                    url.contains('megalobiz.com') ||
                                    url.contains('kugou.com')
                                ? ResponseType.plain
                                : ResponseType.json,
                        headers: {
                          'Accept': 'application/json',
                          'User-Agent':
                              'IfallMusic/${SidifyBranding.versionLabel} (https://github.com/ifallertzia/ifallmusic)',
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
        // The extra rungs answer in more shapes than the original two did:
        // JSON objects, JSON arrays and plain-text (KuGou's LRC, Megalobiz's
        // HTML). Anything else is not a body we can read.
        if (data is! Map && data is! List && data is! String) {
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

    final List<String> chain = <String>{
      // The two original rungs are always present, whatever the listener chose.
      LyricsProviders.lrclib,
      ...(useProviders ?? providers),
      LyricsProviders.plainFallback,
    }.toList();

    // ---- rung 1: LRCLIB exact ------------------------------------------
    if (chain.contains(LyricsProviders.lrclib)) {
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
    }

    // ---- rung 2: LRCLIB search -----------------------------------------
    if (result == null &&
        chain.contains(LyricsProviders.lrclib) &&
        cancelToken?.isCancelled != true) {
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

    // ---- rungs 3…: every extra provider the listener enabled ------------
    for (final String provider in chain) {
      if (result != null) break;
      if (cancelToken?.isCancelled == true) break;
      if (provider == LyricsProviders.lrclib ||
          provider == LyricsProviders.plainFallback) continue;
      for (final LyricsQuery q in variants) {
        final LyricsResult? hit = await _tryProvider(
          provider,
          q,
          durationSecs: durationSecs,
          get: get,
        );
        if (hit != null) {
          result = hit;
          break;
        }
        if (cancelToken?.isCancelled == true) break;
      }
    }

    // ---- last rung: the plain-text fallback that has always been here ----
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

  /// One extra rung. Returns `null` — never an error — when the provider does
  /// not answer with something we can turn into lyrics.
  Future<LyricsResult?> _tryProvider(
    String provider,
    LyricsQuery q, {
    required int durationSecs,
    required Future<dynamic> Function(String, [Map<String, dynamic>?]) get,
  }) {
    switch (provider) {
      case LyricsProviders.lrcRed:
        return _lrcRed(q, get: get);
      case LyricsProviders.kugou:
        return _kuGou(q, durationSecs: durationSecs, get: get);
      case LyricsProviders.megalobiz:
        return _megalobiz(q, get: get);
      default:
        // Musixmatch and Genius both need an API key, and "Embedded" means the
        // lyrics travel inside a downloaded file — none of them are reachable
        // from here, so this rung simply yields to the next one.
        return Future<LyricsResult?>.value();
    }
  }

  Future<LyricsResult?> _lrcRed(
    LyricsQuery q, {
    required Future<dynamic> Function(String, [Map<String, dynamic>?]) get,
  }) async {
    final dynamic data = await get('https://lrc.red/api/get', <String, dynamic>{
      'title': q.title,
      'artist': q.artist,
    });
    if (data is! Map<String, dynamic>) return null;
    final String synced = (data['syncedLyrics'] as String? ?? '').trim();
    final String plain = (data['plainLyrics'] as String? ?? '').trim();
    if (synced.isEmpty && plain.isEmpty) return null;
    final List<LyricLine> lines = parseLrc(synced);
    return LyricsResult(
      plain: plain.isNotEmpty ? plain : lines.map((LyricLine l) => l.text).join('\n'),
      lines: usableSync(lines) ? lines : const <LyricLine>[],
      source: LyricsProviders.lrcRed,
    );
  }

  /// KuGou: search for the track, then pull the timed KRC for the closest hit.
  Future<LyricsResult?> _kuGou(
    LyricsQuery q, {
    required int durationSecs,
    required Future<dynamic> Function(String, [Map<String, dynamic>?]) get,
  }) async {
    final dynamic search = await get(
      'https://songsearch.kugou.com/song_search_v2',
      <String, dynamic>{
        'keyword': '${q.artist} - ${q.title}',
        'page': 1,
        'pagesize': 8,
        'platform': 'WebFilter',
        'userid': -1,
        'iscorrection': 1,
      },
    );
    final List<dynamic> rows = (search is Map && search['data'] is Map)
        ? (search['data']['lists'] as List? ?? const <dynamic>[])
        : const <dynamic>[];
    String? bestHash;
    int bestDelta = 1 << 30;
    for (final dynamic row in rows) {
      if (row is! Map) continue;
      final int length = row['duration'] is int
          ? row['duration'] as int
          : int.tryParse('${row['duration']}') ?? 0;
      final int delta = durationSecs > 0 ? (length - durationSecs).abs() : 0;
      if (delta < bestDelta && row['FileHash'] is String) {
        bestDelta = delta;
        bestHash = row['FileHash'] as String;
      }
    }
    if (bestHash == null || bestHash.isEmpty) return null;

    final dynamic detail = await get(
      'https://krcs.kugou.com/search',
      <String, dynamic>{
        'ver': 1,
        'man': 'yes',
        'client': 'mobi',
        'hash': bestHash,
        'keyword': q.title,
      },
    );
    if (detail is! Map) return null;
    final List<dynamic> candidates = detail['candidates'] as List? ?? const <dynamic>[];
    if (candidates.isEmpty) return null;
    final Map<dynamic, dynamic> first = candidates.first as Map;
    final String id = '${first['id'] ?? ''}';
    final String accessKey = '${first['accesskey'] ?? ''}';
    if (id.isEmpty || accessKey.isEmpty) return null;

    final dynamic raw = await get('https://lyrics.kugou.com/download', <String, dynamic>{
      'ver': 1,
      'client': 'pc',
      'id': id,
      'accesskey': accessKey,
      'fmt': 'lrc',
      'charset': 'utf8',
    });
    if (raw is! Map || raw['content'] is! String) return null;
    // KuGou returns base64-encoded LRC.
    final String decoded = _decodeBase64Utf8(raw['content'] as String);
    if (decoded.trim().isEmpty) return null;
    final List<LyricLine> lines = parseLrc(decoded);
    if (lines.isEmpty && decoded.trim().isEmpty) return null;
    return LyricsResult(
      plain: lines.map((LyricLine l) => l.text).join('\n'),
      lines: usableSync(lines) ? lines : const <LyricLine>[],
      source: LyricsProviders.kugou,
    );
  }

  /// Megalobiz: community-timed lines. The site is HTML, so this rung only
  /// accepts a page whose embedded LRC block parses cleanly.
  Future<LyricsResult?> _megalobiz(
    LyricsQuery q, {
    required Future<dynamic> Function(String, [Map<String, dynamic>?]) get,
  }) async {
    final dynamic search = await get(
      'https://www.megalobiz.com/search/all',
      <String, dynamic>{'qry': '${q.artist} ${q.title}'},
    );
    if (search is! String) return null;
    final RegExp link = RegExp(
      r'href="(/lrc/[^"\s]+\.lrc)"',
      caseSensitive: false,
    );
    final String? path = link.firstMatch(search)?.group(1);
    if (path == null) return null;
    final dynamic body = await get('https://www.megalobiz.com$path');
    if (body is! String || body.trim().isEmpty) return null;
    final List<LyricLine> lines = parseLrc(body);
    if (lines.isEmpty) return null;
    return LyricsResult(
      plain: lines.map((LyricLine l) => l.text).join('\n'),
      lines: usableSync(lines) ? lines : const <LyricLine>[],
      source: LyricsProviders.megalobiz,
    );
  }

  static String _decodeBase64Utf8(String source) {
    try {
      final List<int> bytes = base64.decode(base64.normalize(source));
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return '';
    }
  }

}