import 'package:fcm_studio/app/widgets/prompt_dialog.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/settings/view/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_process_runner.dart';

const adbVersion = 'Android Debug Bridge version 1.0.41\n';

void main() {
  Future<void> openSettings(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('nav-settings')));
    await tester.pumpAndSettle();
  }

  testWidgets('shows where adb was found and its version', (tester) async {
    final runner = FakeProcessRunner()
      ..on('/opt/homebrew/bin/adb version', ok(adbVersion));
    await pumpApp(
      tester,
      await buildTestDependencies(tester, processRunner: runner),
    );
    await openSettings(tester);
    expect(find.text('/opt/homebrew/bin/adb'), findsOneWidget);
    expect(
      find.text('Android Debug Bridge version 1.0.41 · Homebrew'),
      findsOneWidget,
    );
  });

  testWidgets('shows that adb was not found and where it looked', (
    tester,
  ) async {
    await pumpApp(tester, await buildTestDependencies(tester));
    await openSettings(tester);
    expect(find.text('adb was not found'), findsOneWidget);
    expect(find.textContaining('/opt/homebrew/bin/adb'), findsOneWidget);
  });

  testWidgets('Change… uses the typed path; Find automatically clears it', (
    tester,
  ) async {
    final runner = FakeProcessRunner()
      ..on('/opt/homebrew/bin/adb version', ok(adbVersion))
      ..on('/custom/adb version', ok(adbVersion));
    await pumpApp(
      tester,
      await buildTestDependencies(tester, processRunner: runner),
    );
    await openSettings(tester);

    await tester.tap(find.byKey(SettingsScreen.changeKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PromptDialog.fieldKey), '/custom/adb');
    await tester.tap(find.byKey(PromptDialog.confirmKey));
    await settleAsync(tester);
    expect(find.text('/custom/adb'), findsOneWidget);
    expect(find.textContaining('set in Settings'), findsOneWidget);

    await tester.tap(find.byKey(SettingsScreen.automaticKey));
    await settleAsync(tester);
    expect(find.text('/opt/homebrew/bin/adb'), findsOneWidget);
    expect(find.text('Find again'), findsOneWidget);
  });

  testWidgets('Find again searches once more when no path is set', (
    tester,
  ) async {
    final runner = FakeProcessRunner()
      ..on('/opt/homebrew/bin/adb version', ok(adbVersion));
    await pumpApp(
      tester,
      await buildTestDependencies(tester, processRunner: runner),
    );
    await openSettings(tester);
    final before = runner.commands
        .where((c) => c == '/opt/homebrew/bin/adb version')
        .length;
    expect(find.text('Find again'), findsOneWidget);

    await tester.tap(find.byKey(SettingsScreen.automaticKey));
    await settleAsync(tester);

    expect(
      runner.commands.where((c) => c == '/opt/homebrew/bin/adb version'),
      hasLength(before + 1),
    );
  });

  testWidgets('a typed path that does not run adb is flagged', (tester) async {
    final runner = FakeProcessRunner()
      ..on('/opt/homebrew/bin/adb version', ok(adbVersion));
    await pumpApp(
      tester,
      await buildTestDependencies(tester, processRunner: runner),
    );
    await openSettings(tester);
    await tester.tap(find.byKey(SettingsScreen.changeKey));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PromptDialog.fieldKey), '/wrong/adb');
    await tester.tap(find.byKey(PromptDialog.confirmKey));
    await settleAsync(tester);
    expect(find.textContaining("/wrong/adb doesn't run adb"), findsOneWidget);
  });

  testWidgets('on the web there is no Settings section', (tester) async {
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        platform: const PlatformFeatures(deviceAccess: DeviceAccess.noWebUsb),
      ),
    );
    expect(find.byKey(const Key('nav-settings')), findsNothing);
    expect(find.byKey(const Key('nav-history')), findsOneWidget);
  });
}
