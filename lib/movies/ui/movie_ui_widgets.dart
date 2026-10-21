import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/app_feedback.dart';
import '../../core/theme/sidify_theme.dart';
import '../models/movie_models.dart';
import '../services/eon_movies_service.dart';
import '../services/movie_download_service.dart';
import 'movie_downloads_page.dart';

/// Resilient network poster/backdrop widget with automatic secondary URL
/// failover and zero-network placeholder when [imageUrl] is empty.
class MoviePosterImage extends StatefulWidget {
  const MoviePosterImage({
    super.key,
    required this.imageUrl,
    this.fallbackUrl = '',
    this.fit = BoxFit.cover,
    this.borderRadius = BorderRadius.zero,
  });

  final String imageUrl;
  final String fallbackUrl;
  final BoxFit fit;
  final BorderRadius borderRadius;

  @override
  State<MoviePosterImage> createState() => _MoviePosterImageState();
}

class _MoviePosterImageState extends State<MoviePosterImage> {
  bool _triedFallback = false;

  @override
  void didUpdateWidget(covariant MoviePosterImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageUrl != widget.imageUrl) {
      _triedFallback = false;
    }
  }

  Widget _placeholder(SidifyTokens t) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[t.raised2, t.raised],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.local_movies_rounded,
        color: t.text3,
        size: 28,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final String activeUrl = _triedFallback && widget.fallbackUrl.isNotEmpty
        ? widget.fallbackUrl
        : widget.imageUrl;

    if (activeUrl.trim().isEmpty) {
      return ClipRRect(
        borderRadius: widget.borderRadius,
        child: _placeholder(t),
      );
    }

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: CachedNetworkImage(
        imageUrl: activeUrl,
        fit: widget.fit,
        placeholder: (_, __) => _placeholder(t),
        errorWidget: (_, __, ___) {
          if (!_triedFallback &&
              widget.fallbackUrl.isNotEmpty &&
              widget.fallbackUrl != widget.imageUrl) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                setState(() => _triedFallback = true);
              }
            });
          }
          return _placeholder(t);
        },
      ),
    );
  }
}

/// Action button opening [MovieDownloadsPage] with live active/total badge.
class MovieDownloadsActionButton extends StatelessWidget {
  const MovieDownloadsActionButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final MovieDownloadService downloads =
        context.watch<MovieDownloadService>();
    final int active = downloads.activeCount;
    final int total = downloads.totalCount;

    return Material(
      color: t.raised,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () => openMovieDownloadsPage(context),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 12,
            vertical: 8,
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: t.edge),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                active > 0
                    ? Icons.downloading_rounded
                    : Icons.download_done_rounded,
                size: 18,
                color: active > 0 ? t.brand : t.text,
              ),
              if (!compact) ...<Widget>[
                const SizedBox(width: 6),
                Text(
                  'Downloads',
                  style: SidifyText.label(t.text),
                ),
              ],
              if (total > 0) ...<Widget>[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: active > 0 ? t.brand : t.fill3,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    active > 0 ? '$active' : '$total',
                    style: SidifyText.caption(
                      active > 0 ? Colors.white : t.text,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Interactive quality row card with resolution, codec, size, audio languages,
/// and live Download / Progress / Play controls.
class MovieQualityDownloadTile extends StatelessWidget {
  const MovieQualityDownloadTile({
    super.key,
    required this.detail,
    required this.quality,
  });

  final MovieDetail detail;
  final MovieQualityLink quality;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final MovieDownloadService dlService =
        context.watch<MovieDownloadService>();
    final MovieDownloadItem? existing =
        dlService.itemById('mdl_${quality.id}');
    final String langs =
        quality.languages.isNotEmpty ? quality.languages : detail.languages;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: t.raised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: t.brand.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            quality.displayQuality,
                            style: SidifyText.label(t.brand),
                          ),
                        ),
                        if (quality.isZipPack)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: t.fill2,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'ZIP PACK',
                              style: SidifyText.caption(t.text),
                            ),
                          ),
                        if (quality.sizeLabel.isNotEmpty)
                          Text(
                            quality.sizeLabel,
                            style: SidifyText.label(t.text),
                          ),
                      ],
                    ),
                    if (langs.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.translate_rounded,
                            size: 13,
                            color: t.text2,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              langs,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SidifyText.caption(t.text2),
                            ),
                          ),
                        ],
                      ),
                    ],
                    if (quality.isZipPack) ...<Widget>[
                      const SizedBox(height: 5),
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.playlist_play_rounded,
                            size: 14,
                            color: t.brand,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Episode-wise available — tap Download',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: SidifyText.caption(t.brand),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _buildTrailingAction(context, t, dlService, existing),
            ],
          ),
          if (existing != null &&
              (existing.isActive ||
                  existing.status == MovieDownloadStatus.paused)) ...<Widget>[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: existing.status == MovieDownloadStatus.resolving
                    ? null
                    : existing.progress,
                minHeight: 5,
                backgroundColor: t.fill2,
                valueColor: AlwaysStoppedAnimation<Color>(t.brand),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    existing.status == MovieDownloadStatus.resolving
                        ? 'Finding fastest direct mirror...'
                        : existing.status == MovieDownloadStatus.paused
                            ? 'Paused • ${MovieByteFmt.bytes(existing.downloadedBytes)}'
                            : '${(existing.progress * 100).toStringAsFixed(0)}% • '
                                '${MovieByteFmt.bytes(existing.downloadedBytes)}'
                                '${existing.totalBytes > 0 ? ' / ${MovieByteFmt.bytes(existing.totalBytes)}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SidifyText.caption(t.text2),
                  ),
                ),
                if (existing.speedBytesPerSec > 0)
                  Text(
                    MovieByteFmt.speed(existing.speedBytesPerSec),
                    style: SidifyText.caption(t.brand),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTrailingAction(
    BuildContext context,
    SidifyTokens t,
    MovieDownloadService dlService,
    MovieDownloadItem? existing,
  ) {
    if (existing == null ||
        existing.status == MovieDownloadStatus.canceled ||
        existing.status == MovieDownloadStatus.failed) {
      final bool retry = existing?.status == MovieDownloadStatus.failed;
      return Material(
        color: t.primary,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () async {
            if (quality.isZipPack) {
              await showMovieZipPackOptions(
                context,
                detail: detail,
                quality: quality,
              );
              return;
            }
            await dlService.enqueueDownload(detail: detail, quality: quality);
            showAppNotice(
              'Download started: ${detail.cleanTitle} (${quality.displayQuality})',
            );
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  retry ? Icons.refresh_rounded : Icons.download_rounded,
                  size: 16,
                  color: t.onPrimary,
                ),
                const SizedBox(width: 5),
                Text(
                  retry ? 'Retry' : 'Download',
                  style: SidifyText.label(t.onPrimary),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (existing.status == MovieDownloadStatus.completed) {
      return Material(
        color: const Color(0xFF1DB954).withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () => dlService.openFile(existing),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Icon(
                  Icons.play_circle_fill_rounded,
                  size: 16,
                  color: Color(0xFF1DB954),
                ),
                const SizedBox(width: 5),
                Text(
                  existing.isZip ? 'Open ZIP' : 'Play',
                  style: SidifyText.label(const Color(0xFF1DB954)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (existing.status == MovieDownloadStatus.paused) {
      return IconButton(
        tooltip: 'Resume download',
        onPressed: () => dlService.resume(existing.id),
        icon: Icon(Icons.play_arrow_rounded, color: t.brand),
      );
    }

    return IconButton(
      tooltip: 'Pause download',
      onPressed: () => dlService.pause(existing.id),
      icon: Icon(Icons.pause_circle_filled_rounded, color: t.brand),
    );
  }
}

/// Download choice for a season ZIP pack: episode-wise (only the selected
/// episode's bytes are fetched out of the remote ZIP) or the complete ZIP.
Future<void> showMovieZipPackOptions(
  BuildContext context, {
  required MovieDetail detail,
  required MovieQualityLink quality,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ZipPackOptionsSheet(detail: detail, quality: quality),
  );
}

class _ZipPackOptionsSheet extends StatefulWidget {
  const _ZipPackOptionsSheet({required this.detail, required this.quality});

  final MovieDetail detail;
  final MovieQualityLink quality;

  @override
  State<_ZipPackOptionsSheet> createState() => _ZipPackOptionsSheetState();
}

class _ZipPackOptionsSheetState extends State<_ZipPackOptionsSheet> {
  bool _loadingEpisodes = false;
  String? _error;
  MovieZipPackListing? _listing;

  Future<void> _loadEpisodes() async {
    setState(() {
      _loadingEpisodes = true;
      _error = null;
    });
    try {
      final EonMoviesService svc = context.read<EonMoviesService>();
      final MovieZipPackListing listing = await svc.listZipPackEpisodes(
        widget.quality,
        fallbackTitle: widget.detail.cleanTitle,
      );
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _loadingEpisodes = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Bad state: ', '');
        _loadingEpisodes = false;
      });
    }
  }

  Future<void> _downloadWholeZip() async {
    final MovieDownloadService dlService =
        context.read<MovieDownloadService>();
    await dlService.enqueueDownload(
      detail: widget.detail,
      quality: widget.quality,
    );
    showAppNotice(
      'Download started: ${widget.detail.cleanTitle} '
      '(${widget.quality.displayQuality} ZIP)',
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _downloadEpisode(MovieZipEpisode episode) async {
    final MovieDownloadService dlService =
        context.read<MovieDownloadService>();
    final MovieQualityLink epQuality =
        EonMoviesService.qualityForZipEpisode(widget.quality, episode);
    await dlService.enqueueDownload(
      detail: widget.detail,
      quality: epQuality,
    );
    showAppNotice(
      'Download started: ${episode.episodeLabel.isNotEmpty ? episode.episodeLabel : episode.fileName} '
      '(${widget.quality.displayQuality}) — this episode only',
    );
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    // Watch here (in build) so episode rows update with download progress;
    // rows themselves are built lazily by the ListView.
    final MovieDownloadService dlService =
        context.watch<MovieDownloadService>();
    final MovieZipPackListing? listing = _listing;
    final double maxHeight = MediaQuery.of(context).size.height * 0.78;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(maxHeight: maxHeight),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
        decoration: BoxDecoration(
          color: t.bg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: t.edge),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Center(
              child: Container(
                width: 42,
                height: 4,
                decoration: BoxDecoration(
                  color: t.fill3,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Icon(Icons.folder_zip_rounded, size: 20, color: t.brand),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.quality.displayQuality} • Season Pack (ZIP)',
                    style: SidifyText.titleM(t.text),
                  ),
                ),
                if (widget.quality.sizeLabel.isNotEmpty)
                  Text(
                    widget.quality.sizeLabel,
                    style: SidifyText.label(t.text2),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              listing != null
                  ? listing.zipFileName
                  : 'The source hosts this season as one ZIP — but you can '
                      'still download just a single episode from it.',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: SidifyText.caption(t.text2),
            ),
            const SizedBox(height: 14),
            if (_loadingEpisodes)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 26),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      CircularProgressIndicator(color: t.brand),
                      const SizedBox(height: 12),
                      Text(
                        'Finding episodes inside the ZIP…',
                        style: SidifyText.bodyS(t.text2),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'The full ZIP is not downloaded — just a few KB',
                        style: SidifyText.caption(t.text2),
                      ),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: t.raised,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.edge),
                    ),
                    child: Text(
                      _error!,
                      style: SidifyText.bodyS(t.text2),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _zipOptionTile(
                    t,
                    icon: Icons.folder_zip_rounded,
                    title:
                        'Complete Season ZIP${widget.quality.sizeLabel.isNotEmpty ? ' (${widget.quality.sizeLabel})' : ''}',
                    subtitle: 'All episodes in one ZIP file',
                    onTap: _downloadWholeZip,
                  ),
                ],
              )
            else if (listing == null)
              Column(
                children: <Widget>[
                  _zipOptionTile(
                    t,
                    icon: Icons.playlist_play_rounded,
                    title: 'Episode-wise Download',
                    subtitle:
                        'Shows the episodes inside — only the selected one '
                        'downloads, not the whole season',
                    onTap: _loadEpisodes,
                  ),
                  const SizedBox(height: 10),
                  _zipOptionTile(
                    t,
                    icon: Icons.folder_zip_rounded,
                    title:
                        'Complete Season ZIP${widget.quality.sizeLabel.isNotEmpty ? ' (${widget.quality.sizeLabel})' : ''}',
                    subtitle: 'All episodes in one ZIP file',
                    onTap: _downloadWholeZip,
                  ),
                ],
              )
            else ...<Widget>[
              Text(
                '${listing.episodes.length} episodes found — only the one '
                'you pick will download',
                style: SidifyText.bodyS(t.text2),
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: listing.episodes.length,
                  itemBuilder: (BuildContext context, int i) {
                    return _buildEpisodeRow(t, listing.episodes[i], dlService);
                  },
                ),
              ),
              const SizedBox(height: 10),
              _zipOptionTile(
                t,
                icon: Icons.folder_zip_rounded,
                title:
                    'Complete Season ZIP (${MovieByteFmt.bytes(listing.totalBytes)})',
                subtitle: 'All episodes in one ZIP file',
                onTap: _downloadWholeZip,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEpisodeRow(
    SidifyTokens t,
    MovieZipEpisode episode,
    MovieDownloadService dlService,
  ) {
    final MovieQualityLink epQuality =
        EonMoviesService.qualityForZipEpisode(widget.quality, episode);
    final MovieDownloadItem? existing =
        dlService.itemById('mdl_${epQuality.id}');

    Widget trailing;
    if (!episode.isSupported) {
      trailing = Text(
        'ZIP only',
        style: SidifyText.caption(t.text2),
      );
    } else if (existing?.status == MovieDownloadStatus.completed) {
      trailing = IconButton(
        tooltip: 'Play',
        onPressed: () => dlService.openFile(existing!),
        icon: const Icon(
          Icons.play_circle_fill_rounded,
          color: Color(0xFF1DB954),
        ),
      );
    } else if (existing != null && existing.isActive) {
      trailing = Text(
        '${(existing.progress * 100).toStringAsFixed(0)}%',
        style: SidifyText.label(t.brand),
      );
    } else if (existing?.status == MovieDownloadStatus.paused) {
      trailing = IconButton(
        tooltip: 'Resume',
        onPressed: () => dlService.resume(existing!.id),
        icon: Icon(Icons.play_arrow_rounded, color: t.brand),
      );
    } else {
      trailing = IconButton(
        tooltip: 'Download episode',
        onPressed: () => _downloadEpisode(episode),
        icon: Icon(Icons.download_rounded, color: t.brand),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: t.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.edge),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.brand.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              episode.episodeNumber > 0
                  ? '${episode.episodeNumber}'
                  : '${episode.index + 1}',
              style: SidifyText.label(t.brand),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  episode.episodeLabel.isNotEmpty
                      ? (episode.seasonLabel.isNotEmpty
                          ? '${episode.seasonLabel} • ${episode.episodeLabel}'
                          : episode.episodeLabel)
                      : 'Episode ${episode.index + 1}',
                  style: SidifyText.label(t.text),
                ),
                const SizedBox(height: 2),
                Text(
                  '${episode.sizeLabel} • ${episode.fileName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: SidifyText.caption(t.text2),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }

  Widget _zipOptionTile(
    SidifyTokens t, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Material(
      color: t.raised,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.edge),
          ),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: t.brand.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, size: 19, color: t.brand),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: SidifyText.titleM(t.text)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: SidifyText.caption(t.text2)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: t.text2),
            ],
          ),
        ),
      ),
    );
  }
}
