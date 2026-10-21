import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/app_feedback.dart';
import '../../core/theme/sidify_theme.dart';
import '../models/movie_models.dart';
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
