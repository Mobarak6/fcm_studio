import 'package:fcm_studio/features/presets/cubit/presets_state.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_groups.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final at = DateTime.utc(2026, 10, 6);

  Preset preset(String name, {String group = '', bool builtIn = false}) =>
      Preset(
        id: name,
        name: name,
        group: group,
        builtIn: builtIn,
        template: const {},
        createdAt: at,
        updatedAt: at,
      );

  test('groups with your presets come first, then No group, then the rest', () {
    final groups = groupPresets(
      userPresets: [
        preset('a', group: 'Zeta'),
        preset('b', group: 'alpha'),
        preset('c'),
      ],
      builtIns: [
        preset('x', group: 'Generic', builtIn: true),
        preset('y', group: '6amMart', builtIn: true),
        preset('z', group: 'Zeta', builtIn: true),
      ],
    );
    expect(groups.map((g) => g.key), [
      'alpha',
      'zeta',
      '',
      '6ammart',
      'generic',
    ]);
    expect(groups.map((g) => g.name), [
      'alpha',
      'Zeta',
      'No group',
      '6amMart',
      'Generic',
    ]);
  });

  test('inside a group, your presets come before the built-in ones', () {
    final groups = groupPresets(
      userPresets: [
        preset('a', group: 'G'),
        preset('b', group: 'G'),
      ],
      builtIns: [
        preset('y', group: 'G', builtIn: true),
        preset('x', group: 'G', builtIn: true),
      ],
    );
    expect(groups.single.presets.map((p) => p.name), ['a', 'b', 'y', 'x']);
  });

  test('groups that differ only in case or spaces are one group', () {
    final groups = groupPresets(
      userPresets: [
        preset('a', group: 'stackFood'),
        preset('b', group: ' StackFood '),
      ],
      builtIns: const [],
    );
    expect(groups.single.key, 'stackfood');
    expect(
      groups.single.name,
      'stackFood',
      reason: 'the first preset spells it',
    );
    expect(groups.single.presets, hasLength(2));
  });

  test('there is no No group section when every preset has a group', () {
    final groups = groupPresets(
      userPresets: const [],
      builtIns: [preset('x', group: 'Generic', builtIn: true)],
    );
    expect(groups.map((g) => g.key), ['generic']);
  });

  test('PresetsState groups its presets and lists the names A→Z', () {
    final state = PresetsState(
      builtIns: [
        preset('x', group: 'Generic', builtIn: true),
        preset('y', group: '6amMart', builtIn: true),
      ],
      userPresets: [
        preset('a', group: 'zeta'),
        preset('b'),
      ],
    );
    expect(state.groups.map((g) => g.key), ['zeta', '', '6ammart', 'generic']);
    expect(state.groupNames, ['6amMart', 'Generic', 'zeta']);
  });
}
