import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixed_clock.dart';

void main() {
  const renderer = MessageRenderer();
  const notification = {'title': 'Hi'};

  Map<String, Object?> message(RenderResult result) =>
      result.request!['message']! as Map<String, Object?>;

  test('puts the target first and keeps the template fields', () {
    final result = renderer.render(
      template: {'notification': notification},
      target: const TokenTarget('abc:APA91bxyz'),
    );
    expect(result.canSend, isTrue);
    expect(result.request, {
      'message': {'token': 'abc:APA91bxyz', 'notification': notification},
    });
    expect(message(result).keys.first, 'token');
  });

  test('adds validate_only only for dry runs', () {
    final normal = renderer.render(
      template: {'notification': notification},
      target: const TopicTarget('news'),
    );
    final dryRun = renderer.render(
      template: {'notification': notification},
      target: const TopicTarget('news'),
      validateOnly: true,
    );
    expect(normal.request!.containsKey('validate_only'), isFalse);
    expect(dryRun.request!['validate_only'], isTrue);
  });

  test('turns data values into strings and notes each conversion', () {
    final result = renderer.render(
      template: {
        'notification': notification,
        'data': {
          'order_id': 42,
          'urgent': true,
          'meta': {'a': 1},
          'list': [1, 2],
          'text': 'ok',
          'gone': null,
        },
      },
      target: const TopicTarget('news'),
    );
    expect(message(result)['data'], {
      'order_id': '42',
      'urgent': 'true',
      'meta': '{"a":1}',
      'list': '[1,2]',
      'text': 'ok',
    });
    expect(
      result.notes.map((n) => n.path),
      containsAll([
        'data.order_id',
        'data.urgent',
        'data.meta',
        'data.list',
        'data.gone',
      ]),
    );
    expect(result.canSend, isTrue);
  });

  test('blocks data keys that FCM v1 reserves', () {
    for (final key in [
      'from',
      'message_type',
      'google.c.a.e',
      'gcm.notification.title',
    ]) {
      final result = renderer.render(
        template: {
          'notification': notification,
          'data': {key: 'v'},
        },
        target: const TopicTarget('news'),
      );
      expect(result.canSend, isFalse, reason: key);
      expect(result.errors.single.path, 'data.$key', reason: key);
    }
  });

  test('warns about data keys that older SDKs reserve', () {
    for (final key in ['notification', 'gcm_custom', 'googleish']) {
      final result = renderer.render(
        template: {
          'notification': notification,
          'data': {key: 'v'},
        },
        target: const TopicTarget('news'),
      );
      expect(result.canSend, isTrue, reason: key);
      expect(
        result.warnings.map((w) => w.path),
        contains('data.$key'),
        reason: key,
      );
    }
  });

  test('rejects target fields inside the template', () {
    final result = renderer.render(
      template: {'token': 'x', 'notification': notification},
      target: const TokenTarget('abc'),
    );
    expect(result.errors.single.path, 'token');
    expect(result.request, isNull);
    expect(result.canSend, isFalse);
  });

  test('rejects data that is not an object', () {
    final result = renderer.render(
      template: {'notification': notification, 'data': 'oops'},
      target: const TopicTarget('news'),
    );
    expect(result.errors.single.path, 'data');
  });

  test('includes target validation errors', () {
    final result = renderer.render(
      template: {'notification': notification},
      target: const TokenTarget(''),
    );
    expect(result.errors.single.message, 'Enter a device token.');
  });

  test(
    'warns when a data-only message is not set up for background delivery',
    () {
      final result = renderer.render(
        template: {
          'data': {'a': 'b'},
        },
        target: const TopicTarget('news'),
      );
      expect(
        result.warnings.map((w) => w.path),
        containsAll(['android.priority', 'apns']),
      );
    },
  );

  test('a correctly set up background message has no delivery warnings', () {
    final result = renderer.render(
      template: {
        'data': {'a': 'b'},
        'android': {'priority': 'high'},
        'apns': {
          'headers': {'apns-priority': '5'},
          'payload': {
            'aps': {'content-available': 1},
          },
        },
      },
      target: const TopicTarget('news'),
    );
    expect(result.warnings, isEmpty);
  });

  test('warns when the payload is over 4096 bytes', () {
    final result = renderer.render(
      template: {
        'notification': notification,
        'data': {'big': 'x' * 5000},
      },
      target: const TopicTarget('news'),
    );
    expect(result.warnings.map((w) => w.path), contains('message'));
    expect(result.canSend, isTrue);
  });

  group('placeholders', () {
    final clock = FixedClock(DateTime.utc(2026, 10, 3, 12));
    final placeholderRenderer = MessageRenderer(
      clock: clock,
      newId: () => 'id-1',
    );
    const title = VariableDef(key: 'title', label: 'Title', required: true);
    const badge = VariableDef(
      key: 'badge',
      label: 'Badge',
      type: VariableType.number,
    );
    const urgent = VariableDef(
      key: 'urgent',
      type: VariableType.boolean,
      defaultValue: 'false',
    );

    RenderResult renderWith(
      Map<String, Object?> template,
      Map<String, String> values,
    ) => placeholderRenderer.render(
      template: template,
      target: const TopicTarget('news'),
      variables: const [title, badge, urgent],
      values: values,
    );

    test('fills placeholders from values, then from defaults', () {
      final result = renderWith(
        {
          'notification': {
            'title': '{{title}}',
            'body': 'Urgent: {{ urgent }}',
          },
        },
        {'title': 'Hi'},
      );
      expect(message(result)['notification'], {
        'title': 'Hi',
        'body': 'Urgent: false',
      });
    });

    test('a lone number or boolean placeholder keeps its type', () {
      final result = renderWith(
        {
          'notification': notification,
          'apns': {
            'payload': {
              'aps': {'badge': '{{badge}}'},
            },
          },
          'android': {'direct_boot_ok': '{{urgent}}'},
        },
        {'badge': '3', 'urgent': 'true'},
      );
      expect(message(result)['apns'], {
        'payload': {
          'aps': {'badge': 3},
        },
      });
      expect(message(result)['android'], {'direct_boot_ok': true});
    });

    test('a placeholder inside longer text is inserted as text', () {
      final result = renderWith(
        {
          'notification': {'title': 'You have {{badge}} new'},
        },
        {'badge': '3'},
      );
      expect(message(result)['notification'], {'title': 'You have 3 new'});
    });

    test('built-in values need no definition', () {
      final result = renderWith({
        'notification': notification,
        'data': {'at': '{{now_iso}}', 'ms': '{{now_ms}}', 'id': '{{uuid}}'},
      }, {});
      expect(message(result)['data'], {
        'at': '2026-10-03T12:00:00.000Z',
        'ms': '${clock.now().millisecondsSinceEpoch}',
        'id': 'id-1',
      });
      expect(result.notes.map((n) => n.path), contains('placeholders'));
    });

    test('an unknown placeholder blocks sending and is listed once', () {
      final result = renderWith({
        'notification': notification,
        'data': {'order': '{{order_id}}', 'again': '{{order_id}}'},
      }, {});
      expect(result.canSend, isFalse);
      expect(result.errors.single.path, 'data.order');
      expect(
        result.errors.single.message,
        'Unknown placeholder {{order_id}}. Add it under Variables.',
      );
      expect(result.undefinedPlaceholders, ['order_id']);
    });

    test('an empty required value blocks sending', () {
      final result = renderWith(
        {
          'notification': {'title': '{{title}}'},
        },
        {'title': '  '},
      );
      expect(result.errors.single.message, 'Fill in "Title" ({{title}}).');
    });

    test('a value that is not a number blocks sending instead of crashing', () {
      final result = renderWith(
        {
          'notification': notification,
          'apns': {
            'payload': {
              'aps': {'badge': '{{badge}}'},
            },
          },
        },
        {'badge': '12a'},
      );
      expect(result.canSend, isFalse);
      expect(
        result.errors.single.message,
        '"Badge" must be a number, not "12a".',
      );
    });

    test('an empty optional typed placeholder removes its field', () {
      final result = renderWith({
        'notification': notification,
        'apns': {
          'payload': {
            'aps': {'badge': '{{badge}}', 'sound': 'default'},
          },
        },
      }, {});
      expect(message(result)['apns'], {
        'payload': {
          'aps': {'sound': 'default'},
        },
      });
      expect(
        result.notes.map((n) => n.message),
        contains('Removed because {{badge}} is empty.'),
      );
    });

    test('NaN, Infinity and hex are not numbers and do not crash', () {
      for (final text in ['NaN', 'Infinity', '0x1F']) {
        final result = renderWith(
          {
            'notification': notification,
            'apns': {
              'payload': {
                'aps': {'badge': '{{badge}}'},
              },
            },
          },
          {'badge': text},
        );
        expect(result.canSend, isFalse, reason: text);
        expect(
          result.errors.single.message,
          '"Badge" must be a number, not "$text".',
        );
      }
    });
  });
}
