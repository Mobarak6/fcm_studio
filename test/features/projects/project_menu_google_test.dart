import 'dart:async';

import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:fcm_studio/features/projects/view/sign_in_again_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_google_auth_flow.dart';

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('project-menu')));
  await tester.pumpAndSettle();
}

void main() {
  const account = GoogleAccountRef(testGoogleEmail);

  testWidgets('a Google project shows its account and signs in again', (
    tester,
  ) async {
    final flow = FakeGoogleAuthFlow(
      signIns: [
        googleCredentials(),
        googleCredentials(token: 'ya29.google-2', refreshToken: '1//refresh-2'),
      ],
    );
    final dependencies = await buildTestDependencies(tester, googleFlow: flow);
    await pumpApp(tester, dependencies);
    await addGoogleTestProject(tester);

    await openMenu(tester);
    expect(find.text('Signed in as $testGoogleEmail'), findsOneWidget);
    await tester.tap(find.text('Sign in again…'));
    await settleAsync(tester);

    expect(find.text('Signed in again as $testGoogleEmail.'), findsOneWidget);
    expect(flow.calls.last, 'signIn $testGoogleEmail');
    expect(
      await tester.runAsync(
        () => dependencies.projectsRepository.readGoogleRefreshToken(account),
      ),
      '1//refresh-2',
    );
  });

  testWidgets('Cancel while signing in again keeps the old sign-in', (
    tester,
  ) async {
    final flow = FakeGoogleAuthFlow();
    final dependencies = await buildTestDependencies(tester, googleFlow: flow);
    await pumpApp(tester, dependencies);
    await addGoogleTestProject(tester);
    flow.signInGate = Completer<void>();

    await openMenu(tester);
    await tester.tap(find.text('Sign in again…'));
    // Not pumpAndSettle: the dialog's progress bar animates until it closes.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('Finish signing in as $testGoogleEmail in your browser…'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(SignInAgainDialog.cancelKey));
    await settleAsync(tester);

    expect(find.text('Sign-in was cancelled.'), findsOneWidget);
    expect(
      await tester.runAsync(
        () => dependencies.projectsRepository.readGoogleRefreshToken(account),
      ),
      '1//refresh-1',
    );
  });

  testWidgets('signing in again as another account is refused', (tester) async {
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        googleFlow: FakeGoogleAuthFlow(),
        googleUserInfo: FakeGoogleUserInfo([
          testGoogleEmail,
          'other@example.com',
        ]),
      ),
    );
    await addGoogleTestProject(tester);
    await openMenu(tester);
    await tester.tap(find.text('Sign in again…'));
    await settleAsync(tester);
    expect(
      find.textContaining('You signed in as other@example.com'),
      findsOneWidget,
    );
  });

  testWidgets('a service-account project has no Google items', (tester) async {
    await pumpAppWithProject(tester);
    await openMenu(tester);
    expect(find.text('Sign in again…'), findsNothing);
    expect(find.textContaining('Signed in as'), findsNothing);
  });

  testWidgets('removing a Google project says what happens to the sign-in', (
    tester,
  ) async {
    await pumpApp(
      tester,
      await buildTestDependencies(tester, googleFlow: FakeGoogleAuthFlow()),
    );
    await addGoogleTestProject(tester);
    await openMenu(tester);
    await tester.tap(find.text('Remove project…'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('sign-in for $testGoogleEmail is forgotten'),
      findsOneWidget,
    );
  });
}
