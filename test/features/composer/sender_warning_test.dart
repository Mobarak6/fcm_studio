import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/composer/view/sender_warning.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/device_fixtures.dart';
import '../../helpers/service_account_fixture.dart';

void main() {
  testWidgets(
    'a phone token from another project is flagged, and Switch project fixes it',
    (tester) async {
      final (projects, composer) = await pumpAppWithProject(tester);
      final targets = readCubit<TargetsCubit>(tester);
      await tester.runAsync(() async {
        await projects.addFromServiceAccount(
          serviceAccountJson(
            projectId: 'other-project',
            clientEmail: 'sender@other-project.iam.gserviceaccount.com',
          ),
          persistKey: true,
        );
        await projects.setProjectNumber('other-project', '999000999000');
        await projects.select(testProjectId);
        await targets.saveDeviceToken(
          DeviceToken(
            token: fakeDeviceToken,
            senderId: '999000999000',
            method: TokenReadMethod.runAs,
            readAt: DateTime.utc(2026, 10, 4),
            serial: redmiSerial,
            package: 'com.syldel.delivery',
            deviceName: 'Redmi 14C',
          ),
          projectId: 'other-project',
        );
      });
      composer.setTarget(TargetKind.token, fakeDeviceToken);
      await tester.pump();

      expect(
        find.text(
          'This token belongs to project number 999000999000, '
          'not Demo Project (demo-project).',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(SenderWarning.switchKey));
      await settleAsync(tester);
      expect(projects.state.selectedId, 'other-project');
      expect(find.byKey(const Key('sender-warning')), findsNothing);
    },
  );

  testWidgets('a pasted token with no known sender shows no warning', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.setTargetValue(fakeDeviceToken);
    await tester.pump();
    expect(find.byKey(const Key('sender-warning')), findsNothing);
  });
}
