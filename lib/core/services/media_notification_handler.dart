import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart' as audio;

import '../models/song.dart';
import 'library_service.dart';
import 'local_music_service.dart';
import 'music_download_service.dart';
import 'playback_service.dart';

/// One media session, connected to the app's real queue rather than a
/// just_audio_background single-source queue. Stream extraction is untouched.
class MediaNotificationHandler extends BaseAudioHandler with SeekHandler {
  PlaybackService? _playback;
  LibraryService? _library;
  LocalMusicService? _localMusic;
  MusicDownloadService? _downloads;
  StreamSubscription<audio.PlaybackEvent>? _events;
  bool _stopped = false;
  void attach(
    PlaybackService playback,
    LibraryService library, {
    LocalMusicService? localMusic,
    MusicDownloadService? downloads,
  }) {
    _playback?.removeListener(_publish);
    _library?.removeListener(_publish);
    _localMusic?.removeListener(_publish);
    _downloads?.removeListener(_publish);
    _events?.cancel();
    _playback = playback;
    _library = library;
    _localMusic = localMusic;
    _downloads = downloads;
    playback.addListener(_publish);
    library.addListener(_publish);
    localMusic?.addListener(_publish);
    downloads?.addListener(_publish);
    _events = playback.player.playbackEventStream.listen(
      (_) => _publish(),
      onError: (Object _) {},
    );
    _publish();
  }

  MediaItem _item(Song s) => MediaItem(
    id: s.id,
    title: s.title,
    artist: s.artist,
    album: s.album ?? s.subtitle ?? 'IfallMusic',
    artUri: s.thumbnailUrl.startsWith('https://')
        ? Uri.tryParse(s.thumbnailUrl)
        : null,
    duration:
        s.id == _playback?.current?.id && _playback!.duration > Duration.zero
        ? _playback!.duration
        : s.duration,
    rating: Rating.newHeartRating(_library?.isLiked(s.id) ?? false),
  );
  void _publish() {
    final p = _playback;
    if (p == null || p.current == null) return;
    if (p.isLoading || p.isPlaying) _stopped = false;
    if (_stopped) return;
    mediaItem.add(_item(p.current!));
    queue.add(p.queue.map(_item).toList());
    final state = p.player.processingState;
    playbackState.add(
      PlaybackState(
        controls: [
          MediaControl.skipToPrevious,
          p.isPlaying ? MediaControl.pause : MediaControl.play,
          MediaControl.skipToNext,
          MediaControl(
            androidIcon: 'drawable/ic_notification_like',
            label: _library!.isLiked(p.current!.id) ? 'Unlike' : 'Like',
            action: MediaAction.custom,
            customAction: const CustomMediaAction(name: 'toggleLike'),
          ),
          MediaControl.stop,
        ],
        androidCompactActionIndices: const [0, 1, 2],
        systemActions: const {
          MediaAction.seek,
          MediaAction.seekForward,
          MediaAction.seekBackward,
          MediaAction.setRating,
        },
        processingState: p.isLoading
            ? AudioProcessingState.loading
            : switch (state) {
                audio.ProcessingState.idle => AudioProcessingState.idle,
                audio.ProcessingState.loading => AudioProcessingState.loading,
                audio.ProcessingState.buffering =>
                  AudioProcessingState.buffering,
                audio.ProcessingState.ready => AudioProcessingState.ready,
                audio.ProcessingState.completed =>
                  AudioProcessingState.completed,
              },
        playing: p.isPlaying,
        updatePosition: p.player.position,
        bufferedPosition: p.player.bufferedPosition,
        speed: p.speed,
        queueIndex: p.currentIndex,
      ),
    );
  }

  MediaItem _folder(String id, String title, String subtitle) => MediaItem(
        id: id,
        title: title,
        artist: subtitle,
        playable: false,
        extras: const <String, Object>{'browsable': true},
      );

  @override
  Future<List<MediaItem>> getChildren(
    String parentMediaId, [
    Map<String, dynamic>? options,
  ]) async {
    final LibraryService? library = _library;
    if (library == null) return <MediaItem>[];
    if (parentMediaId == AudioService.browsableRootId) {
      return <MediaItem>[
        _folder('liked', 'Liked Songs', '${library.likedSongs.length} songs'),
        _folder('playlists', 'Playlists', '${library.playlists.length} playlists'),
        _folder('downloads', 'Downloads', '${_downloads?.downloaded.length ?? 0} songs'),
        _folder('on_device', 'On device', '${_localMusic?.songs.length ?? 0} songs'),
      ];
    }
    if (parentMediaId == 'liked') return library.likedSongs.map(_item).toList();
    if (parentMediaId == 'downloads') {
      return (_downloads?.downloaded ?? <MusicDownloadJob>[])
          .map((MusicDownloadJob job) => _item(job.song))
          .toList();
    }
    if (parentMediaId == 'on_device') return (_localMusic?.songs ?? <Song>[]).map(_item).toList();
    if (parentMediaId == 'playlists') {
      return library.playlists
          .map((playlist) => _folder('playlist:${playlist.id}', playlist.name, '${playlist.count} songs'))
          .toList();
    }
    if (parentMediaId.startsWith('playlist:')) {
      final String id = parentMediaId.substring('playlist:'.length);
      for (final playlist in library.playlists) {
        if (playlist.id == id) return playlist.songs.map(_item).toList();
      }
    }
    return <MediaItem>[];
  }

  @override
  Future<void> play() async {
    _stopped = false;
    await _playback?.resume();
  }

  @override
  Future<void> pause() async {
    await _playback?.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    await _playback?.seekTo(position);
  }

  @override
  Future<void> skipToNext() async {
    await _playback?.next();
  }

  @override
  Future<void> skipToPrevious() async {
    await _playback?.previous();
  }

  @override
  Future<void> playFromMediaId(
    String mediaId, [
    Map<String, dynamic>? extras,
  ]) async {
    final PlaybackService? playback = _playback;
    final LibraryService? library = _library;
    if (playback == null || library == null) return;
    for (final MusicDownloadJob job in _downloads?.downloaded ?? <MusicDownloadJob>[]) {
      if (job.song.id == mediaId && job.offlinePath != null) {
        await playback.playOfflineSong(job.song, job.offlinePath!);
        return;
      }
    }
    final List<Song> candidates = <Song>[
      ...library.likedSongs,
      ...library.playlists.expand((playlist) => playlist.songs),
      ...?_localMusic?.songs,
    ];
    final int index = candidates.indexWhere((Song song) => song.id == mediaId);
    if (index >= 0) await playback.playSong(candidates[index]);
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    final p = _playback;
    if (p != null && index >= 0 && index < p.queue.length)
      await p.skipToIndex(index);
  }

  @override
  Future<void> setRating(Rating rating, [Map<String, dynamic>? extras]) async {
    final song = _playback?.current;
    if (song != null && rating.hasHeart() != _library!.isLiked(song.id))
      await _library!.toggleLike(song);
  }

  @override
  Future<dynamic> customAction(
    String name, [
    Map<String, dynamic>? extras,
  ]) async {
    final song = _playback?.current;
    if (name == 'toggleLike' && song != null) await _library?.toggleLike(song);
  }

  @override
  Future<void> stop() async {
    await seekForward(false);
    await _playback?.stop();
    _stopped = true;
    playbackState.add(
      PlaybackState(processingState: AudioProcessingState.idle, playing: false),
    );
    mediaItem.add(null);
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() => stop();
}
