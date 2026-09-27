import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
