import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/listen_together_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/sidify_theme.dart';

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
/// Chat lives only as long as the room does — nothing is stored on a
/// server or on this phone.
class RoomChatPanel extends StatefulWidget {
  const RoomChatPanel({super.key, required this.height});

  final double height;

  @override
  State<RoomChatPanel> createState() => _RoomChatPanelState();
}

class _RoomChatPanelState extends State<RoomChatPanel> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _input = TextEditingController();
  int _seenCount = 0;
  bool _hasNew = false;
  bool _canSend = false;

  static const List<String> _emoji = <String>[
    '❤️', '🔥', '😂', '😮', '👍', '🎵', '👏', '😍',
  ];

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

  void _send(JamService jam) {
    final String text = _input.text.trim();
    if (text.isEmpty) return;
    if (jam.sendChat(text)) {
      _input.clear();
      setState(() => _canSend = false);
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
                                'Say hello 👋\nMessages live only while this room does.',
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
                              return _ChatBubble(
                                message: m,
                                mine: isMine(m),
                                onRetry: m.failed
                                    ? () => jam.resendChat(m)
                                    : null,
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
          const SizedBox(height: 8),
          SizedBox(
            height: 34,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: <Widget>[
                for (final String e in _emoji)
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
                          ? 'Message the room…'
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

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({
    required this.message,
    required this.mine,
    this.onRetry,
  });

  final JamChatMessage message;
  final bool mine;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final SidifyTokens t = context.sidify;
    final Color bg = mine ? t.brand : t.fill2;
    final Color fg = mine ? Colors.white : t.text;
    final Widget bubble = Opacity(
      opacity: message.pending ? 0.65 : 1,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
          children: <Widget>[
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  message.by,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: t.brand,
                  ),
                ),
              ),
            Text(
              message.text,
              style: TextStyle(fontSize: 14.5, height: 1.35, color: fg),
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
        child: onRetry == null
            ? bubble
            : GestureDetector(onTap: onRetry, child: bubble),
      ),
    );
  }
}
