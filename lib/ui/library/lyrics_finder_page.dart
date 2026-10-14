import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/youtube_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../player/lyrics_view.dart';
import '../widgets/sidify_widgets.dart';

/// The Lyrics finder from the Library: look up the words to any song.
/// Type a title, pick the song, read along — credited to Sidify, always.
class LyricsFinderPage extends StatefulWidget {
  const LyricsFinderPage({super.key});

  @override
  State<LyricsFinderPage> createState() => _LyricsFinderPageState();
}

class _LyricsFinderPageState extends State<LyricsFinderPage> {
  final TextEditingController _controller = TextEditingController();
  List<Song> _results = <Song>[];
  bool _loading = false;
  bool _searched = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    final String q = query.trim();
    if (q.isEmpty) return;
    setState(() {
      _loading = true;
      _searched = true;
    });
    try {
      final List<Song> songs =
          await context.read<YoutubeService>().searchSongs(q, limit: 15);
      if (!mounted) return;
      setState(() {
        _results = songs;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _results = <Song>[];
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_rounded, color: t.text),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Lyrics finder', style: SidifyText.titleM(t.text)),
      ),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: t.fill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.edge, width: 0.5),
              ),
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 12),
                  Icon(Icons.lyrics_rounded, size: 19, color: t.text2),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autofocus: true,
                      onSubmitted: _search,
                      style: TextStyle(fontSize: 16, color: t.text),
                      decoration: InputDecoration(
                        hintText: 'Song or artist…',
                        hintStyle: TextStyle(color: t.text2),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _search(_controller.text),
                    child: Text('Find', style: TextStyle(color: t.text)),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : !_searched
                    ? const EmptyState(
                        icon: Icons.lyrics_rounded,
                        title: 'Find the words',
                        desc: 'Search a song and Sidify will find its '
                            'lyrics, timed line by line when it can.',
                      )
                    : _results.isEmpty
                        ? const EmptyState(
                            icon: Icons.search_off_rounded,
                            title: 'No songs found',
                            desc: 'Try another title or artist.',
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.only(bottom: 190),
                            physics: const BouncingScrollPhysics(),
                            itemCount: _results.length,
                            itemBuilder: (BuildContext context, int i) {
                              final Song s = _results[i];
                              return Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: () => Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => LyricsViewPage(song: s),
                                      settings: const RouteSettings(
                                        name: 'sidify/lyrics',
                                      ),
                                    ),
                                  ),
                                  child: Container(
                                    height: 64,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16),
                                    child: Row(
                                      children: <Widget>[
                                        Artwork(
                                          url: s.thumbnailUrl,
                                          size: 52,
                                          radius: 6,
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            mainAxisAlignment:
                                                MainAxisAlignment.center,
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: <Widget>[
                                              Text(
                                                s.title,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 15,
                                                  color: t.text,
                                                ),
                                              ),
                                              Text(
                                                s.artist,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 13,
                                                  color: t.text2,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(Icons.chevron_right_rounded,
                                            size: 18, color: t.text3),
                                      ],
                                    ),
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
