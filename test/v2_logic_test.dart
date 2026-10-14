import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/config/branding.dart';
import 'package:ifallmusic/core/services/playlist_sync_service.dart';
import 'package:ifallmusic/core/services/recommendation_engine.dart';
import 'package:ifallmusic/core/utils/backup_codec.dart';
import 'package:ifallmusic/core/utils/filenames.dart';
import 'package:ifallmusic/core/utils/text_match.dart';

void main() {
  group('artist routing scores', () {
    test('exact and near names clear 0.8, unrelated names do not', () {
      expect(TextMatch.score('Arijit Singh', 'Arijit Singh'), 1);
      expect(TextMatch.score('Arijit Singh', 'Arijit Singh Official'), greaterThan(0.8));
      expect(TextMatch.score('Arijit Singh', 'T-Series'), lessThan(0.8));
    });
  });

  group('recommendations', () {
    RecoTrack track(String id, {String artist = 'Ari'}) {
      return RecoTrack(id: id, title: id, artist: artist);
    }

    test('mix never returns the current song or the last 10 plays', () {
      final RecoTrack current = track('now');
      final List<RecoTrack> similar = <RecoTrack>[
        current,
        for (int i = 0; i < 12; i++) track('s$i'),
      ];
      final List<RecoTrack> searched = <RecoTrack>[
        for (int i = 0; i < 8; i++) track('q$i', artist: 'Other'),
      ];
      final List<RecoTrack> discovery = <RecoTrack>[
        for (int i = 0; i < 6; i++) track('d$i', artist: 'New'),
      ];
      final List<RecoTrack> mixed = RecommendationEngine.mix(
        similar: similar,
        searchDriven: searched,
        discovery: discovery,
        signals: RecoSignals(
          current: current,
          recentIds: <String>[for (int i = 0; i < 10; i++) 's$i'],
        ),
      );
      final Set<String> ids = mixed.map((RecoTrack t) => t.id).toSet();
      expect(ids.contains('now'), isFalse);
      for (int i = 0; i < 10; i++) {
        expect(ids.contains('s$i'), isFalse);
      }
      expect(mixed, isNotEmpty);
    });
  });

  group('backup and filenames', () {
    test('backup json must contain a library key', () {
      expect(validateBackupJson(''), isNotNull);
      expect(validateBackupJson('{"nope":[]}'), isNotNull);
      expect(validateBackupJson('{"playlists":[]}'), isNull);
    });

    test('saved names use the app suffix and reject html', () {
      expect(Filenames.saxify('Night Drive', 'mp3'), 'Night Drive${SidifyBranding.fileSuffix}.mp3');
      expect(Filenames.looksCorrupt('<html>nope'.codeUnits, 20), isTrue);
      expect(Filenames.looksCorrupt(<int>[0x49, 0x44, 0x33], 2048), isFalse);
    });
  });


  group('playlist payload', () {
    test('single and bulk payloads become playlists', () {
      final single = PlaylistSyncService.playlistsFromPayload(<String, dynamic>{
        'title': 'Road',
        'songs': <Map<String, dynamic>>[
          <String, dynamic>{'id': 'v1', 'title': 'One', 'artist': 'A', 'thumb': ''},
        ],
      });
      expect(single, hasLength(1));
      expect(single.first.songs.first.id, 'v1');

      final bulk = PlaylistSyncService.playlistsFromPayload(<String, dynamic>{
        'playlists': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'p1',
            'name': 'All',
            'songs': <Map<String, dynamic>>[
              <String, dynamic>{'id': 'v2', 'title': 'Two', 'artist': 'B', 'thumb': ''},
            ],
          },
        ],
      });
      expect(bulk.single.name, 'All');
    });
  });
}
