import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../movies/models/movie_models.dart';
import '../../movies/services/movie_download_service.dart';
import '../utils/format.dart';
import 'app_notifications.dart';
import 'music_download_service.dart';

/// Where a download is, as far as the notification shade is concerned.
enum DownloadNoticeState { resolving, queued, running, paused, done, failed, canceled }

/// One download, reduced to what a notification can say about it.
class DownloadNotice {
  const DownloadNotice({
    required this.key,
    required this.title,
    required this.state,
    this.percent = 0,
    this.detail = '',
  });

  /// Stable identity for the whole life of this download.
  final String key;

  /// `Pushpa 2 · 720p`, `Glass Track · Glass Artist`.
  final String title;

  final DownloadNoticeState state;

  /// 0–100, drawn as Android's own progress bar and written into the body.
  final int percent;

  /// `1.2 GB of 2.9 GB · 3.1 MB/s` — whatever the service knows.
  final String detail;

  /// True while there is still something to watch.
  bool get isLive =>
      state == DownloadNoticeState.resolving ||
      state == DownloadNoticeState.queued ||
      state == DownloadNoticeState.running ||
      state == DownloadNoticeState.paused;

  int get id => downloadNotificationId(key);

  String get payload => '${DownloadNotifications.payloadPrefix}$key';

  /// The second line of the card: the percentage first, then whatever the
  /// service knows about bytes and speed.
  String get body {
    return switch (state) {
      DownloadNoticeState.resolving => 'Finding a server…',
      DownloadNoticeState.queued =>
        detail.isEmpty ? 'Waiting in the queue' : detail,
      DownloadNoticeState.running =>
        detail.isEmpty ? '$percent%' : '$percent% · $detail',
      DownloadNoticeState.paused => detail.isEmpty
          ? 'Paused · $percent%'
          : 'Paused · $percent% · $detail',
      // The word the person was waiting for.
      DownloadNoticeState.done =>
        detail.isEmpty ? 'Downloaded' : 'Downloaded · $detail',
      DownloadNoticeState.failed =>
        detail.isEmpty ? 'Download failed' : 'Download failed · $detail',
      DownloadNoticeState.canceled => '',
    };
  }
}

/// One movie/episode download as a notification card.
DownloadNotice movieDownloadNotice(MovieDownloadItem item) {
  return DownloadNotice(
    key: 'movie:${item.id}',
    title: movieDownloadTitle(item),
    state: switch (item.status) {
      MovieDownloadStatus.resolving => DownloadNoticeState.resolving,
      MovieDownloadStatus.queued => DownloadNoticeState.queued,
      MovieDownloadStatus.downloading => DownloadNoticeState.running,
      MovieDownloadStatus.paused => DownloadNoticeState.paused,
      MovieDownloadStatus.completed => DownloadNoticeState.done,
      MovieDownloadStatus.failed => DownloadNoticeState.failed,
      MovieDownloadStatus.canceled => DownloadNoticeState.canceled,
    },
    percent: (item.progress * 100).round(),
    detail: movieDownloadDetail(item),
  );
}

/// `Pushpa 2 · S01 E04 · 720p` — the line the card is recognised by.
String movieDownloadTitle(MovieDownloadItem item) {
  final String title =
      item.movieTitle.trim().isNotEmpty ? item.movieTitle.trim() : 'Download';
  return <String>[
    title,
    if (item.seasonLabel.trim().isNotEmpty) item.seasonLabel.trim(),
    if (item.episodeLabel.trim().isNotEmpty) item.episodeLabel.trim(),
    if (item.qualityLabel.trim().isNotEmpty) item.qualityLabel.trim(),
  ].join(' · ');
}

String movieDownloadDetail(MovieDownloadItem item) {
  if (item.status == MovieDownloadStatus.completed) {
    if (item.totalBytes > 0) return Fmt.bytes(item.totalBytes);
    return item.sizeLabel.trim();
  }
  if (item.status == MovieDownloadStatus.failed) return item.errorMessage.trim();
  return <String>[
    if (item.totalBytes > 0)
      '${Fmt.bytes(item.downloadedBytes)} of ${Fmt.bytes(item.totalBytes)}'
    else if (item.downloadedBytes > 0)
      Fmt.bytes(item.downloadedBytes),
    if (item.speedBytesPerSec >= 1024)
      '${Fmt.bytes(item.speedBytesPerSec.round())}/s',
  ].join(' · ');
}

/// One song download as a notification card.
DownloadNotice musicDownloadNotice(MusicDownloadJob job) {
  return DownloadNotice(
    key: 'song:${job.song.id}',
    title: musicDownloadTitle(job),
    state: switch (job.phase) {
      MusicDownloadPhase.idle => DownloadNoticeState.queued,
      MusicDownloadPhase.running => DownloadNoticeState.running,
      MusicDownloadPhase.done => DownloadNoticeState.done,
      MusicDownloadPhase.failed => DownloadNoticeState.failed,
      MusicDownloadPhase.cancelled => DownloadNoticeState.canceled,
    },
    percent: (job.fraction * 100).round(),
    detail: musicDownloadDetail(job),
  );
}

String musicDownloadTitle(MusicDownloadJob job) {
  final String title =
      job.song.title.trim().isNotEmpty ? job.song.title.trim() : 'Song';
  final String artist = job.song.artist.trim();
  return artist.isEmpty ? title : '$title · $artist';
}

String musicDownloadDetail(MusicDownloadJob job) {
  if (job.phase == MusicDownloadPhase.done) {
    return job.size > 0 ? Fmt.bytes(job.size) : '';
  }
  if (job.phase == MusicDownloadPhase.failed) return job.error ?? '';
  if (job.size > 0) {
    return '${Fmt.bytes(job.received)} of ${Fmt.bytes(job.size)}';
  }
  return job.received > 0 ? Fmt.bytes(job.received) : '';
}

/// Every download the two services currently know about, as notification
/// cards. Movies first so a long download keeps the top slot.
List<DownloadNotice> currentNotices({
  MusicDownloadService? music,
  MovieDownloadService? movies,
}) {
  return <DownloadNotice>[
    for (final MovieDownloadItem item in movies?.items ?? const <MovieDownloadItem>[])
      movieDownloadNotice(item),
    for (final MusicDownloadJob job in music?.jobs ?? const <MusicDownloadJob>[])
      musicDownloadNotice(job),
  ];
}

/// Notification ids live in their own band so they can never collide with the
/// update reminder's.
const int _idBase = 8200;
const int _idSpan = 900000;

/// A download's card id: its key folded into the band above, so the same
/// download always redraws the same card instead of stacking new ones.
int downloadNotificationId(String key) =>
    _idBase + ((key.hashCode & 0x7fffffff) % _idSpan);

/// Everything the shade says about a download, for songs and for movies.
///
/// While a file is coming down there is a card with a live percentage, a byte
/// count and a speed; when it lands the same card says **Downloaded** and can
/// be tapped away. Nothing here is `ongoing`, so a swipe always works — and
/// because Android will not tell us about a swipe, the shade is asked what it
/// still holds: a card the person dismissed stays dismissed instead of popping
/// back on the next progress tick.
///
/// It listens to the two download services rather than being called from
/// inside them, so neither download path has to know notifications exist.
class DownloadNotifications {
  DownloadNotifications();

  static const String channelId = 'sidify_downloads';
  static const String channelName = 'Downloads';
  static const String payloadPrefix = 'sidify-download:';

  /// The card's own icon: a down arrow, so a download is not mistaken for the
  /// music notification sitting next to it.
  static const String icon = 'ic_notification_download';

  /// The mirrors and the CDN report progress every 180–250 ms. Redrawing the
  /// shade that often is noise and battery for a number nobody can read.
  static const Duration _updateEvery = Duration(milliseconds: 900);

  /// How often Android is asked what is still in the shade.
  static const Duration _activeCheckEvery = Duration(seconds: 2);

  final Map<String, _Tracked> _tracked = <String, _Tracked>{};
  DateTime _lastActiveCheck = DateTime.fromMillisecondsSinceEpoch(0);

  MusicDownloadService? _music;
  MovieDownloadService? _movies;
  bool _running = false;
  bool _dirty = false;

  /// False until the first pass has recorded what was already there.
  ///
  /// Both services persist their lists, and a download the app was killed
  /// during comes back marked as still running. Announcing those would put a
  /// card in the shade that never moves; the first pass therefore only takes
  /// notes, and cards start appearing from the second pass onwards — which is
  /// also when a real download's first byte arrives.
  bool _baselined = false;

  /// Starts watching both download queues. Idempotent per service.
  void attach({MusicDownloadService? music, MovieDownloadService? movies}) {
    if (music != null && music != _music) {
      _music?.removeListener(_sync);
      _music = music;
      music.addListener(_sync);
    }
    if (movies != null && movies != _movies) {
      _movies?.removeListener(_sync);
      _movies = movies;
      movies.addListener(_sync);
    }
    unawaited(_sync());
  }

  void dispose() {
    _music?.removeListener(_sync);
    _movies?.removeListener(_sync);
    _music = null;
    _movies = null;
    _tracked.clear();
  }

  // ------------------------------------------------------------------- syncing

  /// Serialized on purpose: two rapid progress events must not interleave two
  /// passes, or a stale "42%" can be drawn over the "Downloaded" that followed
  /// it. A change that arrives mid-pass is picked up by one more pass.
  Future<void> _sync() async {
    if (!AppNotifications.supported) return;
    if (_running) {
      _dirty = true;
      return;
    }
    _running = true;
    try {
      do {
        _dirty = false;
        await _pass();
      } while (_dirty);
    } catch (error) {
      // The shade is a courtesy; a download must never fail because of it.
      debugPrint('[Sidify][Downloads] notification pass skipped: $error');
      _dirty = false;
    } finally {
      _running = false;
    }
  }

  Future<void> _pass() async {
    final List<DownloadNotice> notices = currentNotices(
      music: _music,
      movies: _movies,
    );

    await _learnAboutDismissals(notices);

    final Set<String> present = notices
        .map((DownloadNotice n) => n.key)
        .toSet();
    for (final String key in _tracked.keys.toList()) {
      if (present.contains(key)) continue;
      final _Tracked? tracked = _tracked.remove(key);
      // Gone from the list: cancelled, or deleted from Downloads. A card that
      // already said "Downloaded" is left alone — it belongs to the person now.
      if (tracked != null && !tracked.announced) {
        await AppNotifications.cancel(downloadNotificationId(key));
      }
    }

    for (final DownloadNotice notice in notices) {
      await _apply(notice, baseline: !_baselined);
    }
    _baselined = true;
  }

  Future<void> _apply(DownloadNotice notice, {required bool baseline}) async {
    final bool firstSighting = !_tracked.containsKey(notice.key);
    final _Tracked tracked =
        _tracked.putIfAbsent(notice.key, () => _Tracked(notice.state));
    final DownloadNoticeState previous = tracked.state;
    tracked.state = notice.state;

    if (!notice.isLive) {
      // A download that was already finished when this session started — every
      // song and movie restored from storage — is recorded and never announced.
      // Otherwise each launch would post a pile of old "Downloaded" cards.
      if (baseline || firstSighting || tracked.announced) return;
      tracked.announced = true;
      if (notice.state == DownloadNoticeState.canceled) {
        await AppNotifications.cancel(notice.id);
        return;
      }
      await _post(notice);
      return;
    }

    if (baseline) {
      // Recorded, not announced: see [_baselined].
      tracked.lastPercent = notice.percent;
      return;
    }
    if (firstSighting) await AppNotifications.requestPermission();
    if (tracked.dismissed) return;

    final bool moved = notice.percent != tracked.lastPercent;
    final bool stateChanged = previous != notice.state;
    final bool due =
        DateTime.now().difference(tracked.lastPost) >= _updateEvery;
    if (tracked.lastPercent < 0 || stateChanged || (moved && due)) {
      tracked.lastPercent = notice.percent;
      tracked.lastPost = DateTime.now();
      await _post(notice);
    }
  }

  Future<void> _post(DownloadNotice notice) async {
    final bool terminal = !notice.isLive;
    final int percent = notice.percent.clamp(0, 100);
    await AppNotifications.show(
      notice.id,
      notice.title,
      notice.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          channelId,
          channelName,
          channelDescription:
              'Live progress while songs, movies and episodes download',
          icon: icon,
          importance: Importance.low,
          priority: Priority.low,
          category: AndroidNotificationCategory.progress,
          // Never `ongoing`: the whole point is that the person can swipe a
          // download card away whenever they like.
          ongoing: false,
          // A tap on a live card must not erase the progress; the finished one
          // has said what it came to say and goes when it is tapped.
          autoCancel: terminal,
          onlyAlertOnce: true,
          playSound: false,
          enableVibration: false,
          silent: !terminal,
          showWhen: terminal,
          showProgress: !terminal,
          maxProgress: 100,
          progress: percent,
          visibility: NotificationVisibility.public,
          ticker: terminal
              ? '${notice.title} downloaded'
              : 'Downloading ${notice.title}',
        ),
      ),
      payload: notice.payload,
    );
    final _Tracked? tracked = _tracked[notice.key];
    if (tracked != null && !terminal) tracked.posted = true;
  }

  /// Android has no "this was swiped away" callback, but it does answer "what
  /// is in the shade right now". A card that was confirmed there and is now
  /// gone was dismissed on purpose, so its progress stops being redrawn.
  Future<void> _learnAboutDismissals(List<DownloadNotice> notices) async {
    final List<DownloadNotice> watched = notices
        .where((DownloadNotice n) =>
            n.isLive && !(_tracked[n.key]?.dismissed ?? false))
        .toList();
    if (watched.isEmpty) return;

    final DateTime now = DateTime.now();
    if (now.difference(_lastActiveCheck) < _activeCheckEvery) return;
    _lastActiveCheck = now;

    final Set<int>? active = await AppNotifications.activeIds();
    // `null` means the question could not be asked — not "nothing is showing".
    if (active == null) return;

    for (final DownloadNotice notice in watched) {
      final _Tracked? tracked = _tracked[notice.key];
      if (tracked == null || !tracked.posted) continue;
      if (active.contains(notice.id)) {
        tracked.seenActive = true;
      } else if (tracked.seenActive) {
        tracked.dismissed = true;
      }
    }
  }
}

/// What has already happened to one download's card.
class _Tracked {
  _Tracked(this.state);

  DownloadNoticeState state;

  /// The finished card has been posted — it is posted exactly once.
  bool announced = false;

  /// A progress card has actually been handed to Android.
  bool posted = false;

  /// …and Android has confirmed it is in the shade.
  bool seenActive = false;

  /// The person swiped it away: stop redrawing it.
  bool dismissed = false;

  int lastPercent = -1;
  DateTime lastPost = DateTime.fromMillisecondsSinceEpoch(0);
}
