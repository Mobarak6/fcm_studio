import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:fcm_studio/features/projects/cubit/projects_state.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/projects/domain/google_session.dart';
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

sealed class GoogleSignInResult {
  const GoogleSignInResult();
}

/// Signed in; these are the account's Firebase projects. Nothing is saved yet.
final class GoogleProjectsFound extends GoogleSignInResult {
  const GoogleProjectsFound(this.session, {required this.projects});

  final GoogleSession session;
  final List<FirebaseProjectInfo> projects;

  String get email => session.email;
}

final class GoogleSignInFailed extends GoogleSignInResult {
  const GoogleSignInFailed(this.message);

  final String message;
}

/// The user cancelled; there is nothing to report.
final class GoogleSignInStopped extends GoogleSignInResult {
  const GoogleSignInStopped();
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

  /// False when `config/oauth.json` has no client for this platform.
  bool get canSignInWithGoogle => _authRegistry.canSignInWithGoogle;

  /// Signs in to Google and lists the account's Firebase projects (spec §4.2).
  /// Nothing is saved until [addGoogleProjects].
  Future<GoogleSignInResult> signInWithGoogle({Future<void>? cancel}) async {
    final GoogleSession session;
    try {
      session = await _authRegistry.signInWithGoogle(cancel: cancel);
    } on GoogleSignInCancelled {
      return const GoogleSignInStopped();
    } on AuthException catch (e) {
      return GoogleSignInFailed(e.message);
    } catch (e) {
      return GoogleSignInFailed('Google sign-in failed: ${redact('$e')}');
    }
    try {
      final projects = await _firebaseApi.listProjects(session.provider);
      return GoogleProjectsFound(session, projects: projects);
    } on FirebaseApiException catch (e) {
      return GoogleSignInFailed(e.message);
    } on AuthException catch (e) {
      return GoogleSignInFailed(e.message);
    } catch (e) {
      return GoogleSignInFailed(
        'Could not list your Firebase projects: ${redact('$e')}',
      );
    }
  }

  /// Saves the account's sign-in and adds the picked projects. A project that
  /// is already added switches to the account and keeps its environment
  /// (plan Decision 7). Returns null on success, or what went wrong.
  Future<String?> addGoogleProjects(
    GoogleSession session,
    List<FirebaseProjectInfo> picked,
  ) async {
    if (picked.isEmpty) {
      return null;
    }
    final credential = session.account;
    final byId = {for (final project in state.projects) project.id: project};
    final added = [
      for (final info in picked)
        Project(
          id: info.projectId,
          displayName: info.displayName,
          projectNumber:
              info.projectNumber ?? byId[info.projectId]?.projectNumber,
          environment:
              byId[info.projectId]?.environment ?? ProjectEnvironment.dev,
          credential: credential,
        ),
    ];
    final replaced = <CredentialRef>{};
    for (final project in added) {
      final old = byId[project.id];
      if (old != null && old.credential != credential) {
        replaced.add(old.credential);
      }
    }
    final addedIds = {for (final project in added) project.id};
    final projects = [
      ...state.projects.where((p) => !addedIds.contains(p.id)),
      ...added,
    ]..sort(_byName);
    final selectedId = _selectionAfterAdding(added, projects);

    try {
      final refreshToken = session.credentials.refreshToken;
      if (refreshToken != null) {
        await _repository.saveGoogleRefreshToken(credential, refreshToken);
      }
      for (final project in added) {
        await _repository.save(project);
      }
      for (final old in replaced) {
        await _repository.deleteSecretIfUnused(old);
      }
      await _repository.writeSelectedProjectId(selectedId);
    } catch (e) {
      return 'Could not save the projects: ${redact('$e')}';
    }

    _authRegistry.registerGoogle(session);
    for (final old in replaced) {
      if (!projects.any((p) => p.credential == old)) {
        _authRegistry.forget(old);
      }
    }
    emit(
      state.copyWith(
        status: ProjectsStatus.ready,
        projects: projects,
        selectedId: () => selectedId,
      ),
    );
    return null;
  }

  /// Signs in to [account] again, e.g. after its sign-in expired (plan
  /// Decision 6). Another account is refused, and the old sign-in stays.
  /// Returns null on success, or what went wrong.
  Future<String?> signInAgain(
    GoogleAccountRef account, {
    Future<void>? cancel,
  }) async {
    final GoogleSession session;
    try {
      session = await _authRegistry.signInWithGoogle(
        loginHint: account.email,
        cancel: cancel,
      );
    } on GoogleSignInCancelled {
      return 'Sign-in was cancelled.';
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Google sign-in failed: ${redact('$e')}';
    }
    if (session.account != account) {
      return 'You signed in as ${session.email}, but these projects use '
          '${account.email}. Sign in again and choose ${account.email}.';
    }
    final refreshToken = session.credentials.refreshToken;
    if (refreshToken != null) {
      try {
        await _repository.saveGoogleRefreshToken(account, refreshToken);
      } catch (e) {
        return 'Could not save the sign-in: ${redact('$e')}';
      }
    }
    _authRegistry.registerGoogle(session);
    return null;
  }

  /// Plan Decision 12.
  String? _selectionAfterAdding(List<Project> added, List<Project> projects) {
    if (added.length == 1) {
      return added.single.id;
    }
    final current = state.selectedId;
    if (current != null && projects.any((p) => p.id == current)) {
      return current;
    }
    return ([...added]..sort(_byName)).first.id;
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
