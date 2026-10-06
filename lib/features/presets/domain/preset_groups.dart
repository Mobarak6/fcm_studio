import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';

/// Presets that share a group (preset groups spec §3).
class PresetGroup extends Equatable {
  const PresetGroup({
    required this.key,
    required this.name,
    required this.presets,
  });

  /// The section name for presets without a group.
  static const noGroupName = 'No group';

  /// How groups are compared: trimmed and lower-cased, like names.
  /// `''` is No group.
  static String keyOf(String group) => PresetCodec.normalizeName(group);

  final String key;

  /// As the first preset in the group spells it, or [noGroupName].
  final String name;

  /// Your presets first, then the built-in ones.
  final List<Preset> presets;

  @override
  List<Object?> get props => [key, name, presets];
}

/// Lists presets by group, in the order the Presets screen and the picker
/// show them: named groups that hold one of [userPresets], A→Z; then No
/// group; then the other groups, A→Z. Inside a group, [userPresets] (sorted
/// by name) come first, then [builtIns] in file order.
List<PresetGroup> groupPresets({
  required List<Preset> userPresets,
  required List<Preset> builtIns,
}) {
  final byKey = <String, List<Preset>>{};
  for (final preset in [...userPresets, ...builtIns]) {
    byKey
        .putIfAbsent(PresetGroup.keyOf(preset.group), () => <Preset>[])
        .add(preset);
  }
  final yours = {for (final p in userPresets) PresetGroup.keyOf(p.group)};
  final named = byKey.keys.where((key) => key.isNotEmpty);
  final keys = [
    ...(named.where(yours.contains).toList()..sort()),
    if (byKey.containsKey('')) '',
    ...(named.where((key) => !yours.contains(key)).toList()..sort()),
  ];
  return [
    for (final key in keys)
      PresetGroup(
        key: key,
        name: key.isEmpty ? PresetGroup.noGroupName : byKey[key]!.first.group,
        presets: byKey[key]!,
      ),
  ];
}
