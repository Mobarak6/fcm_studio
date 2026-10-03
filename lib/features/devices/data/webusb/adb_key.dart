import 'dart:convert';
import 'dart:typed_data';

/// The browser's adb key: signs the phone's challenge and introduces itself
/// in Android's public key format (design §4.5).
class AdbKey {
  AdbKey({
    required this.n,
    required this.e,
    required this.d,
    this.p,
    this.q,
    this.dp,
    this.dq,
    this.qi,
  });

  /// Reads a WebCrypto JWK export. Throws [FormatException] when a value is
  /// missing or the key is not 2048 bits.
  factory AdbKey.fromJwk(Map<String, Object?> jwk) {
    BigInt value(String name) {
      final text = jwk[name];
      if (text is! String || text.isEmpty) {
        throw FormatException('The adb key has no "$name".');
      }
      return _bigInt(base64Url.decode(base64Url.normalize(text)));
    }

    BigInt? optional(String name) => jwk[name] is String ? value(name) : null;

    final key = AdbKey(
      n: value('n'),
      e: value('e'),
      d: value('d'),
      p: optional('p'),
      q: optional('q'),
      dp: optional('dp'),
      dq: optional('dq'),
      qi: optional('qi'),
    );
    if (key.n.bitLength != modulusBits) {
      throw FormatException(
        'The adb key must be $modulusBits bits, not ${key.n.bitLength}.',
      );
    }
    return key;
  }

  static const modulusBits = 2048;
  static const _modulusBytes = modulusBits ~/ 8;

  /// DER prefix of a SHA-1 DigestInfo; adb's token is used as the digest.
  static const _sha1DigestInfo = [
    0x30, 0x21, 0x30, 0x09, 0x06, 0x05, 0x2B, 0x0E, 0x03, 0x02, 0x1A, 0x05,
    0x00, 0x04, 0x14, //
  ];

  final BigInt n;
  final BigInt e;
  final BigInt d;
  final BigInt? p;
  final BigInt? q;
  final BigInt? dp;
  final BigInt? dq;
  final BigInt? qi;

  /// RSA PKCS#1 v1.5 over a SHA-1 DigestInfo holding [token] as the digest,
  /// as adb's `RSA_sign(NID_sha1, …)` does. Returns 256 bytes.
  Uint8List sign(List<int> token) {
    if (token.length != 20) {
      throw ArgumentError.value(token.length, 'token', 'must be 20 bytes');
    }
    final t = [..._sha1DigestInfo, ...token];
    final block = Uint8List(_modulusBytes)..[1] = 0x01;
    block.fillRange(2, _modulusBytes - t.length - 1, 0xFF);
    block.setRange(_modulusBytes - t.length, _modulusBytes, t);
    return _bytes(_power(_bigInt(block)), _modulusBytes);
  }

  /// `m^d mod n`, with the Chinese remainder theorem when the JWK has the
  /// values for it (about 3 times faster in the browser).
  BigInt _power(BigInt m) {
    final (p, q, dp, dq, qi) = (this.p, this.q, this.dp, this.dq, this.qi);
    if (p == null || q == null || dp == null || dq == null || qi == null) {
      return m.modPow(d, n);
    }
    final m1 = m.modPow(dp, p);
    final m2 = m.modPow(dq, q);
    final h = (qi * (m1 - m2)) % p;
    return m2 + h * q;
  }

  /// Android's RSAPublicKey layout, all little-endian: the modulus size in
  /// 32-bit words, n0inv, the modulus, R² mod n, and the exponent.
  Uint8List androidPublicKey() {
    final r32 = BigInt.one << 32;
    final n0inv = (r32 - n.modInverse(r32)) % r32;
    final rr = (BigInt.one << (2 * modulusBits)) % n;
    final data = ByteData(4 + 4 + _modulusBytes * 2 + 4)
      ..setUint32(0, _modulusBytes ~/ 4, Endian.little)
      ..setUint32(4, n0inv.toInt(), Endian.little)
      ..setUint32(8 + _modulusBytes * 2, e.toInt(), Endian.little);
    return data.buffer.asUint8List()
      ..setRange(8, 8 + _modulusBytes, _bytes(n, _modulusBytes).reversed)
      ..setRange(
        8 + _modulusBytes,
        8 + _modulusBytes * 2,
        _bytes(rr, _modulusBytes).reversed,
      );
  }

  /// The `AUTH` public key payload: base64, a space, [name], and a NUL.
  String publicKeyPayload(String name) =>
      '${base64.encode(androidPublicKey())} $name\u0000';

  static BigInt _bigInt(List<int> bytes) => bytes.isEmpty
      ? BigInt.zero
      : BigInt.parse(
          bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
          radix: 16,
        );

  /// [value] as [length] big-endian bytes.
  static Uint8List _bytes(BigInt value, int length) {
    final hex = value.toRadixString(16).padLeft(length * 2, '0');
    return Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);
  }
}
