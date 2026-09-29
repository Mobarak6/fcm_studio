import 'dart:convert';

import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/view/preset_details_dialog.dart';
import 'package:fcm_studio/features/presets/view/preset_picker.dart';
import 'package:fcm_studio/features/presets/view/presets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_file_access.dart';
import '../../helpers/keyboard.dart';

void main() {
  Future<(ComposerCubit, PresetsCubit, FakeFileAccess)> openPresets(
    WidgetTester tester,
  ) async {
    final files = FakeFileAccess();
    final (_, composer) = await pumpAppWithProject(tester, files: files);
    await tester.tap(find.byKey(const Key('nav-presets')));
    await tester.pumpAndSettle();
    return (composer, readCubit<PresetsCubit>(tester), files);
  }

  Future<Preset> saveMine(
    WidgetTester tester,
    PresetsCubit presets,
    String name,
  ) async {
    final saved = (await tester.runAsync(
      () => presets.saveAs(
        name: name,
        template: const {
          'notification': {'title': 'A'},
        },
        variables: const [],
      ),
    ))!;
    await tester.pump();
    return saved;
  }

  testWidgets("lists the built-in presets and the user's own", (tester) async {
    final (_, presets, _) = await openPresets(tester);
    await saveMine(tester, presets, 'Mine');
    expect(find.text('Simple notification'), findsOneWidget);
    expect(find.text('Data only (silent / background)'), findsOneWidget);
    expect(find.text('Mine'), findsOneWidget);
  });

  testWidgets('Open in composer loads the preset and shows the composer', (
    tester,
  ) async {
    final (composer, _, _) = await openPresets(tester);
    await tester.tap(find.text('Notification + data'));
    await tester.pumpAndSettle();
    expect(composer.state.preset?.id, 'builtin.notification_data');
    expect(readCubit<NavigationCubit>(tester).state, AppSection.composer);
  });

  testWidgets('Duplicate makes an editable copy', (tester) async {
    final (_, presets, _) = await openPresets(tester);
    await tester.tap(find.byKey(const ValueKey('preset-menu-builtin.simple')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await settleAsync(tester);
    expect(presets.state.userPresets.single.name, 'Simple notification (copy)');
    expect(find.text('Simple notification (copy)'), findsOneWidget);
  });

  testWidgets('Export all saves a presets file without the built-in ones', (
    tester,
  ) async {
    final (_, presets, files) = await openPresets(tester);
    await saveMine(tester, presets, 'My alerts');
    await tester.tap(find.byKey(PresetsScreen.exportKey));
    await settleAsync(tester);
    expect(files.saved.single.name, 'my-alerts.fcmpresets.json');
    expect(PresetCodec.decode(files.saved.single.text).map((p) => p.name), [
      'My alerts',
    ]);
  });

  testWidgets('Import asks about name conflicts and can keep both', (
    tester,
  ) async {
    final (_, presets, files) = await openPresets(tester);
    final mine = await saveMine(tester, presets, 'Mine');
    files.nextOpen = PresetCodec.encode([mine], exportedAt: DateTime.utc(2026));

    await tester.tap(find.byKey(PresetsScreen.importKey));
    await tester.pumpAndSettle();
    expect(find.text('Some presets already exist'), findsOneWidget);
    await tester.tap(find.text('Keep both'));
    await settleAsync(tester);

    expect(presets.state.userPresets.map((p) => p.name), ['Mine', 'Mine (2)']);
    expect(find.text('Imported 1 preset.'), findsOneWidget);
  });

  testWidgets('a newer presets file is explained and nothing is imported', (
    tester,
  ) async {
    final (_, presets, files) = await openPresets(tester);
    files.nextOpen = jsonEncode({
      'format': PresetCodec.format,
      'version': 2,
      'presets': <Object?>[],
    });
    await tester.tap(find.byKey(PresetsScreen.importKey));
    await tester.pumpAndSettle();
    expect(find.text("Can't import this file"), findsOneWidget);
    expect(find.textContaining('newer FCM Studio'), findsOneWidget);
    expect(presets.state.userPresets, isEmpty);
  });

  testWidgets('deleting the preset loaded in the composer detaches it', (
    tester,
  ) async {
    final (composer, presets, _) = await openPresets(tester);
    final mine = await saveMine(tester, presets, 'Mine');
    composer.loadPreset(mine);

    await tester.tap(find.byKey(ValueKey('preset-menu-${mine.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await settleAsync(tester);

    expect(presets.state.userPresets, isEmpty);
    expect(composer.state.preset, isNull);
  });

  testWidgets('renaming the loaded preset survives a later Update', (
    tester,
  ) async {
    final (composer, presets, _) = await openPresets(tester);
    final mine = await saveMine(tester, presets, 'Mine');
    composer
      ..loadPreset(mine)
      ..setField(['notification', 'title'], 'B');

    await tester.tap(find.byKey(ValueKey('preset-menu-${mine.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PresetDetailsDialog.nameKey), 'Renamed');
    await tester.tap(find.byKey(PresetDetailsDialog.saveKey));
    await settleAsync(tester);
    expect(composer.state.preset?.name, 'Renamed');
    expect(composer.state.isDirty, isTrue, reason: 'the edit is kept');

    await tester.tap(find.byKey(const Key('nav-composer')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PresetPicker.updateKey));
    await settleAsync(tester);

    final stored = presets.state.userPresets.single;
    expect(stored.name, 'Renamed');
    expect(stored.template, {
      'notification': {'title': 'B'},
    });
    expect(composer.state.preset, stored);
    expect(composer.state.isDirty, isFalse);
  });

  testWidgets('a Replace import of the loaded preset shows the new version', (
    tester,
  ) async {
    final (composer, presets, files) = await openPresets(tester);
    final mine = await saveMine(tester, presets, 'Mine');
    composer.loadPreset(mine);
    files.nextOpen = PresetCodec.encode([
      mine.copyWith(
        template: const {
          'notification': {'title': 'Imported'},
        },
      ),
    ], exportedAt: DateTime.utc(2026));

    await tester.tap(find.byKey(PresetsScreen.importKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Replace'));
    await settleAsync(tester);

    const imported = {
      'notification': {'title': 'Imported'},
    };
    expect(presets.state.userPresets.single.template, imported);
    expect(composer.state.template, imported);
    expect(composer.state.preset, presets.state.userPresets.single);
    expect(composer.state.isDirty, isFalse);
    expect(editorController(tester).text, contains('Imported'));
  });
}
