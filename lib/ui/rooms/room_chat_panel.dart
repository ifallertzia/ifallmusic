import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../core/services/listen_together_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/sidify_theme.dart';

/// The emoji offered by the long-press reaction bar. The server only lets
/// these through, so a message can never be filled with arbitrary strings.
const List<String> kRoomEmoji = <String>[
  '❤️', '🔥', '😂', '😮', '👍', '🎵', '👏', '😍',
];

/// One entry in the merged room feed: a chat message or an activity line.
class _FeedEntry {
  const _FeedEntry.chat(this.message) : activity = null;
  const _FeedEntry.activity(this.activity) : message = null;

  final JamChatMessage? message;
  final JamActivity? activity;

  int get atMs => message?.atMs ?? activity?.atMs ?? 0;
}

/// The room's conversation: chat bubbles with the "Alice skipped" activity
/// lines woven between them, exactly like the website's rooms.
///
/// Hold a bubble (or slide it a little) to reply; hold without sliding for
/// the emoji / edit / copy menu. Your own bubbles carry a single tick until
/// somebody else in the room has read them, then two green ticks.
///
/// Chat lives only as long as the room does — nothing is stored on a
/// server or on this phone.
class RoomChatPanel extends StatefulWidget {
  const RoomChatPanel({
    super.key,
    required this.height,
    this.onClose,
  });

  final double height;

  /// When the panel is shown as a popup, this closes it.
  final VoidCallback? onClose;

  @override
  State<RoomChatPanel> createState() => _RoomChatPanelState();
}

class _RoomChatPanelState extends State<RoomChatPanel> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  int _seenCount = 0;
  int _lastReadSeq = 0;
  bool _hasNew = false;
  bool _canSend = false;
  JamChatMessage? _replyTo;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_nearBottom && _hasNew) {
        setState(() => _hasNew = false);
      }
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _input.dispose();
    super.dispose();
  }

  bool get _nearBottom =>
      !_scroll.hasClients ||
      _scroll.position.maxScrollExtent - _scroll.position.pixels < 140;

  void _scrollToBottom({bool animated = true}) {
    if (!_scroll.hasClients) return;
    final double target = _scroll.position.maxScrollExtent;
    if (animated) {
      _scroll.animateTo(
        target,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    } else {
      _scroll.jumpTo(target);
    }
  }

  void _maybeFollow(int count, bool lastIsMine) {
    if (count <= _seenCount) {
      _seenCount = count;
      return;
    }
    final bool firstBuild = _seenCount == 0;
    _seenCount = count;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (firstBuild || lastIsMine || _nearBottom) {
        _scrollToBottom(animated: !firstBuild);
        if (_hasNew) setState(() => _hasNew = false);
      } else if (!_hasNew) {
        setState(() => _hasNew = true);
      }
    });
  }

  /// A visible chat panel is a read receipt. One frame per new highest
  /// sequence is enough; the server rebroadcasts it to everyone else.
  void _markRead(JamService jam) {
    if (!jam.isConnected) return;
    int maxSeq = 0;
    for (final JamChatMessage m in jam.chatMessages) {
      if (!m.pending && m.seq > maxSeq) maxSeq = m.seq;
    }
    if (maxSeq <= 0 || maxSeq == _lastReadSeq) return;
    _lastReadSeq = maxSeq;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) jam.markChatRead(maxSeq);
    });
  }

  void _send(JamService jam) {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    if (jam.sendChat(text, replyTo: _replyTo)) {
      _input.clear();
      setState(() {
        _canSend = false;
        _replyTo = null;
      });
    }
  }

  void _addEmoji(String emoji) {
    final String next = _input.text + emoji;
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    setState(() => _canSend = next.trim().isNotEmpty);
  }

  void _startReply(JamChatMessage message) {
    if (!mounted) return;
    setState(() => _replyTo = message);
  }

  Future<void> _editMessage(
    BuildContext context,
    JamService jam,
    JamChatMessage message,
  ) async {
    final TextEditingController controller =
        TextEditingController(text: message.text);
    final SidifyTokens t = context.sidify;
    final String? edited = await showDialog<String>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        backgroundColor: t.raised,
        title: Text('Edit message', style: TextStyle(color: t.text)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          maxLength: JamService.maxChatRunes,
          style: TextStyle(color: t.text),
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Cancel', style: TextStyle(color: t.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: Text(
              'Save',
              style: TextStyle(color: t.brand, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
    controller.dispose();
    if (edited != null && edited.trim().isNotEmpty) {
      jam.editChat(message, edited);
    }
  }

  /// Long-press menu: emoji reactions at the top, then reply / edit / copy.
  Future<void> _openActions(
    BuildContext context,
    JamService jam,
    JamChatMessage message,
    bool mine,
  ) async {
    final SidifyTokens t = context.sidify;
    await showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: t.raised,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                'React to message',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: t.text2,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 6,
                children: <Widget>[
                  for (final String e in kRoomEmoji)
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        jam.toggleReaction(message, e);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(7),
                        child: Text(e, style: const TextStyle(fontSize: 24)),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Divider(color: t.edge, height: 1),
              ListTile(
                leading: Icon(Icons.reply_rounded, color: t.text),
                title: Text('Reply', style: TextStyle(color: t.text)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _startReply(message);
                },
              ),
              if (mine)
                ListTile(
                  leading: Icon(Icons.edit_rounded, color: t.text),
                  title: Text('Edit message', style: TextStyle(color: t.text)),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    unawaited(_editMessage(context, jam, message));
                  },
                ),
              ListTile(
                leading: Icon(Icons.copy_rounded, color: t.text),
                title: Text('Copy text', style: TextStyle(color: t.text)),
                onTap: () async {
                  Navigator.of(ctx).pop();
                  await Clipboard.setData(ClipboardData(text: message.text));
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final JamService jam = context.watch<JamService>();
    final SettingsService settings = context.watch<SettingsService>();
    final String selfUserId = settings.installId;
    final String selfMemberId = jam.you?.memberId ?? '';

    bool isMine(JamChatMessage m) =>
        (m.userId.isNotEmpty && m.userId == selfUserId) ||
        (m.memberId.isNotEmpty && m.memberId == selfMemberId);

    final List<_FeedEntry> feed = <_FeedEntry>[
      for (final JamChatMessage m in jam.chatMessages) _FeedEntry.chat(m),
      for (final JamActivity a in jam.activities) _FeedEntry.activity(a),
    ]..sort((_FeedEntry a, _FeedEntry b) => a.atMs.compareTo(b.atMs));
    final bool lastIsMine =
        feed.isNotEmpty && feed.last.message != null && isMine(feed.last.message!);
    _maybeFollow(feed.length, lastIsMine);
    _markRead(jam);

    return SizedBox(
      height: widget.height,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 8),
            child: Row(
              children: <Widget>[
                Icon(Icons.chat_bubble_outline_rounded, size: 16, color: t.text2),
                const SizedBox(width: 6),
                Text(
                  'Chat',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: t.text,
                  ),
                ),
                const Spacer(),
                Text(
                  '${jam.members.length} listening',
                  style: TextStyle(fontSize: 12, color: t.text2),
                ),
                if (widget.onClose != null)
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: widget.onClose,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Icon(Icons.close_rounded, size: 18, color: t.text2),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: t.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: t.edge, width: 0.5),
                    ),
                    child: feed.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'Say hello 👋\nHold a message to react, edit or copy. '
                                'Slide it a little to reply.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  color: t.text2,
                                ),
                              ),
                            ),
                          )
                        : ListView.builder(
                            controller: _scroll,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            itemCount: feed.length,
                            itemBuilder: (BuildContext context, int i) {
                              final _FeedEntry entry = feed[i];
                              if (entry.activity != null) {
                                return _ActivityLine(activity: entry.activity!);
                              }
                              final JamChatMessage m = entry.message!;
                              final bool mine = isMine(m);
                              return _ChatBubble(
                                message: m,
                                mine: mine,
                                selfMemberId: selfMemberId,
                                read: jam.isReadByOthers(m),
                                onRetry: m.failed
                                    ? () => jam.resendChat(m)
                                    : null,
                                onReply: () => _startReply(m),
                                onHold: () => unawaited(
                                  _openActions(context, jam, m, mine),
                                ),
                                onReact: (String emoji) =>
                                    jam.toggleReaction(m, emoji),
                              );
                            },
                          ),
                  ),
                ),
                if (_hasNew)
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Material(
                        color: t.brand,
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () {
                            _scrollToBottom();
                            setState(() => _hasNew = false);
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 6,
                            ),
                            child: Text(
                              'New messages ↓',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_replyTo != null) _replyPreview(t),
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (final String e in kRoomEmoji)
                  InkWell(
                    borderRadius: BorderRadius.circular(999),
                    onTap: () => _addEmoji(e),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      child: Text(e, style: const TextStyle(fontSize: 18)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Container(
            decoration: BoxDecoration(
              color: t.fill,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: t.edge, width: 0.5),
            ),
            child: Row(
              children: <Widget>[
                const SizedBox(width: 16),
                Expanded(
                  child: TextField(
                    controller: _input,
                    enabled: jam.isConnected,
                    maxLength: JamService.maxChatRunes,
                    textInputAction: TextInputAction.send,
                    onChanged: (String v) =>
                        setState(() => _canSend = v.trim().isNotEmpty),
                    onSubmitted: (_) => _send(jam),
                    style: TextStyle(fontSize: 15, color: t.text),
                    decoration: InputDecoration(
                      hintText: jam.isConnected
                          ? (_replyTo == null
                              ? 'Message the room…'
                              : 'Reply to ${_replyTo!.by}…')
                          : 'Reconnecting…',
                      hintStyle: TextStyle(color: t.text2),
                      border: InputBorder.none,
                      isDense: true,
                      counterText: '',
                      contentPadding:
                          const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Material(
                    color: _canSend && jam.isConnected
                        ? t.brand
                        : t.fill2,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _canSend && jam.isConnected
                          ? () => _send(jam)
                          : null,
                      child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          size: 18,
                          color: _canSend && jam.isConnected
                              ? Colors.white
                              : t.text3,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _replyPreview(SidifyTokens t) {
    final JamChatMessage reply = _replyTo!;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: t.fill,
          borderRadius: BorderRadius.circular(10),
          border: Border(left: BorderSide(color: t.brand, width: 2)),
        ),
        child: Row(
          children: <Widget>[
            Icon(Icons.reply_rounded, size: 16, color: t.brand),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'Replying to ${reply.by}',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: t.brand,
                    ),
                  ),
                  Text(
                    reply.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: t.text2),
                  ),
                ],
              ),
            ),
            InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => setState(() => _replyTo = null),
              child: Icon(Icons.close_rounded, size: 16, color: t.text2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens the room chat as a big popup anchored near the top of the screen.
/// The red launcher uses this from every section of the app.
class RoomChatPopup {
  RoomChatPopup._();

  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      insetPadding: const EdgeInsets.fromLTRB(12, 24, 12, 24),
      builder: (BuildContext ctx) {
        final SidifyTokens t = ctx.sidify;
        // Leave space for the status bar, the dialog padding and the
        // keyboard, so the panel never overflows on a small phone.
        final double screen = MediaQuery.sizeOf(ctx).height;
        final double keyboard = MediaQuery.viewInsetsOf(ctx).bottom;
        final double top = MediaQuery.paddingOf(ctx).top;
        final double available = screen - keyboard - top - 76;
        final double panelHeight = (available * 0.9).clamp(280.0, 620.0);
        return Align(
          alignment: Alignment.topCenter,
          child: Material(
            color: t.surface,
            borderRadius: BorderRadius.circular(20),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: RoomChatPanel(
                height: panelHeight,
                onClose: () => Navigator.of(ctx).pop(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ActivityLine extends StatelessWidget {
  const _ActivityLine({required this.activity});

  final JamActivity activity;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: t.fill,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            activity.detail,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: t.text2),
          ),
        ),
      ),
    );
  }
}

/// Hold a bubble for the reaction menu, or slide it sideways to reply.
///
/// A raw pointer listener (rather than a gesture recognizer) is used on
/// purpose: the chat list must keep scrolling vertically while a horizontal
/// drag becomes a reply, and a long press must still open the menu. A
/// recognizer in the gesture arena would win one of those at the expense
/// of the others.
class _SwipeReply extends StatefulWidget {
  const _SwipeReply({
    required this.child,
    required this.onReply,
    required this.onHold,
    required this.color,
  });

  final Widget child;
  final VoidCallback onReply;
  final VoidCallback onHold;
  final Color color;

  @override
  State<_SwipeReply> createState() => _SwipeReplyState();
}

class _SwipeReplyState extends State<_SwipeReply> {
  Timer? _hold;
  bool _holdFired = false;
  bool _dragging = false;
  bool _done = false;
  double _dx = 0;
  Offset _start = Offset.zero;

  void _onDown(PointerDownEvent event) {
    _start = event.position;
    _dx = 0;
    _dragging = false;
    _holdFired = false;
    _done = false;
    _hold?.cancel();
    _hold = Timer(const Duration(milliseconds: 500), () {
      if (!mounted || _done) return;
      _holdFired = true;
      widget.onHold();
    });
    setState(() {});
  }

  void _onMove(PointerMoveEvent event) {
    if (_holdFired || _done) return;
    final double dx = event.position.dx - _start.dx;
    final double dy = event.position.dy - _start.dy;
    if (dy.abs() > 12 && dy.abs() > dx.abs()) {
      // A vertical scroll: never open a menu halfway through it.
      _hold?.cancel();
      _holdFired = true;
      return;
    }
    if (dx.abs() < 6 || dx.abs() < dy.abs() * 1.2) return;
    _hold?.cancel();
    _dragging = true;
    setState(() => _dx = dx.clamp(0.0, 64.0));
  }

  void _onUp(PointerUpEvent event) {
    _hold?.cancel();
    final bool reply = _dragging && _dx >= 26;
    _reset();
    if (reply) widget.onReply();
  }

  void _onCancel(PointerCancelEvent event) {
    _hold?.cancel();
    _reset();
  }

  void _reset() {
    _done = true;
    _dragging = false;
    _holdFired = false;
    _dx = 0;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _hold?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _onDown,
        onPointerMove: _onMove,
        onPointerUp: _onUp,
        onPointerCancel: _onCancel,
        child: Stack(
          children: <Widget>[
            if (_dx > 2)
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Icon(
                    _dx >= 26 ? Icons.reply_rounded : Icons.reply_outlined,
                    size: 18,
                    color: widget.color,
                  ),
                ),
              ),
            Transform.translate(
              offset: Offset(_dx, 0),
              child: widget.child,
            ),
          ],
        ),
      );
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.mine,
    required this.selfMemberId,
    required this.read,
    required this.onReply,
    required this.onHold,
    required this.onReact,
    this.onRetry,
  });

  final JamChatMessage message;
  final bool mine;
  final String selfMemberId;
  final bool read;
  final VoidCallback onReply;
  final VoidCallback onHold;
  final ValueChanged<String> onReact;
  final VoidCallback? onRetry;

  String get _time {
    if (message.atMs <= 0) return '';
    final DateTime at = DateTime.fromMillisecondsSinceEpoch(message.atMs);
    final String h = at.hour.toString().padLeft(2, '0');
    final String m = at.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final Color bg = mine ? t.brand : t.fill2;
    final Color fg = mine ? Colors.white : t.text;
    final Color faint = mine ? Colors.white70 : t.text3;
    final Widget bubble = Opacity(
      opacity: message.pending ? 0.65 : 1,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: message.failed
              ? Border.all(color: t.danger, width: 1)
              : null,
        ),
        child: Column(
          crossAxisAlignment:
              mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  message.by,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: t.brand,
                  ),
                ),
              ),
            if (message.replyTo != null) _quoted(context),
            Text(
              message.text,
              style: TextStyle(fontSize: 15, height: 1.35, color: fg),
            ),
            if (message.reactions.isNotEmpty) _chips(context),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (_time.isNotEmpty)
                  Text(_time, style: TextStyle(fontSize: 10, color: faint)),
                if (message.editedAtMs > 0) ...<Widget>[
                  const SizedBox(width: 4),
                  Text('· edited', style: TextStyle(fontSize: 10, color: faint)),
                ],
                if (mine) ...<Widget>[
                  const SizedBox(width: 4),
                  _ticks(t, faint),
                ],
              ],
            ),
            if (message.pending || message.failed)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(
                  message.failed ? 'Not sent — tap to retry' : 'Sending…',
                  style: TextStyle(
                    fontSize: 10.5,
                    color: message.failed
                        ? t.danger
                        : (mine ? Colors.white70 : t.text3),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: _SwipeReply(
          color: mine ? Colors.white70 : t.brand,
          onReply: onReply,
          onHold: onHold,
          child: onRetry == null
              ? bubble
              : GestureDetector(onTap: onRetry, child: bubble),
        ),
      ),
    );
  }

  Widget _quoted(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final JamReply reply = message.replyTo!;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 7),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: mine ? Colors.white.withValues(alpha: 0.16) : t.fill,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: mine ? Colors.white : t.brand,
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            reply.by,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: mine ? Colors.white : t.brand,
            ),
          ),
          Text(
            reply.text.isEmpty ? 'Message' : reply.text,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: mine ? Colors.white70 : t.text2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chips(BuildContext context) {
    final SidifyTokens t = context.sidify;
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Wrap(
        spacing: 5,
        runSpacing: 4,
        children: <Widget>[
          for (final MapEntry<String, List<String>> entry
              in message.reactions.entries)
            if (entry.value.isNotEmpty)
              GestureDetector(
                onTap: () => onReact(entry.key),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: mine ? Colors.white24 : t.fill,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: entry.key.isNotEmpty &&
                              message.reactedBy(entry.key, selfMemberId)
                          ? t.brand
                          : Colors.transparent,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(entry.key, style: const TextStyle(fontSize: 12)),
                      if (entry.value.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(left: 3),
                          child: Text(
                            '${entry.value.length}',
                            style: TextStyle(fontSize: 11, color: t.text2),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }

  Widget _ticks(SidifyTokens t, Color faint) {
    if (message.failed) {
      return Icon(Icons.error_outline_rounded, size: 13, color: t.danger);
    }
    if (message.pending) {
      return Icon(Icons.schedule_rounded, size: 13, color: faint);
    }
    return Icon(
      read ? Icons.done_all_rounded : Icons.check_rounded,
      size: 15,
      color: read ? const Color(0xFF34C759) : faint,
    );
  }
}
