import 'package:fcm_studio/core/storage/app_database_platform.dart';
import 'package:sembast/sembast_memory.dart';

/// The local database for projects (and in later milestones presets, targets and history).
/// Secrets never go here; they live in SecretStore.
class AppDatabase {
  AppDatabase(this.db);

  static const fileName = 'fcm_studio.db';

  final Database db;

  static Future<AppDatabase> open() async =>
      AppDatabase(await openPlatformDatabase(fileName));

  /// A fresh, empty database for tests.
  static Future<AppDatabase> inMemory() async =>
      AppDatabase(await newDatabaseFactoryMemory().openDatabase(fileName));

  Future<void> close() => db.close();
}
