/// The names the playback sheet shows for a file's audio and subtitle tracks.
///
/// The files arrive muxed by whoever uploaded them, so a track title is their
/// advertisement: `-eonmovies.com.hin.aac.2ch`. The rule this suite holds to is
/// narrow on purpose — their domain becomes ours, everything else the file said
/// is still said, just readable.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ifallmusic/core/utils/track_labels.dart';

void main() {
  group('cleanTrackTitle', () {
    test("the uploader's domain is replaced by ours", () {
      expect(
        cleanTrackTitle('-eonmovies.com.hin.aac.2ch'),
        'Ifallertzia Hindi AAC Stereo',
      );
      expect(
        cleanTrackTitle('[ www.eonmovies.com ] Hindi AAC 2.0'),
        'Ifallertzia Hindi AAC Stereo',
      );
      expect(
        cleanTrackTitle('https://new4.eonmovies.click/pushpa2.mkv'),
        'Ifallertzia',
      );
      expect(cleanTrackTitle('EONMOVIES.COM'), trackSourceName);
    });

    test('the rest of the title survives, readable', () {
      expect(
        cleanTrackTitle('[EonMovies.Com] English 5.1 DTS-HD MA'),
        'Ifallertzia English 5.1 DTS-HD MA',
      );
      expect(
        cleanTrackTitle('Hindi_Dubbed_By_NTb'),
        'Hindi Dubbed By NTb',
        reason: 'a release group is not a domain and must not be touched',
      );
      expect(cleanTrackTitle('DUAL AUDIO'), 'Dual audio');
      expect(cleanTrackTitle('S01E02 English 720p'), 'S01E02 English 720p');
    });

    test('nothing is invented for a title that says nothing', () {
      expect(cleanTrackTitle(''), '');
      expect(cleanTrackTitle('Track 2'), '', reason: 'a bare index is not a name');
    });

    test('a filename or a resolution is never mistaken for a website', () {
      expect(cleanTrackTitle('movie.720p.mkv'), isNot(contains(trackSourceName)));
      expect(cleanTrackTitle('S01.E04'), isNot(contains(trackSourceName)));
    });
  });

  group('describeAudioTrack', () {
    test('title first, then only what the title did not already say', () {
      expect(
        describeAudioTrack(
          title: '[ www.eonmovies.com ] Hindi AAC 2.0',
          language: 'hin',
          codec: 'aac',
          channels: 2,
        ),
        'Ifallertzia Hindi AAC Stereo',
      );
      expect(
        describeAudioTrack(title: 'eonmovies.com', language: 'tam'),
        'Ifallertzia • Tamil',
      );
    });

    test('container metadata alone still reads as a name', () {
      expect(
        describeAudioTrack(language: 'hin', codec: 'eac3', channels: 6),
        'Hindi • E-AC3 • 5.1',
      );
    });

    test('an unlabelled track falls back to its slot', () {
      expect(describeAudioTrack(), 'Audio 1');
      expect(describeAudioTrack(index: 2), 'Audio 3');
    });

    test('language and codec tags are words, not codes', () {
      expect(audioTrackLanguage('hin'), 'Hindi');
      expect(audioTrackLanguage('hi'), 'Hindi');
      expect(audioTrackLanguage('qaa'), 'QAA', reason: 'unknown tags survive');
      expect(audioTrackCodec('subrip'), 'SRT');
      expect(audioTrackCodec('eac3'), 'E-AC3');
      expect(channelLayoutLabel(6), '5.1');
      expect(channelLayoutLabel(2), 'Stereo');
    });
  });

  group('describeSubtitleTrack', () {
    test('the same swap, and no channel count that subtitles do not have', () {
      expect(
        describeSubtitleTrack(
          title: '-eonmovies.com.eng.srt',
          language: 'eng',
          codec: 'subrip',
        ),
        'Ifallertzia English SRT',
      );
      expect(
        describeSubtitleTrack(language: 'eng', codec: 'srt'),
        'English • SRT',
      );
      expect(describeSubtitleTrack(), 'Subtitle 1');
    });
  });
}
