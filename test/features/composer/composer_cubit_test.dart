import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/composer/domain/template_edits.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_google.dart';
import '../../helpers/fake_token_provider.dart';
import '../../helpers/fcm_fixtures.dart';
import '../../helpers/project_fixture.dart';
import '../../helpers/sender_fixture.dart';

void main() {
  const token = 'abc:APA91bxyz';
  late AppDatabase database;

  setUp(() async => database = await AppDatabase.inMemory());
  tearDown(() => database.close());

  ComposerCubit build({
    http.Client? client,
    FakeResolver? auth,
    MessageRenderer renderer = const MessageRenderer(),
  }) => ComposerCubit(
    sender: buildSender(database, client: client, auth: auth),
    renderer: renderer,
  );

  Map<String, Object?> messageOf(ComposerCubit cubit) =>
      cubit.state.render.request!['message']! as Map<String, Object?>;

  final preset = Preset(
    id: 'p1',
    name: 'Order update',
    variables: const [
      VariableDef(
        key: 'order_id',
        label: 'Order',
        required: true,
        defaultValue: '42',
      ),
    ],
    template: const {
      'notification': {'title': 'Order {{order_id}}'},
    },
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  test('starts with the default template and asks for a token', () {
    final cubit = build();
    expect(cubit.state.template, isNotNull);
    expect(cubit.state.render.errors.single.message, 'Enter a device token.');
    expect(cubit.state.canSend, isFalse);
  });

  test('reports invalid JSON with its line number', () {
    final cubit = build()..updateTemplateText('{\n  "data": {},\n}');
    expect(cubit.state.template, isNull);
    expect(cubit.state.jsonError, contains('line 3'));
    expect(cubit.state.canSend, isFalse);
  });

  test('rejects a top-level value that is not an object', () {
    final cubit = build()..updateTemplateText('[]');
    expect(cubit.state.jsonError, contains('must be a JSON object'));
  });

  test('rejects empty text', () {
    final cubit = build()..updateTemplateText('   ');
    expect(cubit.state.jsonError, contains('empty'));
  });

  test('renders the request once a token is entered', () {
    final cubit = build()..setTargetValue(token);
    expect(cubit.state.canSend, isTrue);
    expect(messageOf(cubit)['token'], token);
  });

  test('switching to topic re-renders with the same value', () {
    final cubit = build()
      ..setTargetValue('/topics/news')
      ..setTargetKind(TargetKind.topic);
    expect(messageOf(cubit)['topic'], 'news');
  });

  test('sends, stores the result and records it in history', () async {
    final cubit = build()..setTargetValue(token);
    await cubit.send(testProject);
    expect(cubit.state.sendStatus, SendStatus.done);
    expect(cubit.state.lastResult, isA<FcmSendSuccess>());
    expect(cubit.state.lastExplanation, isNull);
    expect(cubit.state.lastSentDryRun, isFalse);
    expect(await HistoryRepository(database: database).loadAll(), hasLength(1));
  });

  test('explains a failed send', () async {
    final cubit = build(
      client: fakeGoogle(fcmStatus: 404, fcmBody: unregisteredBody),
    )..setTargetValue(token);
    await cubit.send(testProject);
    expect(cubit.state.lastResult, isA<FcmSendFailure>());
    expect(cubit.state.lastExplanation?.title, 'Token is no longer valid');
  });

  test('explains a missing key instead of throwing', () async {
    final cubit = build(
      auth: FakeResolver(
        error: const AuthException(
          'The service account key for demo-project is not available in this session. '
          'Add the project again with the same key file.',
        ),
      ),
    )..setTargetValue(token);

    await cubit.send(testProject);

    expect(
      cubit.state.lastResult,
      isA<FcmSendFailure>().having(
        (r) => r.error.transport,
        'transport',
        FcmTransportError.auth,
      ),
    );
    expect(cubit.state.lastExplanation?.title, 'Could not get an access token');
    expect(
      cubit.state.lastExplanation?.explanation,
      contains('Add the project again'),
    );
  });

  test('ignores Send while a send is in progress', () async {
    final gate = Completer<http.Response>();
    var requests = 0;
    final cubit = build(
      client: MockClient((_) {
        requests++;
        return gate.future;
      }),
    )..setTargetValue(token);

    final first = cubit.send(testProject);
    await Future<void>.delayed(Duration.zero);
    await cubit.send(testProject);
    gate.complete(http.Response(successBody, 200));
    await first;

    expect(requests, 1);
    expect(cubit.state.lastResult, isA<FcmSendSuccess>());
  });

  test('does not send when the message has errors', () async {
    var requests = 0;
    final cubit = build(
      client: MockClient((_) async {
        requests++;
        return http.Response(successBody, 200);
      }),
    );
    await cubit.send(testProject);
    expect(requests, 0);
    expect(cubit.state.sendStatus, SendStatus.idle);
  });

  test(
    'an unexpected failure ends the send instead of leaving it stuck',
    () async {
      final cubit = build(
        auth: FakeResolver(error: Exception('Keychain access denied')),
      )..setTargetValue(token);

      await cubit.send(testProject);

      expect(cubit.state.sendStatus, SendStatus.done);
      expect(
        cubit.state.lastResult,
        isA<FcmSendFailure>()
            .having(
              (r) => r.error.transport,
              'transport',
              FcmTransportError.unexpected,
            )
            .having(
              (r) => r.error.message,
              'message',
              contains('Keychain access denied'),
            ),
      );
      expect(cubit.state.canSend, isTrue);
    },
  );

  group('variables and presets', () {
    test(
      'loading a preset sets the template, variables and default values',
      () {
        final cubit = build()
          ..setTargetValue(token)
          ..loadPreset(preset);
        expect(cubit.state.preset, preset);
        expect(cubit.state.values, {'order_id': '42'});
        expect(messageOf(cubit)['notification'], {'title': 'Order 42'});
        expect(cubit.state.isDirty, isFalse);
      },
    );

    test(
      'values re-render; template edits make the preset dirty until saved',
      () {
        final cubit = build()
          ..setTargetValue(token)
          ..loadPreset(preset)
          ..setVariableValue('order_id', '7');
        expect(messageOf(cubit)['notification'], {'title': 'Order 7'});
        expect(cubit.state.isDirty, isFalse, reason: 'values are not saved');

        cubit.setField(['notification', 'body'], 'Shipped');
        expect(cubit.state.isDirty, isTrue);

        cubit.presetSaved(preset.copyWith(template: cubit.state.template));
        expect(cubit.state.isDirty, isFalse);
      },
    );

    test('changing the variables makes the preset dirty', () {
      final cubit = build()
        ..loadPreset(preset)
        ..setVariables(const [VariableDef(key: 'order_id')]);
      expect(cubit.state.isDirty, isTrue);
    });

    test('the quick fix defines placeholders that have no variable', () {
      final cubit = build()
        ..updateTemplateText('{"notification": {"title": "{{a}} {{b}}"}}');
      expect(cubit.state.render.undefinedPlaceholders, ['a', 'b']);
      cubit.addMissingVariables();
      expect(cubit.state.variables.map((v) => v.key), ['a', 'b']);
      expect(cubit.state.render.undefinedPlaceholders, isEmpty);
    });

    test('setVariables keeps the values of keys that still exist', () {
      final cubit = build()
        ..loadPreset(preset)
        ..setVariableValue('order_id', '7')
        ..setVariables(const [
          VariableDef(key: 'order_id'),
          VariableDef(key: 'extra', defaultValue: 'x'),
        ]);
      expect(cubit.state.values, {'order_id': '7', 'extra': 'x'});
    });

    test('detachPreset forgets a deleted preset', () {
      final cubit = build()
        ..loadPreset(preset)
        ..detachPreset('other')
        ..detachPreset('p1');
      expect(cubit.state.preset, isNull);
    });
  });

  group('form edits', () {
    test('setField updates the template and rewrites the JSON text', () {
      final cubit = build()..setField(['android', 'priority'], 'high');
      expect(cubit.state.template!['android'], {'priority': 'high'});
      expect(cubit.state.templateText, contains('"priority": "high"'));
      expect(
        ComposerCubit.parseTemplate(cubit.state.templateText).$1,
        cubit.state.template,
      );
    });

    test('form edits are ignored while the JSON is invalid', () {
      final cubit = build()
        ..updateTemplateText('{')
        ..setField(['android', 'priority'], 'high');
      expect(cubit.state.templateText, '{');
    });

    test('the data-only switch goes both ways', () {
      final cubit = build()..setDataOnly(true);
      expect(TemplateEdits.isDataOnly(cubit.state.template!), isTrue);
      cubit.setDataOnly(false);
      expect(TemplateEdits.isDataOnly(cubit.state.template!), isFalse);
    });

    test('setDataEntries replaces data in order', () {
      final cubit = build()
        ..setDataEntries(const [MapEntry('b', '2'), MapEntry('a', '1')]);
      expect(
        TemplateEdits.dataEntries(cubit.state.template!).map((e) => e.key),
        ['b', 'a'],
      );
    });
  });

  group('sending', () {
    test('a dry run adds validate_only and is recorded as one', () async {
      final cubit = build()
        ..setTargetValue(token)
        ..setValidateOnly(true);
      expect(cubit.state.render.request!['validate_only'], isTrue);
      await cubit.send(testProject);
      expect(cubit.state.lastSentDryRun, isTrue);
      expect(
        (await HistoryRepository(
          database: database,
        ).loadAll()).single.validateOnly,
        isTrue,
      );
    });

    test('built-in placeholders get fresh values for each send', () async {
      var n = 0;
      final requests = <http.Request>[];
      final cubit =
          build(
              renderer: MessageRenderer(newId: () => 'id-${++n}'),
              client: fakeGoogle(onFcmRequest: requests.add),
            )
            ..updateTemplateText(
              '{"data": {"id": "{{uuid}}"}, "android": {"priority": "high"}}',
            )
            ..setTargetValue(token);
      final previewId =
          (messageOf(cubit)['data']! as Map<String, Object?>)['id'];
      await cubit.send(testProject);
      final sent = jsonDecode(requests.single.body) as Map<String, Object?>;
      final sentMessage = sent['message']! as Map<String, Object?>;
      expect(
        (sentMessage['data']! as Map<String, Object?>)['id'],
        isNot(previewId),
      );
    });

    test('the preset name goes into history', () async {
      final cubit = build()
        ..setTargetValue(token)
        ..loadPreset(preset);
      await cubit.send(testProject);
      expect(
        (await HistoryRepository(
          database: database,
        ).loadAll()).single.presetName,
        'Order update',
      );
    });

    test('curl returns a command for the current request', () async {
      final cubit = build()..setTargetValue(token);
      expect(
        await cubit.curl(testProject, includeAccessToken: false),
        contains(r'$FCM_ACCESS_TOKEN'),
      );
      cubit.setTargetValue('');
      expect(await cubit.curl(testProject, includeAccessToken: false), isNull);
    });
  });

  test(
    'openMessage loads a stored message with its target and no variables',
    () {
      final cubit = build()
        ..loadPreset(preset)
        ..openMessage(
          template: const {
            'notification': {'title': 'Old'},
          },
          target: const TopicTarget('news'),
        );
      expect(cubit.state.preset, isNull);
      expect(cubit.state.variables, isEmpty);
      expect(cubit.state.targetKind, TargetKind.topic);
      expect(cubit.state.targetValue, 'news');
      expect(cubit.state.template, {
        'notification': {'title': 'Old'},
      });
    },
  );

  test('showField asks the JSON editor to show the line of the field', () {
    final cubit = build()
      ..updateTemplateText('{\n  "data": {\n    "a": "1"\n  }\n}')
      ..showField('message.data[0].value');
    expect(cubit.state.jsonFocus?.line, 3);
    final first = cubit.state.jsonFocus;
    cubit.showField('message.data[0].value');
    expect(
      cubit.state.jsonFocus,
      isNot(first),
      reason: 'a repeat is a new request',
    );
  });
}
