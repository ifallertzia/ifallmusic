/// The download card: what the notification shade is told while a song, a
/// movie or an episode is coming down, and what it says when it lands.
///
/// Posting itself belongs to Android and is exercised on a device; what is
/// pinned here is the mapping from a download to a card, because that is the
/// part with the numbers in it — a percentage that never moves, or a card that
/// announces last week's downloads again at every launch, is a bug nobody can
/// see without a phone in front of them.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:ifallmusic/core/models/song.dart';
import 'package:ifallmusic/core/services/download_notifications.dart';
import 'package:ifallmusic/core/services/music_download_service.dart';
import 'package:ifallmusic/movies/models/movie_models.dart';

MovieDownloadItem _movie({
  String id = 'm1',
  String title = 'Pushpa 2',
  String quality = '720p',
  String season = '',
  String episode = '',
  MovieDownloadStatus status = MovieDownloadStatus.downloading,
  int done = 1024 * 1024 * 1024,
  int total = 2 * 1024 * 1024 * 1024,
  double speed = 3.2 * 1024 * 1024,
  String error = '',
  String sizeLabel = '',
}) {
  return MovieDownloadItem(
    id: id,
    movieTitle: title,
    qualityLabel: quality,
    sourceDlUrl: 'https://mirror.invalid/file.mkv',
    status: status,
    createdAtMs: 0,
    seasonLabel: season,
    episodeLabel: episode,
    downloadedBytes: done,
    totalBytes: total,
    speedBytesPerSec: speed,
    errorMessage: error,
    sizeLabel: sizeLabel,
  );
}

MusicDownloadJob _song({
  String id = 's1',
  MusicDownloadPhase phase = MusicDownloadPhase.running,
  double fraction = 0.42,
  int received = 4200000,
  int size = 10000000,
}) {
  final MusicDownloadJob job = MusicDownloadJob(
    song: Song(
      id: id,
      title: 'Glass Track',
      artist: 'Glass Artist',
      thumbnailUrl: '',
    ),
  )
    ..phase = phase
    ..fraction = fraction
    ..received = received
    ..size = size;
  return job;
}

void main() {
  group('movie download card', () {
    test('a running download carries a live percentage', () {
      final DownloadNotice notice = movieDownloadNotice(_movie());
      expect(notice.state, DownloadNoticeState.running);
      expect(notice.isLive, isTrue);
      expect(notice.percent, 50);
      expect(notice.body, startsWith('50%'));
      expect(notice.body, contains('1.0 GB of 2.0 GB'));
      expect(notice.body, contains('MB/s'));
      expect(notice.title, 'Pushpa 2 · 720p');
    });

    test('an episode names its season and episode', () {
      expect(
        movieDownloadNotice(
          _movie(season: 'Season 1', episode: 'E04', quality: '480p'),
        ).title,
        'Pushpa 2 · Season 1 · E04 · 480p',
      );
    });

    test('a mirror hunt and a queue slot say so instead of showing 0%', () {
      expect(
        movieDownloadNotice(
          _movie(status: MovieDownloadStatus.resolving, done: 0, total: 0),
        ).body,
        'Finding a server…',
      );
      expect(
        movieDownloadNotice(
          _movie(status: MovieDownloadStatus.queued, done: 0, total: 0),
        ).body,
        'Waiting in the queue',
        reason: 'a queue slot has no bytes and no speed of its own to report',
      );
    });

    test('a paused download keeps its percentage', () {
      final DownloadNotice notice = movieDownloadNotice(
        _movie(status: MovieDownloadStatus.paused),
      );
      expect(notice.isLive, isTrue);
      expect(notice.body, startsWith('Paused · 50%'));
    });

    test('finished says Downloaded, and failed says why', () {
      final DownloadNotice done = movieDownloadNotice(
        _movie(status: MovieDownloadStatus.completed, speed: 0),
      );
      expect(done.state, DownloadNoticeState.done);
      expect(done.isLive, isFalse);
      expect(done.body, startsWith('Downloaded'));

      final DownloadNotice failed = movieDownloadNotice(
        _movie(status: MovieDownloadStatus.failed, error: 'Mirror died'),
      );
      expect(failed.state, DownloadNoticeState.failed);
      expect(failed.body, contains('Mirror died'));

      final DownloadNotice canceled = movieDownloadNotice(
        _movie(status: MovieDownloadStatus.canceled),
      );
      expect(canceled.state, DownloadNoticeState.canceled);
      expect(canceled.isLive, isFalse);
    });
  });

  group('song download card', () {
    test('a running song carries a live percentage', () {
      final DownloadNotice notice = musicDownloadNotice(_song());
      expect(notice.state, DownloadNoticeState.running);
      expect(notice.percent, 42);
      expect(notice.body, startsWith('42%'));
      expect(notice.title, 'Glass Track · Glass Artist');
    });

    test('finished says Downloaded', () {
      final DownloadNotice notice = musicDownloadNotice(
        _song(phase: MusicDownloadPhase.done, fraction: 1),
      );
      expect(notice.state, DownloadNoticeState.done);
      expect(notice.body, 'Downloaded · ${notice.detail}');
      expect(notice.body, startsWith('Downloaded'));
    });

    test('cancelled says nothing at all', () {
      expect(
        musicDownloadNotice(_song(phase: MusicDownloadPhase.cancelled)).body,
        '',
      );
    });
  });

  group('card identity', () {
    test('the same download always redraws the same card', () {
      expect(movieDownloadNotice(_movie()).id, movieDownloadNotice(_movie()).id);
      expect(
        movieDownloadNotice(_movie(id: 'm1')).id,
        isNot(movieDownloadNotice(_movie(id: 'm2')).id),
      );
      expect(
        movieDownloadNotice(_movie()).id,
        isNot(musicDownloadNotice(_song()).id),
        reason: 'a movie and a song with equal ids are two downloads',
      );
    });

    test('card ids stay in their own band, away from the update reminder', () {
      for (final String key in <String>['movie:a', 'song:b', 'movie:zzzz']) {
        final int id = downloadNotificationId(key);
        expect(id, greaterThanOrEqualTo(8200));
        expect(id, lessThan(8200 + 900000));
        expect(id, isNot(7401));
      }
    });

    test('the payload carries the download key back on a tap', () {
      final DownloadNotice notice = movieDownloadNotice(_movie());
      expect(notice.payload, '${DownloadNotifications.payloadPrefix}movie:m1');
    });
  });

  group('every state has a line', () {
    test('no download state is left without a body', () {
      for (final DownloadNoticeState state in DownloadNoticeState.values) {
        final DownloadNotice notice = DownloadNotice(
          key: 'k',
          title: 'Title',
          state: state,
          percent: 7,
        );
        expect(
          notice.body,
          state == DownloadNoticeState.canceled ? '' : isNotEmpty,
          reason: '$state needs a body',
        );
      }
    });
  });
}
