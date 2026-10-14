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
    // No decodable artwork (empty, `content://`, `file://`) — the neutral mesh.
    // Never sample the logo: the palette must follow the song's cover, and a
    // local song without one gets graphite, not brand colours.
    if (!ArtworkCache.isNetworkArtwork(url)) {
      return Future<MeshPalette>.value(MeshPalette.fallback);
    }
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

/// The Now Playing background: the same artwork sampling as [MeshPalette],
/// taken in the opposite direction. Where the mesh lit four corners, this
/// keeps one deep, quiet colour — the sleeve's own hue pinned to a lightness
/// where white type stays readable — plus a single gentle grade for depth.
///
/// It is derived once per sleeve, from the palette that is already cached for
/// it, so a progress tick never costs a decode and a track change never costs
/// a re-sample.
@immutable
class PlayerBackdrop {
  const PlayerBackdrop({
    required this.base,
    required this.wash,
    required this.tint,
    required this.veil,
  });

  /// The screen's colour: the artwork's average hue, kept dark and desaturated
  /// enough that a bright sleeve never turns into a glow.
  final Color base;

  /// The top of the screen, a shade off [base]. This is the only grading the
  /// background is allowed.
  final Color wash;

  /// The sleeve's most luminous corner, at a whisper of alpha, drifting in
  /// from the top-left. Colour variation for depth — never a spotlight.
  final Color tint;

  /// The shade the controls sit on, so the lower third stays stable whatever
  /// the artwork is.
  final Color veil;

  /// Monochrome, missing or unreadable artwork lands here: graphite.
  static const PlayerBackdrop fallback = PlayerBackdrop(
    base: Color(0xFF121215),
    wash: Color(0xFF191A1E),
    tint: Color(0x0DFFFFFF),
    veil: Color(0x58000000),
  );

  /// Saturation ceiling for a background colour.
  ///
  /// The value that actually has to hold on screen is 0.34, but the clamp is
  /// set a little under it: a colour is quantised to 8-bit channels on its way
  /// out of [HSLColor], and saturation re-derived from those channels can land
  /// a hair above the number that went in (a purple sleeve measured 0.347 from
  /// a 0.34 clamp). The headroom keeps the guarantee true for every hue.
  static const double _satCeiling = 0.32;

  /// Turns a sampled sleeve into a background.
  ///
  /// The hue is whatever the artwork actually is — yellow-green sleeves come
  /// out a deep muted olive, blues a navy-slate, reds a burgundy, purples a
  /// plum, oranges a burnt amber — and only two things are decided by rule:
  ///
  ///  * **saturation** is cut to at most a third (and floored just above zero,
  ///    so a grey cover still reads as its own grey), which is what stops a
  ///    neon-yellow cover from painting a yellow screen;
  ///  * **lightness** is pinned inside a narrow band under 0.17, which keeps
  ///    white text at roughly 5:1 contrast on every hue, bright or dark.
  ///
  /// [tint] picks the brightest quadrant of the sleeve at 12% alpha, and [veil]
  /// is the same hue taken almost black — a scrim, not a glow.
  factory PlayerBackdrop.of(MeshPalette palette) {
    // A palette can only ever come back with four colours, but a caller that
    // built one by hand may not have: fall back rather than index into nothing.
    final List<Color> sampled =
        palette.colors.isEmpty ? MeshPalette.fallback.colors : palette.colors;
    final HSLColor hue = HSLColor.fromColor(_averageOf(sampled));
    final HSLColor base = hue
        .withSaturation(hue.saturation.clamp(0.05, _satCeiling))
        .withLightness((0.050 + hue.lightness * 0.105).clamp(0.045, 0.165));
    final HSLColor wash = base
        .withLightness((base.lightness + 0.05).clamp(0.0, 0.24))
        .withSaturation((base.saturation * 0.85).clamp(0.0, _satCeiling));
    Color hot = sampled.first;
    for (final Color c in sampled) {
      if (c.computeLuminance() > hot.computeLuminance()) hot = c;
    }
    final Color tint = HSLColor.fromColor(hot)
        .withSaturation(hot.computeLuminance() > 0.7 ? 0.35 : 0.55)
        .withLightness(0.66)
        .toColor()
        .withValues(alpha: 0.12);
    return PlayerBackdrop(
      base: base.toColor(),
      wash: wash.toColor(),
      tint: tint,
      veil: base
          .withLightness(base.lightness * 0.35)
          .toColor()
          .withValues(alpha: 0.42),
    );
  }

  /// Channel average of the quadrant colours — the sleeve's overall hue,
  /// without a second pass over the pixels.
  static Color _averageOf(List<Color> colors) {
    if (colors.isEmpty) return MeshPalette.fallback.base;
    double r = 0, g = 0, b = 0;
    for (final Color c in colors) {
      r += c.r;
      g += c.g;
      b += c.b;
    }
    final int n = colors.length;
    return Color.from(
      alpha: 1.0,
      red: (r / n).clamp(0.0, 1.0),
      green: (g / n).clamp(0.0, 1.0),
      blue: (b / n).clamp(0.0, 1.0),
    );
  }

  static PlayerBackdrop lerp(
    PlayerBackdrop a,
    PlayerBackdrop b,
    double t,
  ) =>
      PlayerBackdrop(
        base: Color.lerp(a.base, b.base, t)!,
        wash: Color.lerp(a.wash, b.wash, t)!,
        tint: Color.lerp(a.tint, b.tint, t)!,
        veil: Color.lerp(a.veil, b.veil, t)!,
      );

  @override
  String toString() => 'PlayerBackdrop(${base.toARGB32()}, ${wash.toARGB32()})';
}

/// The background itself: one deep colour, one gentle top-to-bottom grade and
/// a low-alpha corner wash. Deliberately **no** blurred blobs, no circle
/// behind the artwork and no lit spot at the bottom of the screen — the four
/// quadrant blobs this class used to paint are what made every sleeve look
/// like a yellow spotlight.
class MeshBackdrop extends StatelessWidget {
  const MeshBackdrop({
    super.key,
    required this.backdrop,
    this.scrim = true,
  });

  final PlayerBackdrop backdrop;
  final bool scrim;

  @override
  Widget build(BuildContext context) {
    final PlayerBackdrop b = backdrop;
    return DecoratedBox(
      decoration: BoxDecoration(color: b.base),
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          // Depth, quietly: the top third lifts by a few percent of lightness
          // and then the screen holds one colour all the way down.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: <Color>[b.wash, b.base, b.base],
                stops: const <double>[0, 0.42, 1],
              ),
            ),
          ),
          // The sleeve's own colour, graded in from the top-left at 12%. A
          // diagonal wash, not a radial glow: it can never read as a circle.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: const Alignment(0.35, 0.85),
                colors: <Color>[b.tint, b.tint.withValues(alpha: 0)],
              ),
            ),
          ),
          if (scrim)
            DecoratedBox(
              // The lower half stays stable — the same hue, almost black — so
              // the controls, the volume slider and the EQ never sit on top of
              // the artwork's brightest colour.
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.transparent, b.veil],
                  stops: const <double>[0.42, 1],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Resolves the palette for [artworkUrl] (or a neutral graphite backdrop when
/// artwork tinting — "Colour from artwork" — is off, exactly like the web app)
/// and cross-fades the screen colour when the track changes: the previous
/// backdrop is handed to the new one as its starting point, so interrupting a
/// fade mid-flight bends it towards the next colour instead of flashing.
class MeshBackdropFor extends StatefulWidget {
  const MeshBackdropFor({
    super.key,
    required this.artworkUrl,
    required this.dynamicColor,
    this.scrim = true,
    this.reduceMotion = false,
  });

  final String artworkUrl;
  final bool dynamicColor;
  final bool scrim;

  /// "Reduce motion" jumps between colours instead of fading.
  final bool reduceMotion;

  @override
  State<MeshBackdropFor> createState() => _MeshBackdropForState();
}

class _MeshBackdropForState extends State<MeshBackdropFor>
    with SingleTickerProviderStateMixin {
  static const Duration _fadeTime = Duration(milliseconds: 850);

  PlayerBackdrop _from = PlayerBackdrop.fallback;
  PlayerBackdrop _to = PlayerBackdrop.fallback;
  String _url = '';
  bool _dynamic = true;

  late final AnimationController _fade;

  /// Monotonic token: a slower extraction for a previous sleeve must never
  /// overwrite the palette of the song that is playing now.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(vsync: this, duration: _fadeTime, value: 1);
    _sync();
  }

  @override
  void didUpdateWidget(MeshBackdropFor old) {
    super.didUpdateWidget(old);
    if (old.artworkUrl != widget.artworkUrl ||
        old.dynamicColor != widget.dynamicColor) {
      _sync();
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  void _sync() {
    _url = widget.artworkUrl;
    _dynamic = widget.dynamicColor;
    final int generation = ++_generation;
    if (!widget.dynamicColor ||
        ArtworkCache.isPlaceholder(widget.artworkUrl)) {
      _apply(MeshPalette.fallback);
      return;
    }
    final MeshPalette? hit = MeshPaletteService.cached(widget.artworkUrl);
    if (hit != null) _apply(hit);
    MeshPaletteService.extract(widget.artworkUrl).then((MeshPalette p) {
      if (!mounted || generation != _generation) return;
      setState(() => _apply(p));
    });
  }

  /// One sampled sleeve in, one screen colour out — and the fade only starts
  /// if the colour actually differs, so re-opening the same track is free.
  void _apply(MeshPalette palette) {
    final PlayerBackdrop next = widget.dynamicColor
        ? PlayerBackdrop.of(palette)
        : PlayerBackdrop.fallback;
    if (next.base == _to.base &&
        next.wash == _to.wash &&
        next.tint == _to.tint) {
      return;
    }
    // Start the new fade from wherever the old one currently is, so a fast
    // double-skip never snaps through a colour it was still leaving.
    _from = PlayerBackdrop.lerp(_from, _to, _fade.value);
    _to = next;
    if (widget.reduceMotion) {
      _from = next;
      if (_fade.isAnimating) _fade.stop();
      _fade.value = 1;
      return;
    }
    _fade.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    // Stay glued to the track: if a rebuild ever hands in a new sleeve without
    // didUpdateWidget seeing it, resync on the next frame instead of painting
    // the previous song's colours until the player is reopened.
    if (widget.artworkUrl != _url || widget.dynamicColor != _dynamic) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sync();
      });
    }
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _fade,
        builder: (BuildContext context, Widget? _) => MeshBackdrop(
          backdrop: PlayerBackdrop.lerp(
            _from,
            _to,
            Curves.easeOutCubic.transform(_fade.value.clamp(0.0, 1.0)),
          ),
          scrim: widget.scrim,
        ),
      ),
    );
  }
}
