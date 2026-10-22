/// Runs one player seek while making sure its recovery watchdog is already
/// active before the native seek starts.
///
/// media_kit's native seek waits for libmpv's asynchronous command reply. A
/// stream that does not handle a seek can leave that reply pending, so arming
/// the watchdog only after `await player.seek(...)` can leave playback running
/// at the old position forever with no recovery attempt.
Future<void> runMovieSeekWithWatchdog({
  required Duration target,
  required Future<void> Function(Duration target) seek,
  required void Function(Duration target) armWatchdog,
  required void Function(Duration target) onError,
}) async {
  armWatchdog(target);
  try {
    await seek(target);
  } catch (_) {
    onError(target);
  }
}
