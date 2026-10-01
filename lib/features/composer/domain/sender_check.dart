import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

/// A token that belongs to a different Firebase project than the selected
/// one (spec §7.1).
class SenderMismatch extends Equatable {
  const SenderMismatch({
    required this.senderId,
    required this.project,
    this.switchTo,
  });

  final String senderId;
  final Project project;

  /// A saved project whose number is [senderId], for "Switch project".
  final Project? switchTo;

  String get message =>
      'This token belongs to project number $senderId, not ${project.label}.';

  @override
  List<Object?> get props => [senderId, project, switchTo];
}

abstract final class SenderCheck {
  /// Null unless both numbers are known and differ.
  static SenderMismatch? check({
    required String? senderId,
    required Project? project,
    required List<Project> projects,
  }) {
    final number = project?.projectNumber;
    if (senderId == null ||
        project == null ||
        number == null ||
        senderId == number) {
      return null;
    }
    return SenderMismatch(
      senderId: senderId,
      project: project,
      switchTo: projects.where((p) => p.projectNumber == senderId).firstOrNull,
    );
  }
}
