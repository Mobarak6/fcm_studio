import 'dart:math';

/// Creates a new unique id. Injected so tests get predictable ids.
typedef IdGenerator = String Function();

final Random _random = Random.secure();

/// A random version 4 UUID, e.g. `3f2b8c1e-9d4a-4f6b-8e2a-1c3d5e7f9a0b`.
String newUuid() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
