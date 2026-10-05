import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:sembast/sembast.dart';

/// App settings that are not about one feature's data. The same store holds
/// the selected project (ProjectsRepository).
class SettingsRepository {
  SettingsRepository({required AppDatabase database}) : _db = database.db;

  static final _settings = StoreRef<String, String>('settings');
  static const _adbPathKey = 'adbPath';
  static const _bridgeAutoConnectKey = 'bridgeAutoConnect';

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

  /// Whether the web page connects to the bridge by itself (bridge design
  /// §4.4): on after the first connection, off after Disconnect.
  Future<bool> readBridgeAutoConnect() async =>
      await _settings.record(_bridgeAutoConnectKey).get(_db) == 'true';

  Future<void> writeBridgeAutoConnect(bool on) async {
    final record = _settings.record(_bridgeAutoConnectKey);
    if (on) {
      await record.put(_db, 'true');
    } else {
      await record.delete(_db);
    }
  }
}
