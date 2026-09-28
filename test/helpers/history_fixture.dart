import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

import 'fcm_fixtures.dart';
import 'service_account_fixture.dart';

HistoryEntry historyEntry(
  String id, {
  DateTime? sentAt,
  String projectId = testProjectId,
  bool ok = true,
  bool dryRun = false,
  String value = 'abc:APA91bxyz',
  String? presetName,
  ProjectEnvironment environment = ProjectEnvironment.dev,
}) => HistoryEntry(
  id: id,
  sentAt: sentAt ?? DateTime.utc(2026, 10, 3, 9),
  projectId: projectId,
  environment: environment,
  target: HistoryTarget(kind: TargetKind.token, value: value, label: 'Redmi'),
  presetName: presetName,
  request: {
    if (dryRun) 'validate_only': true,
    'message': {
      'token': value,
      'notification': {'title': 'Order shipped'},
    },
  },
  validateOnly: dryRun,
  httpStatus: ok ? 200 : 404,
  outcome: ok
      ? const HistorySuccess('projects/demo-project/messages/0:1')
      : const HistoryFailure(
          code: 'UNREGISTERED',
          explanation: 'Token is no longer valid',
        ),
  responseBody: ok ? successBody : unregisteredBody,
  duration: const Duration(milliseconds: 120),
);
