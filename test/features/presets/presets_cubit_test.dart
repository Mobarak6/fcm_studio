import 'dart:convert';

import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/data/presets_repository.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/presets_fixture.dart';

class _BrokenUserPresets extends PresetsRepository {
  _BrokenUserPresets(AppDatabase database)
    : super(database: database, loadBuiltInJson: loadBuiltInPresetsFromFile);

  @override
  Future<List<Preset>> loadUserPresets() =>
      Future.error(StateError('disk error'));
}

void main() {
  late AppDatabase database;
  late FixedClock clock;
  var ids = 0;

  setUp(() async {
    database = await AppDatabase.inMemory();
    clock = FixedClock(DateTime.utc(2026, 10, 3, 9));
    ids = 0;
  });

  tearDown(() => database.close());

  Future<PresetsCubit> loaded() async {
    final cubit = PresetsCubit(
      repository: PresetsRepository(
        database: database,
        loadBuiltInJson: loadBuiltInPresetsFromFile,
      ),
      clock: clock,
      newId: () => 'id-${++ids}',
    );
    await cubit.load();
    return cubit;
  }

  const template = {
    'notification': {'title': '{{title}}'},
  };
  const variables = [VariableDef(key: 'title')];

  test('loads the four built-in presets as read-only', () async {
    final cubit = await loaded();
    expect(cubit.state.status, PresetsStatus.ready);
    expect(cubit.state.builtIns, hasLength(116));
    expect(cubit.state.builtIns.every((p) => p.builtIn), isTrue);
    expect(cubit.state.userPresets, isEmpty);
    expect(cubit.state.byId('builtin.simple')?.name, 'Simple notification');
  });

  test('Save as stores a new preset that survives a restart', () async {
    final cubit = await loaded();
    final saved = await cubit.saveAs(
      name: ' Order update ',
      template: template,
      variables: variables,
    );
    expect(saved.name, 'Order update');
    expect(saved.id, 'id-1');
    expect(saved.createdAt, clock.now());
    expect(cubit.state.userPresets, [saved]);

    final restarted = await loaded();
    expect(restarted.state.userPresets, [saved]);
  });

  test(
    'Update overwrites a user preset; built-in presets are read-only',
    () async {
      final cubit = await loaded();
      final saved = await cubit.saveAs(
        name: 'A',
        template: template,
        variables: variables,
      );
      clock.advance(const Duration(minutes: 1));
      final updated = await cubit.update(
        saved.id,
        template: const {
          'notification': {'title': 'Fixed'},
        },
        variables: const [],
      );
      expect(cubit.state.userPresets.single, updated);
      expect(updated.updatedAt, clock.now());
      expect(updated.createdAt, saved.createdAt);
      await expectLater(
        cubit.update(
          cubit.state.builtIns.first.id,
          template: template,
          variables: variables,
        ),
        throwsStateError,
      );
      await expectLater(
        cubit.update('missing', template: template, variables: variables),
        throwsStateError,
      );
    },
  );

  test('Update keeps the stored name and description', () async {
    final cubit = await loaded();
    final saved = await cubit.saveAs(
      name: 'A',
      template: template,
      variables: variables,
    );
    await cubit.rename(saved, name: 'B', description: 'Renamed', group: 'G');
    final updated = await cubit.update(
      saved.id,
      template: const {
        'notification': {'title': 'Fixed'},
      },
      variables: variables,
    );
    expect(updated.name, 'B');
    expect(updated.description, 'Renamed');
    expect(updated.group, 'G');
    expect(updated.createdAt, saved.createdAt);
    expect(cubit.state.userPresets.single, updated);
  });

  test('Save as and Update refuse a template that sets the target', () async {
    expect(
      Preset.templateProblem(const {
        'topic': 'news',
        'notification': <String, Object?>{},
      }),
      'The template sets "topic"; remove it — the target is set in the '
      'Target field.',
    );
    expect(Preset.templateProblem(template), isNull);

    final cubit = await loaded();
    await expectLater(
      cubit.saveAs(
        name: 'With token',
        template: const {'token': 'abc', ...template},
        variables: const [],
      ),
      throwsA(
        isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('"token"'),
        ),
      ),
    );
    expect(cubit.state.userPresets, isEmpty);

    final saved = await cubit.saveAs(
      name: 'A',
      template: template,
      variables: variables,
    );
    await expectLater(
      cubit.update(
        saved.id,
        template: const {'condition': "'a' in topics", ...template},
        variables: variables,
      ),
      throwsArgumentError,
    );
    final restarted = await loaded();
    expect(restarted.state.userPresets, [saved]);
  });

  test('a stored preset that cannot be read is skipped', () async {
    final cubit = await loaded();
    final saved = await cubit.saveAs(
      name: 'A',
      template: template,
      variables: variables,
    );
    final store = stringMapStoreFactory.store('presets');
    await store.record('bad-template').put(database.db, {
      ...saved.toJson(),
      'id': 'bad-template',
      'name': 'Bad',
      'template': {'token': 'abc'},
    });
    await store.record('bad-types').put(database.db, {
      'id': 'bad-types',
      'name': 42,
    });

    final restarted = await loaded();
    expect(restarted.state.status, PresetsStatus.ready);
    expect(restarted.state.builtIns, hasLength(116));
    expect(restarted.state.userPresets, [saved]);
  });

  test('the built-in presets load even when the user presets cannot', () async {
    final cubit = PresetsCubit(repository: _BrokenUserPresets(database));
    await expectLater(cubit.load(), throwsStateError);
    expect(cubit.state.status, PresetsStatus.ready);
    expect(cubit.state.builtIns, hasLength(116));
  });

  test('duplicate makes an editable copy with a free name', () async {
    final cubit = await loaded();
    final simple = cubit.state.byId('builtin.simple')!;
    final first = await cubit.duplicate(simple);
    final second = await cubit.duplicate(simple);
    expect(first.name, 'Simple notification (copy)');
    expect(second.name, 'Simple notification (copy) (2)');
    expect(first.builtIn, isFalse);
    expect(first.template, simple.template);
  });

  test('rename, nameTaken and delete', () async {
    final cubit = await loaded();
    final saved = await cubit.saveAs(
      name: 'A',
      template: template,
      variables: variables,
    );
    expect(cubit.state.nameTaken('a'), isTrue);
    expect(cubit.state.nameTaken('a', exceptId: saved.id), isFalse);
    expect(cubit.state.nameTaken('SIMPLE NOTIFICATION'), isFalse);
    expect(
      cubit.state.nameTaken('SIMPLE NOTIFICATION', group: ' generic '),
      isTrue,
    );

    final renamed = await cubit.rename(
      saved,
      name: 'B',
      description: 'Mine',
      group: '',
    );
    expect(cubit.state.userPresets.single.name, 'B');
    expect(cubit.state.userPresets.single.description, 'Mine');

    await cubit.delete(renamed);
    await cubit.delete(cubit.state.builtIns.first);
    expect(cubit.state.userPresets, isEmpty);
    expect(cubit.state.builtIns, hasLength(116));
  });

  test('export includes built-in presets, as normal presets', () async {
    final cubit = await loaded();
    await cubit.saveAs(name: 'A', template: template, variables: variables);
    final exported = PresetCodec.decode(cubit.exportText(cubit.state.all));
    expect(exported, hasLength(117));
    expect(
      exported.map((p) => p.name),
      containsAll(['A', 'Simple notification']),
    );
    expect(exported.any((p) => p.builtIn), isFalse);
  });

  test(
    'import with Replace overwrites user presets but never built-in ones',
    () async {
      final cubit = await loaded();
      final saved = await cubit.saveAs(
        name: 'A',
        template: template,
        variables: variables,
      );
      final file = PresetCodec.encode([
        saved.copyWith(
          template: const {
            'notification': {'title': 'Imported'},
          },
        ),
        saved.copyWith(id: 'x', name: 'Simple notification', group: 'Generic'),
      ], exportedAt: clock.now());

      final preview = cubit.previewImport(file);
      expect(preview.conflicts, ['A', 'Generic › Simple notification']);

      expect(await cubit.applyImport(preview, ImportConflictChoice.replace), 2);
      expect(cubit.state.userPresets.map((p) => p.name), [
        'A',
        'Simple notification (2)',
      ]);
      expect(cubit.state.userPresets.first.template, {
        'notification': {'title': 'Imported'},
      });
      expect(cubit.state.byId('builtin.simple')?.name, 'Simple notification');
    },
  );

  test('a newer presets file is rejected and nothing is imported', () async {
    final cubit = await loaded();
    expect(
      () => cubit.previewImport(
        jsonEncode({
          'format': PresetCodec.format,
          'version': 9,
          'presets': <Object?>[],
        }),
      ),
      throwsA(isA<PresetFormatException>()),
    );
    expect(cubit.state.userPresets, isEmpty);
  });

  test(
    'Save as and rename store the group trimmed; duplicate keeps it',
    () async {
      final cubit = await loaded();
      final saved = await cubit.saveAs(
        name: 'A',
        group: ' StackFood ',
        template: template,
        variables: variables,
      );
      expect(saved.group, 'StackFood');

      final moved = await cubit.rename(
        saved,
        name: 'A',
        description: '',
        group: ' Food ',
      );
      expect(moved.group, 'Food');

      final copy = await cubit.duplicate(cubit.state.byId('builtin.simple')!);
      expect(copy.group, 'Generic');

      final restarted = await loaded();
      expect(
        restarted.state.userPresets.map((p) => p.group),
        unorderedEquals(['Food', 'Generic']),
      );
    },
  );
}
