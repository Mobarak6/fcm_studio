import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixed_clock.dart';

void main() {
  late AppDatabase database;
  late TargetsRepository repository;
  final clock = FixedClock(DateTime.utc(2026, 10, 3, 9));
  var ids = 0;

  setUp(() async {
    database = await AppDatabase.inMemory();
    repository = TargetsRepository(database: database);
    ids = 0;
  });

  tearDown(() => database.close());

  Future<TargetsCubit> loaded() async {
    final cubit = TargetsCubit(
      repository: repository,
      clock: clock,
      newId: () => 't${++ids}',
    );
    await cubit.load();
    addTearDown(cubit.close);
    return cubit;
  }

  test('saves a target, with a default label when none is given', () async {
    final cubit = await loaded();
    final saved = await cubit.save(
      const TopicTarget('/topics/news'),
      label: ' ',
      projectId: 'demo-project',
    );
    expect(saved.label, 'Topic news');
    expect(saved.value, 'news');
    expect(saved.projectId, 'demo-project');
    expect(saved.lastUsedAt, clock.now());
    expect(cubit.state.targets, [saved]);
    expect(cubit.state.matching(const TopicTarget('news')), saved);
  });

  test('rename and remove', () async {
    final cubit = await loaded();
    final saved = await cubit.save(const TopicTarget('news'), label: 'News');
    await cubit.rename(saved, 'Breaking');
    expect(cubit.state.targets.single.label, 'Breaking');
    await cubit.remove(cubit.state.targets.single);
    expect(cubit.state.targets, isEmpty);
  });

  test(
    'picks up changes made elsewhere, e.g. a send marking a target used',
    () async {
      final cubit = await loaded();
      final next = cubit.stream.first;
      await repository.save(
        SavedTarget(
          id: 'x',
          label: 'X',
          kind: TargetKind.topic,
          value: 'news',
          lastUsedAt: clock.now(),
        ),
      );
      expect((await next).targets.single.id, 'x');
    },
  );
}
