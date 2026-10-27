import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/services/listen_together_service.dart';
import '../../core/services/settings_service.dart';
import '../../core/theme/sidify_theme.dart';
import 'room_chat_panel.dart';

/// The red room-chat button. It is painted in the app's root stack, above
/// the navigator, so once a room is joined it is reachable from EVERY
/// section — Home, Explore, Search, Library, the room itself, pushed pages
/// and Movies — instead of only from the Listen Together tab.
///
/// Pushing it opens the chat as a popup at the top of the screen. While a
/// dialog or the full player covers the screen the launcher steps aside,
/// exactly like the glass dock.
class RoomChatLauncher extends StatelessWidget {
  const RoomChatLauncher({
    super.key,
    required this.hidden,
    required this.navigatorKey,
  });

  /// True while a popup / full player is on top (from the route observer).
  final bool hidden;

  /// The launcher is painted ABOVE the navigator, so it cannot find one by
  /// walking up its own context. The overlay context (below the navigator)
  /// is where a dialog can be pushed from.
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    final SettingsService settings = context.watch<SettingsService>();
    final JamService jam = context.watch<JamService>();
    if (hidden || settings.displayName.isEmpty || !jam.inRoom) {
      return const SizedBox.shrink();
    }
    final SidifyTokens t = context.sidify;
    final double safe = MediaQuery.paddingOf(context).bottom;
    return Positioned(
      right: 18,
      // Sits above the dock: the tab bar (~62px) plus the mini player row.
      bottom: safe + 168,
      child: Semantics(
        label: 'Open room chat',
        button: true,
        child: Material(
          color: t.brand,
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: Colors.black54,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () {
              final BuildContext? dialogContext =
                  navigatorKey.currentState?.overlay?.context;
              if (dialogContext == null || !dialogContext.mounted) return;
              unawaited(RoomChatPopup.show(dialogContext));
            },
            child: SizedBox(
              width: 54,
              height: 54,
              child: Stack(
                alignment: Alignment.center,
                children: <Widget>[
                  const Icon(
                    Icons.chat_bubble_rounded,
                    size: 25,
                    color: Colors.white,
                  ),
                  Positioned(
                    right: 11,
                    top: 11,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: jam.isConnected
                            ? const Color(0xFF34C759)
                            : Colors.white70,
                        shape: BoxShape.circle,
                        border: Border.all(color: t.brand, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

