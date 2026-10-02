import 'dart:async';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:fcm_studio/features/projects/view/add_project_dialog.dart';
import 'package:fcm_studio/features/projects/view/google_projects_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_google.dart';
import '../../helpers/fake_google_auth_flow.dart';

Future<void> openAddProject(WidgetTester tester) async {
  await tester.tap(find.text('Add project'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Google sign-in is shown disabled, with a hint, when not set up',
    (tester) async {
      await pumpApp(tester, await buildTestDependencies(tester));
      await openAddProject(tester);
      final button = tester.widget<OutlinedButton>(
        find.byKey(AddProjectDialog.googleKey),
      );
      expect(button.onPressed, isNull);
      expect(find.textContaining('docs/oauth-setup.md'), findsOneWidget);
    },
  );

  testWidgets(
    'signing in lists the projects of the account and adds the ticked one',
    (tester) async {
      await pumpApp(
        tester,
        await buildTestDependencies(
          tester,
          googleFlow: FakeGoogleAuthFlow(),
          client: fakeGoogle(
            firebaseProjects: const [
              listedTestProject,
              {
                'projectId': 'other-app',
                'displayName': 'Other App',
                'projectNumber': '555',
              },
            ],
          ),
        ),
      );
      await openAddProject(tester);
      await tester.tap(find.byKey(AddProjectDialog.googleKey));
      await settleAsync(tester);

      expect(find.text('Projects for $testGoogleEmail'), findsOneWidget);
      expect(find.text('Demo Project'), findsOneWidget);
      expect(find.text('Other App'), findsOneWidget);
      await tester.tap(
        find.byKey(GoogleProjectsDialog.projectKey('other-app')),
      );
      await tester.pump();
      await tester.tap(find.byKey(GoogleProjectsDialog.addKey));
      await settleAsync(tester);

      expect(find.byType(GoogleProjectsDialog), findsNothing);
      final state = readCubit<ProjectsCubit>(tester).state;
      expect(state.projects, hasLength(1));
      expect(
        state.selected,
        const Project(
          id: 'other-app',
          displayName: 'Other App',
          projectNumber: '555',
          credential: GoogleAccountRef(testGoogleEmail),
        ),
      );
    },
  );

  testWidgets('Cancel stops waiting for the browser', (tester) async {
    final flow = FakeGoogleAuthFlow()..signInGate = Completer<void>();
    await pumpApp(
      tester,
      await buildTestDependencies(tester, googleFlow: flow),
    );
    await openAddProject(tester);
    await tester.tap(find.byKey(AddProjectDialog.googleKey));
    await tester.pump();
    expect(find.text('Finish signing in in your browser…'), findsOneWidget);

    await tester.tap(find.byKey(AddProjectDialog.cancelGoogleKey));
    await settleAsync(tester);
    expect(flow.cancels, 1);
    expect(find.text('Finish signing in in your browser…'), findsNothing);
    expect(find.text('Choose key file…'), findsOneWidget);
    expect(readCubit<ProjectsCubit>(tester).state.projects, isEmpty);
  });

  testWidgets('closing the dialog while waiting stops the sign-in', (
    tester,
  ) async {
    final flow = FakeGoogleAuthFlow()..signInGate = Completer<void>();
    await pumpApp(
      tester,
      await buildTestDependencies(tester, googleFlow: flow),
    );
    await openAddProject(tester);
    await tester.tap(find.byKey(AddProjectDialog.googleKey));
    await tester.pump();

    await tester.tapAt(const Offset(5, 5));
    await settleAsync(tester);
    expect(find.byType(AddProjectDialog), findsNothing);
    expect(flow.cancels, 1);
  });

  testWidgets('a failed sign-in shows what went wrong', (tester) async {
    final flow = FakeGoogleAuthFlow(
      signIns: const [AuthException('Google sign-in failed (invalid_client).')],
    );
    await pumpApp(
      tester,
      await buildTestDependencies(tester, googleFlow: flow),
    );
    await openAddProject(tester);
    await tester.tap(find.byKey(AddProjectDialog.googleKey));
    await settleAsync(tester);
    expect(
      find.text('Google sign-in failed (invalid_client).'),
      findsOneWidget,
    );
  });

  testWidgets('an account without Firebase projects says so', (tester) async {
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        googleFlow: FakeGoogleAuthFlow(),
        client: fakeGoogle(firebaseProjects: const []),
      ),
    );
    await openAddProject(tester);
    await tester.tap(find.byKey(AddProjectDialog.googleKey));
    await settleAsync(tester);
    expect(find.textContaining('has no Firebase projects'), findsOneWidget);
    final add = tester.widget<FilledButton>(
      find.byKey(GoogleProjectsDialog.addKey),
    );
    expect(add.onPressed, isNull);
  });

  testWidgets('a project that is already added says it will switch accounts', (
    tester,
  ) async {
    await pumpApp(
      tester,
      await buildTestDependencies(tester, googleFlow: FakeGoogleAuthFlow()),
    );
    await addTestProject(tester);
    await openAddProject(tester);
    await tester.tap(find.byKey(AddProjectDialog.googleKey));
    await settleAsync(tester);
    expect(find.textContaining('already added'), findsOneWidget);
  });
}
