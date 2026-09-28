import 'package:fcm_studio/features/composer/view/send_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fcm_fixtures.dart';
import '../../helpers/keyboard.dart';

void main() {
  const token = 'abc:APA91bxyz';

  ButtonStyleButton sendButton(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(find.byKey(SendPanel.sendButtonKey));

  testWidgets('invalid JSON shows the error and disables Send', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer
      ..setTargetValue(token)
      ..updateTemplateText('{"notification": ');
    await tester.pump();
    await showJsonTab(tester);

    expect(find.textContaining('Invalid JSON'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);
  });

  testWidgets('Send is enabled once the message is valid and a token is set', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    expect(sendButton(tester).onPressed, isNull);

    composer.setTargetValue(token);
    await tester.pump();

    expect(sendButton(tester).onPressed, isNotNull);
    expect(find.textContaining('"token": "abc:APA91bxyz"'), findsOneWidget);
  });

  testWidgets('a successful send shows the message name', (tester) async {
    final (projects, composer) = await pumpAppWithProject(tester);
    composer.setTargetValue(token);
    await tester.runAsync(() => composer.send(projects.state.selected!));
    await tester.pump();

    expect(find.text('Sent'), findsOneWidget);
    expect(
      find.textContaining('projects/demo-project/messages/0:1'),
      findsOneWidget,
    );
  });

  testWidgets('a failed send shows the explanation', (tester) async {
    final (projects, composer) = await pumpAppWithProject(
      tester,
      fcmStatus: 404,
      fcmBody: unregisteredBody,
    );
    composer.setTargetValue(token);
    await tester.runAsync(() => composer.send(projects.state.selected!));
    await tester.pump();

    expect(find.text('Token is no longer valid'), findsOneWidget);
    expect(find.text('Raw response (HTTP 404)'), findsOneWidget);
  });
}
