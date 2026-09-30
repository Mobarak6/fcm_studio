import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:sembast/sembast.dart';

/// App settings that are not about one feature's data. The same store holds
/// the selected project (ProjectsRepository).
class SettingsRepository {
  SettingsRepository({required AppDatabase database}) : _db = database.db;

  static final _settings = StoreRef<String, String>('settings');
  static const _adbPathKey = 'adbPath';

  final Database _db;

  Future<String?> readAdbPath() => _settings.record(_adbPathKey).get(_db);

  /// Null or blank clears the path, so adb is found automatically again.
  Future<void> writeAdbPath(String? path) async {
    final record = _settings.record(_adbPathKey);
    final trimmed = path?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await record.delete(_db);
    } else {
      await record.put(_db, trimmed);
    }
  }
}
