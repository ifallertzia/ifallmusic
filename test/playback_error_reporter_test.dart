import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/config/branding.dart';
import 'package:ifallmusic/core/models/song.dart';
import 'package:ifallmusic/core/services/playback_error_reporter.dart';

void main() {
  test(
    'email draft contains causes, never stream credentials or local paths',
    () {
      final report = PlaybackErrorReport(
        song: const Song(
          id: 'aaaaaaaaaaa',
          title: 'Song & Title',
          artist: 'Artist',
          thumbnailUrl: '',
        ),
        error: StateError(
          '403 https://stream.example/play?token=SECRET /data/user/0/private.mp3 authorization=SECRET',
        ),
        stack: StackTrace.fromString(
          'PlaybackService.start (package:ifallmusic/playback.dart:10:2)',
        ),
        stage: 'load source',
        queueIndex: 2,
        queueLength: 8,
      );
      expect(report.body, contains('403'));
      expect(report.body, contains('StateError'));
      expect(report.body, isNot(contains('SECRET')));
      expect(report.body, isNot(contains('/data/user')));
      expect(report.mailUri.path, IfallBranding.contactEmail);
      expect(report.mailUri.queryParameters['body'], report.body);
      expect(report.body, contains('Queue position: 3 / 8'));
    },
  );
  test('diagnostic bodies are bounded', () {
    final report = PlaybackErrorReport(
      song: const Song(
        id: 'aaaaaaaaaaa',
        title: '',
        artist: '',
        thumbnailUrl: '',
      ),
      error: Exception('x' * 20000),
      stack: StackTrace.empty,
      stage: 'load',
      queueIndex: 0,
      queueLength: 1,
    );
    expect(report.body.length, lessThanOrEqualTo(7000));
  });
}
