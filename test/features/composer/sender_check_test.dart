import 'package:fcm_studio/features/composer/domain/sender_check.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const demo = Project(
    id: 'demo-project',
    displayName: 'Demo Project',
    projectNumber: '123456789012',
    credential: ServiceAccountRef('a@demo-project.iam.gserviceaccount.com'),
  );
  const other = Project(
    id: 'other-project',
    displayName: 'Other',
    projectNumber: '999000999000',
    credential: ServiceAccountRef('b@other-project.iam.gserviceaccount.com'),
  );
  const noNumber = Project(
    id: 'no-number',
    displayName: 'no-number',
    credential: ServiceAccountRef('c@no-number.iam.gserviceaccount.com'),
  );

  test('no warning when a number is unknown or the numbers match', () {
    expect(
      SenderCheck.check(senderId: null, project: demo, projects: const [demo]),
      isNull,
    );
    expect(
      SenderCheck.check(
        senderId: '999',
        project: noNumber,
        projects: const [noNumber],
      ),
      isNull,
    );
    expect(
      SenderCheck.check(
        senderId: '123456789012',
        project: demo,
        projects: const [demo],
      ),
      isNull,
    );
    expect(
      SenderCheck.check(senderId: '999', project: null, projects: const []),
      isNull,
    );
  });

  test(
    'warns in the spec wording and offers the project the token belongs to',
    () {
      final mismatch = SenderCheck.check(
        senderId: '999000999000',
        project: demo,
        projects: const [demo, other],
      )!;
      expect(
        mismatch.message,
        'This token belongs to project number 999000999000, '
        'not Demo Project (demo-project).',
      );
      expect(mismatch.switchTo, other);
    },
  );

  test('offers no switch when no saved project has that number', () {
    expect(
      SenderCheck.check(
        senderId: '555',
        project: demo,
        projects: const [demo],
      )!.switchTo,
      isNull,
    );
  });
}
