import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifallmusic/movies/services/movie_seek_runner.dart';

void main() {
  test('watchdog starts before a native seek that stays pending', () async {
    final Completer<void> nativeReply = Completer<void>();
    final List<String> events = <String>[];
    const Duration target = Duration(minutes: 42);

    final Future<void> running = runMovieSeekWithWatchdog(
      target: target,
      armWatchdog: (Duration value) {
        expect(value, target);
        events.add('watchdog');
      },
      seek: (Duration value) {
        expect(value, target);
        events.add('seek');
        return nativeReply.future;
      },
      onError: (_) => fail('a pending seek has not failed'),
    );

    // The native reply is still pending, but recovery is already armed.
    expect(events, <String>['watchdog', 'seek']);

    nativeReply.complete();
    await running;
  });

  test('a rejected native seek reaches the error handler', () async {
    const Duration target = Duration(minutes: 12);
    final List<String> events = <String>[];

    await runMovieSeekWithWatchdog(
      target: target,
      armWatchdog: (_) => events.add('watchdog'),
      seek: (_) async => throw StateError('seek rejected'),
      onError: (Duration value) {
        expect(value, target);
        events.add('error');
      },
    );

    expect(events, <String>['watchdog', 'error']);
  });
}
