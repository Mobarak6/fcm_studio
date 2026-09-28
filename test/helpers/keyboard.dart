import 'package:fcm_studio/features/composer/view/message_editor_tabs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

CodeLineEditingController editorController(WidgetTester tester) => tester
    .widget<CodeEditor>(find.byType(CodeEditor, skipOffstage: false))
    .controller!;

/// Brings the JSON tab to the front.
Future<void> showJsonTab(WidgetTester tester) async {
  await tester.tap(find.byKey(MessageEditorTabs.jsonTabKey));
  await tester.pump();
}

/// Presses Enter while [modifier] is held.
Future<void> pressWithEnter(
  WidgetTester tester,
  LogicalKeyboardKey modifier,
) async {
  await tester.sendKeyDownEvent(modifier);
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.sendKeyUpEvent(modifier);
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}
