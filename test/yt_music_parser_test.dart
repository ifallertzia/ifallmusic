import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/models/song.dart';
import 'package:ifallmusic/services/yt_music_parser.dart';
import 'package:ifallmusic/services/yt_music_service.dart';

MusicSearchResult fixture(String name) => parseMusicSearch(
  jsonDecode(File('test/fixtures/yt_music_$name.json').readAsStringSync())
      as Map<String, dynamic>,
);
void main() {
  test(
    'Songs shelf ignores translated title, extracts album, artist and duration',
    () {
      final result = fixture('songs');
      final song = result.tracks.single;
      expect(song.id, 'abcdefghijk');
      expect(song.quality, QualityTier.high);
      expect(song.artistId, 'UCartist');
      expect(song.albumId, 'MPREbalbum');
      expect(song.durationSecs, 268);
      expect(song.source, TrackSource.ytMusic);
      expect(song.artworkUrl, endsWith('=w544-h544-l90-rj'));
      expect(result.continuation, 'NEXT');
    },
  );
  test('unfiltered card, album, artist and playlist classification', () {
    final result = fixture('all');
    expect(
      result.tracks.map((s) => s.id),
      containsAll(['toptrack123', 'abcdefghijk', 'zyxwvutsrqp']),
    );
    expect(result.items.map((i) => i.kind), [
      'album',
      'artist',
      'playlist',
      'album',
    ]);
    expect(result.tracks.last.quality, QualityTier.normal);
  });
  test('continuations and source-first dedupe', () {
    final songs = fixture('songs').tracks;
    final all = fixture('all').tracks;
    final continuation = fixture('continuation');
    expect(continuation.tracks.single.quality, QualityTier.normal);
    final merged = mergeMusicResults(songs, all, songs);
    expect(merged.first.id, songs.first.id);
    expect(merged.map((s) => s.id).toSet().length, merged.length);
  });
  test('quality, raw query sanitizing and backward-compatible JSON', () {
    expect(
      classifyQuality('MUSIC_VIDEO_TYPE_OFFICIAL_SOURCE_MUSIC', ''),
      QualityTier.high,
    );
    expect(classifyQuality(null, 'Artist - Topic'), QualityTier.high);
    expect(
      classifyQuality('MUSIC_VIDEO_TYPE_OMV', 'Artist'),
      QualityTier.normal,
    );
    expect(YtMusicService.sanitize('  Kesariya\n  '), 'Kesariya');
    expect(YtMusicService.sanitize('a' * 130).length, 120);
    final old = Song.fromJson({
      'id': 'abcdefghijk',
      'title': 'Song',
      'artist': 'Artist',
    });
    expect(old.source, TrackSource.youtube);
    expect(old.quality, QualityTier.normal);
    final song = fixture('songs').tracks.single;
    final restored = Song.fromJson(song.toJson());
    expect(restored.albumId, song.albumId);
    expect(restored.quality, song.quality);
    expect(restored.source, TrackSource.ytMusic);
    expect(restored.copyWith(subtitle: 'Mix').artistId, song.artistId);
  });
}
