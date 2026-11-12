import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../core/services/app_feedback.dart';
import '../../core/services/native_bridge.dart';
import '../../core/theme/sidify_theme.dart';
import '../models/movie_models.dart';
import '../services/movie_download_service.dart';
import 'local_videos_page.dart';
import 'movie_player_page.dart';
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
  const MovieDownloadsPage({super.key, this.embedded = false});

  /// True when shown as the Movies-mode Downloads tab (no AppBar/back).
  final bool embedded;

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

    if (widget.embedded) {
      return SafeArea(bottom: false, child: _body(t, service, filtered, all, embedded: true));
    }
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
      body: _body(t, service, filtered, all, embedded: false),
    );
  }

  Widget _body(
    SidifyTokens t,
    MovieDownloadService service,
    List<MovieDownloadItem> filtered,
    List<MovieDownloadItem> all, {
    required bool embedded,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (embedded)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text('Downloads', style: SidifyText.display(t.text)),
                ),
                Builder(
                  builder: (BuildContext context) => IconButton(
                    tooltip: 'On this device',
                    onPressed: () => openLocalVideosPage(context),
                    icon: Icon(Icons.smartphone_rounded, color: t.text),
                  ),
                ),
              ],
            ),
          ),
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
                onPressed: () => _confirmAndDelete(context),
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
          if (item.status == MovieDownloadStatus.failed) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'Download failed — check your connection and tap Retry.',
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
          'Connecting to Ifallertzia…',
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
          '${item.activeServer.isNotEmpty ? ' • Ifallertzia' : ''}',
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

  /// Deleting is permanent, so the bin never deletes on its own: it asks
  /// first and only "Yes, delete" removes the download. "No", the back button
  /// and a tap outside the dialog all leave everything exactly as it was.
  Future<void> _confirmAndDelete(BuildContext context) async {
    final bool confirmed = await showMovieDeleteConfirmation(
      context,
      title: item.movieTitle,
      detail: item.subtitleSummary,
      inProgress: item.status != MovieDownloadStatus.completed,
    );
    if (!confirmed) return;
    await service.remove(item.id);
    showAppNotice(
      'Download deleted',
      duration: const Duration(seconds: 2),
    );
  }

  /// Copies the finished file to the phone's public Downloads folder.
  Future<void> _saveToPhone() async {
    if (service.isSavingToDevice(item.id)) {
      showAppNotice(
        'Still saving — large files take a moment.',
        duration: const Duration(seconds: 2),
      );
      return;
    }

    // Android 9 and older write to shared storage through the classic storage
    // permission; Android 10+ goes through MediaStore and needs none.
    if (Platform.isAndroid) {
      final int sdk = await NativeBridge.sdkInt();
      if (sdk > 0 && sdk < 29) {
        PermissionStatus status = await Permission.storage.status;
        if (!status.isGranted) status = await Permission.storage.request();
        if (!status.isGranted) {
          showAppNotice(
            status.isPermanentlyDenied
                ? 'Allow storage access for Sidify in Settings to save files.'
                : 'Storage permission is needed to save to Downloads.',
            duration: const Duration(seconds: 3),
          );
          if (status.isPermanentlyDenied) await openAppSettings();
          return;
        }
      }
    }

    if (item.publicUri.isEmpty) {
      showAppNotice(
        'Saving to Downloads… keep the app open.',
        duration: const Duration(seconds: 2),
      );
    }
    final MovieSaveOutcome outcome = await service.saveToPhoneDownloads(item);
    switch (outcome.status) {
      case MovieSaveStatus.saved:
        showAppNotice(
          'Saved to phone storage: Download/IfallMusic',
          duration: const Duration(seconds: 3),
        );
      case MovieSaveStatus.alreadySaved:
        showAppNotice(
          'Already saved in Download/IfallMusic',
          duration: const Duration(seconds: 2),
        );
      case MovieSaveStatus.busy:
        showAppNotice(
          'Still saving — large files take a moment.',
          duration: const Duration(seconds: 2),
        );
      case MovieSaveStatus.missingFile:
        showAppNotice(
          'The downloaded file was moved or deleted. Download it again.',
          duration: const Duration(seconds: 3),
        );
      case MovieSaveStatus.unsupported:
        showAppNotice(
          'Saving to Downloads is available on Android only.',
          duration: const Duration(seconds: 3),
        );
      case MovieSaveStatus.failed:
        showAppNotice(
          outcome.message.isNotEmpty
              ? 'Could not save to Downloads. ${outcome.message}'
              : 'Could not save to Downloads. Please try again.',
          duration: const Duration(seconds: 4),
        );
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
            if (!item.isZip) {
              await openLocalMoviePlayer(context, item: item);
              return;
            }
            final OpenResult res = await service.openFile(item);
            if (res.type != ResultType.done) {
              showAppNotice(
                'Could not open this file.',
                duration: const Duration(seconds: 2),
              );
            }
          },
        ),
      );
      final bool saving = service.isSavingToDevice(item.id);
      buttons.add(
        _actionPill(
          t,
          icon: saving
              ? Icons.hourglass_top_rounded
              : item.publicUri.isNotEmpty
                  ? Icons.download_done_rounded
                  : Icons.save_alt_rounded,
          label: saving
              ? 'Saving…'
              : item.publicUri.isNotEmpty
                  ? 'Saved in Downloads'
                  : 'Save to Downloads',
          busy: saving,
          onTap: _saveToPhone,
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
    bool busy = false,
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
              if (busy)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: primary ? t.onPrimary : t.text,
                  ),
                )
              else
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

/// The "are you sure?" dialog shown before a download is deleted.
///
/// Resolves to true only when "Yes, delete" is tapped. "No", the system back
/// button and a tap outside the dialog all resolve to false, and the caller
/// then does nothing.
Future<bool> showMovieDeleteConfirmation(
  BuildContext context, {
  required String title,
  String detail = '',
  bool inProgress = false,
}) async {
  final bool? confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.6),
    builder: (BuildContext dialogContext) {
      final SidifyTokens t = dialogContext.sidify;
      return Dialog(
        backgroundColor: t.raised,
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: t.edge),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: t.danger.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: t.danger,
                    size: 28,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Are you sure you want to delete?',
                  textAlign: TextAlign.center,
                  style: SidifyText.titleM(t.text),
                ),
                const SizedBox(height: 10),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: SidifyText.label(t.text),
                ),
                if (detail.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    detail,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: SidifyText.caption(t.text2),
                  ),
                ],
                const SizedBox(height: 10),
                Text(
                  inProgress
                      ? 'The download will be stopped and removed from this '
                          'device. This action cannot be undone.'
                      : 'The file will be removed from this device. This '
                          'action cannot be undone.',
                  textAlign: TextAlign.center,
                  style: SidifyText.bodyS(t.text2),
                ),
                const SizedBox(height: 22),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: t.text,
                          side: BorderSide(color: t.edge),
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('No'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: t.danger,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(46),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text('Yes, delete'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return confirmed == true;
}
