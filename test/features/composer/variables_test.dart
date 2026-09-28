import 'package:fcm_studio/features/composer/view/variables_section.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:fcm_studio/features/presets/view/variables_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  testWidgets('the quick fix defines placeholders that have no variable', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    // The preview shows the request only once there is a target.
    composer.setTargetValue('abc:APA91bxyz');
    composer.updateTemplateText(
      '{"notification": {"title": "Order {{order_id}}"}}',
    );
    await tester.pump();
    expect(
      find.textContaining('{{order_id}} without a definition'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(VariablesSection.addMissingKey));
    await tester.pump();
    expect(composer.state.variables.single.key, 'order_id');

    await tester.enterText(
      find.byKey(const ValueKey('variable-order_id')),
      '42',
    );
    await tester.pump();
    expect(find.textContaining('"title": "Order 42"'), findsOneWidget);
  });

  testWidgets('each variable type gets its own input', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.setVariables(const [
      VariableDef(key: 'on', type: VariableType.boolean),
      VariableDef(
        key: 'size',
        type: VariableType.enumeration,
        options: ['s', 'l'],
      ),
      VariableDef(key: 'note', type: VariableType.multiline),
    ]);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('variable-on')),
        matching: find.byType(Switch),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('variable-size')),
        matching: find.byType(DropdownButton<String>),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('variable-on')));
    await tester.pump();
    expect(composer.state.values['on'], 'true');
  });

  testWidgets('the variables dialog adds a number variable', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    await tester.tap(find.byKey(VariablesSection.editKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('variable-add')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('variable-key-0')),
      'badge',
    );
    await tester.tap(find.byKey(const ValueKey('variable-type-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Number').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('variables-save')));
    await tester.pumpAndSettle();

    expect(
      composer.state.variables.single,
      const VariableDef(key: 'badge', type: VariableType.number),
    );
  });

  testWidgets('the variables dialog refuses a duplicate key', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    await tester.tap(find.byKey(VariablesSection.editKey));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('variable-add')));
      await tester.pump();
      await tester.enterText(find.byKey(ValueKey('variable-key-$i')), 'a');
    }
    await tester.tap(find.byKey(const Key('variables-save')));
    await tester.pump();

    expect(find.text('The key "a" is used twice.'), findsOneWidget);
    expect(find.byType(VariablesDialog), findsOneWidget);
    expect(composer.state.variables, isEmpty);
  });
}
