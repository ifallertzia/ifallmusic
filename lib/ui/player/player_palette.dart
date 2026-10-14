import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/services/artwork_cache.dart';

/// Colours sampled from one album sleeve, for the Now Playing mesh backdrop
/// and the collection headers — the port of the web app's `palette.ts` /
/// `MeshBackdrop`: four luminous quadrant colours over a dimmed base.
///
/// Extraction reuses [ArtworkCache.providerFor] (no extra network request),
/// decodes at 48×48 and averages each quadrant. Results are cached per URL;
/// any failure resolves to the neutral graphite palette, never a throw.
@immutable
class MeshPalette {
  const MeshPalette({required this.colors, required this.base});

  /// Four tuned quadrant colours (top-left, top-right, bottom-right,
  /// bottom-left), vivid but kept below glare.
  final List<Color> colors;

  /// The dimmed dominant colour the mesh sits on.
  final Color base;

  static const MeshPalette fallback = MeshPalette(
    colors: <Color>[
      Color(0xFF3A3A40),
      Color(0xFF2A2A30),
      Color(0xFF45454C),
      Color(0xFF26262B),
    ],
    base: Color(0xFF17171B),
  );

  Color get primary => colors.first;
}

class MeshPaletteService {
  MeshPaletteService._();

  static final Map<String, MeshPalette> _cache = <String, MeshPalette>{};
  static final Map<String, Future<MeshPalette>> _pending =
      <String, Future<MeshPalette>>{};

  static MeshPalette? cached(String url) => _cache[url];

  static void warm(String url) {
    if (url.isEmpty || _cache.containsKey(url)) return;
    unawaited(extract(url));
  }

  static Future<MeshPalette> extract(String url) {
    if (url.isEmpty) return Future<MeshPalette>.value(MeshPalette.fallback);
    final MeshPalette? hit = _cache[url];
    if (hit != null) return Future<MeshPalette>.value(hit);
    final Future<MeshPalette>? inFlight = _pending[url];
    if (inFlight != null) return inFlight;
    final Future<MeshPalette> future = _extract(url).then(
      (MeshPalette palette) {
        _cache[url] = palette;
        return palette;
      },
      onError: (Object _) => MeshPalette.fallback,
    ).whenComplete(() => _pending.remove(url));
    _pending[url] = future;
    return future;
  }

  static Future<MeshPalette> _extract(String url) async {
    final ui.Image image = await _decodeSmall(ArtworkCache.providerFor(url));
    try {
      final ByteData? data =
          await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (data == null) return MeshPalette.fallback;
      return _fromPixels(data, image.width, image.height);
    } finally {
      image.dispose();
    }
  }

  static Future<ui.Image> _decodeSmall(ImageProvider provider) {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    final ImageStream stream = ResizeImage(
      provider,
      width: 48,
      height: 48,
      allowUpscaling: false,
    ).resolve(ImageConfiguration.empty);
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        stream.removeListener(listener);
        completer.complete(info.image);
      },
      onError: (Object error, StackTrace? stack) {
        stream.removeListener(listener);
        completer.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  static MeshPalette _fromPixels(ByteData data, int w, int h) {
    // Quadrant sums: [tl, tr, br, bl], plus the whole-frame average.
    final List<List<double>> sums =
        List<List<double>>.generate(5, (_) => <double>[0, 0, 0, 0]);
    final Uint8List bytes = data.buffer.asUint8List();
    for (int y = 0; y < h; y++) {
      for (int x = 0; x < w; x++) {
        final int i = (y * w + x) * 4;
        if (i + 3 >= bytes.length) continue;
        final int a = bytes[i + 3];
        if (a < 16) continue;
        final int quad = (y < h / 2 ? 0 : 2) + (x < w / 2 ? 0 : 1);
        // Map to [tl=0, tr=1, br=2, bl=3].
        final int q = switch (quad) { 0 => 0, 1 => 1, 2 => 3, _ => 2 };
        for (final int slot in <int>[q, 4]) {
          sums[slot][0] += bytes[i];
          sums[slot][1] += bytes[i + 1];
          sums[slot][2] += bytes[i + 2];
          sums[slot][3] += 1;
        }
      }
    }
    Color avg(List<double> s, Color fallback) {
      if (s[3] == 0) return fallback;
      return Color.fromARGB(
        255,
        (s[0] / s[3]).round(),
        (s[1] / s[3]).round(),
        (s[2] / s[3]).round(),
      );
    }

    final List<Color> fb = MeshPalette.fallback.colors;
    final List<Color> tuned = <Color>[
      for (int i = 0; i < 4; i++) _tune(avg(sums[i], fb[i])),
    ];
    return MeshPalette(colors: tuned, base: _dim(avg(sums[4], fb[0]), 0.24));
  }

  /// `tune()` from the web palette: lift saturation a touch and keep the
  /// colour luminous but never glaring.
  static Color _tune(Color c) {
    final HSLColor hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation((hsl.saturation * 1.15).clamp(0.15, 0.85))
        .withLightness(hsl.lightness.clamp(0.28, 0.52))
        .toColor();
  }

  static Color _dim(Color c, double amount) {
    final HSLColor hsl = HSLColor.fromColor(c);
    return hsl
        .withSaturation((hsl.saturation * 0.9).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * amount).clamp(0.04, 0.2))
        .toColor();
  }
}

/// The mesh itself: four blurred blobs at the corners over [MeshPalette.base],
/// crossfading when the track changes. In Flutter the "blur" is a radial
/// gradient per blob, which reads the same and costs no backdrop filter.
class MeshBackdrop extends StatelessWidget {
  const MeshBackdrop({
    super.key,
    required this.palette,
    this.scrim = true,
  });

  final MeshPalette palette;
  final bool scrim;

  @override
  Widget build(BuildContext context) {
    final List<Color> c = palette.colors;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      color: palette.base,
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          _blob(c[0], const Alignment(-0.75, -0.8)),
          _blob(c[1], const Alignment(0.85, -0.7)),
          _blob(c[2], const Alignment(0.7, 0.85)),
          _blob(c[3], const Alignment(-0.85, 0.75)),
          if (scrim)
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Color(0x1A000000), Color(0x61000000)],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _blob(Color color, Alignment alignment) {
    return Align(
      alignment: alignment,
      child: Container(
        width: 340,
        height: 340,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: <Color>[
              color.withValues(alpha: 0.85),
              color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}

/// Resolves the palette for [artworkUrl] (or a neutral mesh when artwork
/// tinting — "Colour from artwork" — is off, exactly like the web app).
class MeshBackdropFor extends StatefulWidget {
  const MeshBackdropFor({
    super.key,
    required this.artworkUrl,
    required this.dynamicColor,
    this.scrim = true,
  });

  final String artworkUrl;
  final bool dynamicColor;
  final bool scrim;

  @override
  State<MeshBackdropFor> createState() => _MeshBackdropForState();
}

class _MeshBackdropForState extends State<MeshBackdropFor> {
  MeshPalette _palette = MeshPalette.fallback;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(MeshBackdropFor old) {
    super.didUpdateWidget(old);
    if (old.artworkUrl != widget.artworkUrl ||
        old.dynamicColor != widget.dynamicColor) {
      _load();
    }
  }

  void _load() {
    if (!widget.dynamicColor || widget.artworkUrl.isEmpty) {
      _palette = MeshPalette.fallback;
      return;
    }
    _palette = MeshPaletteService.cached(widget.artworkUrl) ?? _palette;
    MeshPaletteService.extract(widget.artworkUrl).then((MeshPalette p) {
      if (mounted && widget.artworkUrl.isNotEmpty) {
        setState(() => _palette = p);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return MeshBackdrop(palette: _palette, scrim: widget.scrim);
  }
}
