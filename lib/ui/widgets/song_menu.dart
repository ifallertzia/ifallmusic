import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/library_service.dart';
import '../../core/services/music_download_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/saxify_theme.dart';
import '../../core/utils/format.dart';
import '../../screens/lyrics_finder_screen.dart';
import '../artist/artist_router.dart';
import '../downloads/storage_permission.dart';
import 'add_to_playlist_sheet.dart';
import 'artwork.dart';

/// The overflow sheet behind every track row.
Future<void> showSongSheet(
  BuildContext context,
  Song song, {
  bool radio = false,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (BuildContext sheetContext) =>
        _SongSheet(song: song, radio: radio),
  );
}

class _SongSheet extends StatelessWidget {
  const _SongSheet({required this.song, required this.radio});

  final Song song;
  final bool radio;

  Future<void> _openArtist(BuildContext context) async {
    await openArtistByName(
      context,
      name: song.artist,
      channelId: song.channelId,
    );
  }

  Future<void> _download(BuildContext context) async {
    final bool allowed = await StoragePermission.ensure(context);
    if (!allowed || !context.mounted) return;
    final PlaybackService playback = context.read<PlaybackService>();
    final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Saving to Download/IfallMusic. Playback keeps going.'),
      ),
    );
    final MusicDownloadJob job = await context
        .read<MusicDownloadService>()
        .enqueue(song, playback);
    if (!context.mounted) return;
    final String message = switch (job.phase) {
      MusicDownloadPhase.done => 'Song Downloads folder mein save ho gaya!',
      MusicDownloadPhase.failed =>
        job.error ?? 'Could not save that song. Playback keeps going.',
      MusicDownloadPhase.cancelled =>
        'Download cancelled. Playback keeps going.',
      _ => 'Saving to Download/IfallMusic. Playback keeps going.',
    };
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final LibraryService library = context.watch<LibraryService>();
    final PlaybackService playback = context.read<PlaybackService>();
    final bool liked = library.isLiked(song.id);

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        child: Container(
          decoration: const BoxDecoration(
            color: SaxifyColors.surface,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(SaxifyTheme.radiusLg),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: SaxifyColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                child: Row(
                  children: <Widget>[
                    Artwork(url: song.thumbnailUrl, size: 54, radius: 10),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            song.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${song.artist} · ${Fmt.duration(song.duration)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: SaxifyColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              _Action(
                icon: Icons.play_circle_outline_rounded,
                label: 'Play now',
                onTap: () {
                  Navigator.of(context).pop();
                  radio ? playback.playRadio(song) : playback.playSong(song);
                },
              ),
              _Action(
                icon: Icons.playlist_add_rounded,
                label: 'Play next',
                onTap: () {
                  Navigator.of(context).pop();
                  playback.playNext(song);
                  _toast(context, 'Playing next');
                },
              ),
              _Action(
                icon: Icons.queue_music_rounded,
                label: 'Add to queue',
                onTap: () {
                  Navigator.of(context).pop();
                  playback.addToQueue(song);
                  _toast(context, 'Added to queue');
                },
              ),
              _Action(
                icon: liked
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                label: liked ? 'Remove from Liked Songs' : 'Add to Liked Songs',
                onTap: () {
                  library.toggleLike(song);
                  Navigator.of(context).pop();
                },
              ),
              _Action(
                icon: Icons.playlist_add_check_circle_outlined,
                label: 'Add to playlist',
                onTap: () {
                  Navigator.of(context).pop();
                  showAddToPlaylistSheet(context, song);
                },
              ),
              _Action(
                icon: Icons.person_outline_rounded,
                label: 'Go to artist',
                onTap: () {
                  Navigator.of(context).pop();
                  _openArtist(context);
                },
              ),
              _Action(
                icon: Icons.download_rounded,
                label: 'Download song',
                onTap: () {
                  final BuildContext host = Navigator.of(context).context;
                  Navigator.of(context).pop();
                  _download(host);
                },
              ),
              _Action(
                icon: Icons.lyrics_outlined,
                label: 'Lyrics',
                onTap: () {
                  final host = Navigator.of(context).context;
                  Navigator.of(context).pop();
                  showLyricsPanel(host, song);
                },
              ),
              _Action(
                icon: Icons.share_outlined,
                label: 'Share · copy link',
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: 'https://music.youtube.com/watch?v=${song.id}',
                    ),
                  );
                  if (context.mounted) {
                    _toast(context, 'Song link copied');
                    Navigator.of(context).pop();
                  }
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Action extends StatelessWidget {
  const _Action({required this.icon, required this.label, required this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, size: 21, color: SaxifyColors.textSecondary),
      title: Text(
        label,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 22),
    );
  }
}
