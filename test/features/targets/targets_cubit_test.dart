import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/device_fixtures.dart';
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

  test(
    'a token read from a phone is saved once per phone and app, then updated',
    () async {
      final cubit = await loaded();
      DeviceToken read(String token) => DeviceToken(
        token: token,
        senderId: '123456789012',
        method: TokenReadMethod.runAs,
        readAt: clock.now(),
        serial: redmiSerial,
        package: 'com.syldel.delivery',
        deviceName: 'Redmi 14C',
      );

      final first = await cubit.saveDeviceToken(
        read(fakeDeviceToken),
        projectId: 'demo-project',
      );
      expect(first.label, 'Redmi 14C · com.syldel.delivery (debug)');
      expect(first.kind, TargetKind.token);
      expect(first.value, fakeDeviceToken);
      expect(first.senderId, '123456789012');
      expect(first.projectId, 'demo-project');
      expect(
        first.source,
        const TargetSource(
          kind: TargetSourceKind.device,
          serial: redmiSerial,
          model: 'Redmi 14C',
          package: 'com.syldel.delivery',
        ),
      );

      final second = await cubit.saveDeviceToken(read(otherDeviceToken));
      expect(second.id, first.id);
      expect(cubit.state.targets.single.value, otherDeviceToken);
      expect(
        cubit.state.targets.single.projectId,
        'demo-project',
        reason: 'kept when no project is given',
      );
    },
  );
}
