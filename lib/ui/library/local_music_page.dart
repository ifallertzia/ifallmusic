import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/local_music_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../widgets/sidify_widgets.dart';

/// On this device: the music already on the phone, scanned on-device and
/// played locally. Kept from the old Library, wearing Sidify clothes.
class LocalMusicPage extends StatefulWidget {
  const LocalMusicPage({super.key});

  @override
  State<LocalMusicPage> createState() => _LocalMusicPageState();
}

class _LocalMusicPageState extends State<LocalMusicPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final LocalMusicService local = context.read<LocalMusicService>();
      if (!local.hasScanned && !local.scanning) {
        local.scan(context: context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final LocalMusicService local = context.watch<LocalMusicService>();
    final SidifyTokens t = context.sidify;
    final List<Song> songs = local.songs;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('On this device', style: SidifyText.titleM(t.text)),
        actions: <Widget>[
          TextButton(
            onPressed: local.scanning
                ? null
                : () => local.scan(context: context),
            child: Text(
              local.scanning ? 'Scanning…' : 'Re-scan',
              style: TextStyle(color: t.text),
            ),
          ),
        ],
      ),
      body: local.scanning && songs.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : songs.isEmpty
              ? EmptyState(
                  icon: Icons.smartphone_rounded,
                  title: 'No music found yet',
                  desc: local.hasScanned
                      ? 'Add music files to your phone, then re-scan.'
                      : 'Sidify can play the music already on your phone.',
                  action: SidifyButton(
                    label: 'Scan this device',
                    small: true,
                    onTap: () => local.scan(context: context),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 190),
                  physics: const BouncingScrollPhysics(),
                  itemCount: songs.length,
                  itemBuilder: (BuildContext context, int i) => Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: TrackRow(
                      tracks: songs,
                      index: i,
                      onTap: () => context
                          .read<PlaybackService>()
                          .playOfflineQueue(
                            songs,
                            <String, String>{
                              for (final Song s in songs)
                                if (s.localUri != null) s.id: s.localUri!,
                            },
                            startIndex: i,
                          ),
                    ),
                  ),
                ),
    );
  }
}
