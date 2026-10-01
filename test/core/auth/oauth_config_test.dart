import 'dart:io';

import 'package:fcm_studio/core/auth/oauth_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the three client values', () {
    final config = OAuthConfig.parse(
      '{"desktopClientId":"d.apps.googleusercontent.com",'
      '"desktopClientSecret":"s","webClientId":"w.apps.googleusercontent.com"}',
    );
    expect(
      config,
      const OAuthConfig(
        desktopClientId: 'd.apps.googleusercontent.com',
        desktopClientSecret: 's',
        webClientId: 'w.apps.googleusercontent.com',
      ),
    );
    expect(config.hasDesktopClient, isTrue);
    expect(config.hasWebClient, isTrue);
  });

  test('blank values count as missing', () {
    final config = OAuthConfig.parse(
      '{"desktopClientId":"  ","desktopClientSecret":"","webClientId":" w "}',
    );
    expect(config.hasDesktopClient, isFalse);
    expect(config.webClientId, 'w');
  });

  test('the committed example has no clients', () {
    final config = OAuthConfig.parse(
      File('config/oauth.example.json').readAsStringSync(),
    );
    expect(config.hasDesktopClient, isFalse);
    expect(config.hasWebClient, isFalse);
  });

  test('a missing or broken file gives no config', () async {
    expect(
      await OAuthConfig.load(
        () async => throw Exception('Unable to load asset'),
      ),
      isNull,
    );
    expect(await OAuthConfig.load(() async => '[1, 2]'), isNull);
    expect(await OAuthConfig.load(() async => 'not json'), isNull);
    expect(
      await OAuthConfig.load(() async => '{"webClientId":"w"}'),
      const OAuthConfig(webClientId: 'w'),
    );
  });

  test('toString never shows the client secret', () {
    final config = OAuthConfig.parse(
      '{"desktopClientId":"d","desktopClientSecret":"top-secret"}',
    );
    expect('$config', isNot(contains('top-secret')));
  });
}
