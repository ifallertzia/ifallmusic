import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models/song.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/youtube_service.dart';
import '../../core/theme/saxify_theme.dart';
import '../../data/labels.dart';
import '../../widgets/brand_logo.dart';
import '../shell/shell_controller.dart';
import '../widgets/neon.dart';
import '../widgets/search_fab.dart';
import '../widgets/song_tile.dart';

class BrandsPage extends StatefulWidget {
  const BrandsPage({super.key});

  @override
  State<BrandsPage> createState() => _BrandsPageState();
}

class _BrandsPageState extends State<BrandsPage> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final List<MusicBrand> brands = MusicBrands.filter(_filter);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Music brands'),
        actions: const <Widget>[SaxifySearchButton()],
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Filter by label, artist or song vibe',
                prefixIcon: Icon(Icons.filter_alt_outlined),
              ),
              onChanged: (String v) => setState(() => _filter = v),
              onSubmitted: (String v) {
                if (v.trim().isEmpty) return;
                context.read<ShellController>().goSearch(v.trim());
                Navigator.of(context).popUntil((Route<dynamic> r) => r.isFirst);
              },
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 140),
              itemCount: brands.length,
              itemBuilder: (BuildContext context, int i) {
                final MusicBrand brand = brands[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: NeonCard(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => BrandChannelPage(brand: brand),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        BrandLogo(brand: brand),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                brand.name,
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${brand.region} · @${brand.handle}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: SaxifyColors.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: SaxifyColors.textFaint,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class BrandChannelPage extends StatefulWidget {
  const BrandChannelPage({super.key, required this.brand});

  final MusicBrand brand;

  @override
  State<BrandChannelPage> createState() => _BrandChannelPageState();
}

class _BrandChannelPageState extends State<BrandChannelPage> {
  late final Future<List<Song>> _future = _load();
  String? _error;

  Future<List<Song>> _load() async {
    final YoutubeService youtube = context.read<YoutubeService>();
    final String? id = widget.brand.channelId;
    if (id != null) {
      try {
        final List<Song> uploads = await youtube.channelUploads(id, limit: 24);
        if (uploads.isNotEmpty) return uploads;
      } catch (e) {
        _error = '$e';
      }
    }
    return youtube.searchSongs(widget.brand.searchQuery, limit: 20);
  }

  Future<void> _openYoutube() async {
    await launchUrl(
      Uri.parse(widget.brand.youtubeUrl),
      mode: LaunchMode.externalApplication,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.brand.name),
        actions: <Widget>[
          IconButton(
            tooltip: 'Open channel',
            onPressed: _openYoutube,
            icon: const Icon(Icons.open_in_new_rounded),
          ),
          const SaxifySearchButton(),
        ],
      ),
      body: FutureBuilder<List<Song>>(
        future: _future,
        builder: (BuildContext context, AsyncSnapshot<List<Song>> snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final List<Song> songs = snap.data ?? <Song>[];
          if (songs.isEmpty) {
            return EmptyState(
              icon: Icons.video_library_outlined,
              title: 'Channel uploads unavailable',
              message:
                  _error ?? 'Open the official channel on YouTube instead.',
              actionLabel: 'Open channel',
              onAction: _openYoutube,
            );
          }
          return ListView(
            padding: const EdgeInsets.only(bottom: 140),
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                child: NeonButton(
                  label: 'Play uploads',
                  icon: Icons.play_arrow_rounded,
                  expand: true,
                  onPressed: () =>
                      context.read<PlaybackService>().playQueue(songs),
                ),
              ),
              for (int i = 0; i < songs.length; i++)
                SongTile(
                  song: songs[i],
                  onTap: () => context.read<PlaybackService>().playQueue(
                    songs,
                    startIndex: i,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
