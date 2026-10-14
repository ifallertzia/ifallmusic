import '../../config/branding.dart';

/// Safe on-disk names: `{title}_saxify.mp3` / `.mp4`.
class Filenames {
  const Filenames._();

  static String saxify(String title, String extension) {
    final String ext = extension.replaceAll('.', '').toLowerCase();
    final String cleaned = title
        .replaceAll(RegExp(r'[\\/:*?"<>|\u0000]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final String base = cleaned.isEmpty ? 'track' : cleaned;
    final String clipped = base.length > 80 ? base.substring(0, 80).trim() : base;
    return '$clipped${SidifyBranding.fileSuffix}.$ext';
  }

  static bool looksCorrupt(List<int> head, int size) {
    if (size < 512) return true;
    if (head.isEmpty) return true;
    final String sniff = String.fromCharCodes(head.take(16));
    final String lower = sniff.toLowerCase();
    if (lower.startsWith('<!doctype') || lower.startsWith('<html')) return true;
    if (lower.startsWith('{') || lower.startsWith('[')) return true;
    return false;
  }
}
