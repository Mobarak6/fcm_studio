import 'package:fcm_studio/features/composer/domain/send_confirmation.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/project_fixture.dart';

void main() {
  final prod = testProject.copyWith(environment: ProjectEnvironment.prod);

  test('dev and staging projects send without asking', () {
    for (final environment in [
      ProjectEnvironment.dev,
      ProjectEnvironment.staging,
    ]) {
      expect(
        SendConfirmation.forSend(
          project: testProject.copyWith(environment: environment),
          target: const TopicTarget('news'),
          validateOnly: false,
        ),
        isNull,
      );
    }
  });

  test('a prod dry run sends without asking, because nothing is delivered', () {
    expect(
      SendConfirmation.forSend(
        project: prod,
        target: const TopicTarget('news'),
        validateOnly: true,
      ),
      isNull,
    );
  });

  test('a prod token send asks, without typing the project ID', () {
    final confirmation = SendConfirmation.forSend(
      project: prod,
      target: const TokenTarget('fAbC12345678909xYz'),
      validateOnly: false,
    );
    expect(confirmation?.audience, 'one device (token fAbC12…9xYz)');
    expect(confirmation?.requiresTypedProjectId, isFalse);
  });

  test(
    'prod topic and condition sends name the audience and need the project ID',
    () {
      final topic = SendConfirmation.forSend(
        project: prod,
        target: const TopicTarget('/topics/all_zone_store'),
        validateOnly: false,
      );
      expect(topic?.audience, 'every device subscribed to `all_zone_store`');
      expect(topic?.requiresTypedProjectId, isTrue);
      expect(topic?.projectId, 'demo-project');

      final condition = SendConfirmation.forSend(
        project: prod,
        target: const ConditionTarget("'a' in topics"),
        validateOnly: false,
      );
      expect(condition?.audience, "every device matching `'a' in topics`");
      expect(condition?.requiresTypedProjectId, isTrue);
    },
  );
}
