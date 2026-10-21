import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Result of one HTTP `Range: bytes=start-end` request.
class ZipRangeResult {
  const ZipRangeResult({
    required this.statusCode,
    required this.bytes,
    this.totalSize = -1,
  });

  final int statusCode;
  final Uint8List bytes;

  /// Total size of the remote file, parsed from `Content-Range`, or -1 when
  /// the server did not report it.
  final int totalSize;
}

/// Fetches bytes `[start, end]` (inclusive) of a remote file. `end == null`
/// means "to the end of the file".
typedef ZipRangeFetch = Future<ZipRangeResult> Function(int start, int? end);

class RemoteZipException implements Exception {
  const RemoteZipException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// One file entry of a remote ZIP archive, as listed in its central
/// directory.
class RemoteZipEntry {
  const RemoteZipEntry({
    required this.name,
    required this.compressionMethod,
    required this.compressedSize,
    required this.uncompressedSize,
    required this.localHeaderOffset,
    required this.isDirectory,
    required this.isEncrypted,
  });

  final String name;

  /// 0 = stored (no compression), 8 = deflate.
  final int compressionMethod;
  final int compressedSize;
  final int uncompressedSize;
  final int localHeaderOffset;
  final bool isDirectory;
  final bool isEncrypted;
}

/// Reads the table of contents of a ZIP file hosted on a Range-capable HTTP
/// server **without downloading the archive**.
///
/// A ZIP stores its file list (names, sizes, byte offsets) in a "central
/// directory" at the very end of the file, so 3-4 small range requests are
/// enough to learn exactly which episodes a season pack contains and where
/// each episode's bytes live. Episode-wise download then becomes a single
/// range request stream for that episode's byte window.
///
/// Supports classic ZIP and ZIP64 (season packs routinely exceed 4 GB),
/// archives with trailing comments, and entries in sub-folders.
class RemoteZipReader {
  RemoteZipReader(this._fetch);

  final ZipRangeFetch _fetch;

  static const int _sigEocd = 0x06054b50;
  static const int _sigZip64Locator = 0x07064b50;
  static const int _sigZip64Eocd = 0x06064b50;
  static const int _sigCentralHeader = 0x02014b50;
  static const int _sigLocalHeader = 0x04034b50;
  static const int _tailBytes = 70 * 1024;
  static const int _maxEntries = 100000;
  static const int _maxCentralDirectoryBytes = 32 * 1024 * 1024;

  static int _u16(Uint8List b, int o) => b[o] | (b[o + 1] << 8);

  static int _u32(Uint8List b, int o) =>
      b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);

  static int _u64(Uint8List b, int o) => _u32(b, o) | (_u32(b, o + 4) << 32);

  Future<Uint8List> _range(int start, int end) async {
    final ZipRangeResult res = await _fetch(start, end);
    if (res.statusCode == 200) {
      throw const RemoteZipException(
        'This server does not support partial (Range) downloads — episode-wise download is not possible on this mirror.',
      );
    }
    if (res.statusCode != 206) {
      throw RemoteZipException(
        'Range request failed with HTTP ${res.statusCode}.',
      );
    }
    return res.bytes;
  }

  /// Total byte size of the remote file, learned from a 1-byte probe.
  Future<int> probeTotalSize() async {
    final ZipRangeResult probe = await _fetch(0, 0);
    if (probe.statusCode == 200) {
      throw const RemoteZipException(
        'This server does not support partial (Range) downloads — episode-wise download is not possible on this mirror.',
      );
    }
    if (probe.statusCode != 206) {
      throw RemoteZipException(
        'Range request failed with HTTP ${probe.statusCode}.',
      );
    }
    if (probe.totalSize <= 0) {
      throw const RemoteZipException(
        'Server did not report the ZIP size (Content-Range missing).',
      );
    }
    return probe.totalSize;
  }

  /// Lists every entry of the remote ZIP. Costs a handful of tiny range
  /// requests regardless of whether the archive is 1 GB or 30 GB.
  Future<List<RemoteZipEntry>> readEntries() async {
    final int total = await probeTotalSize();

    final int tailLen = total < _tailBytes ? total : _tailBytes;
    final Uint8List tail = await _range(total - tailLen, total - 1);
    if (tail.length < 22) {
      throw const RemoteZipException('File is too small to be a ZIP archive.');
    }

    int eocd = -1;
    for (int i = tail.length - 22; i >= 0; i--) {
      if (_u32(tail, i) == _sigEocd && i + 22 + _u16(tail, i + 20) == tail.length) {
        eocd = i;
        break;
      }
    }
    if (eocd < 0) {
      throw const RemoteZipException(
        'ZIP end record not found — file is corrupt or not a ZIP.',
      );
    }

    int entryCount = _u16(tail, eocd + 10);
    int cdSize = _u32(tail, eocd + 12);
    int cdOffset = _u32(tail, eocd + 16);

    if (entryCount == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF) {
      final int loc = eocd - 20;
      if (loc < 0 || _u32(tail, loc) != _sigZip64Locator) {
        throw const RemoteZipException('ZIP64 locator record not found.');
      }
      final int zip64Offset = _u64(tail, loc + 8);
      final Uint8List rec = await _range(zip64Offset, zip64Offset + 55);
      if (rec.length < 56 || _u32(rec, 0) != _sigZip64Eocd) {
        throw const RemoteZipException('ZIP64 end record is invalid.');
      }
      entryCount = _u64(rec, 32);
      cdSize = _u64(rec, 40);
      cdOffset = _u64(rec, 48);
    }

    if (entryCount <= 0 || entryCount > _maxEntries) {
      throw RemoteZipException('Implausible ZIP entry count ($entryCount).');
    }
    if (cdSize <= 0 || cdSize > _maxCentralDirectoryBytes) {
      throw const RemoteZipException('ZIP central directory is too large.');
    }

    final BytesBuilder cdBuilder = BytesBuilder(copy: false);
    int pos = cdOffset;
    final int cdEnd = cdOffset + cdSize;
    while (pos < cdEnd) {
      int chunkEnd = pos + 1024 * 1024 - 1;
      if (chunkEnd > cdEnd - 1) chunkEnd = cdEnd - 1;
      final Uint8List chunk = await _range(pos, chunkEnd);
      if (chunk.isEmpty) {
        throw const RemoteZipException('ZIP central directory was truncated.');
      }
      cdBuilder.add(chunk);
      pos += chunk.length;
    }
    final Uint8List cd = cdBuilder.takeBytes();

    final List<RemoteZipEntry> entries = <RemoteZipEntry>[];
    int o = 0;
    for (int n = 0; n < entryCount; n++) {
      if (o + 46 > cd.length || _u32(cd, o) != _sigCentralHeader) {
        throw const RemoteZipException('ZIP central directory is corrupt.');
      }
      final int flags = _u16(cd, o + 8);
      final int method = _u16(cd, o + 10);
      int compressed = _u32(cd, o + 20);
      int uncompressed = _u32(cd, o + 24);
      final int nameLen = _u16(cd, o + 28);
      final int extraLen = _u16(cd, o + 30);
      final int commentLen = _u16(cd, o + 32);
      int localOffset = _u32(cd, o + 42);

      final int nameStart = o + 46;
      final int extraStart = nameStart + nameLen;
      if (extraStart + extraLen > cd.length) {
        throw const RemoteZipException('ZIP central directory is corrupt.');
      }
      final Uint8List nameBytes =
          Uint8List.sublistView(cd, nameStart, nameStart + nameLen);
      final String name = utf8.decode(nameBytes, allowMalformed: true);

      // ZIP64 extra field (0x0001) carries real values for every field that
      // the fixed-size header had to clamp to 0xFFFFFFFF, in fixed order.
      int eo = extraStart;
      final int extraEnd = extraStart + extraLen;
      while (eo + 4 <= extraEnd) {
        final int tag = _u16(cd, eo);
        final int size = _u16(cd, eo + 2);
        final int body = eo + 4;
        if (tag == 0x0001 && body + size <= extraEnd) {
          int p = body;
          if (uncompressed == 0xFFFFFFFF && p + 8 <= body + size) {
            uncompressed = _u64(cd, p);
            p += 8;
          }
          if (compressed == 0xFFFFFFFF && p + 8 <= body + size) {
            compressed = _u64(cd, p);
            p += 8;
          }
          if (localOffset == 0xFFFFFFFF && p + 8 <= body + size) {
            localOffset = _u64(cd, p);
          }
        }
        eo = body + size;
      }

      entries.add(
        RemoteZipEntry(
          name: name,
          compressionMethod: method,
          compressedSize: compressed,
          uncompressedSize: uncompressed,
          localHeaderOffset: localOffset,
          isDirectory: name.endsWith('/'),
          isEncrypted: (flags & 0x1) != 0,
        ),
      );
      o += 46 + nameLen + extraLen + commentLen;
    }
    return entries;
  }

  /// Absolute byte offset at which [entry]'s (still-compressed) data begins
  /// inside the remote file: local header offset + 30-byte fixed header +
  /// its variable-length name & extra fields.
  Future<int> dataOffsetFor(RemoteZipEntry entry) async {
    final Uint8List hdr =
        await _range(entry.localHeaderOffset, entry.localHeaderOffset + 29);
    if (hdr.length < 30 || _u32(hdr, 0) != _sigLocalHeader) {
      throw const RemoteZipException('Episode local ZIP header is invalid.');
    }
    return entry.localHeaderOffset + 30 + _u16(hdr, 26) + _u16(hdr, 28);
  }
}

/// Turns a fully-downloaded compressed ZIP entry segment on disk into the
/// final playable video file.
///
/// Stored entries (method 0) are already byte-identical to the video, so
/// this is a plain copy; deflated entries (method 8) are raw-inflated.
/// [shouldAbort] is polled between chunks so pause/cancel stays responsive
/// even on multi-GB episodes; returns false when aborted (partial output
/// file removed), true on success.
Future<bool> extractZipEntryFile({
  required File compressedFile,
  required File outFile,
  required int compressionMethod,
  required int expectedSize,
  bool Function()? shouldAbort,
}) async {
  if (compressionMethod != 0 && compressionMethod != 8) {
    throw RemoteZipException(
      'ZIP entry compression method $compressionMethod is not supported.',
    );
  }

  Stream<List<int>> source = compressedFile.openRead();
  if (compressionMethod == 8) {
    source = source.transform(ZLibCodec(raw: true).decoder);
  }

  final IOSink sink = outFile.openWrite(mode: FileMode.write);
  int written = 0;
  bool aborted = false;
  try {
    await for (final List<int> chunk in source) {
      if (shouldAbort != null && shouldAbort()) {
        aborted = true;
        break;
      }
      sink.add(chunk);
      written += chunk.length;
    }
    await sink.flush();
  } finally {
    await sink.close();
  }

  if (aborted) {
    try {
      if (outFile.existsSync()) await outFile.delete();
    } catch (_) {}
    return false;
  }
  if (expectedSize > 0 && written != expectedSize) {
    try {
      if (outFile.existsSync()) await outFile.delete();
    } catch (_) {}
    throw RemoteZipException(
      'Extracted episode size mismatch '
      '($written / $expectedSize bytes) — the download may be corrupt.',
    );
  }
  return true;
}

/// Parses season / episode numbers out of a release-style file name such as
/// `Show.Name.S01E07.720p.WEB-DL.mkv` or `Show - Season 2 Episode 3.mkv`.
/// Returns 0 for whichever part is not present.
({int season, int episode}) seasonEpisodeNumbersFromName(String name) {
  final RegExpMatch? both = RegExp(
    r'S(\d{1,2})E(\d{1,3})',
    caseSensitive: false,
  ).firstMatch(name);
  if (both != null) {
    return (
      season: int.tryParse(both.group(1)!) ?? 0,
      episode: int.tryParse(both.group(2)!) ?? 0,
    );
  }
  final RegExpMatch? season = RegExp(
    r'(?:Season|S)[\s._-]*0*(\d{1,2})\b',
    caseSensitive: false,
  ).firstMatch(name);
  final RegExpMatch? episode = RegExp(
    r'(?:Episode|Ep\.?|E)[\s._-]*0*(\d{1,3})\b',
    caseSensitive: false,
  ).firstMatch(name.replaceAll(RegExp(r'S\d{1,2}E', caseSensitive: false), 'E'));
  return (
    season: season != null ? (int.tryParse(season.group(1)!) ?? 0) : 0,
    episode: episode != null ? (int.tryParse(episode.group(1)!) ?? 0) : 0,
  );
}

/// True for file names that look like playable episode videos inside a pack.
bool isZipVideoEntryName(String name) {
  return RegExp(
    r'\.(mkv|mp4|avi|webm|mov|m4v|ts|wmv)$',
    caseSensitive: false,
  ).hasMatch(name.trim());
}
