import 'dart:convert';

import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/history/cubit/history_cubit.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/history/domain/history_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/fake_google.dart';
import '../../helpers/history_fixture.dart';
import '../../helpers/project_fixture.dart';
import '../../helpers/sender_fixture.dart';

void main() {
  late AppDatabase database;
  late HistoryRepository repository;

  setUp(() async {
    database = await AppDatabase.inMemory();
    repository = HistoryRepository(database: database);
  });

  tearDown(() => database.close());

  Future<HistoryCubit> loaded({http.Client? client}) async {
    final cubit = HistoryCubit(
      repository: repository,
      sender: buildSender(database, client: client, history: repository),
    );
    await cubit.load();
    addTearDown(cubit.close);
    return cubit;
  }

  test('loads entries newest first and filters them', () async {
    await repository.add(
      historyEntry('old', sentAt: DateTime.utc(2026, 10, 3, 9)),
    );
    await repository.add(
      historyEntry('failed', ok: false, sentAt: DateTime.utc(2026, 10, 3, 10)),
    );
    final cubit = await loaded();
    expect(cubit.state.status, HistoryStatus.ready);
    expect(cubit.state.entries.map((e) => e.id), ['failed', 'old']);
    expect(cubit.state.projectIds, ['demo-project']);

    cubit.setFilter(const HistoryFilter(outcome: OutcomeFilter.failure));
    expect(cubit.state.visible.map((e) => e.id), ['failed']);
  });

  test('clear empties the history', () async {
    await repository.add(historyEntry('a'));
    final cubit = await loaded();
    await cubit.clear();
    expect(cubit.state.entries, isEmpty);
  });

  test(
    'resend sends the stored request again and records a new entry',
    () async {
      final requests = <http.Request>[];
      await repository.add(historyEntry('e1'));
      final cubit = await loaded(
        client: fakeGoogle(onFcmRequest: requests.add),
      );

      final reloaded = cubit.stream.firstWhere((s) => s.entries.length == 2);
      final outcome = await cubit.resend(
        cubit.state.entries.single,
        testProject,
      );
      await reloaded;

      expect(outcome.result, isA<FcmSendSuccess>());
      expect(jsonDecode(requests.single.body), historyEntry('e1').request);
    },
  );

  test('curl for an entry', () async {
    await repository.add(historyEntry('e1'));
    final cubit = await loaded();
    expect(
      await cubit.curl(
        cubit.state.entries.single,
        testProject,
        includeAccessToken: false,
      ),
      contains('abc:APA91bxyz'),
    );
  });
}
