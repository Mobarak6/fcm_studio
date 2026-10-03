import 'dart:convert';
import 'dart:io';

import 'package:fcm_studio/features/devices/data/webusb/adb_key.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/adb_key_fixture.dart';

void main() {
  final token = List<int>.generate(20, (i) => i);

  test('signs a token exactly like adb (openssl -pkeyopt digest:sha1)', () {
    final expected = File(
      'test/fixtures/adb/test_adbkey_signature.hex',
    ).readAsStringSync().trim();
    final signature = testAdbKey().sign(token);
    expect(signature, hasLength(256));
    expect(
      signature.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
      expected,
    );
  });

  test('without the CRT values the signature is the same', () {
    final full = testAdbKey();
    expect(
      AdbKey(n: full.n, e: full.e, d: full.d).sign(token),
      full.sign(token),
    );
  });

  test('the Android public key matches adb keygen', () {
    final expected = File(
      'test/fixtures/adb/test_adbkey.pub',
    ).readAsStringSync().split(' ').first;
    expect(base64.encode(testAdbKey().androidPublicKey()), expected);
  });

  test('the AUTH payload is the key, a space, the name and a NUL', () {
    final payload = testAdbKey().publicKeyPayload('fcm-studio@example.com');
    expect(payload, endsWith(' fcm-studio@example.com\u0000'));
    expect(
      payload.split(' ').first,
      base64.encode(testAdbKey().androidPublicKey()),
    );
  });

  test('a token that is not 20 bytes is refused', () {
    expect(() => testAdbKey().sign([1, 2, 3]), throwsArgumentError);
  });

  test('a JWK without n, or with a short modulus, is refused', () {
    final jwk = testAdbKeyJwk();
    expect(() => AdbKey.fromJwk({...jwk}..remove('n')), throwsFormatException);
    expect(() => AdbKey.fromJwk({...jwk, 'n': 'AQAB'}), throwsFormatException);
  });
}
