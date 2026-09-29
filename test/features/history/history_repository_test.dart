import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';

import '../../helpers/history_fixture.dart';

void main() {
  late AppDatabase database;

  setUp(() async => database = await AppDatabase.inMemory());
  tearDown(() => database.close());

  DateTime at(int minute) => DateTime.utc(2026, 10, 3, 9, minute);

  test('loads entries newest first', () async {
    final repository = HistoryRepository(database: database);
    await repository.add(historyEntry('old', sentAt: at(1)));
    await repository.add(historyEntry('new', sentAt: at(2)));
    expect((await repository.loadAll()).map((e) => e.id), ['new', 'old']);
  });

  test('keeps only the newest entries', () async {
    final repository = HistoryRepository(database: database, maxEntries: 3);
    for (var i = 1; i <= 5; i++) {
      await repository.add(historyEntry('e$i', sentAt: at(i)));
    }
    expect((await repository.loadAll()).map((e) => e.id), ['e5', 'e4', 'e3']);
  });

  test('a stored entry that cannot be read is skipped', () async {
    final repository = HistoryRepository(database: database);
    await repository.add(historyEntry('good', sentAt: at(1)));
    final store = stringMapStoreFactory.store('history');
    await store.record('missing-fields').put(database.db, {
      'id': 'missing-fields',
      'sentAt': at(2).toIso8601String(),
    });
    await store.record('unknown-outcome').put(database.db, {
      ...historyEntry('unknown-outcome', sentAt: at(3)).toJson(),
      'outcome': {'kind': 'maybe'},
    });
    await store.record('unknown-environment').put(database.db, {
      ...historyEntry('unknown-environment', sentAt: at(4)).toJson(),
      'environment': 'moon',
    });
    expect((await repository.loadAll()).map((e) => e.id), ['good']);
  });

  test('clear removes everything and announces it', () async {
    final repository = HistoryRepository(database: database);
    await repository.add(historyEntry('a'));
    final changed = repository.changes.first;
    await repository.clear();
    await changed;
    expect(await repository.loadAll(), isEmpty);
  });
}
