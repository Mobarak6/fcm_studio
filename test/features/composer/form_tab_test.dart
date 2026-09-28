import 'package:fcm_studio/features/composer/domain/template_edits.dart';
import 'package:fcm_studio/features/composer/view/data_entries_editor.dart';
import 'package:fcm_studio/features/composer/view/form_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/keyboard.dart';

void main() {
  Finder field(String path) => find.byKey(ValueKey('form-$path'));

  testWidgets('typing in the form updates the template and the JSON editor', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    await tester.enterText(field('notification.title'), 'Order shipped');
    await tester.pump();
    expect(
      TemplateEdits.read(composer.state.template!, ['notification', 'title']),
      'Order shipped',
    );
    expect(editorController(tester).text, contains('"title": "Order shipped"'));
  });

  testWidgets('fields the form does not cover are kept', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.updateTemplateText(
      '{"notification": {"title": "a"}, "fcm_options": {"analytics_label": "x"}}',
    );
    await tester.pump();
    await tester.enterText(field('notification.title'), 'b');
    await tester.pump();
    expect(composer.state.template!['fcm_options'], {'analytics_label': 'x'});
  });

  testWidgets('an edit in the JSON shows up in the form', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.updateTemplateText('{"notification": {"title": "From JSON"}}');
    await tester.pump();
    expect(
      find.descendant(
        of: field('notification.title'),
        matching: find.text('From JSON'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('switching to data only hides the notification fields', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    await tester.tap(find.text('Data only'));
    await tester.pump();
    expect(TemplateEdits.isDataOnly(composer.state.template!), isTrue);
    expect(
      TemplateEdits.read(composer.state.template!, ['android', 'priority']),
      'high',
    );
    expect(field('notification.title'), findsNothing);
  });

  testWidgets('invalid JSON makes the form read-only', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.updateTemplateText('{');
    await tester.pump();
    expect(find.text(FormTab.readOnlyMessage), findsOneWidget);
    expect(field('notification.title'), findsNothing);
  });

  testWidgets(
    'a data key that already exists is refused and both entries are kept',
    (tester) async {
      final (_, composer) = await pumpAppWithProject(tester);
      composer.updateTemplateText('{"data": {"a": "1", "b": "2"}}');
      await tester.pump();
      await tester.enterText(find.byKey(const ValueKey('data-key-1')), 'a');
      await tester.pump();
      expect(find.text('Duplicate key'), findsOneWidget);
      expect(composer.state.template!['data'], {'a': '1', 'b': '2'});
    },
  );

  testWidgets('data rows can be added, moved and removed', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    List<String> keys() => TemplateEdits.dataEntries(
      composer.state.template!,
    ).map((e) => e.key).toList();
    composer.updateTemplateText('{"data": {"a": "1"}}');
    await tester.pump();

    await tester.tap(find.byKey(DataEntriesEditor.addKey));
    await tester.pump();
    expect(keys(), ['a', 'key']);

    await tester.tap(find.byKey(const ValueKey('data-up-1')));
    await tester.pump();
    expect(keys(), ['key', 'a']);

    await tester.tap(find.byKey(const ValueKey('data-remove-0')));
    await tester.pump();
    expect(composer.state.template!['data'], {'a': '1'});
  });

  testWidgets('Show in JSON switches to the JSON tab and selects the line', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.updateTemplateText('{\n  "data": {\n    "a": "1"\n  }\n}');
    await tester.pump();
    expect(find.byType(CodeEditor), findsNothing, reason: 'Form tab first');

    composer.showField('message.data[0].value');
    await tester.pump();
    await tester.pump();

    expect(find.byType(CodeEditor), findsOneWidget);
    expect(editorController(tester).selection.baseIndex, 2);

    // The focused editor's cursor blink keeps a timer; let it run out.
    await tester.pump(const Duration(milliseconds: 200));
  });
}
