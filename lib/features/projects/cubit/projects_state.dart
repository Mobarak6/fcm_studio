import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

enum ProjectsStatus { initial, loading, ready }

class ProjectsState extends Equatable {
  const ProjectsState({
    this.status = ProjectsStatus.initial,
    this.projects = const [],
    this.selectedId,
  });

  final ProjectsStatus status;
  final List<Project> projects;
  final String? selectedId;

  Project? get selected {
    for (final project in projects) {
      if (project.id == selectedId) {
        return project;
      }
    }
    return null;
  }

  ProjectsState copyWith({
    ProjectsStatus? status,
    List<Project>? projects,
    String? Function()? selectedId,
  }) {
    return ProjectsState(
      status: status ?? this.status,
      projects: projects ?? this.projects,
      selectedId: selectedId != null ? selectedId() : this.selectedId,
    );
  }

  @override
  List<Object?> get props => [status, projects, selectedId];
}
