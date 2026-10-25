import 'dart:math';

/// Small id helpers shared by identity, chat and invites.
///
/// The install id and every chat message need a UUIDv4-shaped string, and
/// the party server validates exactly that shape — so it is built once,
/// here, from a secure random source rather than pulled in as a package.
String newUuid([Random? random]) {
  final Random rng = random ?? Random.secure();
  final List<int> bytes = List<int>.generate(16, (_) => rng.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  String hex(int from, int to) => bytes
      .sublist(from, to)
      .map((int b) => b.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
