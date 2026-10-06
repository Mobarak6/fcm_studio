import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/domain/preset_groups.dart';

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

  /// [userPresets] and [builtIns] by group, in display order.
  List<PresetGroup> get groups =>
      groupPresets(userPresets: userPresets, builtIns: builtIns);

  /// Every group's name, A→Z ignoring case, for suggestions. No group isn't
  /// a name.
  List<String> get groupNames => [
    for (final group in groups)
      if (group.key.isNotEmpty) group.name,
  ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  Preset? byId(String id) {
    for (final preset in all) {
      if (preset.id == id) {
        return preset;
      }
    }
    return null;
  }

  /// True when another preset in [group] already uses [name] (both ignoring
  /// case). Presets in different groups may share a name.
  bool nameTaken(String name, {String group = '', String? exceptId}) => all.any(
    (p) =>
        p.id != exceptId &&
        PresetCodec.identityOf(p) == PresetCodec.identity(group, name),
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
