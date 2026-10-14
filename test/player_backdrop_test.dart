/// The Now Playing background, measured on the maths rather than on a screen:
/// the screen colour must come from the sleeve that is actually playing, and it
/// must stay a *background* — the hue of the artwork, deep and desaturated, never
/// the oversized yellow glow this replaced.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ifallmusic/ui/player/player_palette.dart';

MeshPalette _sleeve(List<int> argb) => MeshPalette(
      colors: <Color>[for (final int v in argb) Color(v)],
      base: Color(argb.first),
    );

/// White type needs the screen under it to stay quiet: 0.20 relative luminance
/// is roughly where 4.5:1 contrast starts to slip.
double _lum(Color c) => c.computeLuminance();

void main() {
  group('PlayerBackdrop.of', () {
    test('a bright yellow sleeve becomes a deep olive screen, not a glow', () {
      final PlayerBackdrop b = PlayerBackdrop.of(_sleeve(<int>[
        0xFFFFD400,
        0xFFE8C400,
        0xFFFFE44D,
        0xFFF2D21E,
      ]));
      final HSLColor hsl = HSLColor.fromColor(b.base);
      // Still recognisably the sleeve's own family…
      expect(hsl.hue, closeTo(50, 12));
      // …but restrained: at most a third of the saturation, and dark enough to
      // read white text on. The old mesh painted this hue at L 0.28–0.52 in
      // 340px blobs, which is exactly the yellow spotlight that was removed.
      expect(hsl.saturation, lessThanOrEqualTo(0.34));
      expect(hsl.lightness, lessThanOrEqualTo(0.17));
      expect(_lum(b.base), lessThan(0.20));
      // The grading stays inside a hair's width of the base colour.
      expect((HSLColor.fromColor(b.wash).lightness - hsl.lightness).abs(),
          lessThan(0.08));
      expect(_lum(b.wash), lessThan(0.24));
    });

    test('blue, red, purple and warm sleeves all stay readable', () {
      final Map<String, List<int>> sleeves = <String, List<int>>{
        'blue': <int>[0xFF1B4FD8, 0xFF2C63E8, 0xFF0E2F8C, 0xFF3D74F0],
        'red': <int>[0xFFE0244A, 0xFFC0103A, 0xFFFF5C74, 0xFF8E0B26],
        'purple': <int>[0xFF6E2BD8, 0xFF54179E, 0xFF8F5CF0, 0xFF3C0E72],
        'amber': <int>[0xFFD8781B, 0xFFB45A0E, 0xFFF09A3D, 0xFF7E3C08],
        'mono': <int>[0xFF2A2A2A, 0xFF6E6E6E, 0xFF121212, 0xFFB4B4B4],
      };
      sleeves.forEach((String name, List<int> argb) {
        final PlayerBackdrop b = PlayerBackdrop.of(_sleeve(argb));
        expect(_lum(b.base), lessThan(0.20),
            reason: '$name artwork left a screen too bright to read on');
        expect(HSLColor.fromColor(b.base).saturation, lessThanOrEqualTo(0.34),
            reason: '$name artwork left a saturated glow behind');
        // The bottom of the screen is the darkest thing on it: controls, the
        // volume slider and the queue never sit on a lit spot.
        expect(_lum(b.veil), lessThanOrEqualTo(_lum(b.base) + 0.02),
            reason: '$name lifted the lower half instead of shading it');
      });
    });

    test('monochrome art stays a neutral graphite, not a coloured wash', () {
      final PlayerBackdrop b = PlayerBackdrop.of(_sleeve(<int>[
        0xFFEDEDED,
        0xFF1A1A1A,
        0xFF8C8C8C,
        0xFF454545,
      ]));
      final HSLColor hsl = HSLColor.fromColor(b.base);
      // A grey sleeve must not invent a colour — and must not go pure black
      // either, so the screen still reads as *this* artwork.
      expect(hsl.saturation, lessThan(0.20));
      expect(hsl.lightness, greaterThan(0.04));
      expect(hsl.lightness, lessThan(0.18));
    });

    test('the corner tint is a whisper and never a spotlight', () {
      final PlayerBackdrop b = PlayerBackdrop.of(_sleeve(<int>[
        0xFFFFF2A8,
        0xFFFFD400,
        0xFFF2C400,
        0xFFFFE44D,
      ]));
      // 12% alpha at most, whatever the sleeve is.
      expect(b.tint.a, lessThanOrEqualTo(0.13));
      expect(b.tint.a, greaterThan(0.0));
    });

    test('lerping two backdrops stays between them', () {
      const PlayerBackdrop a = PlayerBackdrop(
        base: Color(0xFF121215),
        wash: Color(0xFF191A1E),
        tint: Color(0x0DFFFFFF),
        veil: Color(0x58000000),
      );
      final PlayerBackdrop b = PlayerBackdrop.of(_sleeve(<int>[
        0xFF1B4FD8,
        0xFF2C63E8,
        0xFF0E2F8C,
        0xFF3D74F0,
      ]));
      final PlayerBackdrop mid = PlayerBackdrop.lerp(a, b, 0.5);
      expect(mid.base, isNot(a.base));
      expect(mid.base, isNot(b.base));
      expect(_lum(mid.base), lessThan(0.24),
          reason: 'a half-way colour must not flash bright');
      expect(PlayerBackdrop.lerp(a, a, 0.4).base, a.base);
      expect(PlayerBackdrop.lerp(a, b, 1).base, b.base);
      expect(PlayerBackdrop.lerp(a, b, 0).base, a.base);
    });

    test('the fallback is a graphite screen, and it is what a failed sleeve '
        'lands on', () {
      // Missing artwork / a decode that threw: still dark, still neutral.
      expect(_lum(PlayerBackdrop.fallback.base), lessThan(0.12));
      final PlayerBackdrop fromFallback = PlayerBackdrop.of(MeshPalette.fallback);
      expect(_lum(fromFallback.base), lessThan(0.20));
      expect(
        HSLColor.fromColor(fromFallback.base).saturation,
        lessThan(0.35),
      );
      // A blank sleeve list must not throw either.
      expect(
        PlayerBackdrop.of(
          const MeshPalette(colors: <Color>[], base: Color(0xFF000000)),
        ).base,
        isA<Color>(),
      );
    });
  });

  testWidgets('the backdrop paints no blobs and no radial glow',
      (WidgetTester tester) async {
    final PlayerBackdrop b = PlayerBackdrop.of(_sleeve(<int>[
      0xFFFFD400,
      0xFFE8C400,
      0xFFFFE44D,
      0xFFF2D21E,
    ]));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MeshBackdrop(backdrop: b),
        ),
      ),
    );
    expect(tester.takeException(), isNull);

    // Everything the screen is made of, and what each layer is allowed to be.
    final Finder layers = find.descendant(
      of: find.byType(MeshBackdrop),
      matching: find.byType(DecoratedBox),
    );
    // The base, the top grade, the corner wash and the scrim: four flat
    // layers, and that is the whole background.
    expect(layers, findsNWidgets(4));
    for (final DecoratedBox box in tester.widgetList<DecoratedBox>(layers)) {
      final BoxDecoration d = box.decoration as BoxDecoration;
      expect(d.gradient, isNot(isA<RadialGradient>()),
          reason: 'a radial blob is back on the Now Playing background');
      expect(d.boxShadow ?? const <BoxShadow>[], isEmpty,
          reason: 'the background must not glow — it is a flat wash');
    }
    // No image is blurred behind the artwork any more either.
    expect(
      find.descendant(
          of: find.byType(MeshBackdrop), matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    // The screen underneath stays under 0.2 luminance, and the corner wash is
    // only ever a 12% whisper — the yellow family that used to flood the
    // screen cannot come back as a glow.
    expect(_lum(b.base), lessThan(0.20));
    expect(b.tint.a, lessThanOrEqualTo(0.13));
  });

  testWidgets('missing artwork gets the graphite screen, not the brand logo',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MeshBackdropFor(artworkUrl: '', dynamicColor: true),
        ),
      ),
    );
    // Long enough for the opening cross-fade to land, so what is asserted is
    // the colour the screen settles on rather than one it is passing through.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);

    final MeshBackdrop backdrop =
        tester.widget<MeshBackdrop>(find.byType(MeshBackdrop));
    // A cover we cannot sample must never invent a colour: graphite, dark.
    expect(HSLColor.fromColor(backdrop.backdrop.base).saturation,
        lessThan(0.20));
    expect(_lum(backdrop.backdrop.base), lessThan(0.20));

    // "Colour from artwork" off hands back the neutral screen exactly.
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MeshBackdropFor(artworkUrl: '', dynamicColor: false),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
    expect(
      tester
          .widget<MeshBackdrop>(find.byType(MeshBackdrop))
          .backdrop
          .base,
      PlayerBackdrop.fallback.base,
    );
  });
}
