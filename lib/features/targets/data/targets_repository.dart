import 'dart:async';

import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/stored_records.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:sembast/sembast.dart';

class TargetsRepository {
  TargetsRepository({required AppDatabase database}) : _db = database.db;

  static final _store = stringMapStoreFactory.store('targets');

  final Database _db;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Fires after every change, so screens can reload.
  Stream<void> get changes => _changes.stream;

  /// All saved targets, most recently used first. A record that can't be
  /// read is skipped.
  Future<List<SavedTarget>> loadAll() async {
    final records = await _store.find(_db);
    return [
      for (final record in records)
        ?readStoredRecord(record, SavedTarget.fromJson),
    ]..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
  }

  Future<void> save(SavedTarget target) async {
    await _store.record(target.id).put(_db, target.toJson());
    _changes.add(null);
  }

  Future<void> remove(String id) async {
    await _store.record(id).delete(_db);
    _changes.add(null);
  }

  Future<SavedTarget?> findMatching(Target target) async {
    for (final saved in await loadAll()) {
      if (saved.matches(target)) {
        return saved;
      }
    }
    return null;
  }

  /// Sets `lastUsedAt` of the saved targets that match [target].
  Future<void> markUsed(Target target, DateTime at) async {
    final matching = (await loadAll()).where((t) => t.matches(target)).toList();
    if (matching.isEmpty) {
      return;
    }
    for (final saved in matching) {
      await _store
          .record(saved.id)
          .put(_db, saved.copyWith(lastUsedAt: at).toJson());
    }
    _changes.add(null);
  }
}
