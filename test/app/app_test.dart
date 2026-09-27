import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';
import '../helpers/service_account_fixture.dart';

void main() {
  testWidgets('shows the empty state and opens the add-project dialog', (
    tester,
  ) async {
    await pumpApp(tester, await buildTestDependencies(tester));

    expect(
      find.text('No projects yet. Add one with a service account key.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Add project'));
    await tester.pumpAndSettle();
    expect(find.text('Choose key file…'), findsOneWidget);
  });

  testWidgets('shows an added project and its environment', (tester) async {
    await pumpApp(tester, await buildTestDependencies(tester));
    final projects = readCubit<ProjectsCubit>(tester);

    await tester.runAsync(
      () => projects.addFromServiceAccount(
        serviceAccountJson(),
        persistKey: true,
      ),
    );
    await tester.pump();
    expect(find.text('Demo Project (demo-project)'), findsOneWidget);
    expect(find.text('DEV'), findsOneWidget);

    await tester.runAsync(
      () => projects.setEnvironment(testProjectId, ProjectEnvironment.prod),
    );
    await tester.pump();
    expect(find.text('PROD'), findsOneWidget);
  });
}
