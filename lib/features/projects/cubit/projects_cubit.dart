import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:fcm_studio/features/projects/cubit/projects_state.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/projects/cubit/projects_state.dart';

sealed class AddProjectResult {
  const AddProjectResult();
}

final class AddProjectSuccess extends AddProjectResult {
  const AddProjectSuccess(this.project, {required this.needsProjectNumber});

  final Project project;

  /// True when the key could not read the project number; the user may enter it.
  final bool needsProjectNumber;
}

final class AddProjectFailure extends AddProjectResult {
  const AddProjectFailure(this.message);

  final String message;
}

class ProjectsCubit extends Cubit<ProjectsState> {
  ProjectsCubit({
    required this._repository,
    required this._authRegistry,
    required this._firebaseApi,
  }) : super(const ProjectsState());

  final ProjectsRepository _repository;
  final ProjectAuthRegistry _authRegistry;
  final FirebaseProjectsApi _firebaseApi;

  Future<void> load() async {
    emit(state.copyWith(status: ProjectsStatus.loading));
    final projects = await _repository.loadAll();
    final saved = await _repository.readSelectedProjectId();
    final selectedId = projects.any((p) => p.id == saved)
        ? saved
        : projects.firstOrNull?.id;
    emit(
      ProjectsState(
        status: ProjectsStatus.ready,
        projects: projects,
        selectedId: selectedId,
      ),
    );
  }

  /// Validates the key, checks it with Google, then saves and selects the project.
  /// Adding a project that already exists updates its key and keeps its settings.
  Future<AddProjectResult> addFromServiceAccount(
    String jsonText, {
    required bool persistKey,
  }) async {
    final ServiceAccountKey key;
    try {
      key = ServiceAccountKey.parse(jsonText);
    } on ServiceAccountKeyException catch (e) {
      return AddProjectFailure(e.message);
    }

    final credential = ServiceAccountRef(key.clientEmail);
    final provider = _authRegistry.registerKey(key);
    try {
      await provider.getToken(forceRefresh: true);
    } on AuthException catch (e) {
      _authRegistry.forget(credential);
      return AddProjectFailure(e.message);
    } catch (e) {
      _authRegistry.forget(credential);
      return AddProjectFailure('Could not check the key: ${redact('$e')}');
    }

    // Project details are optional: any failure here just leaves them blank.
    FirebaseProjectInfo? info;
    try {
      info = await _firebaseApi.getProject(key.projectId, provider);
    } catch (_) {
      info = null;
    }

    final existing = state.projects
        .where((p) => p.id == key.projectId)
        .firstOrNull;
    final project = Project(
      id: key.projectId,
      displayName: info?.displayName ?? existing?.displayName ?? key.projectId,
      projectNumber: info?.projectNumber ?? existing?.projectNumber,
      environment: existing?.environment ?? ProjectEnvironment.dev,
      credential: credential,
    );

    try {
      await _repository.saveServiceAccountKey(key, persist: persistKey);
      await _repository.save(project);
      if (existing != null && existing.credential != credential) {
        _authRegistry.forget(existing.credential);
        await _repository.deleteSecretIfUnused(existing.credential);
      }
      await _repository.writeSelectedProjectId(project.id);
    } catch (e) {
      // e.g. a denied Keychain prompt: report it instead of leaving the dialog spinning.
      _authRegistry.forget(credential);
      return AddProjectFailure('Could not save the project: ${redact('$e')}');
    }

    final projects = [
      ...state.projects.where((p) => p.id != project.id),
      project,
    ]..sort(_byName);
    emit(
      state.copyWith(
        status: ProjectsStatus.ready,
        projects: projects,
        selectedId: () => project.id,
      ),
    );
    return AddProjectSuccess(
      project,
      needsProjectNumber: project.projectNumber == null,
    );
  }

  Future<void> select(String projectId) async {
    if (!state.projects.any((p) => p.id == projectId)) {
      return;
    }
    await _repository.writeSelectedProjectId(projectId);
    emit(state.copyWith(selectedId: () => projectId));
  }

  Future<void> setEnvironment(
    String projectId,
    ProjectEnvironment environment,
  ) => _update(projectId, (p) => p.copyWith(environment: environment));

  Future<void> setProjectNumber(String projectId, String? number) {
    final trimmed = number?.trim();
    return _update(
      projectId,
      (p) => p.copyWith(
        projectNumber: () =>
            trimmed == null || trimmed.isEmpty ? null : trimmed,
      ),
    );
  }

  Future<void> remove(String projectId) async {
    final project = state.projects.where((p) => p.id == projectId).firstOrNull;
    if (project == null) {
      return;
    }
    await _repository.remove(project);
    final remaining = state.projects.where((p) => p.id != projectId).toList();
    if (!remaining.any((p) => p.credential == project.credential)) {
      _authRegistry.forget(project.credential);
    }
    final selectedId = state.selectedId == projectId
        ? remaining.firstOrNull?.id
        : state.selectedId;
    await _repository.writeSelectedProjectId(selectedId);
    emit(state.copyWith(projects: remaining, selectedId: () => selectedId));
  }

  Future<void> _update(
    String projectId,
    Project Function(Project) change,
  ) async {
    final index = state.projects.indexWhere((p) => p.id == projectId);
    if (index < 0) {
      return;
    }
    final updated = change(state.projects[index]);
    await _repository.save(updated);
    final projects = [...state.projects]..[index] = updated;
    emit(state.copyWith(projects: projects));
  }

  static int _byName(Project a, Project b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
}
