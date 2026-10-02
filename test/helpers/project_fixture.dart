import 'package:fcm_studio/features/projects/domain/project.dart';

import 'fake_google_auth_flow.dart';
import 'service_account_fixture.dart';

const testProject = Project(
  id: testProjectId,
  displayName: 'Demo Project',
  projectNumber: testProjectNumber,
  credential: ServiceAccountRef(testClientEmail),
);

const testGoogleProject = Project(
  id: 'google-project',
  displayName: 'Google Project',
  projectNumber: '987654321098',
  credential: GoogleAccountRef(testGoogleEmail),
);
