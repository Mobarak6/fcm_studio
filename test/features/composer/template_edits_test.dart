import 'package:fcm_studio/features/composer/domain/template_edits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const template = <String, Object?>{
    'notification': {'title': 'Hi'},
    'fcm_options': {'analytics_label': 'x'},
  };

  test('read follows the path and returns null when it is missing', () {
    expect(TemplateEdits.read(template, ['notification', 'title']), 'Hi');
    expect(TemplateEdits.read(template, ['android', 'priority']), isNull);
    expect(
      TemplateEdits.read(template, ['notification', 'title', 'x']),
      isNull,
    );
  });

  test('write creates objects on the way and keeps other fields', () {
    final result = TemplateEdits.write(template, [
      'android',
      'notification',
      'channel_id',
    ], 'orders');
    expect(result, {
      'notification': {'title': 'Hi'},
      'fcm_options': {'analytics_label': 'x'},
      'android': {
        'notification': {'channel_id': 'orders'},
      },
    });
    expect(template.containsKey('android'), isFalse);
  });

  test('an empty value removes the key and the objects it leaves empty', () {
    final withTtl = TemplateEdits.write(template, ['android', 'ttl'], '60s');
    expect(TemplateEdits.write(withTtl, ['android', 'ttl'], ''), template);
  });

  test(
    'an emptied notification stays, so the message type does not change',
    () {
      final result = TemplateEdits.write(template, [
        'notification',
        'title',
      ], null);
      expect(result['notification'], <String, Object?>{});
      expect(TemplateEdits.isDataOnly(result), isFalse);
    },
  );

  test('data only removes the notification and sets background delivery', () {
    final result = TemplateEdits.toDataOnly(template);
    expect(TemplateEdits.isDataOnly(result), isTrue);
    expect(result, {
      'fcm_options': {'analytics_label': 'x'},
      'android': {'priority': 'high'},
      'apns': {
        'headers': {'apns-priority': '5', 'apns-push-type': 'background'},
        'payload': {
          'aps': {'content-available': 1},
        },
      },
    });
  });

  test(
    'switching back adds an empty notification and undoes the background settings',
    () {
      final result = TemplateEdits.toNotification(
        TemplateEdits.toDataOnly(template),
      );
      expect(result.keys.first, 'notification');
      expect(result, {
        'notification': {'title': '', 'body': ''},
        'fcm_options': {'analytics_label': 'x'},
        'android': {'priority': 'high'},
      });
    },
  );

  test('withData keeps the order and removes data when empty', () {
    final result = TemplateEdits.withData(template, const [
      MapEntry('b', '2'),
      MapEntry('a', '1'),
    ]);
    expect(TemplateEdits.dataEntries(result).map((e) => e.key), ['b', 'a']);
    expect(
      TemplateEdits.withData(result, const []).containsKey('data'),
      isFalse,
    );
  });
}
