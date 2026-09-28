import 'dart:convert';

import 'package:fcm_studio/features/composer/view/send_panel.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:re_editor/re_editor.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/keyboard.dart';

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
}
