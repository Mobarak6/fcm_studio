import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/view/preset_details_dialog.dart';
import 'package:fcm_studio/features/presets/view/preset_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

Finder get searchField => find.descendant(
  of: find.byKey(PresetPicker.dropdownKey),
  matching: find.byType(TextField),
);

Finder menuEntry(String label) =>
    find.widgetWithText(MenuItemButton, label).hitTestable();

String fieldText(WidgetTester tester) =>
    tester.widget<TextField>(searchField).controller!.text;

void main() {
  Future<void> search(WidgetTester tester, String text) async {
    await tester.tap(searchField);
    await tester.pumpAndSettle();
    await tester.enterText(searchField, text);
    await tester.pumpAndSettle();
  }

  Future<void> pickPreset(WidgetTester tester, String label) async {
    await search(tester, label);
    await tester.tap(menuEntry(label));
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

  testWidgets('typed words match in any order, ignoring case', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    await search(tester, 'CHAT store');
    expect(menuEntry('Store app · Chat message (built-in)'), findsOneWidget);
    expect(menuEntry('User app · Chat message (built-in)'), findsNothing);
    expect(menuEntry('Simple notification (built-in)'), findsNothing);

    await tester.tap(menuEntry('Store app · Chat message (built-in)'));
    await tester.pumpAndSettle();
    expect(composer.state.preset?.id, 'builtin.6ammart.store.message');
  });

  testWidgets('my presets are listed before the built-in ones', (tester) async {
    await pumpAppWithProject(tester);
    await tester.runAsync(
      () => readCubit<PresetsCubit>(tester).saveAs(
        name: 'Mine',
        template: const {
          'notification': {'title': 'A'},
        },
        variables: const [],
      ),
    );
    await tester.pump();
    await tester.tap(searchField);
    await tester.pumpAndSettle();
    double top(Finder finder) => tester.getTopLeft(finder).dy;
    expect(top(menuEntry('No group')), lessThan(top(menuEntry('Mine'))));
    expect(top(menuEntry('Mine')), lessThan(top(menuEntry('6amMart'))));
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
    // The field shows the preset that is still loaded, with its dot.
    expect(fieldText(tester), '• Simple notification (built-in)');

    await pickPreset(tester, 'Data only (silent / background) (built-in)');
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(composer.state.preset?.id, 'builtin.data_only');
  });

  testWidgets("Save as starts with the loaded preset's group", (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final presets = readCubit<PresetsCubit>(tester);
    composer
      ..loadPreset(presets.state.byId('builtin.simple')!)
      ..setField(['notification', 'body'], 'Changed');
    await tester.pump();

    await tester.tap(find.byKey(PresetPicker.saveAsKey));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(PresetDetailsDialog.groupKey))
          .controller!
          .text,
      'Generic',
    );
    await tester.enterText(find.byKey(PresetDetailsDialog.nameKey), 'Mine');
    await tester.tap(find.byKey(PresetDetailsDialog.saveKey));
    await settleAsync(tester);
    expect(presets.state.userPresets.single.group, 'Generic');
  });

  testWidgets('the Group field suggests existing groups and trims', (
    tester,
  ) async {
    await pumpAppWithProject(tester);
    final presets = readCubit<PresetsCubit>(tester);
    await tester.tap(find.byKey(PresetPicker.saveAsKey));
    await tester.pumpAndSettle();
    final group = find.byKey(PresetDetailsDialog.groupKey);
    Finder suggestion(String text) => find.widgetWithText(InkWell, text);

    await tester.enterText(group, '6AM');
    await tester.pumpAndSettle();
    expect(suggestion('6amMart'), findsOneWidget);
    expect(suggestion('Generic'), findsNothing);

    await tester.tap(suggestion('6amMart'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(group).controller!.text, '6amMart');
    expect(
      suggestion('6amMart'),
      findsNothing,
      reason: 'the group typed exactly is not suggested',
    );

    await tester.enterText(group, '  StackFood ');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PresetDetailsDialog.nameKey), 'Mine');
    await tester.tap(find.byKey(PresetDetailsDialog.saveKey));
    await settleAsync(tester);
    expect(presets.state.userPresets.single.group, 'StackFood');
  });

  testWidgets('the group suggestions never cover Save', (tester) async {
    await pumpAppWithProject(tester);
    final presets = readCubit<PresetsCubit>(tester);
    await tester.tap(find.byKey(PresetPicker.saveAsKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PresetDetailsDialog.nameKey), 'Mine');
    await tester.tap(find.byKey(PresetDetailsDialog.groupKey));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InkWell, '6amMart'), findsOneWidget);

    await tester.tap(find.byKey(PresetDetailsDialog.saveKey).hitTestable());
    await settleAsync(tester);
    expect(presets.state.userPresets.single.name, 'Mine');
  });

  testWidgets('presets are listed under their group headers', (tester) async {
    await pumpAppWithProject(tester);
    await tester.tap(searchField);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(menuEntry('6amMart')).dy,
      lessThan(
        tester.getTopLeft(menuEntry('User app · Order status (built-in)')).dy,
      ),
    );
  });

  testWidgets('the search matches group names and hides empty groups', (
    tester,
  ) async {
    await pumpAppWithProject(tester);
    await search(tester, '6ammart chat');
    expect(menuEntry('6amMart'), findsOneWidget);
    expect(menuEntry('User app · Chat message (built-in)'), findsOneWidget);
    expect(menuEntry('Delivery app · Chat message (built-in)'), findsOneWidget);
    expect(menuEntry('Store app · Chat message (built-in)'), findsOneWidget);
    expect(menuEntry('Generic'), findsNothing);

    await tester.enterText(searchField, 'generic');
    await tester.pumpAndSettle();
    expect(menuEntry('Generic'), findsOneWidget);
    expect(menuEntry('Simple notification (built-in)'), findsOneWidget);
    expect(
      menuEntry('Data only (silent / background) (built-in)'),
      findsOneWidget,
    );
    expect(menuEntry('6amMart'), findsNothing);

    await tester.enterText(searchField, 'zzz');
    await tester.pumpAndSettle();
    expect(menuEntry('Generic'), findsNothing);
    expect(menuEntry('6amMart'), findsNothing);
  });

  testWidgets('a group header cannot be picked', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    await tester.tap(searchField);
    await tester.pumpAndSettle();
    expect(
      tester.widget<MenuItemButton>(menuEntry('6amMart')).onPressed,
      isNull,
    );
    await tester.tap(menuEntry('6amMart'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(composer.state.preset, isNull);
  });

  testWidgets('Enter in the Group field saves what was typed', (tester) async {
    await pumpAppWithProject(tester);
    final presets = readCubit<PresetsCubit>(tester);
    await tester.tap(find.byKey(PresetPicker.saveAsKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PresetDetailsDialog.nameKey), 'Mine');
    await tester.enterText(find.byKey(PresetDetailsDialog.groupKey), '6am');
    await tester.pumpAndSettle();
    expect(find.widgetWithText(InkWell, '6amMart'), findsOneWidget);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settleAsync(tester);
    expect(find.byType(PresetDetailsDialog), findsNothing);
    expect(
      presets.state.userPresets.single.group,
      '6am',
      reason: 'Enter never swaps in a suggestion',
    );
  });
}
