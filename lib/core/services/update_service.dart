import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// Everything the in-app updater needs: version + build-number compare against
/// GitHub Releases, in-app APK download with progress, and hand-off to the
/// system installer.
///
/// Two things decide whether an update is offered:
///   1. the semantic version (`2.4.0`), and
///   2. the build number (`+13`) — pubspec's `+N`, which Android uses as
///      `versionCode`.
///
/// Comparing the build number too matters because a release can be rebuilt
/// with the same `x.y.z` and a higher versionCode. Reading only the tag would
/// miss it, and Android would still accept the new APK as an update.
class UpdateService {
  /// This is the repository that publishes the canonical versioned APK release
  /// consumed by the in-app updater.
  static const List<String> releaseRepos = <String>[
    'ifallertzia/Saxify-v1',
  ];

  /// Canonical APK asset name. `build.yml` always uploads the APK under this
  /// exact name so the updater can find it without guessing.
  static const String _apkAssetName = 'app-release.apk';

  /// Machine-readable version manifest published alongside the APK. Optional —
  /// the updater falls back to the release tag when it is absent.
  static const String _manifestAssetName = 'latest.json';

  final http.Client _client = http.Client();

  PackageInfo? _packageInfo;

  Future<PackageInfo> _info() async {
    _packageInfo ??= await PackageInfo.fromPlatform();
    return _packageInfo!;
  }

  Future<String> currentVersion() async => (await _info()).version;

  /// Android `versionCode`, i.e. pubspec's `+N`. Zero when unavailable.
  Future<int> currentBuildNumber() async =>
      int.tryParse((await _info()).buildNumber) ?? 0;

  /// Returns null when we could not reach any release endpoint.
  Future<UpdateInfo?> check() async {
    final PackageInfo info = await _info();
    final String current = info.version;
    final int currentBuild = int.tryParse(info.buildNumber) ?? 0;

    for (final String repo in releaseRepos) {
      try {
        final http.Response res = await _client
            .get(
              Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
              headers: const <String, String>{
                'Accept': 'application/vnd.github+json',
              },
            )
            .timeout(const Duration(seconds: 12));

        if (res.statusCode != 200) continue;

        final Map<String, dynamic> json =
            jsonDecode(res.body) as Map<String, dynamic>;
        final String tag = (json['tag_name'] as String? ?? '').trim();
        if (tag.isEmpty) continue;

        final String? apkUrl = _findAssetUrl(json, _apkAssetName, '.apk');
        final int? size = _findApkSize(json);
        final String notes = json['body'] as String? ?? '';

        // Prefer the explicit manifest: it carries the build number, which the
        // tag alone does not.
        final _Manifest? manifest =
            await _readManifest(_findAssetUrl(json, _manifestAssetName, null));

        final String latestVersion =
            manifest?.version ?? _stripV(tag);
        final int? latestBuild = manifest?.build;

        return UpdateInfo(
          currentVersion: current,
          currentBuildNumber: currentBuild,
          latestVersion: latestVersion,
          latestBuildNumber: latestBuild,
          apkUrl: apkUrl,
          notes: notes,
          sizeBytes: size,
          releaseUrl: json['html_url'] as String?,
          buildNumberFromManifest: manifest != null,
        );
      } catch (e) {
        debugPrint('update check ($repo) failed: $e');
      }
    }
    return null;
  }

  Future<_Manifest?> _readManifest(String? url) async {
    if (url == null || url.isEmpty) return null;
    try {
      final http.Response res = await _client
          .get(Uri.parse(url), headers: const <String, String>{
            'Accept': 'application/json',
          })
          .timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final Map<String, dynamic> json =
          jsonDecode(res.body) as Map<String, dynamic>;
      final String version = (json['version'] as String? ?? '').trim();
      if (version.isEmpty) return null;
      final Object? build = json['build'];
      return _Manifest(
        version: version,
        build: build is int ? build : int.tryParse('$build'),
      );
    } catch (e) {
      debugPrint('latest.json read failed: $e');
      return null;
    }
  }

  /// Exact-name match first, then any asset ending in [suffixFallback].
  String? _findAssetUrl(
    Map<String, dynamic> json,
    String exactName,
    String? suffixFallback,
  ) {
    final Object? assets = json['assets'];
    if (assets is! List) return null;

    String? fallback;
    for (final Object? a in assets) {
      if (a is! Map) continue;
      final String name = (a['name'] as String? ?? '').toLowerCase();
      final String url = a['browser_download_url'] as String? ?? '';
      if (url.isEmpty) continue;
      if (name == exactName) return url;
      if (suffixFallback != null && name.endsWith(suffixFallback)) {
        fallback ??= url;
      }
    }
    return fallback;
  }

  int? _findApkSize(Map<String, dynamic> json) {
    final Object? assets = json['assets'];
    if (assets is! List) return null;
    for (final Object? a in assets) {
      if (a is! Map) continue;
      final String name = (a['name'] as String? ?? '').toLowerCase();
      if (name == _apkAssetName || name.endsWith('.apk')) {
        final Object? size = a['size'];
        if (size is int) return size;
      }
    }
    return null;
  }

  static String _stripV(String tag) =>
      tag.startsWith('v') || tag.startsWith('V') ? tag.substring(1) : tag;

  /// Downloads the APK into app storage and streams progress back.
  /// Returns the saved file path.
  Future<String> downloadApk(
    String url, {
    void Function(double fraction, int receivedBytes)? onProgress,
  }) async {
    final Directory dir = await _downloadDir();
    final File file = File('${dir.path}/saxify-update.apk');

    final http.Request request = http.Request('GET', Uri.parse(url));
    final http.StreamedResponse response = await _client.send(request);
    if (response.statusCode != 200) {
      throw HttpException('Download failed: HTTP ${response.statusCode}');
    }

    final int total = response.contentLength ?? 0;
    int received = 0;

    final IOSink sink = file.openWrite();
    await response.stream.map((List<int> chunk) {
      received += chunk.length;
      if (total > 0 && onProgress != null) {
        onProgress((received / total).clamp(0.0, 1.0), received);
      }
      return chunk;
    }).pipe(sink);

    return file.path;
  }

  Future<Directory> _downloadDir() async {
    try {
      final Directory? external = await getExternalStorageDirectory();
      if (external != null) return external;
    } catch (_) {}
    return getTemporaryDirectory();
  }

  /// Hands the downloaded APK to the Android package installer.
  Future<void> install(String path) async {
    await OpenFilex.open(
      path,
      type: 'application/vnd.android.package-archive',
    );
  }

  void dispose() => _client.close();

  /// Semantic version compare — true when [latest] is newer than [current].
  static bool isNewer(String current, String latest) {
    final List<int> a = _parse(current);
    final List<int> b = _parse(latest);
    for (int i = 0; i < 3; i++) {
      if (b[i] > a[i]) return true;
      if (b[i] < a[i]) return false;
    }
    return false;
  }

  /// Version first, build number second. Used when the release publishes a
  /// `latest.json` manifest, or when two releases share the same `x.y.z`.
  ///
  /// A null [latestBuild] means "unknown", so the build number is not compared
  /// and the decision falls back to the semantic version alone.
  static bool isNewerBuild(
    String currentVersion,
    int currentBuild,
    String latestVersion,
    int? latestBuild,
  ) {
    if (isNewer(currentVersion, latestVersion)) return true;
    if (_parse(currentVersion).join('.') != _parse(latestVersion).join('.')) {
      return false; // latest is strictly older
    }
    if (latestBuild == null) return false;
    return latestBuild > currentBuild;
  }

  static List<int> _parse(String v) {
    final List<int> out = <int>[0, 0, 0];
    final List<String> parts = v.split('+').first.split('.');
    for (int i = 0; i < 3 && i < parts.length; i++) {
      out[i] = int.tryParse(parts[i].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    }
    return out;
  }
}

class _Manifest {
  const _Manifest({required this.version, this.build});

  final String version;
  final int? build;
}

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    this.currentBuildNumber = 0,
    this.latestBuildNumber,
    this.apkUrl,
    this.notes = '',
    this.sizeBytes,
    this.releaseUrl,
    this.buildNumberFromManifest = false,
  });

  final String currentVersion;
  final String latestVersion;
  final int currentBuildNumber;
  final int? latestBuildNumber;
  final String? apkUrl;
  final String notes;
  final int? sizeBytes;
  final String? releaseUrl;

  /// True when the build number came from `latest.json` rather than being
  /// unknown. Drives whether the build number is shown as authoritative.
  final bool buildNumberFromManifest;

  bool get hasUpdate => UpdateService.isNewerBuild(
        currentVersion,
        currentBuildNumber,
        latestVersion,
        latestBuildNumber,
      );

  bool get downloadable => apkUrl != null && apkUrl!.isNotEmpty;

  /// `2.3.6 (build 12)` — what the dialog shows, so a rebuild of the same
  /// version is still visibly a different APK.
  String get currentLabel => currentBuildNumber > 0
      ? '$currentVersion (build $currentBuildNumber)'
      : currentVersion;

  String get latestLabel {
    final int? b = latestBuildNumber;
    if (b == null || b <= 0) return latestVersion;
    return '$latestVersion (build $b)';
  }

  String get sizeLabel {
    final int? s = sizeBytes;
    if (s == null || s <= 0) return '';
    final double mb = s / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}
