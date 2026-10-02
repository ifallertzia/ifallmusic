import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../config/branding.dart';

/// One [ImageProvider] per URL so mini-player and full player share a cache hit.
class ArtworkCache {
  ArtworkCache._();

  static final Map<String, ImageProvider> _providers = <String, ImageProvider>{};
  static const ImageProvider logo = AssetImage(IfallBranding.splashAsset);

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
    if (url.isEmpty) return;
    try {
      await precacheImage(providerFor(url), context);
    } catch (_) {}
  }
}
