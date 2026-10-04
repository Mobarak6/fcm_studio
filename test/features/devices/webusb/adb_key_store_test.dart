import 'dart:convert';

import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_key_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../helpers/adb_key_fixture.dart';

void main() {
  late MemorySecretStore secrets;
  late int generated;
  Object? generateError;

  setUp(() {
    secrets = MemorySecretStore();
    generated = 0;
    generateError = null;
  });

  AdbKeyStore store() => AdbKeyStore(
    secrets: secrets,
    generateJwk: () async {
      generated++;
      final error = generateError;
      if (error != null) {
        throw error;
      }
      return testAdbKeyJwk();
    },
  );

  test('makes the key once and keeps it under adb:browser-key', () async {
    final keys = store();
    final first = await keys.load();
    final second = await keys.load();
    expect(identical(first, second), isTrue);
    expect(generated, 1);
    expect(
      jsonDecode((await secrets.read(AdbKeyStore.secretKey))!),
      testAdbKeyJwk(),
    );
  });

  test('loads at the same time share one key', () async {
    final keys = store();
    final both = await Future.wait([keys.load(), keys.load()]);
    expect(identical(both[0], both[1]), isTrue);
    expect(generated, 1);
  });

  test('a stored key is reused on the next visit', () async {
    await secrets.write(AdbKeyStore.secretKey, jsonEncode(testAdbKeyJwk()));
    final key = await store().load();
    expect(generated, 0);
    expect(key.n, testAdbKey().n);
  });

  test('a damaged stored key is replaced', () async {
    await secrets.write(AdbKeyStore.secretKey, '{"n": "AQAB"');
    final key = await store().load();
    expect(generated, 1);
    expect(key.n, testAdbKey().n);
    expect(
      jsonDecode((await secrets.read(AdbKeyStore.secretKey))!),
      testAdbKeyJwk(),
    );
  });

  test('a failed key creation is tried again next time', () async {
    final keys = store();
    generateError = StateError('WebCrypto failed');
    await expectLater(keys.load(), throwsStateError);
    generateError = null;
    await keys.load();
    expect(generated, 2);
  });
}
