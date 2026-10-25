import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/models/song.dart';
import '../../core/services/app_feedback.dart';
import '../../core/services/jam_friends_service.dart';
import '../../core/services/jam_invite_service.dart';
import '../../core/services/listen_together_service.dart';
import '../../core/services/native_bridge.dart';
import '../../core/services/playback_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/services/youtube_service.dart';
import '../../core/theme/sidify_theme.dart';
import '../widgets/sidify_widgets.dart';
import 'room_chat_panel.dart';

/// Listen Together — rooms for the song side of the app.
///
/// Out of a room this is the lobby: start a room (your current song comes
/// along), join with a six-letter code, and invite the people you have
/// listened with before. In a room it is the room itself: now playing,
/// the shareable code and link, chat, the shared queue, and everyone in it.
class ListenTogetherPage extends StatefulWidget {
  const ListenTogetherPage({super.key, this.embedded = true});

  /// As a tab (inside the shell) vs pushed over it (from the player).
  final bool embedded;

  @override
  State<ListenTogetherPage> createState() => _ListenTogetherPageState();
}

class _ListenTogetherPageState extends State<ListenTogetherPage> {
  final TextEditingController _codeController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  bool _busy = false;
  bool _createHostOnly = false;
  int _createSize = 5;

  JamPreview? _preview;
  String? _previewError;
  bool _previewBusy = false;
  int _previewSeq = 0;

  Timer? _searchDebounce;
  int _searchSeq = 0;
  bool _searching = false;
  List<Song> _results = const <Song>[];

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // The free room server sleeps when idle; start waking it the moment
    // this page exists so Create/Join usually finds it already up.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<JamService>().warmUp();
    });
    // The room's clock advances between server frames; one gentle tick a
    // second keeps "elapsed" honest without rebuilding on every frame.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final JamService jam = context.read<JamService>();
      if (jam.inRoom) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _searchDebounce?.cancel();
    _codeController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------------ actions

  Future<bool> _createRoom() async {
    final JamService jam = context.read<JamService>();
    setState(() => _busy = true);
    final bool ok = await jam.create(maxMembers: _createSize, autoplay: true);
    if (!mounted) return ok;
    if (ok) {
      if (_createHostOnly) jam.setHostOnlyControl(true);
      _seedFromLocal(jam);
    }
    setState(() => _busy = false);
    return ok;
  }

  void _seedFromLocal(JamService jam) {
    final PlaybackService playback = context.read<PlaybackService>();
    final Song? song = playback.current;
    if (song == null) return;
    final List<Song> queue = playback.queue;
    int index = playback.currentIndex;
    if (queue.isNotEmpty) {
      index = index.clamp(0, queue.length - 1).toInt();
      jam.setQueue(
        queue.map((Song s) => JamTrack.fromSong(s)).toList(),
        index: index,
      );
    }
    jam.setTrack(
      JamTrack.fromSong(song),
      positionMs: playback.position.inMilliseconds,
      isPlaying: playback.isPlaying,
      queueIndex: queue.isNotEmpty ? index : 0,
    );
  }

  Future<void> _joinRoom(String code) async {
    final JamService jam = context.read<JamService>();
    setState(() => _busy = true);
    await jam.join(code);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  Future<void> _acceptInvite(JamInvite invite) async {
    final JamInviteService invites = context.read<JamInviteService>();
    setState(() => _busy = true);
    await invites.respond(invite, accept: true);
    if (!mounted) return;
    await _joinRoom(invite.code);
  }

  Future<void> _inviteFriend(JamFriend friend) async {
    final JamService jam = context.read<JamService>();
    final JamInviteService invites = context.read<JamInviteService>();
    if (!jam.inRoom) {
      showAppNotice('Starting a room for you and ${friend.name}…');
      final bool ok = await _createRoom();
      if (!mounted) return;
      if (!ok) return;
    }
    final String? code = jam.code;
    if (code == null) return;
    final res = await invites.sendInvite(toUserId: friend.userId, code: code);
    if (!mounted) return;
    if (res.ok) {
      showAppNotice(
        res.online
            ? 'Invite sent — ${friend.name} is being asked right now.'
            : 'Invite left for ${friend.name}. If their app is closed, '
                'send them the link from the room too.',
      );
    } else {
      showAppNotice(
        res.error ?? 'Invite could not be sent — share the link instead.',
      );
    }
  }

  Future<void> _loadPreview(String code) async {
    final JamService jam = context.read<JamService>();
    final int seq = ++_previewSeq;
    setState(() {
      _previewBusy = true;
      _previewError = null;
    });
    final (JamPreview? preview, String? error) = await jam.preview(code);
    if (!mounted || seq != _previewSeq) return;
    setState(() {
      _previewBusy = false;
      _preview = preview;
      _previewError = error;
    });
  }

  void _onCodeChanged(String value) {
    final String normalised = normalizeJamCode(value);
    if (normalised != _codeController.text) {
      _codeController.value = TextEditingValue(
        text: normalised,
        selection: TextSelection.collapsed(offset: normalised.length),
      );
    }
    if (normalised.length == jamCodeLength) {
      unawaited(_loadPreview(normalised));
    } else {
      _previewSeq++;
      setState(() {
        _preview = null;
        _previewError = null;
        _previewBusy = false;
      });
    }
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    final String query = value.trim();
    if (query.length < 2) {
      setState(() {
        _results = const <Song>[];
        _searching = false;
      });
      return;
    }
    _searchDebounce = Timer(const Duration(milliseconds: 450), () {
      unawaited(_runSearch(query));
    });
  }

  Future<void> _runSearch(String query) async {
    final YoutubeService youtube = context.read<YoutubeService>();
    final int seq = ++_searchSeq;
    setState(() => _searching = true);
    try {
      final List<Song> songs = await youtube.searchSongs(query, limit: 12);
      if (!mounted || seq != _searchSeq) return;
      setState(() {
        _results = songs;
        _searching = false;
      });
    } catch (_) {
      if (!mounted || seq != _searchSeq) return;
      setState(() => _searching = false);
    }
  }

  void _requireControl(JamService jam, VoidCallback action) {
    if (!jam.isConnected) {
      showAppNotice('Reconnecting — controls are back in a moment.');
      return;
    }
    if (!jam.canControl) {
      showAppNotice('Only the host controls playback in this room.');
      return;
    }
    action();
  }

  void _playNow(JamService jam, Song song) {
    _requireControl(jam, () {
      final int at =
          jam.queueItems.indexWhere((JamTrack t) => t.videoId == song.id);
      jam.setTrack(
        JamTrack.fromSong(song),
        queueIndex: at >= 0 ? at : null,
      );
      showAppNotice('Now playing for the room: ${song.title}');
    });
  }

  void _togglePlay(JamService jam) {
    final bool roomPlaying = jam.playback?.isPlaying ?? false;
    _requireControl(jam, () {
      // Pause lands instantly on this device too — a host tapping pause
      // should not hear their own phone play on for a beat.
      if (roomPlaying) {
        unawaited(context.read<PlaybackService>().pause());
      }
      jam.togglePlayPause();
    });
  }

  Future<void> _copy(String text, String notice) async {
    await Clipboard.setData(ClipboardData(text: text));
    showAppNotice(notice);
  }

  Future<void> _shareInvite(JamService jam) async {
    final String url = jam.inviteUrl;
    final String code = jam.code ?? '';
    if (url.isEmpty) return;
    final String text = 'Listen with me on Sidify 🎵\n'
        'Join my room: $url\n'
        'Room code: $code';
    final bool shared = await NativeBridge.shareText(
      text: text,
      title: 'Join my listening room',
    );
    if (!shared) {
      await _copy(text, 'Invite copied — paste it anywhere.');
    }
  }

  Future<bool> _confirm(String title, String body, String action) async {
    final SidifyTokens t = context.sidify;
    final bool? ok = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: t.raised,
        title: Text(title, style: TextStyle(color: t.text)),
        content: Text(body, style: TextStyle(color: t.text2)),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: TextStyle(color: t.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action, style: TextStyle(color: t.danger)),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// The one server affordance left in the UI: run the reachability
  /// test and show its verdict. The address itself is a built-in
  /// constant — never shown, never editable — so there is nothing
  /// here for a listener to see or break.
  Future<void> _runServerTest(JamService jam) async {
    final SidifyTokens t = context.sidify;
    bool testing = false;
    bool testOk = false;
    String? testResult;

    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx, StateSetter setDialogState) {
          return AlertDialog(
            backgroundColor: t.raised,
            title: Text('Room server', style: TextStyle(color: t.text)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Check that rooms can reach their server from this '
                  'phone right now.',
                  style: TextStyle(fontSize: 13, height: 1.45, color: t.text2),
                ),
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: testing
                        ? null
                        : () async {
                            setDialogState(() {
                              testing = true;
                              testResult = null;
                            });
                            final (bool ok, String message) =
                                await jam.testServer();
                            if (!ctx.mounted) return;
                            setDialogState(() {
                              testing = false;
                              testOk = ok;
                              testResult = message;
                            });
                          },
                    icon: testing
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: t.brand,
                            ),
                          )
                        : const Icon(Icons.wifi_tethering_rounded, size: 18),
                    label: Text(testing ? 'Running…' : 'Run test'),
                    style: TextButton.styleFrom(foregroundColor: t.brand),
                  ),
                ),
                if (testing)
                  Text(
                    'Asking the server… if it was asleep, this can take '
                    'a minute.',
                    style:
                        TextStyle(fontSize: 12.5, height: 1.4, color: t.text2),
                  ),
                if (testResult != null)
                  Text(
                    testResult!,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: testOk ? t.brand : t.danger,
                    ),
                  ),
              ],
            ),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text('Close', style: TextStyle(color: t.text2)),
              ),
            ],
          );
        },
      ),
    );
  }

  // --------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final JamService jam = context.watch<JamService>();
    final Widget body = SafeArea(
      bottom: false,
      child: jam.inRoom ? _roomView(context, jam) : _lobbyView(context, jam),
    );
    if (widget.embedded) return body;
    return Scaffold(backgroundColor: t.bg, body: body);
  }

  // --------------------------------------------------------------------- lobby

  Widget _lobbyView(BuildContext context, JamService jam) {
    final SidifyTokens t = context.sidify;
    final SettingsService settings = context.watch<SettingsService>();
    final JamFriendsService friendsService =
        context.watch<JamFriendsService>();
    final JamInviteService invites = context.watch<JamInviteService>();
    final PlaybackService playback = context.watch<PlaybackService>();
    final Song? current = playback.current;
    final String code = _codeController.text;
    final String lastCode = settings.jamLastCode ?? '';
    final bool joinReady = code.length == jamCodeLength && !_busy;

    return ListView(
      padding: const EdgeInsets.only(bottom: 190),
      physics: const BouncingScrollPhysics(),
      children: <Widget>[
        const PageTitle('Listen Together'),
        if (jam.state == JamConnectionState.error && jam.error != null)
          _errorBanner(jam.error!, jam.clearError),
        if (jam.serverWaking) _wakingHint(jam),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Text(
            'Start a room, share the code or link, and everyone hears the '
            'same song at the same moment — chat included.',
            style: TextStyle(fontSize: 14, height: 1.5, color: t.text2),
          ),
        ),

        // Someone is asking *us*.
        for (final JamInvite invite in invites.pending)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: t.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.brand.withValues(alpha: 0.35)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '${invite.fromName} wants to listen with you 🎧',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Room ${invite.code}',
                    style: TextStyle(fontSize: 13, color: t.text2),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: <Widget>[
                      SidifyButton(
                        label: 'Join',
                        small: true,
                        onTap: _busy ? null : () => _acceptInvite(invite),
                      ),
                      const SizedBox(width: 8),
                      SidifyButton(
                        label: 'Not now',
                        small: true,
                        variant: SidifyButtonVariant.ghost,
                        onTap: () =>
                            invites.respond(invite, accept: false),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

        // ------------------------------------------------------- create a room
        _card(
          t,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.groups_rounded, size: 19, color: t.brand),
                const SizedBox(width: 8),
                Text(
                  'Start a room',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ],
            ),
            if (current != null) ...<Widget>[
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Artwork(url: current.thumbnailUrl, size: 44, radius: 8),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          current.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: t.text),
                        ),
                        Text(
                          'Your current song and queue come along',
                          style: TextStyle(fontSize: 12.5, color: t.text2),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Only I control playback',
                        style: TextStyle(fontSize: 14, color: t.text),
                      ),
                      Text(
                        'Guests listen and chat; you drive',
                        style: TextStyle(fontSize: 12.5, color: t.text2),
                      ),
                    ],
                  ),
                ),
                SidifySwitch(
                  value: _createHostOnly,
                  onChanged: (bool v) => setState(() => _createHostOnly = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Room size',
                    style: TextStyle(fontSize: 14, color: t.text),
                  ),
                ),
                _stepper(
                  t,
                  value: _createSize,
                  min: 2,
                  max: 10,
                  onChanged: (int v) => setState(() => _createSize = v),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: SidifyButton(
                label: _busy ? 'Starting…' : 'Create room',
                icon: Icons.play_arrow_rounded,
                onTap: _busy ? null : () => _createRoom(),
              ),
            ),
          ],
        ),

        // --------------------------------------------------------- join a room
        _card(
          t,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(Icons.meeting_room_rounded, size: 19, color: t.brand),
                const SizedBox(width: 8),
                Text(
                  'Join with a code',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Container(
              decoration: BoxDecoration(
                color: t.fill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.edge, width: 0.5),
              ),
              child: TextField(
                controller: _codeController,
                onChanged: _onCodeChanged,
                textCapitalization: TextCapitalization.characters,
                autocorrect: false,
                textAlign: TextAlign.center,
                maxLength: 10,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 6,
                  color: t.text,
                ),
                decoration: InputDecoration(
                  hintText: 'ABC123',
                  hintStyle: TextStyle(color: t.text3, letterSpacing: 6),
                  border: InputBorder.none,
                  counterText: '',
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 20,
              child: _previewBusy
                  ? Text(
                      'Checking the room…',
                      style: TextStyle(fontSize: 12.5, color: t.text2),
                    )
                  : _previewError != null
                      ? Text(
                          _previewError!,
                          style: TextStyle(fontSize: 12.5, color: t.danger),
                        )
                      : _preview != null
                          ? Text(
                              _preview!.isFull
                                  ? "${_preview!.hostName}'s room is full "
                                      '(${_preview!.memberCount}/${_preview!.maxMembers})'
                                  : "${_preview!.hostName}'s room · "
                                      '${_preview!.memberCount}/${_preview!.maxMembers} in',
                              style: TextStyle(
                                fontSize: 12.5,
                                color:
                                    _preview!.isFull ? t.danger : t.text2,
                              ),
                            )
                          : const SizedBox.shrink(),
            ),
            const SizedBox(height: 10),
            Row(
              children: <Widget>[
                SidifyButton(
                  label: _busy ? 'Joining…' : 'Join room',
                  icon: Icons.login_rounded,
                  onTap: joinReady ? () => _joinRoom(code) : null,
                ),
                if (lastCode.isNotEmpty && lastCode != code) ...<Widget>[
                  const SizedBox(width: 8),
                  SidifyButton(
                    label: 'Rejoin $lastCode',
                    variant: SidifyButtonVariant.secondary,
                    onTap: _busy ? null : () => _joinRoom(lastCode),
                  ),
                ],
              ],
            ),
          ],
        ),

        // -------------------------------------------------------------- friends
        const SectionHeader(
          title: 'Friends',
          subtitle: 'PEOPLE YOU HAVE LISTENED WITH',
        ),
        if (friendsService.friends.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'Nobody yet. After your first room together, friends appear '
              'here — invite them next time with one tap, no code needed.',
              style: TextStyle(fontSize: 13, height: 1.5, color: t.text2),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: SidifyGroup(
              children: <Widget>[
                for (final JamFriend friend in friendsService.friends)
                  _friendRow(context, friend, invites, friendsService),
              ],
            ),
          ),

        // --------------------------------------------------------------- server
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SidifyGroup(
            children: <Widget>[
              SidifyGroupRow(
                icon: Icons.dns_outlined,
                title: 'Room server',
                subtitle: 'Tap to run a connection test',
                chevron: true,
                onTap: () => _runServerTest(jam),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Text(
            'One honest note: a friend gets your invite instantly while '
            'their Sidify app is open or playing music. If the app is fully '
            'closed, only the shared link can reach them.',
            style: TextStyle(fontSize: 12, height: 1.5, color: t.text3),
          ),
        ),
      ],
    );
  }

  Widget _friendRow(
    BuildContext context,
    JamFriend friend,
    JamInviteService invites,
    JamFriendsService friendsService,
  ) {
    final SidifyTokens t = context.sidify;
    final bool online = invites.isOnline(friend.userId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          Stack(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: t.brand.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  _initials(friend.name),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.brand,
                  ),
                ),
              ),
              if (online)
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: 11,
                    height: 11,
                    decoration: BoxDecoration(
                      color: t.playing,
                      shape: BoxShape.circle,
                      border: Border.all(color: t.raised, width: 2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  friend.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, color: t.text),
                ),
                Text(
                  online
                      ? 'Online now'
                      : 'Listened together ${_ago(friend.lastSeenMs)}',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: online ? t.playing : t.text2,
                  ),
                ),
              ],
            ),
          ),
          SidifyButton(
            label: 'Invite',
            small: true,
            icon: Icons.send_rounded,
            onTap: _busy ? null : () => _inviteFriend(friend),
          ),
          IconButton(
            tooltip: 'Remove friend',
            icon: Icon(Icons.close_rounded, size: 17, color: t.text3),
            onPressed: () async {
              final bool ok = await _confirm(
                'Remove ${friend.name}?',
                'They will come back automatically the next time you '
                    'share a room.',
                'Remove',
              );
              if (ok) await friendsService.remove(friend.userId);
            },
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------------------- room

  Widget _roomView(BuildContext context, JamService jam) {
    final SidifyTokens t = context.sidify;
    final JamPlayback? pb = jam.playback;
    final JamTrack? track = jam.currentTrack;
    final int queueIndex = jam.queue.index;
    final List<JamTrack> upcoming = <JamTrack>[
      for (int i = queueIndex + 1; i < jam.queueItems.length; i++)
        jam.queueItems[i],
    ];
    final List<Song> upcomingSongs =
        upcoming.map((JamTrack tr) => tr.toSong()).toList();
    final String hostName = jam.hostName;
    final String title =
        hostName.isNotEmpty ? "$hostName's room" : 'Listen Together';

    return ListView(
      padding: const EdgeInsets.only(bottom: 190),
      physics: const BouncingScrollPhysics(),
      children: <Widget>[
        PageTitle(title, trailing: _statusChip(t, jam)),
        if (jam.isReconnecting)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: t.fill,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.edge, width: 0.5),
              ),
              child: Row(
                children: <Widget>[
                  SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: t.brand,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Connection dropped — your seat is saved, '
                      'getting you back in…',
                      style: TextStyle(fontSize: 13, color: t.text2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (jam.error != null && jam.state == JamConnectionState.connected)
          _errorBanner(jam.error!, jam.clearError),

        // -------------------------------------------------------- now playing
        _card(
          t,
          children: <Widget>[
            if (track == null)
              Text(
                'Nothing playing yet. Add a song below — or just play '
                'anything in the app and the room follows.',
                style: TextStyle(fontSize: 14, height: 1.5, color: t.text2),
              )
            else ...<Widget>[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Artwork(url: track.thumbnailUrl, size: 72, radius: 10),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          track.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: t.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.5, color: t.text2),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          <String>[
                            if (pb?.startedByName != null &&
                                pb!.startedByName!.isNotEmpty)
                              'Started by ${pb.startedByName}',
                            '${jam.members.length} of ${jam.party?.maxMembers ?? 5} in the room',
                            if (track.durationMs > 0)
                              '${_clock(jam.positionNow)} / '
                                  '${_clock(Duration(milliseconds: track.durationMs))}',
                          ].join(' · '),
                          style: TextStyle(fontSize: 12, color: t.text3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  SidifyIconButton(
                    icon: Icons.skip_previous_rounded,
                    label: 'Previous song',
                    size: 44,
                    iconSize: 24,
                    tone: 'fill',
                    onTap: () => _requireControl(jam, jam.previous),
                  ),
                  const SizedBox(width: 18),
                  Material(
                    color: t.brand,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _togglePlay(jam),
                      child: SizedBox(
                        width: 60,
                        height: 60,
                        child: Icon(
                          (pb?.isPlaying ?? false)
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded,
                          size: 30,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 18),
                  SidifyIconButton(
                    icon: Icons.skip_next_rounded,
                    label: 'Next song',
                    size: 44,
                    iconSize: 24,
                    tone: 'fill',
                    onTap: () => _requireControl(jam, jam.next),
                  ),
                ],
              ),
            ],
          ],
        ),

        // --------------------------------------------------------- code + share
        _card(
          t,
          children: <Widget>[
            Text(
              'Room code',
              style: TextStyle(fontSize: 12.5, color: t.text2),
            ),
            const SizedBox(height: 6),
            GestureDetector(
              onTap: () => _copy(jam.code ?? '', 'Room code copied.'),
              child: Row(
                children: <Widget>[
                  Text(
                    jam.code ?? '',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 6,
                      color: t.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.copy_rounded, size: 17, color: t.text3),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Anyone with the code or link can join this room.',
              style: TextStyle(fontSize: 12.5, color: t.text2),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                SidifyButton(
                  label: 'Share link',
                  small: true,
                  icon: Icons.ios_share_rounded,
                  onTap: () => _shareInvite(jam),
                ),
                SidifyButton(
                  label: 'Copy code',
                  small: true,
                  variant: SidifyButtonVariant.secondary,
                  icon: Icons.copy_rounded,
                  onTap: () => _copy(jam.code ?? '', 'Room code copied.'),
                ),
                SidifyButton(
                  label: 'Copy link',
                  small: true,
                  variant: SidifyButtonVariant.secondary,
                  icon: Icons.link_rounded,
                  onTap: () => _copy(jam.inviteUrl, 'Invite link copied.'),
                ),
              ],
            ),
          ],
        ),

        // ----------------------------------------------------------------- chat
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: RoomChatPanel(height: 360),
        ),
        const SizedBox(height: 20),

        // ------------------------------------------------------------ add songs
        const SectionHeader(title: 'Add songs'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
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
                Icon(Icons.search_rounded, size: 19, color: t.text2),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    style: TextStyle(fontSize: 15, color: t.text),
                    decoration: InputDecoration(
                      hintText: 'Search songs for the room…',
                      hintStyle: TextStyle(color: t.text2),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                  ),
                ),
                if (_searching)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.brand,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        for (final Song song in _results)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: Row(
              children: <Widget>[
                Artwork(url: song.thumbnailUrl, size: 46, radius: 7),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        song.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14.5, color: t.text),
                      ),
                      Text(
                        song.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: t.text2),
                      ),
                    ],
                  ),
                ),
                SidifyIconButton(
                  icon: Icons.play_arrow_rounded,
                  label: 'Play now',
                  tone: 'fill',
                  onTap: () => _playNow(jam, song),
                ),
                const SizedBox(width: 6),
                SidifyIconButton(
                  icon: Icons.playlist_add_rounded,
                  label: 'Add to queue',
                  tone: 'fill',
                  onTap: () => _requireControl(jam, () {
                    jam.addToQueue(<JamTrack>[JamTrack.fromSong(song)]);
                    showAppNotice('Added to the room queue.');
                  }),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),

        // -------------------------------------------------------------- up next
        SectionHeader(
          title: 'Up next',
          trailing: upcoming.isNotEmpty
              ? TextButton(
                  onPressed: () => _requireControl(jam, jam.clearQueue),
                  child: Text(
                    'Clear',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: t.brand,
                    ),
                  ),
                )
              : null,
        ),
        if (upcoming.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              'The queue is empty after this one — add what plays next.',
              style: TextStyle(fontSize: 13, color: t.text2),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              children: <Widget>[
                for (int i = 0; i < upcoming.length; i++)
                  TrackRow(
                    tracks: upcomingSongs,
                    index: i,
                    numbered: true,
                    onTap: () => _requireControl(jam, () {
                      jam.setTrack(
                        upcoming[i],
                        queueIndex: queueIndex + 1 + i,
                      );
                    }),
                    onRemove: () => _requireControl(
                      jam,
                      () => jam.removeFromQueue(upcoming[i].videoId),
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 12),

        // ---------------------------------------------------------------- people
        SectionHeader(
          title: 'In this room',
          subtitle:
              '${jam.members.length} OF ${jam.party?.maxMembers ?? 5}',
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SidifyGroup(
            children: <Widget>[
              for (final JamMember member in jam.members)
                _memberRow(context, jam, member),
            ],
          ),
        ),

        // -------------------------------------------------------------- settings
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: SidifyGroup(
            header: 'Room settings',
            children: <Widget>[
              SidifyGroupRow(
                icon: Icons.auto_awesome_rounded,
                title: 'AutoPlay',
                subtitle: 'Keep similar songs coming when the queue ends',
                trailing: SidifySwitch(
                  value: jam.autoplayEnabled,
                  onChanged: (bool v) =>
                      _requireControl(jam, () => jam.setAutoplay(v)),
                ),
              ),
              SidifyGroupRow(
                icon: Icons.lock_rounded,
                title: 'Only the host controls',
                subtitle: jam.isHost
                    ? 'Guests listen and chat'
                    : 'The host decides this',
                trailing: SidifySwitch(
                  value: jam.hostOnlyControl,
                  onChanged: (bool v) {
                    if (!jam.isHost) {
                      showAppNotice('Only the host can change this.');
                      return;
                    }
                    jam.setHostOnlyControl(v);
                  },
                ),
              ),
              SidifyGroupRow(
                icon: Icons.people_outline_rounded,
                title: 'Room size',
                subtitle: jam.isHost ? null : 'Set by the host',
                trailing: jam.isHost
                    ? _stepper(
                        t,
                        value: jam.party?.maxMembers ?? 5,
                        min: 2,
                        max: 10,
                        onChanged: (int v) => jam.setMaxMembers(v),
                      )
                    : Text(
                        '${jam.party?.maxMembers ?? 5}',
                        style: TextStyle(fontSize: 14, color: t.text2),
                      ),
              ),
              SidifyGroupRow(
                icon: Icons.logout_rounded,
                title: 'Leave room',
                subtitle: 'The music keeps playing on this phone',
                onTap: () async {
                  await jam.leave();
                  showAppNotice('You left the room.');
                },
              ),
              if (jam.isHost)
                SidifyGroupRow(
                  icon: Icons.stop_circle_outlined,
                  title: 'End room for everyone',
                  danger: true,
                  onTap: () async {
                    final bool ok = await _confirm(
                      'End the room?',
                      'Everyone in it will be let go and the code stops '
                          'working. Their music keeps playing on their own '
                          'phones.',
                      'End room',
                    );
                    if (ok) jam.endRoom();
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _memberRow(BuildContext context, JamService jam, JamMember member) {
    final SidifyTokens t = context.sidify;
    final bool isMe = member.memberId == (jam.you?.memberId ?? '');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: <Widget>[
          Opacity(
            opacity: member.connected ? 1 : 0.45,
            child: member.avatarUrl != null && member.avatarUrl!.isNotEmpty
                ? Artwork(url: member.avatarUrl!, size: 38, round: true)
                : Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: t.brand.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      member.initials,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: t.brand,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Flexible(
                      child: Text(
                        member.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: t.text),
                      ),
                    ),
                    if (member.isHost) ...<Widget>[
                      const SizedBox(width: 6),
                      Icon(
                        Icons.workspace_premium_rounded,
                        size: 15,
                        color: t.brand,
                      ),
                    ],
                    if (isMe) ...<Widget>[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: t.fill2,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          'You',
                          style: TextStyle(fontSize: 10.5, color: t.text2),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  member.connected
                      ? (member.isHost ? 'Host' : 'Listening')
                      : 'Away — seat held for a little while',
                  style: TextStyle(fontSize: 12.5, color: t.text2),
                ),
              ],
            ),
          ),
          if (jam.isHost && !isMe)
            IconButton(
              tooltip: 'Remove from room',
              icon: Icon(Icons.person_remove_rounded,
                  size: 19, color: t.danger),
              onPressed: () async {
                final bool ok = await _confirm(
                  'Remove ${member.displayName}?',
                  'They can rejoin with the code if you share it again.',
                  'Remove',
                );
                if (ok) jam.kick(member.memberId);
              },
            ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ small pieces

  Widget _statusChip(SidifyTokens t, JamService jam) {
    final (Color color, String label) = switch (jam.state) {
      JamConnectionState.connected => (
          t.playing,
          jam.roundTripMs != null
              ? 'Synced · ${jam.roundTripMs} ms'
              : 'Synced',
        ),
      JamConnectionState.reconnecting => (t.danger, 'Reconnecting…'),
      _ => (t.text3, 'Connecting…'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: t.fill,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.edge, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: t.text2,
            ),
          ),
        ],
      ),
    );
  }

  /// Shown while the (free, sleepy) room server is being woken up, so a
  /// long first connect reads as "working on it" instead of a hang.
  Widget _wakingHint(JamService jam) {
    final SidifyTokens t = context.sidify;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: t.brand,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Waking up the room server… the first visit after a '
              'quiet spell can take a minute. Hang tight — it keeps '
              'trying on its own.',
              style: TextStyle(fontSize: 12.5, height: 1.4, color: t.text2),
            ),
          ),
          // The wait is open-ended by design, so the way out is a tap.
          if (jam.state == JamConnectionState.joining)
            TextButton(
              onPressed: jam.cancelOpen,
              child: Text('Cancel', style: TextStyle(color: t.text2)),
            ),
        ],
      ),
    );
  }

  Widget _errorBanner(String message, VoidCallback onDismiss) {
    final SidifyTokens t = context.sidify;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: BoxDecoration(
          color: t.danger.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.danger.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.error_outline_rounded, size: 17, color: t.danger),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: TextStyle(fontSize: 13, height: 1.4, color: t.text),
              ),
            ),
            IconButton(
              tooltip: 'Dismiss',
              icon: Icon(Icons.close_rounded, size: 16, color: t.text2),
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(SidifyTokens t, {required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: t.raised,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.edge, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _stepper(
    SidifyTokens t, {
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        SidifyIconButton(
          icon: Icons.remove_rounded,
          label: 'Fewer',
          size: 30,
          tone: 'fill',
          onTap: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(
          width: 30,
          child: Center(
            child: Text(
              '$value',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: t.text,
              ),
            ),
          ),
        ),
        SidifyIconButton(
          icon: Icons.add_rounded,
          label: 'More',
          size: 30,
          tone: 'fill',
          onTap: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
    );
  }

  String _initials(String name) {
    final List<String> parts = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final String p = parts.first;
      return p.substring(0, p.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  String _ago(int ms) {
    final int diff = DateTime.now().millisecondsSinceEpoch - ms;
    if (diff < 60000) return 'just now';
    if (diff < 3600000) return '${diff ~/ 60000}m ago';
    if (diff < 86400000) return '${diff ~/ 3600000}h ago';
    return '${diff ~/ 86400000}d ago';
  }

  String _clock(Duration d) {
    final int total = d.inSeconds < 0 ? 0 : d.inSeconds;
    final int m = total ~/ 60;
    final int s = total % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
