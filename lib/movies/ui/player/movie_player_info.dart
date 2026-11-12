import 'package:flutter/material.dart';

import '../../models/movie_models.dart';
import '../movie_ui_widgets.dart';

/// One button of the action row under the title (My List, Download, Share…).
class MoviePlayerAction {
  const MoviePlayerAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Drawn in the accent colour (a title that is already in My List).
  final bool active;
}

/// What the portrait layout shows below the video: the title and its facts,
/// the action row, the servers this title can be streamed from, the story and
/// the related titles.
///
/// Every section is drawn only when there is something real to put in it — a
/// downloaded file has no synopsis or related titles, so it simply shows its
/// name, its details and the actions that apply to a file.
class MoviePlayerInfoPanel extends StatefulWidget {
  const MoviePlayerInfoPanel({
    super.key,
    required this.title,
    required this.meta,
    required this.actions,
    this.rating = '',
    this.genres = const <String>[],
    this.synopsis = '',
    this.serverCount = 0,
    this.currentServer = -1,
    this.failedServers = const <int>{},
    this.onServer,
    this.related = const <MoviePost>[],
    this.onRelated,
    this.footnote = '',
  });

  static const Color accent = Color(0xFFFA2D48);

  final String title;

  /// Year, "Season 1 • Episode 2", the playing quality, the languages…
  final List<String> meta;

  /// The score printed on the title's page (`7.4`), or empty.
  final String rating;
  final List<String> genres;
  final String synopsis;
  final List<MoviePlayerAction> actions;

  /// The mirrors the current quality resolved to. Shown when there is more
  /// than one to choose from.
  final int serverCount;
  final int currentServer;
  final Set<int> failedServers;
  final void Function(int index)? onServer;

  final List<MoviePost> related;
  final void Function(MoviePost post)? onRelated;

  /// A quiet line at the very bottom ("Playing from this device").
  final String footnote;

  @override
  State<MoviePlayerInfoPanel> createState() => _MoviePlayerInfoPanelState();
}

class _MoviePlayerInfoPanelState extends State<MoviePlayerInfoPanel> {
  bool _synopsisOpen = false;

  @override
  Widget build(BuildContext context) {
    final List<String> meta = widget.meta
        .map((String e) => e.trim())
        .where((String e) => e.isNotEmpty)
        .toList();
    final String synopsis = widget.synopsis.trim();
    final bool longSynopsis = synopsis.length > 180;

    return ListView(
      padding: EdgeInsets.fromLTRB(
        0,
        14,
        0,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            widget.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              height: 1.2,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (widget.rating.isNotEmpty || meta.isNotEmpty) ...<Widget>[
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                if (widget.rating.isNotEmpty) _RatingPill(widget.rating),
                for (int i = 0; i < meta.length; i++)
                  Text(
                    i == 0 ? meta[i] : '•  ${meta[i]}',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.66),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (widget.genres.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          SizedBox(
            height: 30,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.genres.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, int i) => _Chip(widget.genres[i]),
            ),
          ),
        ],
        if (widget.actions.isNotEmpty) ...<Widget>[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final MoviePlayerAction action in widget.actions)
                  Expanded(child: _ActionButton(action: action)),
              ],
            ),
          ),
        ],
        if (widget.serverCount > 1 && widget.onServer != null) ...<Widget>[
          const _SectionTitle('Servers'),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.serverCount,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, int i) {
                final bool current = i == widget.currentServer;
                final bool failed = widget.failedServers.contains(i);
                return _ServerChip(
                  label: 'Server ${i + 1}',
                  current: current,
                  failed: failed && !current,
                  onTap: current ? null : () => widget.onServer!(i),
                );
              },
            ),
          ),
        ],
        if (synopsis.isNotEmpty) ...<Widget>[
          const _SectionTitle('Storyline'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: longSynopsis
                  ? () => setState(() => _synopsisOpen = !_synopsisOpen)
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    synopsis,
                    maxLines: _synopsisOpen || !longSynopsis ? null : 4,
                    overflow: _synopsisOpen || !longSynopsis
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.74),
                      fontSize: 13.5,
                      height: 1.45,
                    ),
                  ),
                  if (longSynopsis)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        _synopsisOpen ? 'Show less' : 'Read more',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
        if (widget.related.isNotEmpty && widget.onRelated != null) ...<Widget>[
          const _SectionTitle('More like this'),
          SizedBox(
            height: 208,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: widget.related.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, int i) {
                final MoviePost post = widget.related[i];
                return _RelatedCard(
                  post: post,
                  onTap: () => widget.onRelated!(post),
                );
              },
            ),
          ),
        ],
        if (widget.footnote.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
            child: Text(
              widget.footnote,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.46),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 10),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 15.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RatingPill extends StatelessWidget {
  const _RatingPill(this.rating);

  final String rating;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Rated $rating out of 10',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFFF5C518).withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.star_rounded, size: 15, color: Color(0xFFF5C518)),
            const SizedBox(width: 3),
            Text(
              rating,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.86),
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ServerChip extends StatelessWidget {
  const _ServerChip({
    required this.label,
    required this.current,
    required this.failed,
    required this.onTap,
  });

  final String label;
  final bool current;
  final bool failed;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: current,
      label: current
          ? '$label, playing'
          : (failed ? '$label, failed earlier' : label),
      child: Material(
        color: current
            ? Colors.white
            : Colors.white.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  current
                      ? Icons.play_arrow_rounded
                      : (failed
                          ? Icons.refresh_rounded
                          : Icons.dns_outlined),
                  size: 16,
                  color: current
                      ? Colors.black
                      : Colors.white.withValues(alpha: failed ? 0.5 : 0.86),
                ),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    color: current
                        ? Colors.black
                        : Colors.white.withValues(alpha: failed ? 0.5 : 0.86),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.action});

  final MoviePlayerAction action;

  @override
  Widget build(BuildContext context) {
    final Color color =
        action.active ? MoviePlayerInfoPanel.accent : Colors.white;
    return Semantics(
      button: true,
      label: action.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(action.icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                action.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.78),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelatedCard extends StatelessWidget {
  const _RelatedCard({required this.post, required this.onTap});

  final MoviePost post;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: post.title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 112,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 112,
                height: 164,
                child: MoviePosterImage(
                  imageUrl: post.imageUrl,
                  fallbackUrl: post.fallbackImageUrl,
                  referer: post.link,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                post.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.84),
                  fontSize: 12,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
