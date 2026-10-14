import 'package:flutter/material.dart';

import '../../core/models/album_card.dart';
import '../../core/models/playlist.dart';
import '../../core/models/song.dart';
import '../../services/yt_music_parser.dart';
import '../album/album_page.dart';
import '../library/playlist_detail_page.dart';
import '../player/full_player_page.dart';

/// Route names + the app's page openers. Pushed pages keep the mini player
/// docked underneath (the shell's dock layer handles that); the full player
/// is the one route that covers it.
abstract final class SidifyRoutes {
  static const String fullPlayer = 'sidify/full-player';
  static const String album = 'sidify/album';
  static const String artist = 'sidify/artist';
  static const String playlist = 'sidify/playlist';
  static const String browse = 'sidify/browse';
  static const String together = 'sidify/together';
  static const String settings = 'sidify/settings';
}

void openFullPlayer(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const FullPlayerPage(),
      settings: const RouteSettings(name: SidifyRoutes.fullPlayer),
      fullscreenDialog: true,
    ),
  );
}

void openAlbum(BuildContext context, AlbumCard album) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AlbumPage(album: album),
      settings: const RouteSettings(name: SidifyRoutes.album),
    ),
  );
}

void openPlaylist(BuildContext context, Playlist playlist) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => PlaylistDetailPage(playlist: playlist),
      settings: const RouteSettings(name: SidifyRoutes.playlist),
    ),
  );
}

void openBrowse(BuildContext context, MusicBrowseItem item) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => AlbumPage.fromBrowse(item: item),
      settings: const RouteSettings(name: SidifyRoutes.browse),
    ),
  );
}

/// A song's album, as an album card (the engine's album = an encoded search).
AlbumCard albumCardForSong(Song song) => AlbumCard(
      query: '${song.album ?? song.title} ${song.artist}',
      title: song.album ?? song.title,
      artist: song.artist,
    );
