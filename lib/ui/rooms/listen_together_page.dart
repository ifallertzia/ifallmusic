import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/branding.dart';
import '../../core/models/song.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/library_service.dart';
import '../../core/services/listen_together_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/ifall_ui.dart';
import '../../core/utils/format.dart';
import '../widgets/artwork.dart';

/// Pushes the Listen Together screen.
Future<void> openListenTogether(BuildContext context) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (BuildContext c) => const ListenTogetherPage(),
    ),
  );
}

/// **Listen Together** — a shared, synchronised room.
///
/// Start a room and share its six-character code, or type in somebody else's.
/// Everyone hears the same thing at the same time: the server holds a position
/// plus the instant that position was true, and each device works out where it
/// should be from its own clock offset (see [JamService]).
class ListenTogetherPage extends StatefulWidget {
  const ListenTogetherPage({super.key});

  @override
  State<ListenTogetherPage> createState() => _ListenTogetherPageState();
}

class _ListenTogetherPageState extends State<ListenTogetherPage> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _server = TextEditingController();
  String? _error;

  /// Drives the playhead while the room is playing, so the progress bar moves
  /// even between heartbeats.
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final SettingsService settings = context.read<SettingsService>();
    _server.text = settings.jamServer;
    final String? last = settings.jamLastCode;
    if (last != null && last.isNotEmpty) _code.text = last;
    _ticker = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) => _syncToRoom(),
    );
  }

  /// Mirrors the room onto this device's player.
  ///
  /// The room is the truth. When the room's track differs from what is playing
  /// here, this device starts it; when only the position has drifted, it seeks.
  void _syncToRoom() {
    if (!mounted) return;
    final JamService jam = context.read<JamService>();
    if (!jam.isConnected || jam.playback == null) return;
    final PlaybackService playback = context.read<PlaybackService>();
    final JamTrack? track = jam.currentTrack;
    if (track == null) return;

    final Duration target = jam.positionNow;
    final bool sameTrack = playback.current?.id == track.videoId;
    if (!sameTrack) {
      // Only the member who pressed play triggers the change; everybody else
      // simply follows the state frame.
      unawaited(playback.playSong(track.toSong()));
      return;
    }
    final Duration drift = target - playback.position;
    if (drift.inMilliseconds.abs() > 1200) {
      unawaited(playback.seekTo(target));
    }
    if (jam.playback!.isPlaying && !playback.isPlaying) {
      unawaited(playback.resume());
    } else if (!jam.playback!.isPlaying && playback.isPlaying) {
      unawaited(playback.pause());
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.dispose();
    _server.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final JamService jam = context.read<JamService>();
    setState(() => _error = null);
    final bool ok = await jam.create();
    if (!ok && mounted) setState(() => _error = jam.error);
  }

  Future<void> _join() async {
    final JamService jam = context.read<JamService>();
    final String code = _code.text.trim();
    if (code.isEmpty) {
      setState(() => _error = 'Enter the six-character room code.');
      return;
    }
    setState(() => _error = null);
    final bool ok = await jam.join(code);
    if (!ok && mounted) setState(() => _error = jam.error);
  }

  Future<void> _leave() async {
    await context.read<JamService>().leave();
    if (mounted) setState(() => _error = null);
  }

  Future<void> _saveServer() async {
    final String value = _server.text.trim();
    await context.read<SettingsService>().setJamServer(value);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final JamService jam = context.watch<JamService>();
    final IfallPalette c = IfallPalette.of(context);

    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          'Listen Together',
          style: IfallText.title(c.onSurface),
        ),
        actions: <Widget>[
          if (jam.isConnected)
            TextButton(
              onPressed: _leave,
              child: Text(
                'Leave',
                style: IfallText.caption(c.onSurfaceVariant)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: jam.isConnected
              ? const _RoomView(key: ValueKey<String>('room'))
              : _LobbyView(
                  key: const ValueKey<String>('lobby'),
                  code: _code,
                  server: _server,
                  error: _error ?? jam.error,
                  busy: jam.state == JamConnectionState.joining,
                  onCreate: _create,
                  onJoin: _join,
                  onSaveServer: _saveServer,
                  hasServer: jam.hasServer,
                ),
        ),
      ),
    );
  }
}

// ------------------------------------------------------------------- lobby

class _LobbyView extends StatelessWidget {
  const _LobbyView({
    super.key,
    required this.code,
    required this.server,
    required this.onCreate,
    required this.onJoin,
    required this.onSaveServer,
    required this.busy,
    required this.hasServer,
    this.error,
  });

  final TextEditingController code;
  final TextEditingController server;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final VoidCallback onSaveServer;
  final bool busy;
  final bool hasServer;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
      children: <Widget>[
        Center(
          child: Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: c.accent.withValues(alpha: 0.14),
            ),
            child: Icon(
              Icons.surround_sound_rounded,
              size: 40,
              color: c.accent,
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Listen together, in sync',
          textAlign: TextAlign.center,
          style: IfallText.section(c.onSurface),
        ),
        const SizedBox(height: 8),
        Text(
          'Start a room, share the six-character code, and everybody in it hears '
          'the same track at the same moment — even on different networks.',
          textAlign: TextAlign.center,
          style: IfallText.body(c.onSurfaceVariant),
        ),
        const SizedBox(height: 26),

        // ------------------------------------------------------ server address
        if (!hasServer) ...<Widget>[
          IfallGroup(
            title: 'Room server',
            footer:
                'Rooms need a small server to keep everybody in time. Point this '
                'at your own deployment — nothing about your library is sent to it.',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: TextField(
                  controller: server,
                  style: IfallText.body(c.onSurface),
                  decoration: InputDecoration(
                    hintText: JamService.placeholderServer,
                    hintStyle: IfallText.body(c.onSurfaceVariant),
                    filled: true,
                    fillColor: c.glass,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(IfallUI.rMd),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              IfallRow(
                title: 'Save address',
                icon: Icons.save_outlined,
                onTap: onSaveServer,
              ),
            ],
          ),
        ],

        if (hasServer) ...<Widget>[
          FilledButton.icon(
            onPressed: busy ? null : onCreate,
            style: FilledButton.styleFrom(
              backgroundColor: c.accent,
              foregroundColor:
                  ThemeData.estimateBrightnessForColor(c.accent) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
              minimumSize: const Size(0, 52),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(IfallUI.rPill),
              ),
            ),
            icon: busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color:
                          ThemeData.estimateBrightnessForColor(c.accent) ==
                                  Brightness.dark
                              ? Colors.white
                              : Colors.black,
                    ),
                  )
                : const Icon(Icons.add_rounded),
            label: const Text('Start a room'),
          ),
          const SizedBox(height: 18),

          IfallGroup(
            title: 'Join a room',
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                child: TextField(
                  controller: code,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: IfallText.style(
                    26,
                    weight: FontWeight.w800,
                    letterSpacing: 8,
                    color: c.onSurface,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: 'ABC123',
                    hintStyle: IfallText.style(
                      24,
                      weight: FontWeight.w800,
                      letterSpacing: 8,
                      color: c.onSurfaceVariant.withValues(alpha: 0.4),
                    ),
                    filled: true,
                    fillColor: c.glass,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(IfallUI.rMd),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              IfallRow(
                title: 'Join room',
                icon: Icons.login_rounded,
                onTap: busy ? null : onJoin,
              ),
            ],
          ),
        ],

        if (error != null) ...<Widget>[
          const SizedBox(height: 10),
          IfallGlass(
            radius: IfallUI.rMd,
            blur: 0,
            color: (c.isDark ? IfallColors.dangerLight : const Color(0xFFFF3B30))
                .withValues(alpha: 0.12),
            border: (c.isDark ? IfallColors.dangerLight : const Color(0xFFFF3B30))
                .withValues(alpha: 0.4),
            padding: const EdgeInsets.all(14),
            child: Text(
              error!,
              style: IfallText.body(c.onSurface),
            ),
          ),
        ],
      ],
    );
  }
}

// -------------------------------------------------------------------- room

class _RoomView extends StatelessWidget {
  const _RoomView({super.key});

  @override
  Widget build(BuildContext context) {
    final JamService jam = context.watch<JamService>();
    final PlaybackService playback = context.watch<PlaybackService>();
    final IfallPalette c = IfallPalette.of(context);
    final JamTrack? track = jam.currentTrack;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
      children: <Widget>[
        // ---------------------------------------------------------- the code
        _CodeCard(code: jam.code ?? '', onLeave: () => jam.leave()),
        const SizedBox(height: 14),

        // ------------------------------------------------------ now playing
        if (track != null)
          _NowPlayingCard(
            track: track,
            playing: jam.playback?.isPlaying ?? false,
            position: jam.positionNow,
            startedBy: jam.playback?.startedByName,
            canControl: jam.canControl,
            onPlayPause: () {
              final int ms = playback.position.inMilliseconds;
              if (jam.playback?.isPlaying ?? false) {
                jam.pause(positionMs: ms);
              } else {
                jam.play(positionMs: ms);
              }
            },
            onNext: jam.next,
            onPrevious: jam.previous,
            onSeek: (Duration d) => jam.seek(d),
          )
        else
          IfallGlass(
            radius: IfallUI.rLg,
            blur: 0,
            padding: const EdgeInsets.all(22),
            child: Column(
              children: <Widget>[
                Icon(
                  Icons.queue_music_rounded,
                  size: 30,
                  color: c.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(
                  'Nothing queued yet',
                  style: IfallText.section(c.onSurface),
                ),
                const SizedBox(height: 6),
                Text(
                  'Play something on this device and it will start for everybody '
                  'in the room.',
                  textAlign: TextAlign.center,
                  style: IfallText.body(c.onSurfaceVariant),
                ),
              ],
            ),
          ),
        const SizedBox(height: 14),

        // --------------------------------------------------------- sync card
        _SyncCard(
          offsetMs: jam.clockOffsetMs,
          members: jam.members.length,
          maxMembers: jam.party?.maxMembers ?? 5,
        ),
        const SizedBox(height: 14),

        // ----------------------------------------------------------- members
        IfallSectionHeader(
          title: 'In the room',
          subtitle: '${jam.members.length} of ${jam.party?.maxMembers ?? 5} devices',
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
        ),
        IfallGlass(
          radius: IfallUI.rLg,
          blur: 0,
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: <Widget>[
              for (int i = 0; i < jam.members.length; i++)
                _MemberRow(
                  member: jam.members[i],
                  isYou: jam.members[i].deviceId == jam.you?.deviceId,
                  canKick: jam.isHost &&
                      jam.members[i].deviceId != jam.you?.deviceId,
                  onKick: () => jam.kick(jam.members[i].deviceId),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ------------------------------------------------------ host controls
        if (jam.isHost) ...<Widget>[
          IfallGroup(
            title: 'Host controls',
            children: <Widget>[
              IfallSwitchRow(
                title: 'Only the host can control playback',
                subtitle: 'Everyone else can still listen and watch the queue.',
                icon: Icons.admin_panel_settings_outlined,
                value: jam.hostOnlyControl,
                onChanged: jam.setHostOnlyControl,
              ),
            ],
          ),
        ],

        // ------------------------------------------------------------- queue
        if (jam.queueItems.isNotEmpty) ...<Widget>[
          IfallSectionHeader(
            title: 'Shared queue',
            subtitle: '${jam.queueItems.length} tracks · tap to play for everyone',
            padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
          ),
          IfallGlass(
            radius: IfallUI.rLg,
            blur: 0,
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < jam.queueItems.length; i++)
                  _QueueRow(
                    track: jam.queueItems[i],
                    index: i,
                    active: i == jam.queueIndex,
                    canControl: jam.canControl,
                    onPlay: () => jam.setTrack(
                      jam.queueItems[i],
                      positionMs: 0,
                      isPlaying: true,
                    ),
                    onRemove: () => jam.removeFromQueue(jam.queueItems[i].videoId),
                  ),
              ],
            ),
          ),
        ],

        // ----------------------------------------------- add from this device
        IfallGroup(
          title: 'Add to the room',
          footer: 'The queue holds at most 25 upcoming tracks per room.',
          children: <Widget>[
            IfallRow(
              title: 'Add what is playing now',
              subtitle: playback.current?.title,
              icon: Icons.playlist_add_rounded,
              onTap: playback.current == null
                  ? null
                  : () => jam.addToQueue(
                        <JamTrack>[JamTrack.fromSong(playback.current!)],
                      ),
            ),
            IfallRow(
              title: 'Add this device’s whole queue',
              subtitle: '${playback.queue.length} tracks',
              icon: Icons.playlist_play_rounded,
              onTap: playback.queue.isEmpty
                  ? null
                  : () => jam.addToQueue(
                        playback.queue
                            .map(JamTrack.fromSong)
                            .toList(growable: false),
                      ),
            ),
            IfallRow(
              title: 'Add your liked songs',
              icon: Icons.favorite_rounded,
              onTap: () {
                final List<Song> liked =
                    context.read<LibraryService>().likedSongs;
                if (liked.isEmpty) return;
                jam.addToQueue(
                  liked.take(25).map(JamTrack.fromSong).toList(growable: false),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// The room code, with copy and share.
class _CodeCard extends StatelessWidget {
  const _CodeCard({required this.code, required this.onLeave});

  final String code;
  final VoidCallback onLeave;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return IfallGlass(
      radius: IfallUI.rXl,
      blur: 0,
      color: c.accent.withValues(alpha: 0.10),
      border: c.accent.withValues(alpha: 0.4),
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        children: <Widget>[
          Text(
            'ROOM CODE',
            style: IfallText.label(c.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            code,
            style: IfallText.style(
              38,
              weight: FontWeight.w800,
              letterSpacing: 10,
              color: c.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: code));
                    if (context.mounted) showAppNotice('Room code copied');
                  },
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.onSurface,
                    side: BorderSide(color: c.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(IfallUI.rPill),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showIfallSheet<void>(
                    context: context,
                    builder: (BuildContext c2) => IfallSheet(
                      title: 'Invite',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          Text(
                            'Share this code, or the link below.',
                            style: IfallText.body(c.onSurfaceVariant),
                          ),
                          const SizedBox(height: 18),
                          _InviteRow(
                            label: 'Code',
                            value: code,
                            icon: Icons.tag_rounded,
                          ),
                          const SizedBox(height: 10),
                          _InviteRow(
                            label: 'Link',
                            value: '${IfallBranding.websiteUrl}/room/$code',
                            icon: Icons.link_rounded,
                          ),
                        ],
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: const Text('Invite'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: c.onSurface,
                    side: BorderSide(color: c.outline),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(IfallUI.rPill),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InviteRow extends StatelessWidget {
  const _InviteRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return IfallGlass(
      radius: IfallUI.rMd,
      blur: 0,
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: value));
        if (context.mounted) showAppNotice('$label copied');
      },
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: c.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: IfallText.body(c.onSurface),
            ),
          ),
          Icon(Icons.copy_rounded, size: 16, color: c.onSurfaceVariant),
        ],
      ),
    );
  }
}

/// Now playing, with the room's own transport controls.
class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.track,
    required this.playing,
    required this.position,
    required this.canControl,
    required this.onPlayPause,
    required this.onNext,
    required this.onPrevious,
    required this.onSeek,
    this.startedBy,
  });

  final JamTrack track;
  final bool playing;
  final Duration position;
  final bool canControl;
  final VoidCallback onPlayPause;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final ValueChanged<Duration> onSeek;
  final String? startedBy;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final Duration length = Duration(milliseconds: track.durationMs);
    final double progress = length.inMilliseconds <= 0
        ? 0
        : (position.inMilliseconds / length.inMilliseconds).clamp(0.0, 1.0);

    return IfallGlass(
      radius: IfallUI.rXl,
      blur: 0,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Artwork(url: track.thumbnailUrl, size: 62, radius: 10),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IfallText.body(c.onSurface)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IfallText.caption(c.onSurfaceVariant),
                    ),
                    if (startedBy != null) ...<Widget>[
                      const SizedBox(height: 3),
                      Text(
                        'Started by $startedBy',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: IfallText.caption(c.accent),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: c.accent,
              inactiveTrackColor: c.glassStrong,
              thumbColor: c.onSurface,
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: progress,
              onChanged: canControl
                  ? (double v) => onSeek(
                        Duration(
                          milliseconds: (v * length.inMilliseconds).round(),
                        ),
                      )
                  : null,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: <Widget>[
                Text(Fmt.duration(position), style: IfallText.caption(c.onSurfaceVariant)),
                const Spacer(),
                Text(Fmt.duration(length), style: IfallText.caption(c.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              IconButton(
                onPressed: canControl ? onPrevious : null,
                icon: const Icon(Icons.skip_previous_rounded),
                iconSize: 32,
                color: c.onSurface,
              ),
              const SizedBox(width: 18),
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c.accent,
                ),
                child: IconButton(
                  onPressed: canControl ? onPlayPause : null,
                  icon: Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    color: ThemeData.estimateBrightnessForColor(c.accent) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black,
                  ),
                  iconSize: 30,
                ),
              ),
              const SizedBox(width: 18),
              IconButton(
                onPressed: canControl ? onNext : null,
                icon: const Icon(Icons.skip_next_rounded),
                iconSize: 32,
                color: c.onSurface,
              ),
            ],
          ),
          if (!canControl) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              'The host has locked playback control.',
              style: IfallText.caption(c.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// How well this device is keeping time with the room.
class _SyncCard extends StatelessWidget {
  const _SyncCard({
    required this.offsetMs,
    required this.members,
    required this.maxMembers,
  });

  final int? offsetMs;
  final int members;
  final int maxMembers;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    final String quality = offsetMs == null
        ? 'Measuring…'
        : offsetMs!.abs() < 120
            ? 'Tight'
            : offsetMs!.abs() < 500
                ? 'Good'
                : 'Drifting';
    return IfallGlass(
      radius: IfallUI.rLg,
      blur: 0,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: <Widget>[
          Icon(Icons.sync_rounded, size: 18, color: c.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Sync $quality${offsetMs == null ? '' : ' · ${offsetMs}ms from the room clock'}',
              style: IfallText.caption(c.onSurfaceVariant),
            ),
          ),
          Text(
            '$members/$maxMembers',
            style: IfallText.caption(c.onSurfaceVariant)
                .copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isYou,
    required this.canKick,
    required this.onKick,
  });

  final JamMember member;
  final bool isYou;
  final bool canKick;
  final VoidCallback onKick;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      child: Row(
        children: <Widget>[
          CircleAvatar(
            radius: 17,
            backgroundColor: c.accent.withValues(alpha: 0.20),
            child: Text(
              member.initials,
              style: IfallText.caption(c.accent)
                  .copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  member.displayName + (isYou ? ' (you)' : ''),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: IfallText.body(c.onSurface),
                ),
                if (member.isHost)
                  Text('Host', style: IfallText.caption(c.accent)),
              ],
            ),
          ),
          if (!member.connected)
            Icon(Icons.cloud_off_rounded, size: 16, color: c.onSurfaceVariant),
          if (canKick)
            IconButton(
              onPressed: onKick,
              icon: const Icon(Icons.person_remove_outlined),
              iconSize: 19,
              tooltip: 'Remove from the room',
              color: c.onSurfaceVariant,
            ),
        ],
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.track,
    required this.index,
    required this.active,
    required this.canControl,
    required this.onPlay,
    required this.onRemove,
  });

  final JamTrack track;
  final int index;
  final bool active;
  final bool canControl;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final IfallPalette c = IfallPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: canControl ? onPlay : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 22,
                child: Text(
                  '${index + 1}',
                  style: IfallText.caption(c.onSurfaceVariant),
                ),
              ),
              const SizedBox(width: 6),
              Artwork(url: track.thumbnailUrl, size: 40, radius: 6),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IfallText.body(
                        active ? c.accent : c.onSurface,
                      ),
                    ),
                    Text(
                      track.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: IfallText.caption(c.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (canControl)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded),
                  iconSize: 18,
                  color: c.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
