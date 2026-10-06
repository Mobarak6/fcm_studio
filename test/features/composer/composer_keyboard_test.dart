import 'dart:convert';

import 'package:fcm_studio/features/composer/view/send_panel.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/view/preset_details_dialog.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:re_editor/re_editor.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/keyboard.dart';
import '../../helpers/service_account_fixture.dart';

// re_editor picks its key handling from the platform once per test file, so these
// desktop keyboard tests live in their own file and all run as Windows.
final _windows = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  const token = 'abc:APA91bxyz';

  testWidgets(
    'Ctrl+Enter in the JSON editor sends instead of adding a new line',
    (tester) async {
      final requests = <http.Request>[];
      final (_, composer) = await pumpAppWithProject(
        tester,
        onFcmRequest: requests.add,
      );
      composer.setTargetValue(token);
      await tester.pump();
      final textBefore = editorController(tester).text;

      await showJsonTab(tester);
      await tester.tap(find.byType(CodeEditor));
      await tester.pump();
      await pressWithEnter(tester, LogicalKeyboardKey.controlLeft);
      await settle(tester);

      expect(requests, hasLength(1));
      expect(editorController(tester).text, textBefore);
    },
    variant: _windows,
  );

  testWidgets('an edit is sent even when Send follows immediately', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final (_, composer) = await pumpAppWithProject(
      tester,
      onFcmRequest: requests.add,
    );
    composer.setTargetValue(token);
    await tester.pump();

    editorController(tester).text =
        '{"notification": {"title": "Fresh title"}}';
    await tester.tap(find.byKey(SendPanel.sendButtonKey));
    await settle(tester);

    expect(requests, hasLength(1));
    final sent = jsonDecode(requests.single.body) as Map<String, dynamic>;
    expect((sent['message'] as Map<String, dynamic>)['notification'], {
      'title': 'Fresh title',
    });
  }, variant: _windows);

  testWidgets('holding Ctrl+Enter sends only once', (tester) async {
    final requests = <http.Request>[];
    final (_, composer) = await pumpAppWithProject(
      tester,
      onFcmRequest: requests.add,
    );
    composer.setTargetValue(token);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.enter);
    await settle(tester);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);

    expect(requests, hasLength(1));
  }, variant: _windows);

  testWidgets(
    'Ctrl+S updates the loaded user preset, even from inside the JSON editor',
    (tester) async {
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
        ..setField(['notification', 'title'], 'B');
      await tester.pump();
      await showJsonTab(tester);
      await tester.tap(find.byType(CodeEditor));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settleAsync(tester);

      expect(presets.state.userPresets.single.template, {
        'notification': {'title': 'B'},
      });
      expect(composer.state.isDirty, isFalse);
    },
    variant: _windows,
  );

  testWidgets(
    'Ctrl+S with a user preset loaded and nothing changed writes nothing',
    (tester) async {
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
      composer.loadPreset(mine);
      await tester.pump();
      // Real time passes, so a write would change updatedAt.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settleAsync(tester);

      expect(find.byType(PresetDetailsDialog), findsNothing);
      expect(presets.state.userPresets.single, mine);
      expect(presets.state.userPresets.single.updatedAt, mine.updatedAt);
    },
    variant: _windows,
  );

  testWidgets(
    'Ctrl+Enter sends after opening a preset from the Presets screen',
    (tester) async {
      final requests = <http.Request>[];
      final (_, composer) = await pumpAppWithProject(
        tester,
        onFcmRequest: requests.add,
      );
      composer.setTargetValue(token);
      await tester.pump();

      await tester.tap(find.byKey(const Key('nav-presets')));
      await tester.pumpAndSettle();
      // Close the product sections; the Generic presets are below them.
      for (final key in ['6ammart', '6valley', 'demandium', 'drivemond']) {
        await tester.tap(find.byKey(ValueKey('preset-group-$key')));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.text('Simple notification'));
      await tester.pumpAndSettle();

      await pressWithEnter(tester, LogicalKeyboardKey.controlLeft);
      await settle(tester);

      expect(requests, hasLength(1));
    },
    variant: _windows,
  );

  testWidgets('Ctrl+Enter on a prod project asks before sending', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final (projects, composer) = await pumpAppWithProject(
      tester,
      onFcmRequest: requests.add,
    );
    await tester.runAsync(
      () => projects.setEnvironment(testProjectId, ProjectEnvironment.prod),
    );
    composer.setTargetValue(token);
    await tester.pump();

    await pressWithEnter(tester, LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Send to production?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
  }, variant: _windows);
}
