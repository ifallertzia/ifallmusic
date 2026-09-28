/// Small formatting helpers shared by the UI.
class Fmt {
  const Fmt._();

  /// `4:33` / `1:02:07` — matches the web player.
  static String duration(Duration? d) {
    if (d == null) return '--:--';
    final int h = d.inHours;
    final int m = d.inMinutes.remainder(60);
    final int s = d.inSeconds.remainder(60);
    final String ss = s.toString().padLeft(2, '0');
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:$ss';
    return '$m:$ss';
  }

  static String clock(Duration d) => duration(d);

  static String bytes(int value) {
    if (value < 1024) return '$value B';
    final double kb = value / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
    final double mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    final double gb = mb / 1024;
    return '${gb.toStringAsFixed(gb >= 10 ? 0 : 1)} GB';
  }

  /// `1.2M subscribers`
  static String count(int? value) {
    if (value == null || value <= 0) return '';
    if (value >= 1000000) {
      final double v = value / 1000000;
      return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}M';
    }
    if (value >= 1000) {
      final double v = value / 1000;
      return '${v.toStringAsFixed(v >= 10 ? 0 : 1)}K';
    }
    return '$value';
  }

  /// `Good morning` / `Good afternoon` / `Good evening` — the site greets you by
  /// time of day.
  static String greeting([DateTime? now]) {
    final int h = (now ?? DateTime.now()).hour;
    if (h < 5) return 'Still up';
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    if (h < 21) return 'Good evening';
    return 'Good night';
  }

  static String date(DateTime d) {
    const List<String> months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  /// `2 min ago`, `3 h ago`, `Yesterday`, `12 Sep`
  static String relative(DateTime d, [DateTime? now]) {
    final DateTime ref = now ?? DateTime.now();
    final Duration diff = ref.difference(d);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24 && d.day == ref.day) return '${diff.inHours} h ago';
    if (d.year == ref.year && d.month == ref.month && d.day == ref.day - 1) {
      return 'Yesterday';
    }
    return date(d);
  }
}
