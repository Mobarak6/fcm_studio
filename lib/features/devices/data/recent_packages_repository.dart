import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:sembast/sembast.dart';

/// The last packages whose token was read, per phone (spec §9.2).
class RecentPackagesRepository {
  RecentPackagesRepository({required AppDatabase database}) : _db = database.db;

  static const maxRecent = 5;
  static final _store = stringMapStoreFactory.store('devices');

  final Database _db;

  /// Newest first.
  Future<List<String>> recent(String serial) async {
    final record = await _store.record(serial).get(_db);
    final packages = record?['recentPackages'];
    return packages is List<Object?>
        ? [
            for (final package in packages)
              if (package is String) package,
          ]
        : const [];
  }

  Future<void> remember(String serial, String package) async {
    final updated = [
      package,
      ...(await recent(serial)).where((p) => p != package),
    ].take(maxRecent).toList();
    await _store.record(serial).put(_db, {
      'schemaVersion': 1,
      'recentPackages': updated,
    });
  }
}
