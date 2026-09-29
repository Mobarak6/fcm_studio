import 'dart:async';

import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/stored_records.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:sembast/sembast.dart';

class HistoryRepository {
  HistoryRepository({required AppDatabase database, this.maxEntries = 1000})
    : _db = database.db;

  static final _store = stringMapStoreFactory.store('history');

  /// Only the newest entries are kept (spec §7.2).
  final int maxEntries;
  final Database _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Fires after every change, so the History screen can reload.
  Stream<void> get changes => _changes.stream;

  /// Adds [entry] and removes the oldest entries beyond [maxEntries].
  Future<void> add(HistoryEntry entry) async {
    await _db.transaction((txn) async {
      await _store.record(entry.id).put(txn, entry.toJson());
      final count = await _store.count(txn);
      if (count > maxEntries) {
        final oldest = await _store.findKeys(
          txn,
          finder: Finder(
            sortOrders: [SortOrder('sentAt')],
            limit: count - maxEntries,
          ),
        );
        await _store.records(oldest).delete(txn);
      }
    });
    _changes.add(null);
  }

  /// Newest first. A record that can't be read is skipped.
  Future<List<HistoryEntry>> loadAll() async {
    final records = await _store.find(
      _db,
      finder: Finder(sortOrders: [SortOrder('sentAt', false)]),
    );
    return [
      for (final record in records)
        ?readStoredRecord(record, HistoryEntry.fromJson),
    ];
  }

  Future<void> clear() async {
    await _store.delete(_db);
    _changes.add(null);
  }
}
