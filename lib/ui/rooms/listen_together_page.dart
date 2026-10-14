import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/services/listen_together_service.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../../core/utils/format.dart';
import '../widgets/sidify_widgets.dart';

/// Listen Together — the site's Rooms: start a room, share the six-character
/// code, and everyone hears the same song at the same moment. The room is
/// the truth; this device mirrors it (see [JamService] for the clock math).
class ListenTogetherPage extends StatefulWidget {
  const ListenTogetherPage({super.key, this.embedded = true});

  /// As a tab (inside the shell) vs pushed over it (from the player).
  final bool embedded;

  @override
  State<ListenTogetherPage> createState() => _ListenTogetherPageState();
}

class _ListenTogetherPageState extends State<ListenTogetherPage> {
  final TextEditingController _code = TextEditingController();
  final TextEditingController _server = TextEditingController();
  String? _error;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    final SettingsService settings = context.read<SettingsService>();
    _server.text = settings.jamServer;
    final String? last = settings.jamLastCode;
    if (last != null && last.isNotEmpty) _code.text = last;
    _ticker =
        Timer.periodic(const Duration(milliseconds: 500), (_) => _syncToRoom());
  }

  /// Mirrors the room onto this device's player. When the room's track
  /// differs, this device starts it; when only the position drifted, it seeks.
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

  @override
  Widget build(BuildContext context) {
    final JamService jam = context.watch<JamService>();
    final Widget body = SafeArea(
      bottom: false,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 190),
        physics: const BouncingScrollPhysics(),
        children: <Widget>[
          const PageTitle('Listen Together'),
          if (jam.isConnected)
            _room(context, jam)
          else
            _lobby(context, jam),
        ],
      ),
    );
    if (widget.embedded) return body;
    return Scaffold(
      backgroundColor: context.sidify.bg,
      body: body,
    );
  }

  // ------------------------------------------------------------- the lobby
  Widget _lobby(BuildContext context, JamService jam) {
    final SidifyTokens t = context.sidify;
    final SettingsService settings = context.watch<SettingsService>();
    final PlaybackService playback = context.watch<PlaybackService>();
    final bool busy = jam.state == JamConnectionState.joining;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Text(
            'Start a room, share the code, and everyone hears the same song '
            'at the same moment.',
            style: TextStyle(fontSize: 14.5, height: 1.45, color: t.text2),
          ),
        ),
        if (!jam.hasServer) ...<Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _field(
                  context,
                  controller: _server,
                  hint: JamService.placeholderServer,
                  icon: Icons.dns_rounded,
                  keyboard: TextInputType.url,
                ),
                const SizedBox(height: 10),
                SidifyButton(
                  label: 'Save server',
                  variant: SidifyButtonVariant.secondary,
                  onTap: () async {
                    await settings.setJamServer(_server.text.trim());
                    if (context.mounted) setState(() {});
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  'Rooms need a Listen Together server. Add its address '
                  'above to start or join a room.',
                  style: TextStyle(fontSize: 12.5, color: t.text2),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              SidifyButton(
                label: busy ? 'Starting…' : 'Start a room',
                icon: Icons.people_rounded,
                onTap: busy || !jam.hasServer ? null : _create,
              ),
              const SizedBox(height: 22),
              Row(
                children: <Widget>[
                  Expanded(child: Divider(color: t.hairline)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text('or join with a code',
                        style: TextStyle(fontSize: 12.5, color: t.text2)),
                  ),
                  Expanded(child: Divider(color: t.hairline)),
                ],
              ),
              const SizedBox(height: 14),
              _field(
                context,
                controller: _code,
                hint: 'ABC123',
                icon: Icons.meeting_room_rounded,
                caps: true,
              ),
              const SizedBox(height: 10),
              SidifyButton(
                label: busy ? 'Joining…' : 'Join room',
                variant: SidifyButtonVariant.secondary,
                onTap: busy || !jam.hasServer ? null : _join,
              ),
              if ((_error ?? jam.error ?? '').isNotEmpty) ...<Widget>[
                const SizedBox(height: 14),
                Text(
                  _error ?? jam.error ?? '',
                  style: TextStyle(fontSize: 13, color: t.danger),
                ),
              ],
              if (playback.current != null && jam.hasServer) ...<Widget>[
                const SizedBox(height: 24),
                Text(
                  'Tip: once you are in a room, put the song that is playing '
                  'here into the room from this page.',
                  style: TextStyle(fontSize: 12.5, height: 1.4, color: t.text2),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------- the room
  Widget _room(BuildContext context, JamService jam) {
    final SidifyTokens t = context.sidify;
    final PlaybackService playback = context.watch<PlaybackService>();
    final JamTrack? track = jam.currentTrack;
    final bool playing = jam.playback?.isPlaying ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // The code card.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.edge, width: 0.5),
            ),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'ROOM CODE',
                        style: SidifyText.eyebrow(t.text2),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        jam.code ?? '',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 2,
                          color: t.text,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      Text(
                        '${jam.members.length} listening'
                        '${jam.hostOnlyControl ? ' · host controls' : ''}',
                        style: TextStyle(fontSize: 13, color: t.text2),
                      ),
                    ],
                  ),
                ),
                Column(
                  children: <Widget>[
                    SidifyButton(
                      label: 'Copy code',
                      icon: Icons.copy_rounded,
                      small: true,
                      variant: SidifyButtonVariant.secondary,
                      onTap: () {
                        Clipboard.setData(
                          ClipboardData(text: jam.code ?? ''),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    SidifyButton(
                      label: 'Leave',
                      small: true,
                      variant: SidifyButtonVariant.danger,
                      onTap: () async {
                        await jam.leave();
                        if (mounted) setState(() => _error = null);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // Now playing in the room.
        const SectionHeader(title: 'Now playing'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: t.raised,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.edge, width: 0.5),
            ),
            child: track == null
                ? Text(
                    'Nothing is playing in this room yet. Put a song on and '
                    'everyone will hear it.',
                    style: TextStyle(fontSize: 13.5, height: 1.4, color: t.text2),
                  )
                : Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Artwork(url: track.thumbnailUrl, size: 52, radius: 8),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15.5,
                                    fontWeight: FontWeight.w600,
                                    color: t.text,
                                  ),
                                ),
                                Text(
                                  track.artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, color: t.text2),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          IconButton(
                            icon: Icon(Icons.skip_previous_rounded,
                                size: 30, color: t.text),
                            onPressed: jam.canControl ? jam.previous : null,
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: jam.canControl
                                ? () {
                                    final int ms =
                                        playback.position.inMilliseconds;
                                    if (playing) {
                                      jam.pause(positionMs: ms);
                                    } else {
                                      jam.play(positionMs: ms);
                                    }
                                  }
                                : null,
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                color: t.primary,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                playing
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                                size: 30,
                                color: t.onPrimary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          IconButton(
                            icon: Icon(Icons.skip_next_rounded,
                                size: 30, color: t.text),
                            onPressed: jam.canControl ? jam.next : null,
                          ),
                        ],
                      ),
                      if (track.durationMs > 0)
                        Text(
                          'At ${Fmt.duration(jam.positionNow)} of '
                          '${Fmt.duration(Duration(milliseconds: track.durationMs))}',
                          style: TextStyle(fontSize: 12, color: t.text2),
                        ),
                    ],
                  ),
          ),
        ),

        if (playback.current != null && jam.canControl)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
            child: SidifyButton(
              label: 'Play ${playback.current!.title} in this room',
              icon: Icons.play_circle_rounded,
              variant: SidifyButtonVariant.brand,
              onTap: () {
                jam.setTrack(JamTrack.fromSong(playback.current!));
              },
            ),
          ),

        // Up next in the room.
        if (jam.queueItems.length > 1) ...<Widget>[
          const SectionHeader(title: 'Up next in the room'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < jam.queueItems.length; i++)
                  if (i != jam.queueIndex)
                    Row(
                      children: <Widget>[
                        Artwork(
                          url: jam.queueItems[i].thumbnailUrl,
                          size: 44,
                          radius: 6,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                jam.queueItems[i].title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 14.5, color: t.text),
                              ),
                              Text(
                                jam.queueItems[i].artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: t.text2),
                              ),
                            ],
                          ),
                        ),
                        if (jam.canControl)
                          IconButton(
                            icon: Icon(Icons.close_rounded,
                                size: 16, color: t.text2),
                            onPressed: () => jam.removeFromQueue(
                              jam.queueItems[i].videoId,
                            ),
                          ),
                      ],
                    ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // Members.
        const SectionHeader(title: 'Listening now'),
        SidifyGroup(
          children: <Widget>[
            for (final JamMember m in jam.members)
              SidifyGroupRow(
                title: m.displayName,
                subtitle: m.isHost
                    ? 'Host'
                    : (m.connected ? 'Listening' : 'Away'),
                icon: Icons.person_rounded,
                trailing: Text(
                  m.initials,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: t.text2,
                  ),
                ),
              ),
          ],
        ),
        if (jam.clockOffsetMs != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Clock offset ${jam.clockOffsetMs} ms · kept in sync by Sidify',
              style: TextStyle(fontSize: 12, color: t.text3),
            ),
          ),
      ],
    );
  }

  Widget _field(
    BuildContext context, {
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool caps = false,
    TextInputType keyboard = TextInputType.text,
  }) {
    final SidifyTokens t = context.sidify;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: t.fill,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.edge, width: 0.5),
      ),
      child: Row(
        children: <Widget>[
          const SizedBox(width: 12),
          Icon(icon, size: 19, color: t.text2),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboard,
              textCapitalization: caps
                  ? TextCapitalization.characters
                  : TextCapitalization.none,
              style: TextStyle(
                fontSize: 16,
                color: t.text,
                letterSpacing: caps ? 2 : 0,
              ),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: TextStyle(color: t.text2),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
