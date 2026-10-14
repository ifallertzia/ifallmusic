import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/branding.dart';

/// One [ImageProvider] per URL so mini-player and full player share a cache hit.
class ArtworkCache {
  ArtworkCache._();

  static final Map<String, ImageProvider> _providers = <String, ImageProvider>{};
  static const ImageProvider logo = AssetImage(SidifyBranding.splashAsset);

  /// True only for real, fetchable artwork — an `http(s)` thumbnail.
  ///
  /// On-device songs carry `content://`/`file://` album-art URIs (or nothing
  /// at all); those are NOT loadable as network images. Every artwork slot
  /// must draw the music-note placeholder for them instead of falling back to
  /// the app logo — the logo is branding, not a stand-in for cover art.
  static bool isNetworkArtwork(String url) =>
      url.startsWith('http://') || url.startsWith('https://');

  /// True when the URL points at an on-device image we cannot decode inline
  /// (`content://`, `file://`) or at no image at all.
  static bool isPlaceholder(String url) => !isNetworkArtwork(url);

  static ImageProvider providerFor(String url) {
    if (url.isEmpty || url.startsWith('content:') || url.startsWith('file:')) {
      return logo;
    }
    return _providers.putIfAbsent(
      url,
      () => CachedNetworkImageProvider(url, maxWidth: 512, maxHeight: 512),
    );
  }

  static Future<void> precache(BuildContext context, String url) async {
    if (!isNetworkArtwork(url)) return;
    try {
      await precacheImage(providerFor(url), context);
    } catch (_) {}
  }
}
