import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/google_auth_flow_platform.dart';
import 'package:fcm_studio/core/auth/google_user_info.dart';
import 'package:fcm_studio/core/auth/oauth_config.dart';
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:fcm_studio/core/platform/file_access.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/features/composer/data/message_sender.dart';
import 'package:fcm_studio/features/devices/data/adb_locator.dart';
import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/data/process_runner_platform.dart';
import 'package:fcm_studio/features/devices/data/recent_packages_repository.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/presets/data/presets_repository.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/settings/data/settings_repository.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Every long-lived service, created once at startup.
class AppDependencies {
  factory AppDependencies({
    required http.Client httpClient,
    required AppDatabase database,
    required SecretStore secrets,
    Clock clock = const SystemClock(),
    FileAccess files = const PlatformFileAccess(),
    Future<String> Function()? loadBuiltInPresets,
    PlatformFeatures platform = PlatformFeatures.current,
    ProcessRunner? processRunner,
    Map<String, String>? environment,
    bool? isWindows,
    AdbService Function(String adbPath)? adbServiceFor,
    GoogleAuthFlow? googleFlow,
    GoogleUserInfo? googleUserInfo,
  }) {
    final projectsRepository = ProjectsRepository(
      database: database,
      secrets: secrets,
    );
    final authRegistry = ProjectAuthRegistry(
      repository: projectsRepository,
      httpClient: httpClient,
      clock: clock,
      googleFlow: googleFlow,
      googleUserInfo: googleUserInfo,
    );
    final historyRepository = HistoryRepository(database: database);
    final targetsRepository = TargetsRepository(database: database);
    final runner = processRunner ?? createProcessRunner();
    return AppDependencies._(
      httpClient: httpClient,
      database: database,
      clock: clock,
      files: files,
      platform: platform,
      projectsRepository: projectsRepository,
      authRegistry: authRegistry,
      firebaseProjectsApi: FirebaseProjectsApi(httpClient: httpClient),
      presetsRepository: PresetsRepository(
        database: database,
        loadBuiltInJson:
            loadBuiltInPresets ??
            () => rootBundle.loadString(PresetsRepository.builtInAsset),
      ),
      historyRepository: historyRepository,
      targetsRepository: targetsRepository,
      messageSender: MessageSender(
        fcmClient: FcmClient(httpClient: httpClient),
        auth: authRegistry,
        history: historyRepository,
        targets: targetsRepository,
        clock: clock,
      ),
      settingsRepository: SettingsRepository(database: database),
      recentPackagesRepository: RecentPackagesRepository(database: database),
      adbLocator: AdbLocator(
        runner: runner,
        environment: environment ?? platformEnvironment(),
        isWindows: isWindows ?? platformIsWindows(),
      ),
      adbServiceFor:
          adbServiceFor ??
          (path) => ProcessAdbService(runner: runner, adbPath: path),
    );
  }

  AppDependencies._({
    required this.httpClient,
    required this.database,
    required this.clock,
    required this.files,
    required this.platform,
    required this.projectsRepository,
    required this.authRegistry,
    required this.firebaseProjectsApi,
    required this.presetsRepository,
    required this.historyRepository,
    required this.targetsRepository,
    required this.messageSender,
    required this.settingsRepository,
    required this.recentPackagesRepository,
    required this.adbLocator,
    required this.adbServiceFor,
  });

  static Future<AppDependencies> create() async {
    final httpClient = http.Client();
    // A missing or broken config/oauth.json just leaves Google sign-in off
    // (spec §4.4).
    final oauth = await OAuthConfig.load(
      () => rootBundle.loadString(OAuthConfig.assetPath),
    );
    return AppDependencies(
      httpClient: httpClient,
      database: await AppDatabase.open(),
      // On web, keys stay in memory unless the user ticks "Remember on this browser".
      secrets: LayeredSecretStore(
        persistent: FlutterSecureSecretStore(),
        alwaysPersist: !kIsWeb,
      ),
      googleFlow: createGoogleAuthFlow(oauth, httpClient),
    );
  }

  final http.Client httpClient;
  final AppDatabase database;
  final Clock clock;
  final FileAccess files;
  final PlatformFeatures platform;
  final ProjectsRepository projectsRepository;
  final ProjectAuthRegistry authRegistry;
  final FirebaseProjectsApi firebaseProjectsApi;
  final PresetsRepository presetsRepository;
  final HistoryRepository historyRepository;
  final TargetsRepository targetsRepository;
  final MessageSender messageSender;
  final SettingsRepository settingsRepository;
  final RecentPackagesRepository recentPackagesRepository;
  final AdbLocator adbLocator;
  final AdbService Function(String adbPath) adbServiceFor;
}
