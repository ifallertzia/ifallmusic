/// Which catalog a movie / series result came from.
///
/// Sidify Movies ships two catalogs at once:
///
/// * [eonMovies] — the original EonMovies catalog (normal rows),
/// * [hdhub4u]   — the second catalog, badged *IMAX HD* wherever both catalogs
///   are shown together. Its source name is internal only and is never shown
///   to a person: every visible label says "IMAX HD".
///
/// The provider travels with every model object — post, detail, quality link,
/// episode group and download item — so a link is always resolved by the
/// service that produced it.
enum MovieProvider {
  eonMovies(id: 'eon', label: 'EonMovies', premium: false),
  hdhub4u(id: 'hdhub', label: 'IMAX HD', premium: true);

  const MovieProvider({
    required this.id,
    required this.label,
    required this.premium,
  });

  /// Stable short id — persisted in download records, never renamed.
  final String id;

  /// Human readable catalog name. Never the source site's own name.
  final String label;

  /// Premium catalogs get a badge under their card when both catalogs are
  /// listed side by side in search results.
  final bool premium;

  /// The words shown on the badge for [premium] rows.
  String get badgeLabel => 'IMAX HD';

  static MovieProvider fromId(Object? value) {
    final String raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return MovieProvider.eonMovies;
    for (final MovieProvider provider in MovieProvider.values) {
      if (provider.id == raw || provider.name == raw) return provider;
    }
    return MovieProvider.eonMovies;
  }
}
