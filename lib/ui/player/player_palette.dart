import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/services/artwork_cache.dart';

/// Colours extracted from one album sleeve, pre-darkened for the player
/// backdrop so text, icons and controls always stay readable on top.
@immutable
class PlayerPalette {
  const PlayerPalette({
    required this.primary,
    required this.secondary,
    required this.glow,
  });

  /// Top of the backdrop gradient — a deep, tinted version of the sleeve.
  final Color primary;

  /// Middle of the gradient — an even darker companion shade.
  final Color secondary;

  /// A slightly brighter, more saturated tone used for the ambient halo
  /// behind the artwork and the play-button glow.
  final Color glow;

  /// Neutral charcoal used before extraction finishes or when it fails.
  static const PlayerPalette fallback = PlayerPalette(
    primary: Color(0xFF23242C),
    secondary: Color(0xFF101218),
    glow: Color(0xFF363A4A),
  );
}

/// Extracts the dominant colours of album artwork.
///
/// Implementation notes:
/// - Reuses [ArtworkCache.providerFor], so no extra network request is made —
///   the sleeve already in the image cache is decoded at a tiny resolution.
/// - Runs fully asynchronously; playback is never blocked.
/// - Results are cached per URL, so returning to a song is instant.
/// - Any failure (missing artwork, decode error, …) resolves to
///   [PlayerPalette.fallback] instead of throwing.
class PlayerPaletteService {
  PlayerPaletteService._();

  static final Map<String, PlayerPalette> _cache = <String, PlayerPalette>{};
  static final Map<String, Future<PlayerPalette>> _pending =
      <String, Future<PlayerPalette>>{};

  /// Synchronous cache lookup (null when the sleeve was never analysed).
  static PlayerPalette? cached(String url) => _cache[url];

  /// Resolves the palette for [url], extracting it once and caching it.
  static Future<PlayerPalette> extract(String url) {
    if (url.isEmpty) return Future<PlayerPalette>.value(PlayerPalette.fallback);
    final PlayerPalette? hit = _cache[url];
    if (hit != null) return Future<PlayerPalette>.value(hit);
    final Future<PlayerPalette>? inFlight = _pending[url];
    if (inFlight != null) return inFlight;

    final Future<PlayerPalette> future = _extract(url).then(
      (PlayerPalette palette) {
        _cache[url] = palette;
        return palette;
      },
      onError: (Object _) => PlayerPalette.fallback,
    ).whenComplete(() => _pending.remove(url));
    _pending[url] = future;
    return future;
  }

  // ---------------------------------------------------------------------
  // Extraction
  // ---------------------------------------------------------------------

  static Future<PlayerPalette> _extract(String url) async {
    final ui.Image image = await _decodeSmall(ArtworkCache.providerFor(url));
    try {
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return PlayerPalette.fallback;
      return _paletteFromPixels(data);
    } finally {
      image.dispose();
    }
  }

  /// Decodes the provider at a tiny size (max 48×48) — more than enough for
  /// a dominant-colour pass and cheap enough for the UI isolate.
  static Future<ui.Image> _decodeSmall(ImageProvider provider) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    final ImageStream stream = ResizeImage(
      provider,
      width: 48,
      height: 48,
      allowUpscaling: false,
    ).resolve(ImageConfiguration.empty);

    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool syncCall) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          // Hand out our own handle and release the ImageInfo's one.
          completer.complete(info.image.clone());
        }
        info.dispose();
      },
      onError: (Object error, StackTrace? stackTrace) {
        stream.removeListener(listener);
        if (!completer.isCompleted) completer.completeError(error);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  static PlayerPalette _paletteFromPixels(ByteData data) {
    // Quantise to 4 bits per channel and build a weighted histogram that
    // prefers saturated, mid-brightness colours (the "identity" of a sleeve)
    // over flat blacks and whites.
    final Map<int, _Bucket> buckets = <int, _Bucket>{};
    final int byteCount = data.lengthInBytes;

    for (int i = 0; i + 3 < byteCount; i += 4) {
      final int r = data.getUint8(i);
      final int g = data.getUint8(i + 1);
      final int b = data.getUint8(i + 2);
      final int a = data.getUint8(i + 3);
      if (a < 128) continue;

      final int key = ((r >> 4) << 8) | ((g >> 4) << 4) | (b >> 4);
      final _Bucket bucket = buckets.putIfAbsent(key, _Bucket.new);
      bucket.add(r, g, b);
    }
    if (buckets.isEmpty) return PlayerPalette.fallback;

    _Bucket? best;
    double bestScore = -1;
    for (final _Bucket bucket in buckets.values) {
      final double score = bucket.score;
      if (score > bestScore) {
        bestScore = score;
        best = bucket;
      }
    }
    if (best == null) return PlayerPalette.fallback;

    final HSLColor dominant = HSLColor.fromColor(best.averageColor);

    // Optional second hue for gradient depth: the strongest bucket whose hue
    // clearly differs from the dominant one.
    HSLColor? companion;
    double companionScore = -1;
    for (final _Bucket bucket in buckets.values) {
      final HSLColor hsl = HSLColor.fromColor(bucket.averageColor);
      final double hueDelta = _hueDistance(hsl.hue, dominant.hue);
      if (hueDelta < 40 || hsl.saturation < 0.12) continue;
      final double score = bucket.score;
      if (score > companionScore) {
        companionScore = score;
        companion = hsl;
      }
    }
    // Only keep the companion when it is a meaningful part of the sleeve.
    if (companionScore < bestScore * 0.22) companion = null;

    return _buildPalette(dominant, companion);
  }

  /// Darkens and tempers the extracted hues so the backdrop stays deep and
  /// accessible (white text / icons remain readable on top).
  static PlayerPalette _buildPalette(HSLColor dominant, HSLColor? companion) {
    final double saturation =
        dominant.saturation <= 0.08 ? dominant.saturation : dominant.saturation.clamp(0.28, 0.78);

    final double primaryLightness = dominant.lightness.clamp(0.16, 0.30);
    final Color primary = HSLColor.fromAHSL(
      1,
      dominant.hue,
      saturation,
      primaryLightness,
    ).toColor();

    final HSLColor secondBase = companion ?? dominant;
    final double secondSaturation = secondBase.saturation <= 0.08
        ? secondBase.saturation
        : secondBase.saturation.clamp(0.24, 0.70);
    final Color secondary = HSLColor.fromAHSL(
      1,
      secondBase.hue,
      secondSaturation,
      (primaryLightness * 0.48).clamp(0.06, 0.15),
    ).toColor();

    final Color glow = HSLColor.fromAHSL(
      1,
      dominant.hue,
      math.min(1.0, saturation * 1.15),
      0.36,
    ).toColor();

    return PlayerPalette(primary: primary, secondary: secondary, glow: glow);
  }

  static double _hueDistance(double a, double b) {
    final double d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }
}

class _Bucket {
  int count = 0;
  int _r = 0;
  int _g = 0;
  int _b = 0;

  void add(int r, int g, int b) {
    count++;
    _r += r;
    _g += g;
    _b += b;
  }

  Color get averageColor {
    if (count == 0) return const Color(0xFF000000);
    return Color.fromARGB(255, _r ~/ count, _g ~/ count, _b ~/ count);
  }

  /// Population weighted towards saturated, mid-brightness colours.
  double get score {
    final Color c = averageColor;
    final HSLColor hsl = HSLColor.fromColor(c);
    // 0 at pure black/white, 1 around mid brightness.
    final double brightnessWeight =
        1 - (hsl.lightness - 0.5).abs() * 1.6;
    return count *
        (0.18 + hsl.saturation) *
        brightnessWeight.clamp(0.08, 1.0);
  }
}
