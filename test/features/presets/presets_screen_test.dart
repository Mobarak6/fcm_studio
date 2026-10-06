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
    String name, {
    String group = '',
  }) async {
    final saved = (await tester.runAsync(
      () => presets.saveAs(
        name: name,
        group: group,
        template: const {
          'notification': {'title': 'A'},
        },
        variables: const [],
      ),
    ))!;
    await tester.pump();
    return saved;
  }

  Finder header(String key) => find.byKey(ValueKey('preset-group-$key'));

  /// Closes the long 6amMart section, so the Generic presets below it show.
  Future<void> close6amMart(WidgetTester tester) async {
    await tester.tap(header('6ammart'));
    await tester.pumpAndSettle();
  }

  testWidgets("lists the built-in presets and the user's own", (tester) async {
    final (_, presets, _) = await openPresets(tester);
    await saveMine(tester, presets, 'Mine');
    await close6amMart(tester);
    expect(find.text('Simple notification'), findsOneWidget);
    expect(find.text('Data only (silent / background)'), findsOneWidget);
    expect(find.text('Mine'), findsOneWidget);
  });

  testWidgets('presets are listed by group, groups with yours first', (
    tester,
  ) async {
    final (_, presets, _) = await openPresets(tester);
    await saveMine(tester, presets, 'Ours', group: 'MyShop');
    await saveMine(tester, presets, 'Mine');
    double top(Finder finder) => tester.getTopLeft(finder).dy;
    expect(top(header('myshop')), lessThan(top(find.text('Ours'))));
    expect(top(find.text('Ours')), lessThan(top(header(''))));
    expect(top(header('')), lessThan(top(find.text('Mine'))));
    expect(top(find.text('Mine')), lessThan(top(header('6ammart'))));
    expect(
      find.descendant(of: header(''), matching: find.text('No group')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: header('6ammart'), matching: find.text('23')),
      findsOneWidget,
    );
  });

  testWidgets('a section closes and opens again', (tester) async {
    await openPresets(tester);
    expect(find.text('User app · Order status'), findsOneWidget);

    await close6amMart(tester);
    expect(find.text('User app · Order status'), findsNothing);
    expect(
      tester.getTopLeft(header('6ammart')).dy,
      lessThan(tester.getTopLeft(header('generic')).dy),
    );

    await tester.tap(header('6ammart'));
    await tester.pumpAndSettle();
    expect(find.text('User app · Order status'), findsOneWidget);
  });

  testWidgets('the group checkbox ticks and unticks all of its presets', (
    tester,
  ) async {
    final (_, _, files) = await openPresets(tester);
    final groupBox = find.byKey(const ValueKey('preset-group-check-6ammart'));
    bool? ticked() => tester.widget<Checkbox>(groupBox).value;
    expect(ticked(), isFalse);

    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey('preset-builtin.6ammart.user.order_status'),
        ),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();
    expect(ticked(), isNull, reason: 'some are ticked: a dash');
    expect(find.text('Export 1'), findsOneWidget);

    await tester.tap(groupBox);
    await tester.pump();
    expect(ticked(), isTrue);
    expect(find.text('Export 23'), findsOneWidget);

    await tester.tap(find.byKey(PresetsScreen.exportKey));
    await settleAsync(tester);
    final exported = PresetCodec.decode(files.saved.single.text);
    expect(exported, hasLength(23));
    expect(exported.every((p) => p.group == '6amMart'), isTrue);

    await tester.tap(groupBox);
    await tester.pump();
    expect(ticked(), isFalse);
    expect(find.text('Export all'), findsOneWidget);
  });

  testWidgets('Edit details… moves a preset to another group', (tester) async {
    final (_, presets, _) = await openPresets(tester);
    final mine = await saveMine(tester, presets, 'Mine');
    expect(header(''), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('preset-menu-${mine.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit details…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PresetDetailsDialog.groupKey), 'MyShop');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PresetDetailsDialog.saveKey));
    await settleAsync(tester);

    expect(presets.state.userPresets.single.group, 'MyShop');
    expect(header(''), findsNothing, reason: 'No group is empty now');
    expect(
      tester.getTopLeft(header('myshop')).dy,
      lessThan(tester.getTopLeft(find.text('Mine')).dy),
    );
  });

  testWidgets('Open in composer loads the preset and shows the composer', (
    tester,
  ) async {
    final (composer, _, _) = await openPresets(tester);
    await close6amMart(tester);
    await tester.tap(find.text('Notification + data'));
    await tester.pumpAndSettle();
    expect(composer.state.preset?.id, 'builtin.notification_data');
    expect(readCubit<NavigationCubit>(tester).state, AppSection.composer);
  });

  testWidgets('Duplicate makes an editable copy', (tester) async {
    final (_, presets, _) = await openPresets(tester);
    await close6amMart(tester);
    await tester.tap(find.byKey(const ValueKey('preset-menu-builtin.simple')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await settleAsync(tester);
    expect(presets.state.userPresets.single.name, 'Simple notification (copy)');
    expect(find.text('Simple notification (copy)'), findsOneWidget);
  });

  testWidgets('Export all saves every preset, built-in ones included', (
    tester,
  ) async {
    final (_, presets, files) = await openPresets(tester);
    await saveMine(tester, presets, 'My alerts');
    await tester.tap(find.byKey(PresetsScreen.exportKey));
    await settleAsync(tester);
    expect(files.saved.single.name, 'fcm-studio-presets.fcmpresets.json');
    final exported = PresetCodec.decode(files.saved.single.text);
    expect(exported, hasLength(56));
    expect(exported.first.name, 'My alerts');
    expect(exported.map((p) => p.name), contains('Store app · New order'));
    // They import as normal, editable presets.
    expect(exported.any((p) => p.builtIn), isFalse);
  });

  testWidgets('Export all works before you have presets of your own', (
    tester,
  ) async {
    final (_, _, files) = await openPresets(tester);
    await tester.tap(find.byKey(PresetsScreen.exportKey));
    await settleAsync(tester);
    expect(PresetCodec.decode(files.saved.single.text), hasLength(55));
  });

  testWidgets('a ticked built-in preset is exported on its own', (
    tester,
  ) async {
    final (_, _, files) = await openPresets(tester);
    await close6amMart(tester);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('preset-builtin.simple')),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();
    expect(find.text('Export 1'), findsOneWidget);

    await tester.tap(find.byKey(PresetsScreen.exportKey));
    await settleAsync(tester);
    expect(files.saved.single.name, 'simple-notification.fcmpresets.json');
    expect(PresetCodec.decode(files.saved.single.text).map((p) => p.name), [
      'Simple notification',
    ]);
  });

  testWidgets("a built-in preset's menu offers Export…", (tester) async {
    final (_, _, files) = await openPresets(tester);
    await close6amMart(tester);
    await tester.tap(find.byKey(const ValueKey('preset-menu-builtin.simple')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Export…'));
    await settleAsync(tester);
    expect(files.saved.single.name, 'simple-notification.fcmpresets.json');
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
    await tester.tap(find.text('Edit details…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PresetDetailsDialog.nameKey), 'Renamed');
    expect(
      tester
          .widget<TextField>(find.byKey(PresetDetailsDialog.groupKey))
          .controller!
          .text,
      '',
    );
    await tester.enterText(find.byKey(PresetDetailsDialog.groupKey), 'Ops');
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
    expect(stored.group, 'Ops');
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
