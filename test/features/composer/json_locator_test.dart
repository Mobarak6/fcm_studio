import 'dart:convert';

import 'package:fcm_studio/features/composer/domain/json_locator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const text = '''
{
  "notification": {
    "title": "Hi",
    "body": "the \\"click_action\\" word"
  },
  "data": {
    "order_id": "42",
    "kind": "x"
  },
  "android": {
    "notification": {
      "click_action": "OPEN"
    }
  }
}''';
  final template = jsonDecode(text) as Map<String, Object?>;

  test('finds the line of a key', () {
    expect(JsonLocator.lineOf(text, ['data', 'kind']), 8);
    expect(
      JsonLocator.lineOf(text, ['android', 'notification', 'click_action']),
      12,
    );
  });

  test('falls back to the closest key that exists', () {
    expect(JsonLocator.lineOf(text, ['android', 'notification', 'color']), 11);
    expect(JsonLocator.lineOf(text, ['apns', 'headers']), isNull);
  });

  test('ignores key-like text inside string values', () {
    expect(JsonLocator.lineOf(text, ['notification', 'click_action']), 2);
  });

  test('turns FCM field paths into template keys', () {
    expect(JsonLocator.resolve('message.data[1].value', template), [
      'data',
      'kind',
    ]);
    expect(
      JsonLocator.resolve('message.android.notification.clickAction', template),
      ['android', 'notification', 'click_action'],
    );
    expect(JsonLocator.resolve('message.apns.payload', template), isEmpty);
  });
}
