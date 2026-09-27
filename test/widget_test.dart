import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/models/album_card.dart';
import 'package:ifallmusic/core/theme/saxify_accents.dart';
import 'package:ifallmusic/core/utils/format.dart';
import 'package:ifallmusic/ui/widgets/saxify_logo.dart';

void main() {
  group('AlbumCard ytq codec', () {
    test('decode matches the web site format', () {
      const String encoded =
          'ytq-eyJxIjoibmV3IHNvbmdzIDIwMjYgb2ZmaWNpYWwiLCJ0IjoiTmV3IE11c2ljIDIwMjYiLCJhIjoiRmFsbHkgSXB1cGEifQ';
      final AlbumCard? album = AlbumCard.decode(encoded);
      expect(album, isNotNull);
      expect(album!.query, 'new songs 2026 official');
      expect(album.title, 'New Music 2026');
      expect(album.artist, 'Fally Ipupa');
    });

    test('encode/decode roundtrip', () {
      final String id = AlbumCard.encode(
        query: 'lofi beats',
        title: 'Lo-Fi Corner',
        artist: 'Unknown Artist',
      );
      final AlbumCard? album = AlbumCard.decode(id);
      expect(album, isNotNull);
      expect(album!.query, 'lofi beats');
      expect(album.title, 'Lo-Fi Corner');
      expect(album.artist, 'Unknown Artist');
    });

    test('rejects garbage', () {
      expect(AlbumCard.decode('not-base64!!!'), isNull);
      expect(AlbumCard.decode(''), isNull);
    });
  });

  group('formatting', () {
    test('duration renders m:ss and h:mm:ss', () {
      expect(Fmt.duration(const Duration(minutes: 4, seconds: 33)), '4:33');
      expect(
        Fmt.duration(const Duration(hours: 1, minutes: 2, seconds: 7)),
        '1:02:07',
      );
      expect(Fmt.duration(null), '--:--');
    });

    test('count shortens large numbers', () {
      expect(Fmt.count(1500000), '1.5M');
      expect(Fmt.count(20000), '20K');
      expect(Fmt.count(400), '400');
    });
  });

  group('accents', () {
    test('the deep palette ships, including Silver, and byId falls back', () {
      expect(SaxifyAccents.all.length, 18);
      expect(SaxifyAccents.all.contains(SaxifyAccents.silver), isTrue);
      expect(SaxifyAccents.byId('violet-pulse'), SaxifyAccents.violetPulse);
      expect(SaxifyAccents.byId('nope'), SaxifyAccents.violetPulse);
    });

    test('light accents use black ink so text stays readable', () {
      expect(SaxifyAccents.silver.onAccent, const Color(0xFF000000));
      expect(SaxifyAccents.violetPulse.onAccent, const Color(0xFFFFFFFF));
    });

    test('a custom mix keeps the custom id and both colours', () {
      final SaxifyAccent mix = SaxifyAccent.custom(
        const Color(0xFF123456),
        const Color(0xFF654321),
      );
      expect(mix.id, SaxifyAccent.customAccentId);
      expect(mix.isCustom, isTrue);
      expect(mix.primary, const Color(0xFF123456));
      expect(mix.secondary, const Color(0xFF654321));
    });
  });

  group('branding', () {
    testWidgets('logo renders without a network font', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        Theme(
          data: ThemeData.dark(),
          child: const Center(child: SaxifyLogo(size: 40)),
        ),
      );
      expect(find.byType(SaxifyLogo), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      final image = tester.widget<Image>(find.byType(Image));
      expect(image.image, isA<AssetImage>());
      expect(
        (image.image as AssetImage).assetName,
        'assets/images/saxify_logo.png',
      );
    });
  });
}
