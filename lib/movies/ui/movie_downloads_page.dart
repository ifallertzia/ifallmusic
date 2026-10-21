import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';

import '../../core/services/app_feedback.dart';
import '../../core/services/native_bridge.dart';
import '../../core/theme/sidify_theme.dart';
import '../models/movie_models.dart';
import '../services/movie_download_service.dart';
import 'movie_ui_widgets.dart';

enum _DownloadFilter { all, active, completed }

void openMovieDownloadsPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const MovieDownloadsPage(),
      settings: const RouteSettings(name: 'sidify/movie-downloads'),
    ),
  );
}

/// Dedicated Downloads manager page for Movies & Series showing active queues,
/// live speeds/progress, pause/resume/cancel, file playback, and Downloads export.
class MovieDownloadsPage extends StatefulWidget {
  const MovieDownloadsPage({super.key});

  @override
  State<MovieDownloadsPage> createState() => _MovieDownloadsPageState();
}

class _MovieDownloadsPageState extends State<MovieDownloadsPage> {
  _DownloadFilter _filter = _DownloadFilter.all;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final MovieDownloadService service = context.watch<MovieDownloadService>();
    final List<MovieDownloadItem> all = service.items;

    final List<MovieDownloadItem> filtered = switch (_filter) {
      _DownloadFilter.all => all,
      _DownloadFilter.active => all
          .where(
            (MovieDownloadItem e) =>
                e.isActive ||
                e.status == MovieDownloadStatus.paused ||
                e.status == MovieDownloadStatus.failed,
          )
          .toList(),
      _DownloadFilter.completed => all
          .where(
            (MovieDownloadItem e) => e.status == MovieDownloadStatus.completed,
          )
          .toList(),
    };

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: t.text, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('Movie Downloads', style: SidifyText.title(t.text)),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _filterChip(
                  t,
                  label: 'All (${all.length})',
                  selected: _filter == _DownloadFilter.all,
                  onTap: () => setState(() => _filter = _DownloadFilter.all),
                ),
                _filterChip(
                  t,
                  label: 'Downloading (${service.activeItems.length})',
                  selected: _filter == _DownloadFilter.active,
                  onTap: () => setState(() => _filter = _DownloadFilter.active),
                ),
                _filterChip(
                  t,
                  label: 'Completed (${service.completedItems.length})',
                  selected: _filter == _DownloadFilter.completed,
                  onTap: () =>
                      setState(() => _filter = _DownloadFilter.completed),
                ),
              ],
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            Icons.video_library_outlined,
                            size: 52,
                            color: t.text3,
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'No downloads here yet',
                            style: SidifyText.titleM(t.text),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Any movie or web series episode you download will appear here with pause, resume and instant play.',
                            textAlign: TextAlign.center,
                            style: SidifyText.bodyS(t.text2),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 190),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (BuildContext context, int index) {
                      return _DownloadCard(
                        item: filtered[index],
                        service: service,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _filterChip(
    SidifyTokens t, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? t.primary : t.raised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? t.primary : t.edge),
        ),
        child: Text(
          label,
          style: SidifyText.label(selected ? t.onPrimary : t.text),
        ),
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({required this.item, required this.service});

  final MovieDownloadItem item;
  final MovieDownloadService service;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.raised,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.edge),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 66,
                height: 94,
                child: MoviePosterImage(
                  imageUrl: item.posterUrl,
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      item.movieTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: SidifyText.titleM(t.text),
                    ),
                    const SizedBox(height: 4),
                    if (item.subtitleSummary.isNotEmpty)
                      Text(
                        item.subtitleSummary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: SidifyText.caption(t.text2),
                      ),
                    const SizedBox(height: 6),
                    _statusLine(t),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Delete download',
                onPressed: () => service.remove(item.id),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: t.text2,
                ),
              ),
            ],
          ),
          if (item.isActive || item.status == MovieDownloadStatus.paused) ...<Widget>[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: item.status == MovieDownloadStatus.resolving
                    ? null
                    : item.progress,
                minHeight: 6,
                backgroundColor: t.fill2,
                valueColor: AlwaysStoppedAnimation<Color>(t.brand),
              ),
            ),
          ],
          if (item.errorMessage.isNotEmpty) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              item.errorMessage,
              style: SidifyText.caption(t.danger),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _buildActions(context, t),
          ),
        ],
      ),
    );
  }

  Widget _statusLine(SidifyTokens t) {
    switch (item.status) {
      case MovieDownloadStatus.resolving:
        return Text(
          'Resolving high-speed CDN link...',
          style: SidifyText.caption(t.brand),
        );
      case MovieDownloadStatus.queued:
        return Text('Queued...', style: SidifyText.caption(t.text2));
      case MovieDownloadStatus.downloading:
        final String pct = '${(item.progress * 100).toStringAsFixed(1)}%';
        final String bytes = item.totalBytes > 0
            ? '${MovieByteFmt.bytes(item.downloadedBytes)} / ${MovieByteFmt.bytes(item.totalBytes)}'
            : MovieByteFmt.bytes(item.downloadedBytes);
        final String speed = MovieByteFmt.speed(item.speedBytesPerSec);
        return Text(
          '$pct • $bytes${speed.isNotEmpty ? ' • $speed' : ''}'
          '${item.activeServer.isNotEmpty ? ' • ${item.activeServer}' : ''}',
          style: SidifyText.caption(t.brand),
        );
      case MovieDownloadStatus.paused:
        return Text(
          'Paused • ${MovieByteFmt.bytes(item.downloadedBytes)} saved',
          style: SidifyText.caption(t.text2),
        );
      case MovieDownloadStatus.completed:
        final String finalSize = item.totalBytes > 0
            ? MovieByteFmt.bytes(item.totalBytes)
            : item.sizeLabel;
        return Text(
          'Completed${finalSize.isNotEmpty ? ' • $finalSize' : ''}',
          style: SidifyText.caption(const Color(0xFF1DB954)),
        );
      case MovieDownloadStatus.failed:
        return Text('Failed', style: SidifyText.caption(t.danger));
      case MovieDownloadStatus.canceled:
        return Text('Canceled', style: SidifyText.caption(t.text3));
    }
  }

  List<Widget> _buildActions(BuildContext context, SidifyTokens t) {
    final List<Widget> buttons = <Widget>[];

    if (item.isActive) {
      buttons.add(
        _actionPill(
          t,
          icon: Icons.pause_rounded,
          label: 'Pause',
          primary: true,
          onTap: () => service.pause(item.id),
        ),
      );
      buttons.add(
        _actionPill(
          t,
          icon: Icons.close_rounded,
          label: 'Cancel',
          onTap: () => service.cancel(item.id),
        ),
      );
    } else if (item.status == MovieDownloadStatus.paused ||
        item.status == MovieDownloadStatus.failed ||
        item.status == MovieDownloadStatus.canceled) {
      buttons.add(
        _actionPill(
          t,
          icon: Icons.play_arrow_rounded,
          label: item.status == MovieDownloadStatus.paused ? 'Resume' : 'Retry',
          primary: true,
          onTap: () => service.resume(item.id),
        ),
      );
      if (item.sharePageUrl.isNotEmpty) {
        buttons.add(
          _actionPill(
            t,
            icon: Icons.open_in_browser_rounded,
            label: 'Browser Mirror',
            onTap: () => service.openSharePageExternal(item),
          ),
        );
      }
    } else if (item.status == MovieDownloadStatus.completed) {
      buttons.add(
        _actionPill(
          t,
          icon: item.isZip
              ? Icons.folder_zip_rounded
              : Icons.play_arrow_rounded,
          label: item.isZip ? 'Open ZIP' : 'Play Video',
          primary: true,
          onTap: () async {
            final OpenResult res = await service.openFile(item);
            if (res.type != ResultType.done) {
              showAppNotice(res.message);
            }
          },
        ),
      );
      buttons.add(
        _actionPill(
          t,
          icon: Icons.save_alt_rounded,
          label: item.publicUri.isNotEmpty
              ? 'Saved in Downloads'
              : 'Save to Downloads',
          onTap: () async {
            final SavedFile? saved = await service.saveToDeviceDownloads(item);
            showAppNotice(
              saved != null
                  ? 'Saved to phone Downloads/IfallMusic folder'
                  : 'Saved at ${item.savedPath}',
            );
          },
        ),
      );
    }

    return buttons;
  }

  Widget _actionPill(
    SidifyTokens t, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool primary = false,
  }) {
    return Material(
      color: primary ? t.primary : t.fill2,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                icon,
                size: 16,
                color: primary ? t.onPrimary : t.text,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: SidifyText.label(primary ? t.onPrimary : t.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
