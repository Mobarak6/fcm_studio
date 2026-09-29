import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/core/utils/ids.dart';
import 'package:fcm_studio/features/presets/cubit/presets_state.dart';
import 'package:fcm_studio/features/presets/data/presets_repository.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/presets/cubit/presets_state.dart';

/// The preset list and its actions (spec §6). Storage failures are thrown to
/// the caller, which reports them in the error banner.
class PresetsCubit extends Cubit<PresetsState> {
  PresetsCubit({
    required this._repository,
    this._clock = const SystemClock(),
    this._newId = newUuid,
  }) : super(const PresetsState());

  final PresetsRepository _repository;
  final Clock _clock;
  final IdGenerator _newId;

  /// Loads the built-in and the user presets. When the user presets can't be
  /// read, the built-in ones still appear and the error is rethrown.
  Future<void> load() async {
    emit(state.copyWith(status: PresetsStatus.loading));
    final builtIns = await _repository.loadBuiltIns();
    final List<Preset> userPresets;
    try {
      userPresets = await _repository.loadUserPresets();
    } catch (_) {
      if (!isClosed) {
        emit(state.copyWith(status: PresetsStatus.ready, builtIns: builtIns));
      }
      rethrow;
    }
    if (isClosed) {
      return;
    }
    emit(
      PresetsState(
        status: PresetsStatus.ready,
        builtIns: builtIns,
        userPresets: userPresets,
      ),
    );
  }

  /// "Save as preset": a new preset from the composer's template and variables.
  /// Throws [ArgumentError] when the template sets the target.
  Future<Preset> saveAs({
    required String name,
    required Map<String, Object?> template,
    required List<VariableDef> variables,
    String description = '',
  }) async {
    _checkTemplate(template);
    final now = _clock.now();
    final preset = Preset(
      id: _newId(),
      name: name.trim(),
      description: description.trim(),
      variables: variables,
      template: template,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.save(preset);
    _putUserPreset(preset);
    return preset;
  }

  /// "Update preset": overwrites the stored preset [id] with the composer's
  /// template and variables. Its current name, description and createdAt
  /// stay, so a rename since the composer loaded it is kept. Throws
  /// [StateError] for a missing or built-in preset, and [ArgumentError] when
  /// the template sets the target.
  Future<Preset> update(
    String id, {
    required Map<String, Object?> template,
    required List<VariableDef> variables,
  }) async {
    _checkTemplate(template);
    final preset = state.byId(id);
    if (preset == null) {
      throw StateError('The preset no longer exists.');
    }
    if (preset.builtIn) {
      throw StateError('Built-in presets are read-only.');
    }
    final updated = preset.copyWith(
      template: template,
      variables: variables,
      updatedAt: _clock.now(),
    );
    await _repository.save(updated);
    _putUserPreset(updated);
    return updated;
  }

  /// An editable copy, e.g. of a built-in preset.
  Future<Preset> duplicate(Preset preset) async {
    final now = _clock.now();
    final copy = preset.copyWith(
      id: _newId(),
      name: PresetCodec.uniqueName('${preset.name} (copy)', _takenNames()),
      builtIn: false,
      createdAt: now,
      updatedAt: now,
    );
    await _repository.save(copy);
    _putUserPreset(copy);
    return copy;
  }

  Future<Preset> rename(
    Preset preset, {
    required String name,
    required String description,
  }) async {
    final renamed = preset.copyWith(
      name: name.trim(),
      description: description.trim(),
      updatedAt: _clock.now(),
    );
    await _repository.save(renamed);
    _putUserPreset(renamed);
    return renamed;
  }

  /// Deletes a user preset. Built-in presets are ignored.
  Future<void> delete(Preset preset) async {
    if (preset.builtIn) {
      return;
    }
    await _repository.remove(preset.id);
    emit(
      state.copyWith(
        userPresets: state.userPresets.where((p) => p.id != preset.id).toList(),
      ),
    );
  }

  /// The export file for [presets]. Built-in presets are left out, because
  /// every install has them.
  String exportText(List<Preset> presets) => PresetCodec.encode(
    presets.where((p) => !p.builtIn).toList(),
    exportedAt: _clock.now(),
  );

  /// Reads an import file and lists name conflicts.
  /// Throws [PresetFormatException] when the file can't be imported.
  ImportPreview previewImport(String text) => PresetCodec.preview(
    existing: state.all,
    incoming: PresetCodec.decode(text),
  );

  /// Stores the previewed presets. Returns how many were imported.
  Future<int> applyImport(
    ImportPreview preview,
    ImportConflictChoice choice,
  ) async {
    final toSave = PresetCodec.resolve(
      existing: state.all,
      incoming: preview.incoming,
      choice: choice,
      newId: _newId,
      now: _clock.now(),
    );
    await _repository.saveAll(toSave);
    await load();
    return toSave.length;
  }

  void _putUserPreset(Preset preset) {
    emit(
      state.copyWith(
        userPresets: [
          for (final p in state.userPresets)
            if (p.id != preset.id) p,
          preset,
        ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      ),
    );
  }

  /// A safety net: the UI checks [Preset.templateProblem] before saving.
  static void _checkTemplate(Map<String, Object?> template) {
    final problem = Preset.templateProblem(template);
    if (problem != null) {
      throw ArgumentError(problem);
    }
  }

  Set<String> _takenNames() => {
    for (final p in state.all) PresetCodec.normalizeName(p.name),
  };
}
