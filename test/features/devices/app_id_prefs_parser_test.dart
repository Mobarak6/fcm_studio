import 'dart:io';

import 'package:fcm_studio/features/devices/data/parsers/app_id_prefs_parser.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/device_fixtures.dart';

void main() {
  test('reads the token from the current JSON format', () {
    expect(
      AppIdPrefsParser.parse(appIdPrefsXml({'123456789012': fakeDeviceToken})),
      [FoundToken(token: fakeDeviceToken, senderId: '123456789012')],
    );
  });

  test('lists one token per sender ID, sorted by sender ID', () {
    final tokens = AppIdPrefsParser.parse(
      appIdPrefsXml({
        '999000999000': otherDeviceToken,
        '123456789012': fakeDeviceToken,
      }),
    );
    expect(tokens.map((t) => t.senderId), ['123456789012', '999000999000']);
    expect(tokens.last.token, otherDeviceToken);
  });

  test('accepts the older raw-token format and ignores timestamp keys', () {
    final legacy = 'APA91b${'c' * 120}';
    final tokens = AppIdPrefsParser.parse(
      '<map>\n'
      '    <string name="|T|987654321098|*">$legacy</string>\n'
      '    <string name="|T-timestamp|987654321098|*">1600000000000</string>\n'
      '</map>\n',
    );
    expect(tokens, [FoundToken(token: legacy, senderId: '987654321098')]);
  });

  test('skips entries that are not tokens', () {
    expect(
      AppIdPrefsParser.parse(
        '<map>\n'
        '    <string name="[DEFAULT]|T|111|*">{&quot;token&quot;:&quot;nope&quot;}</string>\n'
        '    <string name="[DEFAULT]|T|222|*">{not json</string>\n'
        '    <string name="|S|id">REDACTED_FID</string>\n'
        '</map>\n',
      ),
      isEmpty,
    );
    expect(AppIdPrefsParser.parse(''), isEmpty);
  });

  test('reads a file in the format of spec §9.3', () {
    final tokens = AppIdPrefsParser.parse(
      File('test/fixtures/adb/appid_prefs_synthetic.xml').readAsStringSync(),
    );
    expect(tokens, isNotEmpty);
    for (final token in tokens) {
      expect(token.token, fakeDeviceToken);
      expect(token.senderId, matches(RegExp(r'^\d+$')));
    }
  });
}
