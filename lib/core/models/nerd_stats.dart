import 'dart:io';

/// What the engine is actually doing for the track that is playing.
///
/// Shown by the "Stats for nerds" sheet on the player. Every field is read
/// back from the player or the resolver rather than inferred from the quality
/// label, so a track that failed over to the legacy resolver says so.
class NerdStats {
  const NerdStats({
    required this.videoId,
    required this.title,
    required this.source,
    required this.container,
    required this.speed,
    required this.volume,
    required this.normalized,
    required this.crossfadeSeconds,
    required this.automix,
    required this.skipSilence,
    required this.resolver,
    required this.position,
    required this.duration,
    this.bitrateKbps,
    this.sampleRateHz,
    this.bitsPerSample,
    this.channels = 2,
    this.sessionId,
  });

  final String videoId;
  final String title;

  /// Human-readable name of the resolver that produced the stream.
  final String source;

  /// `m4a`, `webm`, `ogg`, `flac` … or `—` before the first resolve.
  final String container;

  final int? bitrateKbps;
  final int? sampleRateHz;
  final int? bitsPerSample;
  final int channels;

  final double speed;
  final double volume;
  final bool normalized;
  final int crossfadeSeconds;
  final bool automix;
  final bool skipSilence;
  final String resolver;

  final Duration position;
  final Duration duration;

  /// The Android audio session id, when the platform exposes one. It is what
  /// the system equalizer attaches to.
  final int? sessionId;

  /// `44.1 kHz · 16-bit · Stereo` style summary for the container line.
  String get formatLine {
    final List<String> parts = <String>[];
    if (sampleRateHz != null) {
      parts.add('${(sampleRateHz! / 1000).toStringAsFixed(1)} kHz');
    }
    if (bitsPerSample != null) parts.add('${bitsPerSample}-bit');
    parts.add(channels >= 2 ? 'Stereo' : 'Mono');
    return parts.join(' · ');
  }

  /// Where the playhead is, and how far through the track that is.
  String get progressLine {
    if (duration.inMilliseconds <= 0) return '--:-- / --:--';
    final double pct =
        (position.inMilliseconds / duration.inMilliseconds * 100).clamp(0, 100);
    return '${_clock(position)} / ${_clock(duration)} (${pct.toStringAsFixed(0)}%)';
  }

  String get bufferLine =>
      '$container${bitrateKbps != null ? ' · ${bitrateKbps} kbps' : ''}';

  /// `Platform.operatingSystem` plus the first two dotted parts of the version.
  String get platformLine =>
      '${Platform.operatingSystem} · ${Platform.operatingSystemVersion.split('.').take(2).join('.')}';

  static String _clock(Duration d) {
    final int minutes = d.inMinutes.remainder(60);
    final int seconds = d.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}
