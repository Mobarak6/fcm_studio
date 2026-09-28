import 'package:fcm_studio/app/widgets/prompt_dialog.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/composer/view/target_picker.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  const token = 'fAbC12345678909xYz';

  Finder starIcon(IconData icon) => find.descendant(
    of: find.byKey(TargetPicker.starKey),
    matching: find.byIcon(icon),
  );

  testWidgets('the star saves the current target with a label', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final targets = readCubit<TargetsCubit>(tester);
    composer.setTargetValue(token);
    await tester.pump();
    expect(starIcon(Icons.star_border), findsOneWidget);

    await tester.tap(find.byKey(TargetPicker.starKey));
    await tester.pumpAndSettle();
    expect(find.text('Token fAbC12…9xYz'), findsOneWidget);
    await tester.enterText(find.byKey(PromptDialog.fieldKey), 'Redmi debug');
    await tester.tap(find.byKey(PromptDialog.confirmKey));
    await settleAsync(tester);

    expect(targets.state.targets.single.label, 'Redmi debug');
    expect(targets.state.targets.single.projectId, 'demo-project');
    expect(starIcon(Icons.star), findsOneWidget);
  });

  testWidgets('tapping a filled star removes the saved target', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final targets = readCubit<TargetsCubit>(tester);
    await tester.runAsync(
      () => targets.save(const TokenTarget(token), label: 'Redmi'),
    );
    composer.setTargetValue(token);
    await tester.pump();
    expect(starIcon(Icons.star), findsOneWidget);

    await tester.tap(find.byKey(TargetPicker.starKey));
    await settleAsync(tester);
    expect(targets.state.targets, isEmpty);
    expect(starIcon(Icons.star_border), findsOneWidget);
  });

  testWidgets('suggestions put the current project first and fill the target', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final targets = readCubit<TargetsCubit>(tester);
    await tester.runAsync(() async {
      await targets.save(
        const TokenTarget(token),
        label: 'Phone A',
        projectId: 'demo-project',
      );
      await targets.save(
        const TopicTarget('other-news'),
        label: 'Phone B',
        projectId: 'other-project',
      );
    });
    await tester.pump();

    await tester.enterText(find.byKey(TargetPicker.fieldKey), 'phone');
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Phone A')).dy,
      lessThan(tester.getTopLeft(find.text('Phone B')).dy),
    );

    await tester.tap(find.text('Phone B'));
    await tester.pumpAndSettle();
    expect(composer.state.targetKind, TargetKind.topic);
    expect(composer.state.targetValue, 'other-news');
    expect(
      find.descendant(
        of: find.byKey(TargetPicker.fieldKey),
        matching: find.text('other-news'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a target set from elsewhere shows in the field', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.setTarget(TargetKind.topic, 'news');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(TargetPicker.fieldKey),
        matching: find.text('news'),
      ),
      findsOneWidget,
    );
  });
}
