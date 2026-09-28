import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:sembast/sembast.dart';

class PresetsRepository {
  PresetsRepository({
    required AppDatabase database,
    required this._loadBuiltInJson,
  }) : _db = database.db;

  static const builtInAsset = 'assets/presets/builtin.json';
  static final _store = stringMapStoreFactory.store('presets');

  final Database _db;

  /// Reads [builtInAsset]; tests read the file from disk instead.
  final Future<String> Function() _loadBuiltInJson;

  /// The presets that ship with the app. Read-only.
  Future<List<Preset>> loadBuiltIns() async => [
    for (final preset in PresetCodec.decode(await _loadBuiltInJson()))
      preset.copyWith(builtIn: true),
  ];

  /// The user's presets, sorted by name.
  Future<List<Preset>> loadUserPresets() async {
    final records = await _store.find(_db);
    return records.map((record) => Preset.fromJson(record.value)).toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  Future<void> save(Preset preset) async {
    if (preset.builtIn) {
      throw StateError('Built-in presets are read-only.');
    }
    await _store.record(preset.id).put(_db, preset.toJson());
  }

  Future<void> saveAll(List<Preset> presets) async {
    await _db.transaction((txn) async {
      for (final preset in presets) {
        await _store.record(preset.id).put(txn, preset.toJson());
      }
    });
  }

  Future<void> remove(String id) async {
    await _store.record(id).delete(_db);
  }
}
