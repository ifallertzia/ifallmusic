import 'dart:async';

import 'package:flutter/material.dart';

/// The app's bottom ScaffoldMessenger — still used for notices that need an
/// action button (playback failures with MAIL ERROR, dialogs).
final appMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// One in-app notice: a short message the listener should see immediately.
class AppNotice {
  const AppNotice({
    required this.id,
    required this.message,
    required this.duration,
  });

  final int id;
  final String message;
  final Duration duration;
}

/// The live notice channel.
///
/// Notices are painted by [AppNoticeLayer] high in the widget tree — **above**
/// the floating mini player — so "Download failed", "Saved for offline
/// listening" and friends are always visible, on any page, instead of being
/// hidden behind the dock.
class AppNoticeController extends ChangeNotifier {
  AppNoticeController._();

  static final AppNoticeController instance = AppNoticeController._();

  AppNotice? _current;
  AppNotice? get current => _current;

  int _nextId = 0;
  Timer? _dismiss;

  void show(String message, {Duration duration = const Duration(seconds: 3)}) {
    final String text = message.trim();
    if (text.isEmpty) return;
    _dismiss?.cancel();
    _current = AppNotice(
      id: ++_nextId,
      message: text,
      duration: duration,
    );
    notifyListeners();
    _dismiss = Timer(duration, hide);
  }

  void hide() {
    _dismiss?.cancel();
    _dismiss = null;
    if (_current == null) return;
    _current = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _dismiss?.cancel();
    super.dispose();
  }
}

/// Shows a short notice at the bottom of the screen, above the mini player.
void showAppNotice(
  String message, {
  Duration duration = const Duration(seconds: 3),
}) => AppNoticeController.instance.show(message, duration: duration);

/// The floating notice pill. Anchored just above the mini player so it never
/// lands under the dock, and ignores pointers so it cannot swallow a tap.
class AppNoticeLayer extends StatelessWidget {
  const AppNoticeLayer({super.key, this.bottomPadding = 92});

  /// Clearance for the mini player + tab bar underneath.
  final double bottomPadding;

  @override
  Widget build(BuildContext context) {
    final double inset = MediaQuery.paddingOf(context).bottom;
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, inset + bottomPadding),
          child: ListenableBuilder(
            listenable: AppNoticeController.instance,
            builder: (BuildContext context, Widget? _) {
              final AppNotice? notice = AppNoticeController.instance.current;
              return AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (Widget child, Animation<double> anim) {
                  return FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.35),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  );
                },
                child: notice == null
                    ? const SizedBox.shrink(key: ValueKey<String>('no-notice'))
                    : _NoticePill(
                        key: ValueKey<int>(notice.id),
                        message: notice.message,
                      ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NoticePill extends StatelessWidget {
  const _NoticePill({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 11, 16, 11),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: const Color(0xFF101014).withValues(alpha: 0.94),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.55),
              blurRadius: 26,
              spreadRadius: -8,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.info_outline_rounded,
              size: 17,
              color: Colors.white70,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
