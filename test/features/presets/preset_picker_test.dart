import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/view/preset_details_dialog.dart';
import 'package:fcm_studio/features/presets/view/preset_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  Future<void> pickPreset(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(PresetPicker.dropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('picking a built-in preset loads its template and variables', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    await pickPreset(tester, 'Simple notification (built-in)');
    expect(composer.state.preset?.id, 'builtin.simple');
    expect(find.byKey(const ValueKey('variable-title')), findsOneWidget);
    expect(find.text('Hello from FCM Studio'), findsWidgets);
  });

  testWidgets('an edit shows the dot; Save as stores a preset and clears it', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final presets = readCubit<PresetsCubit>(tester);
    composer
      ..loadPreset(presets.state.byId('builtin.simple')!)
      ..setField(['notification', 'body'], 'Changed');
    await tester.pump();
    expect(find.text('• Simple notification (built-in)'), findsOneWidget);

    await tester.tap(find.byKey(PresetPicker.saveAsKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(PresetDetailsDialog.nameKey),
      'My order message',
    );
    await tester.tap(find.byKey(PresetDetailsDialog.saveKey));
    await settleAsync(tester);

    expect(presets.state.userPresets.single.name, 'My order message');
    expect(composer.state.preset?.name, 'My order message');
    expect(composer.state.isDirty, isFalse);
    expect(find.text('My order message'), findsOneWidget);
  });

  testWidgets('Save as refuses a name that is already used', (tester) async {
    await pumpAppWithProject(tester);
    await tester.tap(find.byKey(PresetPicker.saveAsKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(PresetDetailsDialog.nameKey),
      'simple notification',
    );
    await tester.tap(find.byKey(PresetDetailsDialog.saveKey));
    await tester.pump();
    expect(
      find.text('A preset named "simple notification" already exists.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Update preset is off for built-ins and overwrites a user preset',
    (tester) async {
      final (_, composer) = await pumpAppWithProject(tester);
      final presets = readCubit<PresetsCubit>(tester);
      OutlinedButton update() =>
          tester.widget<OutlinedButton>(find.byKey(PresetPicker.updateKey));

      composer
        ..loadPreset(presets.state.byId('builtin.simple')!)
        ..setField(['notification', 'body'], 'Changed');
      await tester.pump();
      expect(update().onPressed, isNull);

      final mine = (await tester.runAsync(
        () => presets.saveAs(
          name: 'Mine',
          template: const {
            'notification': {'title': 'A'},
          },
          variables: const [],
        ),
      ))!;
      composer
        ..loadPreset(mine)
        ..setField(['notification', 'title'], 'B');
      await tester.pump();
      expect(update().onPressed, isNotNull);

      await tester.tap(find.byKey(PresetPicker.updateKey));
      await settleAsync(tester);
      expect(presets.state.userPresets.single.template, {
        'notification': {'title': 'B'},
      });
      expect(composer.state.isDirty, isFalse);
    },
  );

  testWidgets(
    'Save as refuses a template that sets the target and saves nothing',
    (tester) async {
      final (_, composer) = await pumpAppWithProject(tester);
      final presets = readCubit<PresetsCubit>(tester);
      composer.updateTemplateText(
        '{"token": "abc", "notification": {"title": "Hi"}}',
      );
      await tester.pump();

      await tester.tap(find.byKey(PresetPicker.saveAsKey));
      await tester.pumpAndSettle();
      expect(find.byType(PresetDetailsDialog), findsNothing);
      expect(
        find.text(
          'The template sets "token"; remove it — the target is set in the '
          'Target field.',
        ),
        findsOneWidget,
      );
      await settleAsync(tester);
      expect(presets.state.userPresets, isEmpty);
    },
  );

  testWidgets('Update refuses a template that sets the target', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final presets = readCubit<PresetsCubit>(tester);
    final mine = (await tester.runAsync(
      () => presets.saveAs(
        name: 'Mine',
        template: const {
          'notification': {'title': 'A'},
        },
        variables: const [],
      ),
    ))!;
    composer
      ..loadPreset(mine)
      ..updateTemplateText('{"topic": "news", "notification": {"title": "A"}}');
    await tester.pump();

    await tester.tap(find.byKey(PresetPicker.updateKey));
    await settleAsync(tester);
    expect(
      find.text(
        'The template sets "topic"; remove it — the target is set in the '
        'Target field.',
      ),
      findsOneWidget,
    );
    expect(presets.state.userPresets.single, mine);
    expect(composer.state.isDirty, isTrue);
  });

  testWidgets('Update with invalid JSON says to fix it first', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final presets = readCubit<PresetsCubit>(tester);
    final mine = (await tester.runAsync(
      () => presets.saveAs(
        name: 'Mine',
        template: const {
          'notification': {'title': 'A'},
        },
        variables: const [],
      ),
    ))!;
    composer
      ..loadPreset(mine)
      ..updateTemplateText('{"notification": ');
    await tester.pump();

    await tester.tap(find.byKey(PresetPicker.updateKey));
    await settleAsync(tester);
    expect(
      find.text('Fix the JSON before saving it as a preset.'),
      findsOneWidget,
    );
    expect(presets.state.userPresets.single, mine);
  });

  testWidgets('switching presets with unsaved changes asks first', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final presets = readCubit<PresetsCubit>(tester);
    composer
      ..loadPreset(presets.state.byId('builtin.simple')!)
      ..setField(['notification', 'body'], 'Changed');
    await tester.pump();

    await pickPreset(tester, 'Data only (silent / background) (built-in)');
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(composer.state.preset?.id, 'builtin.simple');

    await pickPreset(tester, 'Data only (silent / background) (built-in)');
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(composer.state.preset?.id, 'builtin.data_only');
  });
}
