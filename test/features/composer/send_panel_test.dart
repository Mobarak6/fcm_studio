import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/composer/view/preview_panel.dart';
import 'package:fcm_studio/features/composer/view/send_confirmation_dialog.dart';
import 'package:fcm_studio/features/composer/view/send_panel.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:re_editor/re_editor.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/clipboard.dart';
import '../../helpers/fcm_fixtures.dart';
import '../../helpers/keyboard.dart';
import '../../helpers/service_account_fixture.dart';

void main() {
  const token = 'abc:APA91bxyz';
  const unavailableBody =
      '{"error":{"code":503,"message":"Try later.","status":"UNAVAILABLE"}}';

  Future<(ProjectsCubit, ComposerCubit)> pumpProd(
    WidgetTester tester, {
    required List<http.Request> requests,
    int fcmStatus = 200,
    String fcmBody = successBody,
  }) async {
    final (projects, composer) = await pumpAppWithProject(
      tester,
      fcmStatus: fcmStatus,
      fcmBody: fcmBody,
      onFcmRequest: requests.add,
    );
    await tester.runAsync(
      () => projects.setEnvironment(testProjectId, ProjectEnvironment.prod),
    );
    await tester.pump();
    return (projects, composer);
  }

  ButtonStyleButton confirmButton(WidgetTester tester) => tester
      .widget<ButtonStyleButton>(find.byKey(SendConfirmationDialog.confirmKey));

  testWidgets('the production banner shows for prod projects only', (
    tester,
  ) async {
    final (projects, _) = await pumpAppWithProject(tester);
    expect(find.byKey(const Key('prod-banner')), findsNothing);
    await tester.runAsync(
      () => projects.setEnvironment(testProjectId, ProjectEnvironment.prod),
    );
    await tester.pump();
    expect(find.byKey(const Key('prod-banner')), findsOneWidget);
  });

  testWidgets(
    'a prod topic send needs the project ID typed before it goes out',
    (tester) async {
      final requests = <http.Request>[];
      final (_, composer) = await pumpProd(tester, requests: requests);
      composer
        ..setTargetKind(TargetKind.topic)
        ..setTargetValue('all_zone_store');
      await tester.pump();

      await tester.tap(find.byKey(SendPanel.sendButtonKey));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('every device subscribed to `all_zone_store`'),
        findsOneWidget,
      );
      expect(confirmButton(tester).onPressed, isNull);

      await tester.enterText(
        find.byKey(SendConfirmationDialog.typedKey),
        'demo-projec',
      );
      await tester.pump();
      expect(confirmButton(tester).onPressed, isNull);

      await tester.enterText(
        find.byKey(SendConfirmationDialog.typedKey),
        'demo-project',
      );
      await tester.pump();
      await tester.tap(find.byKey(SendConfirmationDialog.confirmKey));
      await settleAsync(tester);
      expect(requests, hasLength(1));
    },
  );

  testWidgets('a prod token send asks, and Cancel sends nothing', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final (_, composer) = await pumpProd(tester, requests: requests);
    composer.setTargetValue(token);
    await tester.pump();

    await tester.tap(find.byKey(SendPanel.sendButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Send to production?'), findsOneWidget);
    expect(find.byKey(SendConfirmationDialog.typedKey), findsNothing);
    expect(confirmButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('Cancel'));
    await settleAsync(tester);
    expect(requests, isEmpty);
  });

  testWidgets('a prod dry run goes out without asking', (tester) async {
    final requests = <http.Request>[];
    final (_, composer) = await pumpProd(tester, requests: requests);
    composer
      ..setTargetKind(TargetKind.topic)
      ..setTargetValue('news');
    await tester.tap(find.byKey(SendPanel.dryRunKey));
    await tester.pump();

    await tester.tap(find.byKey(SendPanel.sendButtonKey));
    await settleAsync(tester);
    expect(find.text('Send to production?'), findsNothing);
    expect(requests, hasLength(1));
    expect(find.text('Valid (dry run, not delivered)'), findsOneWidget);
  });

  testWidgets('a dry run adds validate_only to the request', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.setTargetValue(token);
    await tester.tap(find.byKey(SendPanel.dryRunKey));
    await tester.pump();
    expect(find.textContaining('"validate_only": true'), findsOneWidget);
  });

  testWidgets('Retry sends again after a failure', (tester) async {
    final requests = <http.Request>[];
    final (projects, composer) = await pumpAppWithProject(
      tester,
      fcmStatus: 503,
      fcmBody: unavailableBody,
      onFcmRequest: requests.add,
    );
    composer.setTargetValue(token);
    await tester.runAsync(() => composer.send(projects.state.selected!));
    await tester.pump();
    expect(find.text('Temporary FCM problem'), findsOneWidget);

    await tester.tap(find.byKey(ResultView.retryKey));
    await settleAsync(tester);
    expect(requests, hasLength(2));
  });

  testWidgets('Retry on a prod project asks again', (tester) async {
    final requests = <http.Request>[];
    final (_, composer) = await pumpProd(
      tester,
      requests: requests,
      fcmStatus: 503,
      fcmBody: unavailableBody,
    );
    composer.setTargetValue(token);
    await tester.pump();
    await tester.tap(find.byKey(SendPanel.sendButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SendConfirmationDialog.confirmKey));
    await settleAsync(tester);
    expect(requests, hasLength(1));

    await tester.tap(find.byKey(ResultView.retryKey));
    await tester.pumpAndSettle();
    expect(find.text('Send to production?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settleAsync(tester);
    expect(requests, hasLength(1));
  });

  testWidgets('Show in JSON for a field FCM rejected', (tester) async {
    final (projects, composer) = await pumpAppWithProject(
      tester,
      fcmStatus: 400,
      fcmBody: invalidArgumentBody,
    );
    composer
      ..updateTemplateText(
        '{\n  "notification": {"title": "a"},\n  "data": {\n    "count": 42\n  }\n}',
      )
      ..setTargetValue(token);
    await tester.runAsync(() => composer.send(projects.state.selected!));
    await tester.pump();

    final button = find.byKey(
      const ValueKey('show-field-message.data[0].value'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump();
    expect(editorController(tester).selection.baseIndex, 3);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('Show in JSON works from the Preview & result tab when narrow', (
    tester,
  ) async {
    final (projects, composer) = await pumpAppWithProject(
      tester,
      fcmStatus: 400,
      fcmBody: invalidArgumentBody,
    );
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pump();
    composer
      ..updateTemplateText(
        '{\n  "notification": {"title": "a"},\n  "data": {\n    "count": 42\n  }\n}',
      )
      ..setTargetValue(token);
    await tester.runAsync(() => composer.send(projects.state.selected!));
    await tester.pump();

    await tester.tap(find.text('Preview & result'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final button = find.byKey(
      const ValueKey('show-field-message.data[0].value'),
    );
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(CodeEditor).hitTestable(), findsOneWidget);
    expect(editorController(tester).selection.baseIndex, 3);
    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets(r'Copy as cURL with $FCM_ACCESS_TOKEN', (tester) async {
    final copied = mockClipboard(tester);
    final (_, composer) = await pumpAppWithProject(tester);
    composer.setTargetValue(token);
    await tester.pump();

    await tester.tap(find.byKey(PreviewPanel.curlMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'Copy as cURL with $FCM_ACCESS_TOKEN'));
    await settleAsync(tester);
    expect(copied(), contains(r'Bearer $FCM_ACCESS_TOKEN'));
    expect(copied(), contains('projects/demo-project/messages:send'));
  });

  testWidgets('Copy as cURL with the access token warns about it', (
    tester,
  ) async {
    final copied = mockClipboard(tester);
    final (_, composer) = await pumpAppWithProject(tester);
    composer.setTargetValue(token);
    await tester.pump();

    await tester.tap(find.byKey(PreviewPanel.curlMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy as cURL with access token'));
    await settleAsync(tester);
    expect(copied(), contains('Bearer ya29.test-token'));
    expect(find.textContaining('valid for up to 1 hour'), findsOneWidget);
  });
}
