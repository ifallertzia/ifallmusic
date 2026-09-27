import 'package:flutter/material.dart';

final appMessengerKey = GlobalKey<ScaffoldMessengerState>();
void showAppNotice(String message) {
  appMessengerKey.currentState
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        duration: const Duration(seconds: 2),
      ),
    );
}
