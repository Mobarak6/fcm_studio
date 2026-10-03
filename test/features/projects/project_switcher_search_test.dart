import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/view/project_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_google.dart';
import '../../helpers/fake_google_auth_flow.dart';

Finder get searchField => find.descendant(
  of: find.byKey(ProjectSwitcher.dropdownKey),
  matching: find.byType(TextField),
);

Finder menuEntry(String label) =>
    find.widgetWithText(MenuItemButton, label).hitTestable();

Future<ProjectsCubit> pumpWithTwoProjects(WidgetTester tester) async {
  await pumpApp(
    tester,
    await buildTestDependencies(
      tester,
      googleFlow: FakeGoogleAuthFlow(),
      client: fakeGoogle(
        firebaseProjects: const [
          listedTestProject,
          {'projectId': 'other-app', 'displayName': 'Other App'},
        ],
      ),
    ),
  );
  return addGoogleTestProject(tester);
}

void main() {
  testWidgets('typing in the project picker filters by name', (tester) async {
    final projects = await pumpWithTwoProjects(tester);
    expect(projects.state.selectedId, 'demo-project');

    await tester.tap(searchField);
    await tester.pumpAndSettle();
    await tester.enterText(searchField, 'other');
    await tester.pumpAndSettle();
    expect(menuEntry('Other App (other-app)'), findsOneWidget);
    expect(menuEntry('Demo Project (demo-project)'), findsNothing);

    await tester.tap(menuEntry('Other App (other-app)'));
    await settleAsync(tester);
    expect(projects.state.selectedId, 'other-app');
  });

  testWidgets('the project ID matches too, ignoring case', (tester) async {
    await pumpWithTwoProjects(tester);
    await tester.tap(searchField);
    await tester.pumpAndSettle();
    await tester.enterText(searchField, 'DEMO-PRO');
    await tester.pumpAndSettle();
    expect(menuEntry('Demo Project (demo-project)'), findsOneWidget);
    expect(menuEntry('Other App (other-app)'), findsNothing);
  });

  testWidgets(
    'leaving the picker without choosing shows the selected project again',
    (tester) async {
      final projects = await pumpWithTwoProjects(tester);
      await tester.tap(searchField);
      await tester.pumpAndSettle();
      await tester.enterText(searchField, 'oth');
      await tester.pumpAndSettle();

      // Click somewhere else: the menu closes and the typed text is dropped.
      await tester.tapAt(const Offset(700, 800));
      await tester.pumpAndSettle();
      expect(projects.state.selectedId, 'demo-project');
      expect(
        tester.widget<TextField>(searchField).controller?.text,
        'Demo Project (demo-project)',
      );
    },
  );
}
