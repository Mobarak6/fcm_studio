import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';

enum PresetsStatus { initial, loading, ready }

class PresetsState extends Equatable {
  const PresetsState({
    this.status = PresetsStatus.initial,
    this.builtIns = const [],
    this.userPresets = const [],
  });

  final PresetsStatus status;
  final List<Preset> builtIns;

  /// Sorted by name.
  final List<Preset> userPresets;

  List<Preset> get all => [...builtIns, ...userPresets];

  Preset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  /// True when another preset already uses [name] (ignoring case).
  bool nameTaken(String name, {String? exceptId}) => all.any(
    (p) =>
        p.id != exceptId &&
        PresetCodec.normalizeName(p.name) == PresetCodec.normalizeName(name),
  );

  PresetsState copyWith({
    PresetsStatus? status,
    List<Preset>? builtIns,
    List<Preset>? userPresets,
  }) => PresetsState(
    status: status ?? this.status,
    builtIns: builtIns ?? this.builtIns,
    userPresets: userPresets ?? this.userPresets,
  );

  @override
  List<Object?> get props => [status, builtIns, userPresets];
}
