import 'package:fcm_studio/features/projects/domain/project.dart';

import 'service_account_fixture.dart';

const testProject = Project(
  id: testProjectId,
  displayName: 'Demo Project',
  projectNumber: testProjectNumber,
  credential: ServiceAccountRef(testClientEmail),
);
