import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Every long-lived service, created once at startup.
class AppDependencies {
  factory AppDependencies({
    required http.Client httpClient,
    required AppDatabase database,
    required SecretStore secrets,
    Clock clock = const SystemClock(),
  }) {
    final repository = ProjectsRepository(database: database, secrets: secrets);
    return AppDependencies._(
      httpClient: httpClient,
      database: database,
      projectsRepository: repository,
      authRegistry: ProjectAuthRegistry(
        repository: repository,
        httpClient: httpClient,
        clock: clock,
      ),
      firebaseProjectsApi: FirebaseProjectsApi(httpClient: httpClient),
      fcmClient: FcmClient(httpClient: httpClient),
    );
  }

  AppDependencies._({
    required this.httpClient,
    required this.database,
    required this.projectsRepository,
    required this.authRegistry,
    required this.firebaseProjectsApi,
    required this.fcmClient,
  });

  static Future<AppDependencies> create() async => AppDependencies(
    httpClient: http.Client(),
    database: await AppDatabase.open(),
    // On web, keys stay in memory unless the user ticks "Remember on this browser".
    secrets: LayeredSecretStore(
      persistent: FlutterSecureSecretStore(),
      alwaysPersist: !kIsWeb,
    ),
  );

  final http.Client httpClient;
  final AppDatabase database;
  final ProjectsRepository projectsRepository;
  final ProjectAuthRegistry authRegistry;
  final FirebaseProjectsApi firebaseProjectsApi;
  final FcmClient fcmClient;
}
