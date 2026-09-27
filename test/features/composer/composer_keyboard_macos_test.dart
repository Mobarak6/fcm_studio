import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:re_editor/re_editor.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/keyboard.dart';

// re_editor picks its key handling from the platform once per test file, so the
// macOS shortcut map gets its own file.
final _macOS = TargetPlatformVariant.only(TargetPlatform.macOS);

void main() {
  testWidgets(
    'Cmd+Enter in the JSON editor sends instead of adding a new line',
    (tester) async {
      final requests = <http.Request>[];
      final (_, composer) = await pumpAppWithProject(
        tester,
        onFcmRequest: requests.add,
      );
      composer.setTargetValue('abc:APA91bxyz');
      await tester.pump();
      final textBefore = editorController(tester).text;

      await tester.tap(find.byType(CodeEditor));
      await tester.pump();
      await pressWithEnter(tester, LogicalKeyboardKey.metaLeft);
      await settle(tester);

      expect(requests, hasLength(1));
      expect(editorController(tester).text, textBefore);
    },
    variant: _macOS,
  );
}
