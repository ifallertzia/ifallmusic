import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/branding.dart';
import '../models/song.dart';

String redactPlaybackDiagnostic(String input) => input
    .replaceAll(
      RegExp(r'https?://[^\s\)\]>]+', caseSensitive: false),
      '[URL redacted]',
    )
    .replaceAll(
      RegExp(r'(?:/data/|/storage/|/home/|/Users/)[^\s\)]+'),
      '[local path redacted]',
    )
    .replaceAll(
      RegExp(
        r'(authorization|cookie|token|signature|key)\s*[:=]\s*[^\s,;]+',
        caseSensitive: false,
      ),
      '[credential redacted]',
    );

class PlaybackErrorReport {
  PlaybackErrorReport({
    required Song song,
    required Object error,
    required StackTrace stack,
    required String stage,
    required int queueIndex,
    required int queueLength,
  }) : id = DateTime.now().microsecondsSinceEpoch.toString(),
       body = _body(song, error, stack, stage, queueIndex, queueLength);
  final String id, body;
  static String _body(
    Song song,
    Object error,
    StackTrace stack,
    String stage,
    int index,
    int length,
  ) {
    final details = redactPlaybackDiagnostic('''IfallMusic playback error
Time (UTC): ${DateTime.now().toUtc().toIso8601String()}
App: ${IfallBranding.versionLabel}
Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}
Stage: $stage
Track ID: ${song.id}
Title: ${song.title}
Artist: ${song.artist}
Source: ${song.source.name} / ${song.musicVideoType ?? 'unknown'}
Queue position: ${index + 1} / $length
Error type: ${error.runtimeType}
Cause / code: $error
Stack trace:
$stack

Sent voluntarily using “Mail this error to ifallertzia”.
No stream URLs, credentials, local file paths or listening history are attached.
''');
    return details.length <= 7000 ? details : details.substring(0, 7000);
  }

  Uri get mailUri => Uri(
    scheme: 'mailto',
    path: IfallBranding.contactEmail,
    query:
        'subject=${Uri.encodeComponent('IfallMusic playback error #$id')}&body=${Uri.encodeComponent(body)}',
  );
}

class PlaybackErrorReporter {
  static Future<void> remember(PlaybackErrorReport report) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Just the latest redacted report, on-device. Never transmit automatically.
      await prefs.setString(
        'ifall.lastPlaybackError',
        jsonEncode({'id': report.id, 'body': report.body}),
      );
    } catch (_) {
      /* Diagnostics must never interrupt recovery. */
    }
  }

  static Future<bool> compose(PlaybackErrorReport report) async {
    try {
      return await launchUrl(
        report.mailUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}
