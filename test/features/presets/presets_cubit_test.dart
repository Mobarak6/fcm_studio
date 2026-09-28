import 'dart:convert';

import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/data/presets_repository.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/presets_fixture.dart';

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
    expect(cubit.state.builtIns, hasLength(4));
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
        saved,
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
          cubit.state.builtIns.first,
          template: template,
          variables: variables,
        ),
        throwsStateError,
      );
    },
  );

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
    expect(cubit.state.nameTaken('SIMPLE NOTIFICATION'), isTrue);

    final renamed = await cubit.rename(saved, name: 'B', description: 'Mine');
    expect(cubit.state.userPresets.single.name, 'B');
    expect(cubit.state.userPresets.single.description, 'Mine');

    await cubit.delete(renamed);
    await cubit.delete(cubit.state.builtIns.first);
    expect(cubit.state.userPresets, isEmpty);
    expect(cubit.state.builtIns, hasLength(4));
  });

  test('export leaves out built-in presets', () async {
    final cubit = await loaded();
    await cubit.saveAs(name: 'A', template: template, variables: variables);
    final text = cubit.exportText(cubit.state.all);
    expect(PresetCodec.decode(text).map((p) => p.name), ['A']);
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
        saved.copyWith(id: 'x', name: 'Simple notification'),
      ], exportedAt: clock.now());

      final preview = cubit.previewImport(file);
      expect(preview.conflicts, ['A', 'Simple notification']);

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
}
