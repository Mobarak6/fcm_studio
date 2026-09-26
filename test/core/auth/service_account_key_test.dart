import 'dart:convert';

import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/service_account_fixture.dart';

Matcher throwsKeyError(String text) => throwsA(
  isA<ServiceAccountKeyException>().having(
    (e) => e.message,
    'message',
    contains(text),
  ),
);

void main() {
  test('parses a valid service account key', () {
    final key = ServiceAccountKey.parse(serviceAccountJson());
    expect(key.projectId, testProjectId);
    expect(key.clientEmail, testClientEmail);
    expect(key.privateKeyId, 'test-key-id-1');
    expect(key.privateKeyPem, startsWith('-----BEGIN PRIVATE KEY-----'));
  });

  test('rejects text that is not JSON', () {
    expect(
      () => ServiceAccountKey.parse('not json'),
      throwsKeyError('not valid JSON'),
    );
  });

  test('recognises google-services.json', () {
    final file = jsonEncode({
      'project_info': {'project_id': 'x'},
      'client': <Object?>[],
    });
    expect(
      () => ServiceAccountKey.parse(file),
      throwsKeyError('google-services.json'),
    );
  });

  test('recognises an OAuth client file', () {
    final file = jsonEncode({
      'installed': {'client_id': 'x'},
    });
    expect(() => ServiceAccountKey.parse(file), throwsKeyError('OAuth client'));
  });

  test('rejects other credential types', () {
    final file = jsonEncode({
      ...serviceAccountMap(),
      'type': 'authorized_user',
    });
    expect(
      () => ServiceAccountKey.parse(file),
      throwsKeyError('authorized_user'),
    );
  });

  test('names a missing field', () {
    final map = serviceAccountMap()..remove('client_email');
    expect(
      () => ServiceAccountKey.parse(jsonEncode(map)),
      throwsKeyError('"client_email"'),
    );
  });

  test('rejects a private key that is not PKCS#8 PEM', () {
    final file = jsonEncode({
      ...serviceAccountMap(),
      'private_key': 'not a key',
    });
    expect(() => ServiceAccountKey.parse(file), throwsKeyError('PKCS#8'));
  });

  test('rejects a PEM block that is not a usable RSA key', () {
    final file = jsonEncode({
      ...serviceAccountMap(),
      'private_key':
          '-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n',
    });
    expect(
      () => ServiceAccountKey.parse(file),
      throwsKeyError('could not be read'),
    );
  });

  test('toString never contains the private key', () {
    final key = ServiceAccountKey.parse(serviceAccountJson());
    expect(key.toString(), isNot(contains('PRIVATE KEY')));
    expect(key.toString(), contains(testClientEmail));
  });
}
