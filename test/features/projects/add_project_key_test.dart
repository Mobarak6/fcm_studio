import 'dart:convert';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/view/add_project_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_google.dart';
import '../../helpers/service_account_fixture.dart';

Future<void> openAddProject(
  WidgetTester tester, {
  int firebaseStatus = 200,
}) async {
  await pumpApp(
    tester,
    await buildTestDependencies(
      tester,
      client: fakeGoogle(firebaseStatus: firebaseStatus),
    ),
  );
  await tester.tap(find.text('Add project'));
  await tester.pumpAndSettle();
}

Future<void> pasteAndAdd(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(AddProjectDialog.pasteKey), text);
  await tester.pump();
  await tester.tap(find.byKey(AddProjectDialog.addPastedKey));
  await settleAsync(tester);
}

Future<void> drop(WidgetTester tester, List<DropItem> files) async {
  tester.widget<DropTarget>(find.byKey(AddProjectDialog.dropKey)).onDragDone!(
    DropDoneDetails(
      files: files,
      localPosition: Offset.zero,
      globalPosition: Offset.zero,
    ),
  );
  await settleAsync(tester);
}

DropItem droppedFile(String name, String text) =>
    DropItemFile.fromData(utf8.encode(text), name: name, path: name);

List<String> projectIds(WidgetTester tester) => [
  for (final project in readCubit<ProjectsCubit>(tester).state.projects)
    project.id,
];

void main() {
  testWidgets('a pasted key adds the project and closes the dialog', (
    tester,
  ) async {
    await openAddProject(tester);
    await pasteAndAdd(tester, serviceAccountJson());
    expect(find.byType(AddProjectDialog), findsNothing);
    expect(projectIds(tester), [testProjectId]);
  });

  testWidgets('pasted text that is not a key says why; the dialog stays', (
    tester,
  ) async {
    await openAddProject(tester);
    await pasteAndAdd(tester, 'not a key');
    expect(find.byType(AddProjectDialog), findsOneWidget);
    expect(find.textContaining('not valid JSON'), findsOneWidget);
    expect(projectIds(tester), isEmpty);
  });

  testWidgets('Add pasted key is off until something is pasted', (
    tester,
  ) async {
    await openAddProject(tester);
    FilledButton button() =>
        tester.widget<FilledButton>(find.byKey(AddProjectDialog.addPastedKey));
    expect(button().onPressed, isNull);
    await tester.enterText(find.byKey(AddProjectDialog.pasteKey), '   ');
    await tester.pump();
    expect(button().onPressed, isNull);
    await tester.enterText(find.byKey(AddProjectDialog.pasteKey), '{}');
    await tester.pump();
    expect(button().onPressed, isNotNull);
  });

  testWidgets('the pasted key is cleared once it is added', (tester) async {
    // Without the project number the dialog stays open to say so.
    await openAddProject(tester, firebaseStatus: 403);
    await pasteAndAdd(tester, serviceAccountJson());
    expect(projectIds(tester), [testProjectId]);
    expect(find.byType(AddProjectDialog), findsOneWidget);
    expect(
      tester
          .widget<TextField>(find.byKey(AddProjectDialog.pasteKey))
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('a dropped .json key adds the project', (tester) async {
    await openAddProject(tester);
    await drop(tester, [
      droppedFile('notes.txt', 'hello'),
      droppedFile('fcm-key.json', serviceAccountJson()),
    ]);
    expect(find.byType(AddProjectDialog), findsNothing);
    expect(projectIds(tester), [testProjectId]);
  });

  testWidgets('a dropped file that is not .json says so', (tester) async {
    await openAddProject(tester);
    await drop(tester, [droppedFile('photo.png', 'png')]);
    expect(find.text(AddProjectDialog.dropJsonMessage), findsOneWidget);
    expect(projectIds(tester), isEmpty);
  });
}
