import 'dart:convert';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/composer/data/message_sender.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/fake_google.dart';
import '../../helpers/fake_token_provider.dart';
import '../../helpers/fcm_fixtures.dart';
import '../../helpers/fixed_clock.dart';
import '../../helpers/project_fixture.dart';

class _BrokenHistory extends HistoryRepository {
  _BrokenHistory(AppDatabase database) : super(database: database);

  @override
  Future<void> add(HistoryEntry entry) => Future.error(StateError('disk full'));
}

class _BrokenLookup extends TargetsRepository {
  _BrokenLookup(AppDatabase database) : super(database: database);

  @override
  Future<SavedTarget?> findMatching(Target target) =>
      Future.error(StateError('targets store is broken'));
}

class _BrokenMarkUsed extends TargetsRepository {
  _BrokenMarkUsed(AppDatabase database) : super(database: database);

  @override
  Future<void> markUsed(Target target, DateTime at) =>
      Future.error(StateError('targets store is broken'));
}

void main() {
  const token = 'abc:APA91bxyz';
  const request = {
    'message': {
      'token': token,
      'notification': {'title': 'Hi'},
    },
  };
  final clock = FixedClock(DateTime.utc(2026, 10, 3, 9));
  late AppDatabase database;
  late HistoryRepository history;
  late TargetsRepository targets;

  setUp(() async {
    database = await AppDatabase.inMemory();
    history = HistoryRepository(database: database);
    targets = TargetsRepository(database: database);
  });

  tearDown(() => database.close());

  MessageSender build({
    http.Client? client,
    AccessTokenResolver? auth,
    HistoryRepository? historyRepository,
    TargetsRepository? targetsRepository,
  }) => MessageSender(
    fcmClient: FcmClient(httpClient: client ?? fakeGoogle()),
    auth: auth ?? FakeResolver(),
    history: historyRepository ?? history,
    targets: targetsRepository ?? targets,
    clock: clock,
    newId: () => 'entry-1',
  );

  test('a successful send is recorded in history', () async {
    final outcome = await build().send(
      project: testProject,
      request: request,
      target: const TokenTarget(token),
      presetName: 'Simple notification',
    );
    expect(outcome.result, isA<FcmSendSuccess>());
    expect(outcome.explanation, isNull);

    final entry = (await history.loadAll()).single;
    expect(entry.id, 'entry-1');
    expect(entry.sentAt, clock.now());
    expect(entry.projectId, 'demo-project');
    expect(
      entry.outcome,
      const HistorySuccess('projects/demo-project/messages/0:1'),
    );
    expect(
      entry.target,
      const HistoryTarget(kind: TargetKind.token, value: token),
    );
    expect(entry.presetName, 'Simple notification');
    expect(entry.validateOnly, isFalse);
    expect(entry.httpStatus, 200);
    expect(entry.request, request);
  });

  test('a failed send is recorded with its code and explanation', () async {
    final outcome =
        await build(
          client: fakeGoogle(fcmStatus: 404, fcmBody: unregisteredBody),
        ).send(
          project: testProject,
          request: request,
          target: const TokenTarget(token),
        );
    expect(outcome.explanation?.title, 'Token is no longer valid');
    final entry = (await history.loadAll()).single;
    expect(
      entry.outcome,
      const HistoryFailure(
        code: 'UNREGISTERED',
        explanation: 'Token is no longer valid',
      ),
    );
    expect(entry.httpStatus, 404);
  });

  test('a failure before FCM answers is still recorded', () async {
    final outcome =
        await build(
          auth: FakeResolver(error: const AuthException('Key missing')),
        ).send(
          project: testProject,
          request: request,
          target: const TokenTarget(token),
        );
    expect(outcome.explanation?.title, 'Could not get an access token');
    final entry = (await history.loadAll()).single;
    expect(entry.httpStatus, isNull);
    expect(
      entry.outcome,
      const HistoryFailure(
        code: 'AUTH',
        explanation: 'Could not get an access token',
      ),
    );
  });

  test('a Google-account project gets Google sign-in advice', () async {
    final outcome =
        await build(
          auth: FakeResolver(error: const AuthException('expired')),
        ).send(
          project: testGoogleProject,
          request: request,
          target: const TokenTarget(token),
        );
    expect(outcome.explanation?.action, contains('Sign in again'));
  });

  test('dry runs are recorded as dry runs', () async {
    await build().send(
      project: testProject,
      request: {'validate_only': true, ...request},
      target: const TokenTarget(token),
    );
    expect((await history.loadAll()).single.validateOnly, isTrue);
  });

  test('no access token is ever stored', () async {
    await build().send(
      project: testProject,
      request: request,
      target: const TokenTarget(token),
    );
    final stored = jsonEncode((await history.loadAll()).single.toJson());
    expect(stored, isNot(contains('token-1')));
    expect(stored, isNot(contains('Bearer')));
  });

  test('a saved target labels the entry and is marked as used', () async {
    await targets.save(
      SavedTarget(
        id: 't',
        label: 'Redmi',
        kind: TargetKind.token,
        value: token,
        lastUsedAt: DateTime.utc(2026),
      ),
    );
    await build().send(
      project: testProject,
      request: request,
      target: const TokenTarget(token),
    );
    expect((await history.loadAll()).single.target.label, 'Redmi');
    expect((await targets.loadAll()).single.lastUsedAt, clock.now());
  });

  test('a history write that fails still returns the send result', () async {
    final outcome = await build(historyRepository: _BrokenHistory(database))
        .send(
          project: testProject,
          request: request,
          target: const TokenTarget(token),
        );
    expect(outcome.result, isA<FcmSendSuccess>());
    expect(outcome.historyError, contains('disk full'));
  });

  test('a failing saved-target lookup still records the send', () async {
    final outcome = await build(targetsRepository: _BrokenLookup(database))
        .send(
          project: testProject,
          request: request,
          target: const TokenTarget(token),
        );
    expect(outcome.result, isA<FcmSendSuccess>());
    expect(outcome.historyError, isNull);
    final entry = (await history.loadAll()).single;
    expect(entry.target.value, token);
    expect(entry.target.label, isNull);
  });

  test('a failing markUsed is not reported as a history error', () async {
    final failing = _BrokenMarkUsed(database);
    await failing.save(
      SavedTarget(
        id: 't',
        label: 'Redmi',
        kind: TargetKind.token,
        value: token,
        lastUsedAt: DateTime.utc(2026),
      ),
    );
    final outcome = await build(targetsRepository: failing).send(
      project: testProject,
      request: request,
      target: const TokenTarget(token),
    );
    expect(outcome.result, isA<FcmSendSuccess>());
    expect(outcome.historyError, isNull);
    expect((await history.loadAll()).single.target.label, 'Redmi');
  });

  test('curl includes a current access token only when asked', () async {
    final sender = build();
    expect(
      await sender.curl(
        project: testProject,
        request: request,
        includeAccessToken: true,
      ),
      contains("-H 'Authorization: Bearer token-1'"),
    );
    expect(
      await sender.curl(
        project: testProject,
        request: request,
        includeAccessToken: false,
      ),
      contains(r'Bearer $FCM_ACCESS_TOKEN'),
    );
  });

  test('curl with the placeholder works without the key', () async {
    final sender = build(
      auth: FakeResolver(error: const AuthException('Key missing')),
    );
    expect(
      await sender.curl(
        project: testProject,
        request: request,
        includeAccessToken: false,
      ),
      contains(r'$FCM_ACCESS_TOKEN'),
    );
    await expectLater(
      sender.curl(
        project: testProject,
        request: request,
        includeAccessToken: true,
      ),
      throwsA(isA<AuthException>()),
    );
  });
}
