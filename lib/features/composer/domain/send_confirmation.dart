import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/utils/shorten.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

/// What the production safeguard asks before a send (spec §4.3).
class SendConfirmation extends Equatable {
  const SendConfirmation({
    required this.projectId,
    required this.audience,
    required this.requiresTypedProjectId,
  });

  final String projectId;

  /// Who receives the message, e.g. "every device subscribed to `news`".
  final String audience;

  /// True for topic and condition sends: the user must type the project ID.
  final bool requiresTypedProjectId;

  /// Null when no confirmation is needed: the project is not prod, or it is a
  /// dry run, which delivers nothing.
  static SendConfirmation? forSend({
    required Project project,
    required Target target,
    required bool validateOnly,
  }) {
    if (project.environment != ProjectEnvironment.prod || validateOnly) {
      return null;
    }
    return switch (target) {
      TokenTarget(:final token) => SendConfirmation(
        projectId: project.id,
        audience: 'one device (token ${shortenMiddle(token)})',
        requiresTypedProjectId: false,
      ),
      TopicTarget(:final name) => SendConfirmation(
        projectId: project.id,
        audience: 'every device subscribed to `$name`',
        requiresTypedProjectId: true,
      ),
      ConditionTarget(:final expression) => SendConfirmation(
        projectId: project.id,
        audience: 'every device matching `$expression`',
        requiresTypedProjectId: true,
      ),
    };
  }

  @override
  List<Object?> get props => [projectId, audience, requiresTypedProjectId];
}
