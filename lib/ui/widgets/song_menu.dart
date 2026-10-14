import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/album_card.dart';
import '../../core/models/song.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/library_service.dart';
import '../../core/services/music_download_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../album/album_page.dart';
import '../artist/artist_page.dart';
import '../player/lyrics_view.dart';
import 'add_to_playlist_sheet.dart';
import 'sidify_widgets.dart';

/// A bottom sheet in the site's `menu-glass` style: rounded top, hairline
/// edge, blurred raised colour.
Future<void> showSidifySheet(
  BuildContext context, {
  required Widget child,
  String? title,
  String? subtitle,
}) {
  final SidifyTokens t = context.sidify;
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) {
      return SafeArea(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.88,
          ),
          decoration: BoxDecoration(
            color: t.raised.withValues(alpha: 0.94),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            border: Border.all(color: t.edge, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 5,
                decoration: BoxDecoration(
                  color: t.fill3,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              if (title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SidifyText.title(t.text),
                            ),
                            if (subtitle != null)
                              Text(
                                subtitle,
                                style: TextStyle(fontSize: 13, color: t.text2),
                              ),
                          ],
                        ),
                      ),
                      SidifyIconButton(
                        icon: Icons.close_rounded,
                        label: 'Close',
                        tone: 'fill',
                        size: 30,
                        iconSize: 16,
                        onTap: () => Navigator.of(sheetContext).pop(),
                      ),
                    ],
                  ),
                ),
              Flexible(child: child),
            ],
          ),
        ),
      );
    },
  );
}

/// The track menu (the site's TrackMenu): play next, queue, radio, playlist,
/// love, download, lyrics, artist, album, share link.
Future<void> showSongMenu(BuildContext context, Song song) {
  final SidifyTokens t = context.sidify;
  return showSidifySheet(
    context,
    child: Consumer3<PlaybackService, LibraryService, MusicDownloadService>(
      builder: (BuildContext context, PlaybackService playback,
          LibraryService library, MusicDownloadService downloads, _) {
        final bool liked = library.isLiked(song.id);
        final MusicDownloadJob? job = downloads.jobFor(song.id);
        final bool downloaded =
            job?.phase == MusicDownloadPhase.done && job?.offlinePath != null;
        final bool downloading = job?.phase == MusicDownloadPhase.running ||
            job?.phase == MusicDownloadPhase.idle;

        Widget item(IconData icon, String label, VoidCallback onTap,
            {bool danger = false}) {
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                Navigator.of(context).pop();
                onTap();
              },
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: <Widget>[
                    Icon(icon, size: 19, color: danger ? t.danger : t.text),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 15.5,
                          color: danger ? t.danger : t.text,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: <Widget>[
                    Artwork(url: song.thumbnailUrl, size: 52, radius: 8),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: t.text,
                            ),
                          ),
                          Text(
                            song.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 13.5, color: t.text2),
                          ),
                        ],
                      ),
                    ),
                    if (downloaded)
                      Icon(Icons.download_done_rounded, size: 20, color: t.text2),
                  ],
                ),
              ),
              Divider(height: 0.5, thickness: 0.5, color: t.hairline),
              const SizedBox(height: 6),
              item(Icons.play_arrow_rounded, 'Play next', () {
                playback.playNext(song);
                showAppNotice('Playing next');
              }),
              item(Icons.queue_music_rounded, 'Add to queue', () {
                playback.addToQueue(song);
                showAppNotice('Added to queue');
              }),
              item(Icons.radio_rounded, 'Start radio', () {
                playback.playRadio(song);
              }),
              item(Icons.playlist_add_rounded, 'Add to playlist…', () {
                showAddToPlaylistSheet(context, song);
              }),
              item(
                liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                liked ? 'Remove from Liked Songs' : 'Love',
                () => library.toggleLike(song),
              ),
              item(
                downloading
                    ? Icons.downloading_rounded
                    : Icons.download_rounded,
                downloading ? 'Downloading…' : 'Download',
                () async {
                  if (downloading) {
                    downloads.cancel(job);
                    showAppNotice('Download cancelled');
                    return;
                  }
                  final MusicDownloadJob result =
                      await downloads.enqueue(song, playback);
                  if (result.phase == MusicDownloadPhase.done) {
                    showAppNotice('Saved for offline listening');
                  }
                },
              ),
              item(Icons.lyrics_rounded, 'Lyrics', () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LyricsViewPage(song: song),
                    settings: const RouteSettings(name: 'sidify/lyrics'),
                  ),
                );
              }),
              item(Icons.person_rounded, 'Go to artist', () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ArtistPage(
                      name: song.artist,
                      channelId: song.channelId ?? song.artistId,
                    ),
                    settings: const RouteSettings(name: 'sidify/artist'),
                  ),
                );
              }),
              if ((song.album ?? '').isNotEmpty)
                item(Icons.album_rounded, 'Go to album', () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => AlbumPage(
                        album: AlbumCard(
                          query: '${song.album} ${song.artist}',
                          title: song.album!,
                          artist: song.artist,
                        ),
                      ),
                      settings: const RouteSettings(name: 'sidify/album'),
                    ),
                  );
                }),
              item(Icons.link_rounded, 'Copy song link', () {
                Clipboard.setData(
                  ClipboardData(
                    text: 'https://sidify.vercel.app/search?q='
                        '${Uri.encodeQueryComponent('${song.title} ${song.artist}')}',
                  ),
                );
                showAppNotice('Link copied');
              }),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    ),
  );
}
