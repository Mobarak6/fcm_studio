import 'package:fcm_studio/core/utils/redact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redact', () {
    test('removes PEM private keys, including JSON-escaped ones', () {
      const raw =
          '{"private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEsecret\\n-----END PRIVATE KEY-----\\n"}';
      final out = redact(raw);
      expect(out, isNot(contains('MIIEsecret')));
      expect(out, contains('[REDACTED'));
    });

    test('removes bearer tokens', () {
      expect(
        redact('Authorization: Bearer ya29.a0AfB_secret'),
        'Authorization: Bearer [REDACTED]',
      );
    });

    test('removes access and refresh tokens in JSON', () {
      expect(
        redact('{"access_token":"abc","refresh_token":"def"}'),
        '{"access_token":"[REDACTED]","refresh_token":"[REDACTED]"}',
      );
    });

    test('removes bare ya29 access tokens', () {
      expect(redact('got ya29.c.b0Aaek-xyz end'), 'got ya29.[REDACTED] end');
    });

    test('leaves ordinary text alone', () {
      expect(
        redact('Requested entity was not found.'),
        'Requested entity was not found.',
      );
    });
  });
}
