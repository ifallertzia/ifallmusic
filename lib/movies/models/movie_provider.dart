import 'package:flutter/foundation.dart';

/// Which catalog a movie / series result came from.
///
/// Sidify Movies ships two catalogs at once:
///
/// * [eonMovies] — the original EonMovies catalog (normal rows),
/// * [hdhub4u]   — the HDHub4U catalog (badged as *premium* wherever both
///   catalogs are shown together).
///
/// The provider travels with every model object — post, detail, quality link,
/// episode group and download item — so a link is always resolved by the
/// service that produced it.
@immutable
enum MovieProvider {
  eonMovies(id: 'eon', label: 'EonMovies', premium: false),
  hdhub4u(id: 'hdhub', label: 'HDHub4U', premium: true);

  const MovieProvider({
    required this.id,
    required this.label,
    required this.premium,
  });

  /// Stable short id — persisted in download records, never renamed.
  final String id;

  /// Human readable catalog name.
  final String label;

  /// Premium catalogs get a badge under their card when both catalogs are
  /// listed side by side in search results.
  final bool premium;

  /// The word shown on the badge for [premium] rows.
  String get badgeLabel => 'PREMIUM';

  static MovieProvider fromId(Object? value) {
    final String raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return MovieProvider.eonMovies;
    for (final MovieProvider provider in MovieProvider.values) {
      if (provider.id == raw || provider.name == raw) return provider;
    }
    return MovieProvider.eonMovies;
  }
}
