import 'dart:convert';

import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:sembast/sembast.dart';

class ProjectsRepository {
  ProjectsRepository({required AppDatabase database, required this._secrets})
    : _db = database.db;

  static final _projects = stringMapStoreFactory.store('projects');
  static final _settings = StoreRef<String, String>('settings');
  static const _selectedProjectKey = 'selectedProjectId';

  final Database _db;
  final SecretStore _secrets;

  Future<List<Project>> loadAll() async {
    final records = await _projects.find(_db);
    return records.map((record) => Project.fromJson(record.value)).toList()
      ..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );
  }

  Future<void> save(Project project) =>
      _projects.record(project.id).put(_db, project.toJson());

  Future<void> remove(Project project) async {
    await _projects.record(project.id).delete(_db);
    await deleteSecretIfUnused(project.credential);
  }

  /// Deletes the credential's secret unless a stored project still uses it.
  Future<void> deleteSecretIfUnused(CredentialRef credential) async {
    final projects = await loadAll();
    if (projects.any((p) => p.credential == credential)) {
      return;
    }
    await _secrets.delete(credential.secretKey);
  }

  Future<void> saveServiceAccountKey(
    ServiceAccountKey key, {
    required bool persist,
  }) => _secrets.write(
    ServiceAccountRef(key.clientEmail).secretKey,
    key.rawJson,
    persist: persist,
  );

  Future<ServiceAccountKey?> readServiceAccountKey(
    ServiceAccountRef credential,
  ) async {
    final raw = await _secrets.read(credential.secretKey);
    if (raw == null) {
      return null;
    }
    try {
      return ServiceAccountKey.parse(raw);
    } on ServiceAccountKeyException {
      return null;
    }
  }

  /// Desktop only: the browser gets no refresh token (plan Decision 11).
  Future<void> saveGoogleRefreshToken(
    GoogleAccountRef account,
    String refreshToken,
  ) => _secrets.write(
    account.secretKey,
    jsonEncode({'refreshToken': refreshToken}),
  );

  Future<String?> readGoogleRefreshToken(GoogleAccountRef account) async {
    final raw = await _secrets.read(account.secretKey);
    if (raw == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      final token = decoded is Map<String, Object?>
          ? decoded['refreshToken']
          : null;
      return token is String && token.isNotEmpty ? token : null;
    } on FormatException {
      return null;
    }
  }

  Future<String?> readSelectedProjectId() =>
      _settings.record(_selectedProjectKey).get(_db);

  Future<void> writeSelectedProjectId(String? projectId) async {
    final record = _settings.record(_selectedProjectKey);
    if (projectId == null) {
      await record.delete(_db);
    } else {
      await record.put(_db, projectId);
    }
  }
}
