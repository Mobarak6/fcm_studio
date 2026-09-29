import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';

void main() {
  late AppDatabase database;
  late TargetsRepository repository;
  final t0 = DateTime.utc(2026, 10, 3, 9);

  setUp(() async {
    database = await AppDatabase.inMemory();
    repository = TargetsRepository(database: database);
  });

  tearDown(() => database.close());

  SavedTarget topic(String id, String name, {Duration age = Duration.zero}) =>
      SavedTarget(
        id: id,
        label: id,
        kind: TargetKind.topic,
        value: name,
        lastUsedAt: t0.subtract(age),
      );

  test('saves and loads targets, newest first', () async {
    await repository.save(topic('old', 'a', age: const Duration(hours: 1)));
    await repository.save(topic('new', 'b'));
    expect((await repository.loadAll()).map((t) => t.id), ['new', 'old']);
  });

  test('finds a saved target by its normalised value', () async {
    await repository.save(topic('a', 'news'));
    expect(
      (await repository.findMatching(const TopicTarget('/topics/news')))?.id,
      'a',
    );
    expect(await repository.findMatching(const TopicTarget('sport')), isNull);
  });

  test('markUsed updates lastUsedAt and announces the change', () async {
    await repository.save(topic('a', 'news'));
    final changed = repository.changes.first;
    final later = t0.add(const Duration(hours: 1));
    await repository.markUsed(const TopicTarget('news'), later);
    await changed;
    expect((await repository.loadAll()).single.lastUsedAt, later);
  });

  test('a stored target that cannot be read is skipped', () async {
    await repository.save(topic('a', 'news'));
    final store = stringMapStoreFactory.store('targets');
    await store.record('missing-fields').put(database.db, {'id': 'x'});
    await store.record('unknown-kind').put(database.db, {
      ...topic('b', 'sport').toJson(),
      'id': 'unknown-kind',
      'kind': 'carrier-pigeon',
    });
    await store.record('bad-date').put(database.db, {
      ...topic('c', 'weather').toJson(),
      'id': 'bad-date',
      'lastUsedAt': 'yesterday',
    });
    expect((await repository.loadAll()).map((t) => t.id), ['a']);
    expect((await repository.findMatching(const TopicTarget('news')))?.id, 'a');
  });

  test('remove deletes the target', () async {
    await repository.save(topic('a', 'news'));
    await repository.remove('a');
    expect(await repository.loadAll(), isEmpty);
  });
}
