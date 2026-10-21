import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ifallmusic/movies/models/movie_models.dart';
import 'package:ifallmusic/movies/services/eon_html_parser.dart';
import 'package:ifallmusic/movies/services/eon_movies_service.dart';
import 'package:ifallmusic/movies/services/movie_download_service.dart';
import 'package:ifallmusic/movies/services/movie_http_client.dart';
import 'package:ifallmusic/movies/services/remote_zip.dart';

/// Minimal fake transport for ZIP-pack tests (GET routes for the resolver,
/// byte routes for Range reads, 404 POSTs for unused Dotflix actions).
class _FakeTransport implements MovieHttpTransport {
  final Map<String, MovieHttpResponse> getRoutes =
      <String, MovieHttpResponse>{};
  final Map<String, List<int>> rangeRoutes = <String, List<int>>{};

  @override
  final Dio streamDio = Dio();

  @override
  Future<MovieHttpResponse> get(
    String url, {
    Map<String, String> headers = const <String, String>{},
    bool followRedirects = true,
  }) async {
    final MovieHttpResponse? hit = getRoutes[url];
    if (hit != null) return hit;
    return MovieHttpResponse(
      statusCode: 404,
      body: '',
      headers: const <String, String>{},
      effectiveUrl: url,
    );
  }

  @override
  Future<MovieHttpResponse> post(
    String url, {
    required String body,
    Map<String, String> headers = const <String, String>{},
  }) async {
    return MovieHttpResponse(
      statusCode: 404,
      body: '',
      headers: const <String, String>{},
      effectiveUrl: url,
    );
  }

  @override
  Future<MovieRangeResponse> getRange(
    String url, {
    Map<String, String> headers = const <String, String>{},
    required int start,
    int? end,
  }) async {
    final List<int>? data = rangeRoutes[url];
    if (data == null) {
      return MovieRangeResponse(
        statusCode: 404,
        bytes: Uint8List(0),
        headers: const <String, String>{},
        effectiveUrl: url,
      );
    }
    if (start >= data.length) {
      return MovieRangeResponse(
        statusCode: 416,
        bytes: Uint8List(0),
        headers: <String, String>{'content-range': 'bytes */${data.length}'},
        effectiveUrl: url,
      );
    }
    final int last = end == null || end >= data.length ? data.length - 1 : end;
    return MovieRangeResponse(
      statusCode: 206,
      bytes: Uint8List.fromList(data.sublist(start, last + 1)),
      headers: <String, String>{
        'content-range': 'bytes $start-$last/${data.length}',
      },
      effectiveUrl: url,
    );
  }

  @override
  void close() {}
}

void _w16(BytesBuilder b, int v) {
  b.add(<int>[v & 0xFF, (v >> 8) & 0xFF]);
}

void _w32(BytesBuilder b, int v) {
  b.add(<int>[v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
}

void _w64(BytesBuilder b, int v) {
  _w32(b, v & 0xFFFFFFFF);
  _w32(b, (v >> 32) & 0xFFFFFFFF);
}

final List<int> _crcTable = List<int>.generate(256, (int i) {
  int c = i;
  for (int k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1);
  }
  return c;
});

int _crc32(List<int> data) {
  int crc = 0xFFFFFFFF;
  for (final int byte in data) {
    crc = (crc >> 8) ^ _crcTable[(crc ^ byte) & 0xFF];
  }
  return crc ^ 0xFFFFFFFF;
}

/// Builds a real ZIP (classic or ZIP64) holding [files], like the season
/// packs EonMovies hosts — one video file per episode.
Uint8List _buildTestZip(
  List<({String name, List<int> data, int method})> files, {
  bool zip64 = false,
  String comment = '',
}) {
  final BytesBuilder out = BytesBuilder();
  final BytesBuilder cd = BytesBuilder();

  for (final ({String name, List<int> data, int method}) f in files) {
    final List<int> nameBytes = utf8.encode(f.name);
    final List<int> compressed = f.method == 8
        ? ZLibCodec(raw: true).encoder.convert(f.data)
        : f.data;
    final int crc = _crc32(f.data);
    final int localOffset = out.length;

    _w32(out, 0x04034b50);
    _w16(out, zip64 ? 45 : 20);
    _w16(out, 0x800);
    _w16(out, f.method);
    _w16(out, 0);
    _w16(out, 0x21);
    _w32(out, crc);
    _w32(out, compressed.length);
    _w32(out, f.data.length);
    _w16(out, nameBytes.length);
    _w16(out, 0);
    out.add(nameBytes);
    out.add(compressed);

    final BytesBuilder extra = BytesBuilder();
    if (zip64) {
      _w16(extra, 0x0001);
      _w16(extra, 24);
      _w64(extra, f.data.length);
      _w64(extra, compressed.length);
      _w64(extra, localOffset);
    }
    _w32(cd, 0x02014b50);
    _w16(cd, zip64 ? 45 : 20);
    _w16(cd, zip64 ? 45 : 20);
    _w16(cd, 0x800);
    _w16(cd, f.method);
    _w16(cd, 0);
    _w16(cd, 0x21);
    _w32(cd, crc);
    _w32(cd, zip64 ? 0xFFFFFFFF : compressed.length);
    _w32(cd, zip64 ? 0xFFFFFFFF : f.data.length);
    _w16(cd, nameBytes.length);
    _w16(cd, extra.length);
    _w16(cd, 0);
    _w16(cd, 0);
    _w16(cd, 0);
    _w32(cd, 0);
    _w32(cd, zip64 ? 0xFFFFFFFF : localOffset);
    cd.add(nameBytes);
    cd.add(extra.takeBytes());
  }

  final int cdOffset = out.length;
  final Uint8List cdBytes = cd.takeBytes();
  out.add(cdBytes);

  final List<int> commentBytes = utf8.encode(comment);
  if (zip64) {
    final int zip64Offset = out.length;
    _w32(out, 0x06064b50);
    _w64(out, 44);
    _w16(out, 45);
    _w16(out, 45);
    _w32(out, 0);
    _w32(out, 0);
    _w64(out, files.length);
    _w64(out, files.length);
    _w64(out, cdBytes.length);
    _w64(out, cdOffset);
    _w32(out, 0x07064b50);
    _w32(out, 0);
    _w64(out, zip64Offset);
    _w32(out, 1);
    _w32(out, 0x06054b50);
    _w16(out, 0);
    _w16(out, 0);
    _w16(out, 0xFFFF);
    _w16(out, 0xFFFF);
    _w32(out, 0xFFFFFFFF);
    _w32(out, 0xFFFFFFFF);
    _w16(out, 0);
  } else {
    _w32(out, 0x06054b50);
    _w16(out, 0);
    _w16(out, 0);
    _w16(out, files.length);
    _w16(out, files.length);
    _w32(out, cdBytes.length);
    _w32(out, cdOffset);
    _w16(out, commentBytes.length);
    out.add(commentBytes);
  }
  return out.takeBytes();
}

ZipRangeFetch _fetchOver(Uint8List bytes, {bool supportRange = true}) {
  return (int start, int? end) async {
    if (!supportRange) {
      return ZipRangeResult(
        statusCode: 200,
        bytes: bytes,
        totalSize: bytes.length,
      );
    }
    final int last =
        end == null || end >= bytes.length ? bytes.length - 1 : end;
    return ZipRangeResult(
      statusCode: 206,
      bytes: Uint8List.fromList(bytes.sublist(start, last + 1)),
      totalSize: bytes.length,
    );
  };
}

const String _baseUrl = 'https://new4.eonmovies.click';

void main() {
  final List<int> ep1 = utf8.encode('episode-one-video-' * 300);
  final List<int> ep2 = utf8.encode('EP2!' * 1500);
  final List<int> ep10 =
      List<int>.generate(4096, (int i) => (i * 7) & 0xFF);

  List<({String name, List<int> data, int method})> sampleFiles() {
    return <({String name, List<int> data, int method})>[
      (name: 'Show.S01E01.720p.WEB-DL.mkv', data: ep1, method: 0),
      (name: 'Season 1/Show.S01E02.720p.WEB-DL.mkv', data: ep2, method: 8),
      (name: 'Show.S01E10.720p.WEB-DL.mkv', data: ep10, method: 8),
      (name: 'poster.jpg', data: <int>[1, 2, 3], method: 0),
    ];
  }

  group('RemoteZipReader', () {
    for (final bool zip64 in <bool>[false, true]) {
      test('lists entries of a ${zip64 ? 'ZIP64' : 'classic'} remote zip',
          () async {
        final Uint8List zip = _buildTestZip(sampleFiles(), zip64: zip64);
        final RemoteZipReader reader = RemoteZipReader(_fetchOver(zip));

        expect(await reader.probeTotalSize(), zip.length);
        final List<RemoteZipEntry> entries = await reader.readEntries();
        expect(entries.map((RemoteZipEntry e) => e.name), <String>[
          'Show.S01E01.720p.WEB-DL.mkv',
          'Season 1/Show.S01E02.720p.WEB-DL.mkv',
          'Show.S01E10.720p.WEB-DL.mkv',
          'poster.jpg',
        ]);
        expect(entries[0].compressionMethod, 0);
        expect(entries[1].compressionMethod, 8);
        expect(entries[1].uncompressedSize, ep2.length);
        expect(entries[2].uncompressedSize, ep10.length);
      });
    }

    test('round-trips stored and deflated episode bytes exactly', () async {
      final Uint8List zip = _buildTestZip(sampleFiles());
      final RemoteZipReader reader = RemoteZipReader(_fetchOver(zip));
      final List<RemoteZipEntry> entries = await reader.readEntries();

      final Directory dir = await Directory.systemTemp.createTemp('rzip_');
      addTearDown(() async {
        if (dir.existsSync()) await dir.delete(recursive: true);
      });

      for (final (int, List<int>) pair in <(int, List<int>)>[
        (0, ep1),
        (1, ep2),
        (2, ep10),
      ]) {
        final RemoteZipEntry entry = entries[pair.$1];
        final int dataOffset = await reader.dataOffsetFor(entry);
        final File part = File('${dir.path}/ep${pair.$1}.part');
        await part.writeAsBytes(
          zip.sublist(dataOffset, dataOffset + entry.compressedSize),
        );
        final File outFile = File('${dir.path}/ep${pair.$1}.mkv');
        final bool ok = await extractZipEntryFile(
          compressedFile: part,
          outFile: outFile,
          compressionMethod: entry.compressionMethod,
          expectedSize: entry.uncompressedSize,
        );
        expect(ok, isTrue);
        expect(await outFile.readAsBytes(), pair.$2);
      }
    });

    test('rejects servers without Range support', () async {
      final Uint8List zip = _buildTestZip(sampleFiles());
      final RemoteZipReader reader =
          RemoteZipReader(_fetchOver(zip, supportRange: false));
      await expectLater(
        reader.readEntries(),
        throwsA(isA<RemoteZipException>()),
      );
    });

    test('parses season/episode numbers from release names', () {
      expect(
        seasonEpisodeNumbersFromName('Show.Name.S01E07.720p.mkv'),
        (season: 1, episode: 7),
      );
      expect(
        seasonEpisodeNumbersFromName('Show - Season 2 Episode 13.mkv'),
        (season: 2, episode: 13),
      );
      expect(seasonEpisodeNumbersFromName('random-file.mkv').episode, 0);
      expect(isZipVideoEntryName('a/b/Ep.mkv'), isTrue);
      expect(isZipVideoEntryName('poster.jpg'), isFalse);
    });
  });

  group('series detail parser', () {
    test('direct episode quality rows stay episode-wise, pack stays ZIP',
        () {
      const String html = '''
<!doctype html><html><body>
  <h1>Direct Show - Season 1 (2026)</h1>
  <div class="meta-pills"><span class="meta-pill">Series</span></div>
  <div class="dl-row" data-dlname="Episode 1 720p HEVC">
    <span class="dl-row-name">Episode 1 720p HEVC</span><span>400 MB</span>
    <a href="/dl/111">Download</a>
  </div>
  <div class="dl-row" data-dlname="Episode 2 720p HEVC">
    <span class="dl-row-name">Episode 2 720p HEVC</span><span>410 MB</span>
    <a href="/dl/112">Download</a>
  </div>
  <div class="dl-row" data-dlname="396p HEVC">
    <span class="dl-row-name">396p HEVC</span><span>1.47 GB</span>
    <a href="/dl/113">Download</a>
  </div>
</body></html>
''';
      final MovieDetail detail = EonHtmlParser.parseDetail(
        html,
        pageUrl: '$_baseUrl/direct-show-season-1',
        baseUrl: _baseUrl,
      );

      expect(detail.isSeries, isTrue);
      expect(detail.episodeGroups, hasLength(3));

      final MovieEpisodeGroup pack = detail.episodeGroups.first;
      expect(pack.isCompletePack, isTrue);
      expect(pack.qualities.single.isZipPack, isTrue);
      expect(pack.qualities.single.displayQuality, '396p HEVC');

      final MovieEpisodeGroup epGroup = detail.episodeGroups[1];
      expect(epGroup.fullHeading, 'Season 1 • Episode 1');
      expect(epGroup.qualities.single.isZipPack, isFalse);
      expect(epGroup.qualities.single.episodeLabel, 'Episode 1');
      expect(detail.episodeGroups[2].fullHeading, 'Season 1 • Episode 2');
    });
  });

  group('ZIP pack episode-wise download (end-to-end)', () {
    test('lists episodes from the ZIP directory and downloads only one',
        () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final Directory tempDir =
          await Directory.systemTemp.createTemp('zip_ep_dl_');
      addTearDown(() async {
        if (tempDir.existsSync()) await tempDir.delete(recursive: true);
      });

      final Uint8List zipBytes = _buildTestZip(sampleFiles());
      const String zipUrl = 'https://pub-cdn.r2.dev/Show.S01.396p-EON.zip';

      final _FakeTransport transport = _FakeTransport();
      transport.rangeRoutes[zipUrl] = zipBytes;
      transport.getRoutes['$_baseUrl/dl/26803'] = const MovieHttpResponse(
        statusCode: 302,
        body: '',
        headers: <String, String>{
          'location': 'https://dotflix.fit/share/ZIPCODE01',
        },
        effectiveUrl: '$_baseUrl/dl/26803',
      );
      transport.getRoutes[
              'https://dotflix.fit/api/secure-cloudflare-url/ZIPCODE01'] =
          MovieHttpResponse(
        statusCode: 200,
        body: jsonEncode(<String, Object>{
          'success': true,
          'data': <String, String>{'cloudflare_url': zipUrl},
        }),
        headers: const <String, String>{},
        effectiveUrl:
            'https://dotflix.fit/api/secure-cloudflare-url/ZIPCODE01',
      );
      final String escapedRsc = jsonEncode(
        '1:{"initialShareData":{"filename":"Show.S01.396p-EON.zip","formattedFileSize":"1.47 GB"}}',
      );
      transport.getRoutes['https://dotflix.fit/share/ZIPCODE01'] =
          MovieHttpResponse(
        statusCode: 200,
        body: '<script>self.__next_f.push([1,$escapedRsc])</script>',
        headers: const <String, String>{},
        effectiveUrl: 'https://dotflix.fit/share/ZIPCODE01',
      );

      final EonMoviesService svc = EonMoviesService(transport: transport);

      const MovieQualityLink pack = MovieQualityLink(
        id: '26803',
        rawLabel: '396p HEVC',
        resolution: '396p',
        codec: 'HEVC',
        sizeLabel: '1.47 GB',
        dlUrl: '$_baseUrl/dl/26803',
        isZipPack: true,
        seasonLabel: 'Season 1',
        episodeLabel: 'All Episodes (ZIP)',
      );

      // 1. Episode listing comes from range reads of the ZIP directory.
      final MovieZipPackListing listing = await svc.listZipPackEpisodes(
        pack,
        fallbackTitle: 'Show',
      );
      expect(listing.zipFileName, 'Show.S01.396p-EON.zip');
      expect(listing.episodes, hasLength(3)); // poster.jpg is excluded
      expect(
        listing.episodes.map((MovieZipEpisode e) => e.episodeNumber),
        <int>[1, 2, 10],
      );
      expect(listing.episodes[1].episodeLabel, 'Episode 2');
      expect(listing.episodes[1].fileName, 'Show.S01E02.720p.WEB-DL.mkv');

      // 2. Downloading episode 2 fetches only its byte window and inflates
      // it into a playable .mkv with the exact original content.
      final MovieDownloadService downloader =
          await MovieDownloadService.create(
        prefs,
        moviesService: svc,
        customDirectory: tempDir,
        streamOpener: ({
          required String url,
          required Map<String, String> headers,
          required CancelToken cancelToken,
        }) async {
          final RegExpMatch? m = RegExp(r'bytes=(\d+)-(\d+)')
              .firstMatch(headers['Range'] ?? '');
          if (m == null) {
            return OpenedByteStream(
              statusCode: 200,
              contentType: 'application/zip',
              contentLength: zipBytes.length,
              stream: Stream<List<int>>.value(zipBytes),
            );
          }
          final int s = int.parse(m.group(1)!);
          final int e = int.parse(m.group(2)!);
          final List<int> slice = zipBytes.sublist(s, e + 1);
          return OpenedByteStream(
            statusCode: 206,
            contentType: 'application/zip',
            contentLength: slice.length,
            stream: Stream<List<int>>.value(slice),
          );
        },
      );
      addTearDown(downloader.dispose);

      const MovieDetail detail = MovieDetail(
        title: 'Show - Season 1',
        cleanTitle: 'Show',
        type: MovieMediaType.series,
        webUrl: '$_baseUrl/show-season-1',
        defaultSeasonLabel: 'Season 1',
      );
      final MovieQualityLink epQuality =
          EonMoviesService.qualityForZipEpisode(pack, listing.episodes[1]);
      expect(epQuality.id, '26803__zep1');
      expect(epQuality.isZipPack, isFalse);
      expect(epQuality.zipEntryName, 'Season 1/Show.S01E02.720p.WEB-DL.mkv');

      await downloader.enqueueDownload(detail: detail, quality: epQuality);
      for (int i = 0; i < 80; i++) {
        if (downloader.items.first.status == MovieDownloadStatus.completed) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }

      final MovieDownloadItem finished = downloader.items.first;
      expect(finished.status, MovieDownloadStatus.completed,
          reason: finished.errorMessage);
      expect(finished.isZipEntryEpisode, isTrue);
      expect(finished.isZip, isFalse);
      expect(finished.fileName, 'Show.S01E02.720p.WEB-DL.mkv');
      expect(finished.episodeLabel, 'Episode 2');
      expect(await File(finished.savedPath).readAsBytes(), ep2);
    });
  });
}
