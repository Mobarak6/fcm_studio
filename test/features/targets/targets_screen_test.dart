import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/app/widgets/prompt_dialog.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/clipboard.dart';

void main() {
  const token = 'fAbC12345678909xYz';

  Future<(ComposerCubit, TargetsCubit)> openTargets(WidgetTester tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final targets = readCubit<TargetsCubit>(tester);
    await tester.runAsync(
      () => targets.save(
        const TokenTarget(token),
        label: 'Redmi',
        projectId: 'demo-project',
      ),
    );
    await tester.tap(find.byKey(const Key('nav-targets')));
    await tester.pumpAndSettle();
    return (composer, targets);
  }

  testWidgets('shows tokens shortened and copies the full value on tap', (
    tester,
  ) async {
    final copied = mockClipboard(tester);
    await openTargets(tester);
    expect(
      find.textContaining('token · fAbC12…9xYz · demo-project'),
      findsOneWidget,
    );
    await tester.tap(find.text('Redmi'));
    await tester.pumpAndSettle();
    expect(copied(), token);
  });

  testWidgets('Use in composer sets the target and shows the composer', (
    tester,
  ) async {
    final (composer, targets) = await openTargets(tester);
    final id = targets.state.targets.single.id;
    await tester.tap(find.byKey(ValueKey('target-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use in composer'));
    await tester.pumpAndSettle();
    expect(composer.state.targetKind, TargetKind.token);
    expect(composer.state.targetValue, token);
    expect(readCubit<NavigationCubit>(tester).state, AppSection.composer);
  });

  testWidgets('rename and delete', (tester) async {
    final (_, targets) = await openTargets(tester);
    final id = targets.state.targets.single.id;

    await tester.tap(find.byKey(ValueKey('target-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PromptDialog.fieldKey), 'Pixel');
    await tester.tap(find.byKey(PromptDialog.confirmKey));
    await settleAsync(tester);
    expect(targets.state.targets.single.label, 'Pixel');

    await tester.tap(find.byKey(ValueKey('target-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await settleAsync(tester);
    expect(targets.state.targets, isEmpty);
  });
}
