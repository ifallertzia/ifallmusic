import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/services/app_feedback.dart';
import '../../core/services/native_bridge.dart';
import '../../core/theme/sidify_theme.dart';
import '../models/movie_models.dart';
import 'movie_player_page.dart';

void openLocalVideosPage(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const LocalVideosPage(),
      settings: const RouteSettings(name: 'sidify/movie-local-videos'),
    ),
  );
}

enum _LocalVideoState { loading, ready, permissionDenied, unsupported }

class LocalVideosPage extends StatefulWidget {
  const LocalVideosPage({super.key});

  @override
  State<LocalVideosPage> createState() => _LocalVideosPageState();
}

class _LocalVideosPageState extends State<LocalVideosPage> {
  _LocalVideoState _state = _LocalVideoState.loading;
  List<LocalVideoFile> _videos = <LocalVideoFile>[];
  bool _permanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _scan(requestIfNeeded: false);
  }

  Future<Permission> _videoPermission() async {
    final int sdk = await NativeBridge.sdkInt();
    return sdk >= 33 ? Permission.videos : Permission.storage;
  }

  Future<void> _scan({required bool requestIfNeeded}) async {
    if (!Platform.isAndroid) {
      if (mounted) setState(() => _state = _LocalVideoState.unsupported);
      return;
    }
    if (mounted) setState(() => _state = _LocalVideoState.loading);
    final Permission permission = await _videoPermission();
    PermissionStatus status = await permission.status;
    if (!status.isGranted && requestIfNeeded) {
      status = await permission.request();
    }
    if (!status.isGranted) {
      if (!mounted) return;
      setState(() {
        _permanentlyDenied = status.isPermanentlyDenied;
        _state = _LocalVideoState.permissionDenied;
      });
      return;
    }
    final List<LocalVideoFile> files = await NativeBridge.listLocalVideo();
    if (!mounted) return;
    setState(() {
      _videos = files;
      _state = _LocalVideoState.ready;
    });
  }

  Future<void> _play(LocalVideoFile video) async {
    if (video.path.isEmpty || !File(video.path).existsSync()) {
      showAppNotice(
        'This video could not be opened from device storage.',
        duration: const Duration(seconds: 2),
      );
      return;
    }
    final String label = video.width > 0 && video.height > 0
        ? '${video.height}p'
        : '';
    await openLocalMoviePlayer(
      context,
      item: MovieDownloadItem(
        id: 'local_${video.id}',
        movieTitle: video.title.isNotEmpty ? video.title : 'Video',
        qualityLabel: label,
        sourceDlUrl: '',
        status: MovieDownloadStatus.completed,
        createdAtMs: video.dateAdded * 1000,
        savedPath: video.path,
        fileName: video.path.split('/').last,
        mimeType: video.mimeType.isNotEmpty ? video.mimeType : 'video/mp4',
        totalBytes: video.size,
        downloadedBytes: video.size,
      ),
    );
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
        title: Text('On this device', style: SidifyText.titleM(t.text)),
        actions: <Widget>[
          TextButton(
            onPressed: _state == _LocalVideoState.loading
                ? null
                : () => _scan(requestIfNeeded: true),
            child: Text('Re-scan', style: TextStyle(color: t.text)),
          ),
        ],
      ),
      body: _body(t),
    );
  }

  Widget _body(SidifyTokens t) {
    switch (_state) {
      case _LocalVideoState.loading:
        return Center(child: CircularProgressIndicator(color: t.brand));
      case _LocalVideoState.unsupported:
        return _emptyState(
          t,
          icon: Icons.smartphone_rounded,
          title: 'Not available here',
          message: 'On-device videos are available in the Android app.',
        );
      case _LocalVideoState.permissionDenied:
        return _emptyState(
          t,
          icon: Icons.folder_off_rounded,
          title: 'Video access needed',
          message: 'Allow video access to see and play videos saved on this phone.',
          actionLabel: _permanentlyDenied ? 'Open settings' : 'Allow access',
          onAction: _permanentlyDenied
              ? () => openAppSettings()
              : () => _scan(requestIfNeeded: true),
        );
      case _LocalVideoState.ready:
        if (_videos.isEmpty) {
          return _emptyState(
            t,
            icon: Icons.video_library_outlined,
            title: 'No videos found',
            message: 'Videos saved on this phone will appear here.',
            actionLabel: 'Re-scan',
            onAction: () => _scan(requestIfNeeded: true),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 190),
          physics: const BouncingScrollPhysics(),
          itemCount: _videos.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (BuildContext context, int i) {
            final LocalVideoFile video = _videos[i];
            final List<String> meta = <String>[
              if (video.durationMs > 0)
                _formatDuration(Duration(milliseconds: video.durationMs)),
              if (video.size > 0) MovieByteFmt.bytes(video.size),
              if (video.width > 0 && video.height > 0)
                '${video.width}×${video.height}',
            ];
            return Material(
              color: t.raised,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _play(video),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.edge),
                  ),
                  child: Row(
                    children: <Widget>[
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: t.brand.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.play_circle_fill_rounded, color: t.brand, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              video.title.isNotEmpty ? video.title : 'Video',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: SidifyText.body(t.text),
                            ),
                            if (meta.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 3),
                              Text(meta.join(' • '), style: SidifyText.caption(t.text2)),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
    }
  }

  Widget _emptyState(
    SidifyTokens t, {
    required IconData icon,
    required String title,
    required String message,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 52, color: t.text3),
            const SizedBox(height: 14),
            Text(title, style: SidifyText.titleM(t.text)),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: SidifyText.bodyS(t.text2),
            ),
            if (actionLabel != null && onAction != null) ...<Widget>[
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: onAction,
                child: Text(actionLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final int hours = d.inHours;
    final String minutes = (d.inMinutes % 60).toString().padLeft(hours > 0 ? 2 : 1, '0');
    final String seconds = (d.inSeconds % 60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}
