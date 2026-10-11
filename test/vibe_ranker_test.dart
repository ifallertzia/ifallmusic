import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/core/models/song.dart';
import 'package:ifallmusic/core/services/vibe_ranker.dart';

Song track(
  String id,
  String title, {
  String artist = 'Arijit Singh',
  int seconds = 200,
}) => Song(
  id: id,
  title: title,
  artist: artist,
  thumbnailUrl: '',
  duration: Duration(seconds: seconds),
);

void main() {
  group('text identity', () {
    test('title tokens keep the song words and drop the packaging', () {
      final Set<String> tokens =
          titleTokens('Kesariya (Official Video) | Brahmastra | 4K');
      expect(tokens, contains('kesariya'));
      expect(tokens, contains('brahmastra'));
      expect(tokens, isNot(contains('official')));
      expect(tokens, isNot(contains('video')));
      expect(tokens, isNot(contains('4k')));
    });

    test('artist key is the primary artist, normalised', () {
      expect(artistKey('Arijit Singh, Shreya Ghoshal'), 'arijit singh');
      expect(artistKey('Arijit Singh - Topic'), 'arijit singh');
      expect(artistKey('T-Series'), 't series');
      expect(artistKey(''), '');
    });
  });

  group('ranking', () {
    test('the anchor and its alternate recordings never come back', () {
      final VibeMemory memory = VibeMemory();
      final Song anchor = track('aaaaaaaaaaa', 'Kesariya');
      memory.notePlay(anchor);
      final List<Song> ranked = VibeRanker.rank(
        anchor,
        <Song>[
          anchor,
          track('bbbbbbbbbbb', 'Kesariya (Slowed + Reverb)'),
          track('ccccccccccc', 'Kesariya | Brahmastra | Official Audio'),
          track('ddddddddddd', 'Tum Hi Ho'),
        ],
        profile: memory.profile,
      );
      expect(ranked.map((Song s) => s.id), <String>['ddddddddddd']);
    });

    test('the artist the listener keeps playing leads the queue', () {
      final VibeMemory memory = VibeMemory();
      final Song anchor = track('aaaaaaaaaaa', 'Kesariya');
      memory.notePlay(anchor);
      final List<Song> ranked = VibeRanker.rank(
        anchor,
        <Song>[
          track('ccccccccccc', 'Something Else', artist: 'Random Band'),
          track('ddddddddddd', 'Tum Hi Ho'),
        ],
        profile: memory.profile,
        limit: 2,
      );
      expect(ranked.first.id, 'ddddddddddd');
    });

    test('skipped ids and excluded ids never come back', () {
      final VibeMemory memory = VibeMemory();
      memory.noteSkip(track('bbbbbbbbbbb', 'Too loud', artist: 'Loud Band'));
      final List<Song> ranked = VibeRanker.rank(
        track('aaaaaaaaaaa', 'Anchor'),
        <Song>[
          track('bbbbbbbbbbb', 'Too loud', artist: 'Loud Band'),
          track('ccccccccccc', 'Fine'),
          track('ddddddddddd', 'Excluded'),
        ],
        profile: memory.profile,
        excludedIds: <String>{'ddddddddddd'},
      );
      expect(ranked.map((Song s) => s.id), <String>['ccccccccccc']);
    });

    test('a track that followed the anchor before is served first', () {
      final VibeMemory memory = VibeMemory();
      final Song anchor = track('aaaaaaaaaaa', 'Kesariya');
      memory.notePlay(anchor);
      memory.notePlay(track('ddddddddddd', 'Channa Mereya'));
      memory.noteTransition(anchor.id, track('ddddddddddd', 'Channa Mereya'));
      final List<Song> ranked = VibeRanker.rank(
        anchor,
        <Song>[
          track('ccccccccccc', 'Some Other Song', artist: 'Random Band'),
          track('ddddddddddd', 'Channa Mereya'),
        ],
        profile: memory.profile,
      );
      expect(ranked.first.id, 'ddddddddddd');
    });

    test('vibe smoothness keeps a 9-minute mix away from a 3-minute song', () {
      final VibeMemory memory = VibeMemory();
      final Song anchor = track('aaaaaaaaaaa', 'Short One', seconds: 180);
      memory.notePlay(anchor);
      final List<Song> ranked = VibeRanker.rank(
        anchor,
        <Song>[
          track('eeeeeeeeeee', 'Huge Club Mix', artist: 'DJ Set', seconds: 540),
          track(
            'fffffffffff',
            'Same Length',
            artist: 'Other Artist',
            seconds: 190,
          ),
        ],
        profile: memory.profile,
      );
      expect(ranked.first.id, 'fffffffffff');
      expect(
        VibeRanker.proximityCost(
          track('aaaaaaaaaaa', 'A', seconds: 180),
          track('eeeeeeeeeee', 'B', artist: 'Other', seconds: 540),
        ),
        greaterThan(0.5),
      );
    });
  });

  group('memory', () {
    test('likes lift an artist, unliking removes the lift', () {
      final VibeMemory memory = VibeMemory();
      final Song liked = track('aaaaaaaaaaa', 'Loved', artist: 'Darshan Raval');
      expect(memory.profile.artistAffinity('Darshan Raval'), 0);
      memory.noteLike(liked);
      expect(memory.profile.artistAffinity('Darshan Raval'), 1);
      memory.noteUnlike(liked);
      expect(memory.profile.artistAffinity('Darshan Raval'), 0);
    });

    test('the listener is matched across collaborators', () {
      final VibeMemory memory = VibeMemory();
      memory.notePlay(track('aaaaaaaaaaa', 'Hit', artist: 'Arijit Singh'));
      expect(
        memory.profile.artistAffinity('Arijit Singh, Shreya Ghoshal'),
        1,
      );
    });

    test('seeded history still recommends, with a lighter weight', () {
      final VibeMemory memory = VibeMemory();
      memory.seedHistory(<VibeTrack>[
        const VibeTrack(
          id: 'aaaaaaaaaaa',
          title: 'Old Favourite',
          artist: 'Arijit Singh',
        ),
      ]);
      memory.noteLike(track('bbbbbbbbbbb', 'New Favourite', artist: 'Neha'));
      final VibeProfile profile = memory.profile;
      expect(profile.artistAffinity('Arijit Singh'), greaterThan(0));
      expect(profile.artistAffinity('Arijit Singh'), lessThan(1));
      expect(profile.artistAffinity('Neha'), 1);
    });
  });
}
