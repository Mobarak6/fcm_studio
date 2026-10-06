# Preset Groups Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every preset gets an optional group, and the Presets screen and the composer's preset picker list presets by group.

**Architecture:**
- **Model:** `Preset` gets a `group` string field.
- **Grouping:** one pure function, `groupPresets`, decides the order of groups and of the presets inside them. `PresetsState.groups` exposes its result, and both views read it.
- **Setting a group:** the existing details dialog gets a Group field with autocomplete.
- **Built-in groups:** the built-in presets get their groups in `assets/presets/builtin.json`.

**Tech Stack:** Flutter 3.44.9 / Dart 3.12, flutter_bloc, equatable, sembast.

**Spec:** [docs/superpowers/specs/2026-10-06-preset-groups-design.md](../specs/2026-10-06-preset-groups-design.md). It builds on the main spec §5.5 and §6.

## Global Constraints

**Data and format:**
- Groups are compared with `PresetCodec.normalizeName` (trimmed, lower-cased). `''` is No group.
- `kPresetSchemaVersion` stays `1`, and `PresetCodec.version` stays `1`.
- Preset names stay unique across all groups. `nameTaken`, `PresetCodec.preview` and `PresetCodec.resolve` don't change.

**Built-in groups:** `Generic` (the 4 `builtin.*` presets that aren't 6amMart) and `6amMart` (the 23 `builtin.6ammart.*` presets).

**Exact copy:**
- `No group`
- `Group (optional)`
- `Edit details…` (menu item)
- `Edit details` (dialog title)
- `No presets yet. Save one from the composer, or import a file.`

**Keys:**
- `ValueKey('preset-group-$key')` (section header);
- `ValueKey('preset-group-check-$key')` (its checkbox);
- `PresetDetailsDialog.groupKey = Key('preset-group')`;
- picker header entry value `'group:$key'`.

**Code style (repo lints):**
- single quotes, `prefer_final_locals`, `unawaited_futures`, `always_declare_return_types`;
- braces on every `if` body;
- strict inference: type empty literals, e.g. `<Preset>[]`.

**Commands:**
- one test file: `flutter test <file>`;
- the whole suite: `flutter test`;
- lints: `flutter analyze`.

**Git:**
- Commit on `main`.
- **No `Co-Authored-By` trailer** (the user's standing rule). Don't pass an author; the repo config sets it.
- Never stage `.firebase/hosting.YnVpbGQvd2Vi.cache`, `.metadata`, `devtools_options.yaml`, `config/oauth.json` or `config/oauth.example.json`.

## Review Focus

1. **Upgrading with existing presets:** stored presets and old export files have no `group`. They must load into No group, which sits above the built-in groups, so your presets stay near the top. Pinned by the Task 1 test "is empty when missing or not a string, and trimmed" and the Task 3 test "groups with your presets come first, then No group, then the rest".
2. **One group typed two ways** (`6amMart`, ` 6ammart `): one section, one header, and no suggestion of the exact text already typed. Pinned by the Task 3 test "groups that differ only in case or spaces are one group" and the Task 4 test "the Group field suggests existing groups and trims".
3. **Searches that match only a group name, or nothing in a group:** a group-name query lists that whole group, and a header never shows without a preset under it. Pinned by the Task 6 test "the search matches group names and hides empty groups".
4. **A partly ticked group:** its checkbox shows a dash, and a click ticks all of its presets. Export then holds exactly that group's presets, with their group. Pinned by the Task 5 test "the group checkbox ticks and unticks all of its presets".
5. **A preset that changes group** (Edit details…, or Duplicate of a built-in): it moves to the right section, and an emptied section disappears. Pinned by the Task 5 test "Edit details… moves a preset to another group" and the Task 4 cubit test.

## Decisions made while planning (rulings against the spec's silence)

- **The header checkbox sits in the `ListTile`'s leading slot,** so it lines up with the preset checkboxes. The count and the open/closed arrow go in the trailing slot.
- **Duplicating a built-in moves its group up.** The copy is your preset, so its group (for example Generic) now holds one of your presets, and §5.2 lists it first.
- **The picker gets no `searchCallback`.** In Flutter 3.44, `DropdownMenu._handleSubmitted` only selects an `enabled` entry, and arrow keys skip disabled ones. So a highlighted header can't be picked.
- **Screen tests close the 6amMart section to reach the Generic presets.** Scrolling isn't needed: with 6amMart closed, Generic fits on the 1400×900 test screen.

---

### Task 1: The `group` field on `Preset`

**Files:**
- Modify: `lib/features/presets/domain/preset.dart`
- Test: `test/features/presets/preset_codec_test.dart`

**Interfaces:**
- Produces:
  - `Preset.group` (`String`, default `''`);
  - `Preset(..., String group = '')`;
  - `Preset.copyWith({String? group, ...})`.
  - `Preset.fromJson` reads `group` trimmed (anything that isn't a string reads as `''`), and `toJson` writes `'group'`.

- [ ] **Step 1: Write the failing tests**

Add this group at the end of `main()` in `test/features/presets/preset_codec_test.dart`. It already imports `dart:convert`, `preset.dart` and `preset_codec.dart`, and defines `preset` and `created`.

```dart
  group('group', () {
    Map<String, Object?> json({Object? group}) => {
      ...(preset.toJson()..remove('group')),
      'group': ?group,
    };

    test('is empty when missing or not a string, and trimmed', () {
      expect(Preset.fromJson(json()).group, '');
      expect(Preset.fromJson(json(group: 42)).group, '');
      expect(Preset.fromJson(json(group: '  StackFood ')).group, 'StackFood');
    });

    test('travels in an export file', () {
      final text = PresetCodec.encode([
        preset.copyWith(group: 'StackFood'),
      ], exportedAt: created);
      final file = jsonDecode(text) as Map<String, Object?>;
      final first =
          (file['presets']! as List<Object?>).first! as Map<String, Object?>;
      expect(first['group'], 'StackFood');
      expect(PresetCodec.decode(text).single.group, 'StackFood');
    });
  });
```

- [ ] **Step 2: Run the tests to check they fail**

Run: `flutter test test/features/presets/preset_codec_test.dart`
Expected: compile error, "The named parameter 'group' isn't defined" / "The getter 'group' isn't defined".

- [ ] **Step 3: Add the field**

In `lib/features/presets/domain/preset.dart`:

Constructor, after `this.description = '',`:
```dart
    this.group = '',
```

In `fromJson`, next to `final description = json['description'];`:
```dart
    final group = json['group'];
```
and in the returned `Preset(...)`, after `description: ...,`:
```dart
      group: group is String ? group.trim() : '',
```

Field, after `final String description;`:
```dart
  /// The group the preset is listed under, stored trimmed. '' is No group.
  final String group;
```

`copyWith`: add the parameter `String? group,` after `String? description,`, and `group: group ?? this.group,` after `description: ...`.

`toJson`: after `'description': description,`:
```dart
    'group': group,
```

`props`: add `group,` after `description,`.

- [ ] **Step 4: Run the tests to check they pass**

Run: `flutter test test/features/presets/`
Expected: all pass. The existing round-trip test still passes because `group` defaults to `''` on both sides.

- [ ] **Step 5: Commit**

```bash
git add lib/features/presets/domain/preset.dart test/features/presets/preset_codec_test.dart
git commit -m "feat: presets have an optional group

A missing or non-string group reads as no group, so stored presets and
older export files load unchanged. Exports carry the group."
```

---

### Task 2: Built-in presets in the groups Generic and 6amMart

**Files:**
- Modify: `assets/presets/builtin.json`
- Test: `test/features/presets/sixammart_presets_test.dart`, `test/features/presets/preset_codec_test.dart`

**Interfaces:**
- Consumes: `Preset.group` (Task 1).
- Produces:
  - every `builtin.6ammart.*` preset has `group == '6amMart'`, and the other 4 have `group == 'Generic'`;
  - `builtin.6ammart.all.push_notification` is named `Admin push notification (topic)`, and `builtin.6ammart.all.maintenance` is named `Maintenance mode (silent)`.

- [ ] **Step 1: Write the failing tests**

In `test/features/presets/sixammart_presets_test.dart`, change the `'all'` prefix and the names test, and add a group test after it:

```dart
const namePrefixes = {
  // The group says "6amMart", so the presets for every app have no prefix.
  'all': '',
  'user': 'User app · ',
  'delivery': 'Delivery app · ',
  'store': 'Store app · ',
};
```

```dart
  test('names start with the app the preset is for', () {
    for (final preset in presets) {
      final app = preset.id.split('.')[2];
      expect(preset.name, startsWith(namePrefixes[app]!), reason: preset.id);
      expect(preset.name, isNot(startsWith('6amMart')), reason: preset.id);
      expect(preset.description, isNotEmpty, reason: preset.id);
    }
  });

  test('they are all in the 6amMart group', () {
    expect({for (final preset in presets) preset.group}, {'6amMart'});
  });
```

In `test/features/presets/preset_codec_test.dart`, after the test `'the built-in presets are valid and render with their defaults'`, add (the file already imports `dart:io`):

```dart
  test('the built-in presets are in the groups Generic and 6amMart', () {
    final builtIns = PresetCodec.decode(
      File('assets/presets/builtin.json').readAsStringSync(),
    );
    for (final builtIn in builtIns) {
      expect(
        builtIn.group,
        builtIn.id.startsWith('builtin.6ammart.') ? '6amMart' : 'Generic',
        reason: builtIn.id,
      );
    }
    expect(builtIns.where((p) => p.group == 'Generic'), hasLength(4));
  });
```

- [ ] **Step 2: Run the tests to check they fail**

Run: `flutter test test/features/presets/sixammart_presets_test.dart test/features/presets/preset_codec_test.dart`
Expected: FAIL. The names still start with "6amMart · ", and the groups are `''`.

- [ ] **Step 3: Edit the JSON**

The file is hand-formatted, so edit it as text rather than re-serializing it. Run from the repo root:

```bash
python3 - <<'EOF'
import re
path = 'assets/presets/builtin.json'
text = open(path, encoding='utf-8').read()
text = text.replace('"name": "6amMart · Admin push notification (topic)"',
                    '"name": "Admin push notification (topic)"')
text = text.replace('"name": "6amMart · Maintenance mode (silent)"',
                    '"name": "Maintenance mode (silent)"')
out, group = [], None
for line in text.split('\n'):
    m = re.match(r'^      "id": "(.+)",$', line)
    if m:
        group = '6amMart' if m.group(1).startswith('builtin.6ammart.') else 'Generic'
    out.append(line)
    if re.match(r'^      "name": ', line):
        out.append(f'      "group": "{group}",')
open(path, 'w', encoding='utf-8').write('\n'.join(out))
EOF
grep -c '^      "group": ' assets/presets/builtin.json
grep -c '"name": "6amMart' assets/presets/builtin.json
```

Expected output: `27`, then `0`.

- [ ] **Step 4: Run the tests to check they pass**

Run: `flutter test test/features/presets/`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add assets/presets/builtin.json test/features/presets/sixammart_presets_test.dart test/features/presets/preset_codec_test.dart
git commit -m "feat: built-in presets in the groups Generic and 6amMart

All 23 6amMart presets (user, delivery and store app) share one group.
The two presets for every app lose their \"6amMart · \" prefix, since
the group now says it."
```

---

### Task 3: Grouping presets for display

**Files:**
- Create: `lib/features/presets/domain/preset_groups.dart`
- Modify: `lib/features/presets/cubit/presets_state.dart`
- Test: `test/features/presets/preset_groups_test.dart` (new)

**Interfaces:**
- Consumes: `Preset.group` (Task 1); `PresetCodec.normalizeName(String) → String`.
- Produces:
  - `class PresetGroup extends Equatable`, with:
    - `String key` (normalized; `''` for No group);
    - `String name`;
    - `List<Preset> presets`;
    - `static const noGroupName = 'No group'`;
    - `static String keyOf(String group)`.
  - `List<PresetGroup> groupPresets({required List<Preset> userPresets, required List<Preset> builtIns})`.
  - `PresetsState.groups → List<PresetGroup>`.
  - `PresetsState.groupNames → List<String>`: names A→Z ignoring case, No group left out.

- [ ] **Step 1: Write the failing tests**

Create `test/features/presets/preset_groups_test.dart`:

```dart
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
      userPresets: [preset('a', group: 'G'), preset('b', group: 'G')],
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
    expect(groups.single.name, 'stackFood', reason: 'the first preset spells it');
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
      userPresets: [preset('a', group: 'zeta'), preset('b')],
    );
    expect(state.groups.map((g) => g.key), ['zeta', '', '6ammart', 'generic']);
    expect(state.groupNames, ['6amMart', 'Generic', 'zeta']);
  });
}
```

- [ ] **Step 2: Run the tests to check they fail**

Run: `flutter test test/features/presets/preset_groups_test.dart`
Expected: compile error, "Target of URI doesn't exist: 'package:fcm_studio/features/presets/domain/preset_groups.dart'".

- [ ] **Step 3: Write the helper**

Create `lib/features/presets/domain/preset_groups.dart`:

```dart
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
```

In `lib/features/presets/cubit/presets_state.dart`, add the import
`import 'package:fcm_studio/features/presets/domain/preset_groups.dart';` and these getters after `all`:

```dart
  /// [userPresets] and [builtIns] by group, in display order.
  List<PresetGroup> get groups =>
      groupPresets(userPresets: userPresets, builtIns: builtIns);

  /// Every group's name, A→Z ignoring case, for suggestions. No group isn't
  /// a name.
  List<String> get groupNames => [
    for (final group in groups)
      if (group.key.isNotEmpty) group.name,
  ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
```

- [ ] **Step 4: Run the tests to check they pass**

Run: `flutter test test/features/presets/`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/presets/domain/preset_groups.dart lib/features/presets/cubit/presets_state.dart test/features/presets/preset_groups_test.dart
git commit -m "feat: group presets for display

Groups that hold your presets come first, then No group, then the
built-in groups. Groups that differ only in case are one group."
```

---

### Task 4: Setting a group (dialog, cubit and the three callers)

**Files:**
- Modify:
  - `lib/features/presets/cubit/presets_cubit.dart`
  - `lib/features/presets/view/preset_details_dialog.dart`
  - `lib/features/presets/view/preset_actions.dart`
  - `lib/features/presets/view/presets_screen.dart` (the `PresetAction.edit` case and the menu text only)
  - `lib/features/history/view/history_screen.dart` (`_saveAsPreset`)
- Test:
  - `test/features/presets/presets_cubit_test.dart`
  - `test/features/presets/preset_picker_test.dart`
  - `test/features/presets/presets_screen_test.dart`
  - `test/features/history/history_screen_test.dart`

**Interfaces:**
- Consumes:
  - `Preset.group` and `copyWith(group:)` (Task 1);
  - the built-in groups (Task 2);
  - `PresetsState.groupNames` (Task 3).
- Produces:
  - `PresetsCubit.saveAs({..., String group = ''})`;
  - `PresetsCubit.rename(Preset, {required String name, required String description, required String group})`;
  - `typedef PresetDetails = ({String name, String description, String group})`;
  - `showPresetDetailsDialog(context, {required String title, required bool Function(String) isNameTaken, String name = '', String description = '', String group = '', List<String> groups = const []})`;
  - `PresetDetailsDialog.groupKey`.

- [ ] **Step 1: Write the failing tests**

**`test/features/presets/presets_cubit_test.dart`:**

Change both existing `rename` calls so they pass a group:
- line ~122: `await cubit.rename(saved, name: 'B', description: 'Renamed', group: 'G');`, and add `expect(updated.group, 'G');` after `expect(updated.description, 'Renamed');`. This also shows that Update keeps the group.
- line ~235: `final renamed = await cubit.rename(saved, name: 'B', description: 'Mine', group: '');`

Add:

```dart
  test('Save as and rename store the group trimmed; duplicate keeps it', () async {
    final cubit = await loaded();
    final saved = await cubit.saveAs(
      name: 'A',
      group: ' StackFood ',
      template: template,
      variables: variables,
    );
    expect(saved.group, 'StackFood');

    final moved = await cubit.rename(
      saved,
      name: 'A',
      description: '',
      group: ' Food ',
    );
    expect(moved.group, 'Food');

    final copy = await cubit.duplicate(cubit.state.byId('builtin.simple')!);
    expect(copy.group, 'Generic');

    final restarted = await loaded();
    expect(
      restarted.state.userPresets.map((p) => p.group),
      unorderedEquals(['Food', 'Generic']),
    );
  });
```

**`test/features/presets/preset_picker_test.dart`:** add

```dart
  testWidgets("Save as starts with the loaded preset's group", (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final presets = readCubit<PresetsCubit>(tester);
    composer
      ..loadPreset(presets.state.byId('builtin.simple')!)
      ..setField(['notification', 'body'], 'Changed');
    await tester.pump();

    await tester.tap(find.byKey(PresetPicker.saveAsKey));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(PresetDetailsDialog.groupKey))
          .controller!
          .text,
      'Generic',
    );
    await tester.enterText(find.byKey(PresetDetailsDialog.nameKey), 'Mine');
    await tester.tap(find.byKey(PresetDetailsDialog.saveKey));
    await settleAsync(tester);
    expect(presets.state.userPresets.single.group, 'Generic');
  });

  testWidgets('the Group field suggests existing groups and trims', (
    tester,
  ) async {
    await pumpAppWithProject(tester);
    final presets = readCubit<PresetsCubit>(tester);
    await tester.tap(find.byKey(PresetPicker.saveAsKey));
    await tester.pumpAndSettle();
    final group = find.byKey(PresetDetailsDialog.groupKey);
    Finder suggestion(String text) => find.widgetWithText(InkWell, text);

    await tester.enterText(group, '6AM');
    await tester.pumpAndSettle();
    expect(suggestion('6amMart'), findsOneWidget);
    expect(suggestion('Generic'), findsNothing);

    await tester.tap(suggestion('6amMart'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(group).controller!.text, '6amMart');
    expect(
      suggestion('6amMart'),
      findsNothing,
      reason: 'the group typed exactly is not suggested',
    );

    await tester.enterText(group, '  StackFood ');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PresetDetailsDialog.nameKey), 'Mine');
    await tester.tap(find.byKey(PresetDetailsDialog.saveKey));
    await settleAsync(tester);
    expect(presets.state.userPresets.single.group, 'StackFood');
  });
```

In Flutter 3.44, the default Autocomplete options view (`_AutocompleteOptions`) builds each option as an `InkWell`. The text field has no `InkWell`, so `suggestion(...)` finds only option rows.

**`test/features/presets/presets_screen_test.dart`:** in `'renaming the loaded preset survives a later Update'`:
- change `find.text('Rename…')` to `find.text('Edit details…')`;
- after the `enterText` of the name, add:

```dart
    expect(
      tester
          .widget<TextField>(find.byKey(PresetDetailsDialog.groupKey))
          .controller!
          .text,
      '',
    );
    await tester.enterText(find.byKey(PresetDetailsDialog.groupKey), 'Ops');
```

- after `expect(stored.name, 'Renamed');`, add `expect(stored.group, 'Ops');`.

**`test/features/history/history_screen_test.dart`:** in `'Save as preset stores the message without variables'`:
- before tapping save, add `await tester.enterText(find.byKey(PresetDetailsDialog.groupKey), 'Ops');`;
- at the end, add `expect(saved.group, 'Ops');`.

- [ ] **Step 2: Run the tests to check they fail**

Run: `flutter test test/features/presets/ test/features/history/history_screen_test.dart`
Expected: compile errors: no named parameter `group` on `saveAs`/`rename`, and no `PresetDetailsDialog.groupKey`.

- [ ] **Step 3: Update the cubit**

In `lib/features/presets/cubit/presets_cubit.dart`:

`saveAs`: add the parameter `String group = '',` after `String description = '',`. In the new `Preset(...)`, add `group: group.trim(),` after `description: description.trim(),`.

Replace `rename` with:

```dart
  /// "Edit details": a new name, description and group.
  Future<Preset> rename(
    Preset preset, {
    required String name,
    required String description,
    required String group,
  }) async {
    final renamed = preset.copyWith(
      name: name.trim(),
      description: description.trim(),
      group: group.trim(),
      updatedAt: _clock.now(),
    );
    await _repository.save(renamed);
    _putUserPreset(renamed);
    return renamed;
  }
```

`update` and `duplicate` need no change: `copyWith` keeps the group.

- [ ] **Step 4: Add the Group field to the dialog**

Replace `lib/features/presets/view/preset_details_dialog.dart` with:

```dart
import 'package:flutter/material.dart';

typedef PresetDetails = ({String name, String description, String group});

Future<PresetDetails?> showPresetDetailsDialog(
  BuildContext context, {
  required String title,
  required bool Function(String name) isNameTaken,
  String name = '',
  String description = '',
  String group = '',
  List<String> groups = const [],
}) => showDialog<PresetDetails>(
  context: context,
  builder: (_) => PresetDetailsDialog(
    title: title,
    isNameTaken: isNameTaken,
    name: name,
    description: description,
    group: group,
    groups: groups,
  ),
);

/// Asks for a preset's name, description and group. Names must be unique.
class PresetDetailsDialog extends StatefulWidget {
  const PresetDetailsDialog({
    required this.title,
    required this.isNameTaken,
    this.name = '',
    this.description = '',
    this.group = '',
    this.groups = const [],
    super.key,
  });

  static const nameKey = Key('preset-name');
  static const descriptionKey = Key('preset-description');
  static const groupKey = Key('preset-group');
  static const saveKey = Key('preset-details-save');

  final String title;
  final bool Function(String name) isNameTaken;
  final String name;
  final String description;
  final String group;

  /// The existing groups, suggested while typing a group.
  final List<String> groups;

  @override
  State<PresetDetailsDialog> createState() => _PresetDetailsDialogState();
}

class _PresetDetailsDialogState extends State<PresetDetailsDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.name,
  );
  late final TextEditingController _description = TextEditingController(
    text: widget.description,
  );
  late final TextEditingController _group = TextEditingController(
    text: widget.group,
  );
  final FocusNode _groupFocus = FocusNode();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _group.dispose();
    _groupFocus.dispose();
    super.dispose();
  }

  /// The groups that hold the typed text, ignoring case. The group typed
  /// exactly isn't suggested, so a chosen suggestion closes the list.
  Iterable<String> _suggestions(TextEditingValue value) {
    final typed = value.text.trim().toLowerCase();
    return widget.groups.where((group) {
      final candidate = group.toLowerCase();
      return candidate != typed && candidate.contains(typed);
    });
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    if (widget.isNameTaken(name)) {
      setState(() => _error = 'A preset named "$name" already exists.');
      return;
    }
    Navigator.of(context).pop((
      name: name,
      description: _description.text.trim(),
      group: _group.text.trim(),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              key: PresetDetailsDialog.nameKey,
              controller: _name,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Name', errorText: _error),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            TextField(
              key: PresetDetailsDialog.descriptionKey,
              controller: _description,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
            ),
            const SizedBox(height: 12),
            Autocomplete<String>(
              textEditingController: _group,
              focusNode: _groupFocus,
              optionsBuilder: _suggestions,
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) =>
                      TextField(
                        key: PresetDetailsDialog.groupKey,
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Group (optional)',
                        ),
                        onSubmitted: (_) => onFieldSubmitted(),
                      ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: PresetDetailsDialog.saveKey,
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 5: Pass the group from the three callers**

`lib/features/presets/view/preset_actions.dart`, in `savePresetAs`:

```dart
  final details = await showPresetDetailsDialog(
    context,
    title: 'Save as preset',
    isNameTaken: presets.state.nameTaken,
    // A changed 6amMart preset is saved as a 6amMart preset unless changed.
    group: composer.state.preset?.group ?? '',
    groups: presets.state.groupNames,
  );
```

and in the `presets.saveAs(...)` call, add `group: details.group,` after `description: details.description,`.

`lib/features/history/view/history_screen.dart`, in `_saveAsPreset`:
- add `groups: presets.state.groupNames,` to the `showPresetDetailsDialog` call;
- add `group: details.group,` to the `presets.saveAs(...)` call.

`lib/features/presets/view/presets_screen.dart`, in the `PresetAction.edit` case:

```dart
          case PresetAction.edit:
            final details = await showPresetDetailsDialog(
              context,
              title: 'Edit details',
              name: preset.name,
              description: preset.description,
              group: preset.group,
              groups: presets.state.groupNames,
              isNameTaken: (name) =>
                  presets.state.nameTaken(name, exceptId: preset.id),
            );
            if (details != null) {
              final renamed = await presets.rename(
                preset,
                name: details.name,
                description: details.description,
                group: details.group,
              );
              composer.presetUpdated(renamed);
            }
```

In `_PresetTile`'s menu, change `child: Text('Rename…'),` to `child: Text('Edit details…'),`.

- [ ] **Step 6: Run the tests to check they pass**

Run: `flutter test test/features/presets/ test/features/history/ test/features/composer/`
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
git add lib/features/presets/cubit/presets_cubit.dart lib/features/presets/view/preset_details_dialog.dart lib/features/presets/view/preset_actions.dart lib/features/presets/view/presets_screen.dart lib/features/history/view/history_screen.dart test/features/presets/presets_cubit_test.dart test/features/presets/preset_picker_test.dart test/features/presets/presets_screen_test.dart test/features/history/history_screen_test.dart
git commit -m "feat: set a preset's group when saving or editing it

The details dialog gets a Group field that suggests the groups already
in use. Save as starts with the loaded preset's group. Rename… becomes
Edit details…, since it now edits the group too."
```

---

### Task 5: The Presets screen lists presets by group

**Files:**
- Modify: `lib/features/presets/view/presets_screen.dart`
- Test: `test/features/presets/presets_screen_test.dart`

**Interfaces:**
- Consumes:
  - `PresetsState.groups`, `PresetGroup` (Task 3);
  - `PresetsCubit.saveAs(group:)` and Edit details (Task 4);
  - the built-in groups (Task 2).
- Produces:
  - a section header per group with the key `ValueKey('preset-group-$key')`;
  - its tristate checkbox with the key `ValueKey('preset-group-check-$key')`.

- [ ] **Step 1: Write the failing tests**

In `test/features/presets/presets_screen_test.dart`:

Give `saveMine` a group (inside `main()`):

```dart
  Future<Preset> saveMine(
    WidgetTester tester,
    PresetsCubit presets,
    String name, {
    String group = '',
  }) async {
    final saved = (await tester.runAsync(
      () => presets.saveAs(
        name: name,
        group: group,
        template: const {
          'notification': {'title': 'A'},
        },
        variables: const [],
      ),
    ))!;
    await tester.pump();
    return saved;
  }

  Finder header(String key) => find.byKey(ValueKey('preset-group-$key'));

  /// Closes the long 6amMart section, so the Generic presets below it show.
  Future<void> close6amMart(WidgetTester tester) async {
    await tester.tap(header('6ammart'));
    await tester.pumpAndSettle();
  }
```

Replace `"lists the built-in presets and the user's own"` and `'my presets come before the long built-in list'` with:

```dart
  testWidgets("lists the built-in presets and the user's own", (tester) async {
    final (_, presets, _) = await openPresets(tester);
    await saveMine(tester, presets, 'Mine');
    await close6amMart(tester);
    expect(find.text('Simple notification'), findsOneWidget);
    expect(find.text('Data only (silent / background)'), findsOneWidget);
    expect(find.text('Mine'), findsOneWidget);
  });

  testWidgets('presets are listed by group, groups with yours first', (
    tester,
  ) async {
    final (_, presets, _) = await openPresets(tester);
    await saveMine(tester, presets, 'Ours', group: 'StackFood');
    await saveMine(tester, presets, 'Mine');
    double top(Finder finder) => tester.getTopLeft(finder).dy;
    expect(top(header('stackfood')), lessThan(top(find.text('Ours'))));
    expect(top(find.text('Ours')), lessThan(top(header(''))));
    expect(top(header('')), lessThan(top(find.text('Mine'))));
    expect(top(find.text('Mine')), lessThan(top(header('6ammart'))));
    expect(
      find.descendant(of: header(''), matching: find.text('No group')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: header('6ammart'), matching: find.text('23')),
      findsOneWidget,
    );
  });

  testWidgets('a section closes and opens again', (tester) async {
    await openPresets(tester);
    expect(find.text('User app · Order status'), findsOneWidget);

    await close6amMart(tester);
    expect(find.text('User app · Order status'), findsNothing);
    expect(
      tester.getTopLeft(header('6ammart')).dy,
      lessThan(tester.getTopLeft(header('generic')).dy),
    );

    await tester.tap(header('6ammart'));
    await tester.pumpAndSettle();
    expect(find.text('User app · Order status'), findsOneWidget);
  });

  testWidgets('the group checkbox ticks and unticks all of its presets', (
    tester,
  ) async {
    final (_, _, files) = await openPresets(tester);
    final groupBox = find.byKey(const ValueKey('preset-group-check-6ammart'));
    bool? ticked() => tester.widget<Checkbox>(groupBox).value;
    expect(ticked(), isFalse);

    await tester.tap(
      find.descendant(
        of: find.byKey(
          const ValueKey('preset-builtin.6ammart.user.order_status'),
        ),
        matching: find.byType(Checkbox),
      ),
    );
    await tester.pump();
    expect(ticked(), isNull, reason: 'some are ticked: a dash');
    expect(find.text('Export 1'), findsOneWidget);

    await tester.tap(groupBox);
    await tester.pump();
    expect(ticked(), isTrue);
    expect(find.text('Export 23'), findsOneWidget);

    await tester.tap(find.byKey(PresetsScreen.exportKey));
    await settleAsync(tester);
    final exported = PresetCodec.decode(files.saved.single.text);
    expect(exported, hasLength(23));
    expect(exported.every((p) => p.group == '6amMart'), isTrue);

    await tester.tap(groupBox);
    await tester.pump();
    expect(ticked(), isFalse);
    expect(find.text('Export all'), findsOneWidget);
  });

  testWidgets('Edit details… moves a preset to another group', (tester) async {
    final (_, presets, _) = await openPresets(tester);
    final mine = await saveMine(tester, presets, 'Mine');
    expect(header(''), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('preset-menu-${mine.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Edit details…'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(PresetDetailsDialog.groupKey),
      'StackFood',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PresetDetailsDialog.saveKey));
    await settleAsync(tester);

    expect(presets.state.userPresets.single.group, 'StackFood');
    expect(header(''), findsNothing, reason: 'No group is empty now');
    expect(
      tester.getTopLeft(header('stackfood')).dy,
      lessThan(tester.getTopLeft(find.text('Mine')).dy),
    );
  });
```

In these existing tests, add `await close6amMart(tester);` right after `openPresets(...)` (the Generic presets sit below the 23 6amMart ones):
- `'Open in composer loads the preset and shows the composer'`
- `'Duplicate makes an editable copy'`
- `'a ticked built-in preset is exported on its own'`
- `"a built-in preset's menu offers Export…"`

- [ ] **Step 2: Run the tests to check they fail**

Run: `flutter test test/features/presets/presets_screen_test.dart`
Expected: FAIL. No widget has the key `preset-group-6ammart`, and the screen still shows "My presets" and "Built-in".

- [ ] **Step 3: Build the sections**

In `lib/features/presets/view/presets_screen.dart`, add the import
`import 'package:fcm_studio/features/presets/domain/preset_groups.dart';`.

In `_PresetsScreenState`, add after `_selected`:

```dart
  /// The keys of the groups whose sections are closed.
  final Set<String> _closed = {};

  /// True when every preset in [group] is ticked, false when none is, and
  /// null (a dash) when some are.
  bool? _ticked(PresetGroup group) {
    final count = group.presets.where((p) => _selected.contains(p.id)).length;
    if (count == 0) {
      return false;
    }
    return count == group.presets.length ? true : null;
  }
```

In `build`, replace the lines from `final state = …` through `final selected = [...]` with:

```dart
    final state = context.watch<PresetsCubit>().state;
    final groups = state.groups;
    final shown = [for (final group in groups) ...group.presets];
    final selected = [
      for (final p in shown)
        if (_selected.contains(p.id)) p,
    ];
```

Replace the `body: ListView(...)` with:

```dart
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (state.userPresets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'No presets yet. Save one from the composer, or import a file.',
              ),
            ),
          for (final group in groups) ...[
            _GroupHeader(
              group: group,
              open: !_closed.contains(group.key),
              ticked: _ticked(group),
              onToggle: () => setState(() {
                if (!_closed.remove(group.key)) {
                  _closed.add(group.key);
                }
              }),
              onTick: (on) => setState(() {
                for (final preset in group.presets) {
                  if (on) {
                    _selected.add(preset.id);
                  } else {
                    _selected.remove(preset.id);
                  }
                }
              }),
            ),
            if (!_closed.contains(group.key))
              for (final preset in group.presets) tile(preset),
          ],
        ],
      ),
```

Replace the `_Header` class (now unused) with:

```dart
/// A group's section header. Its checkbox ticks every preset in the group;
/// a tap elsewhere opens or closes the section.
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.group,
    required this.open,
    required this.ticked,
    required this.onToggle,
    required this.onTick,
  });

  final PresetGroup group;
  final bool open;

  /// Null when some of the group's presets are ticked.
  final bool? ticked;
  final VoidCallback onToggle;
  final ValueChanged<bool> onTick;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('preset-group-${group.key}'),
      leading: Checkbox(
        key: ValueKey('preset-group-check-${group.key}'),
        tristate: true,
        value: ticked,
        // All ticked: untick them all. Otherwise tick them all.
        onChanged: (_) => onTick(ticked != true),
      ),
      title: Text(group.name, style: Theme.of(context).textTheme.titleSmall),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('${group.presets.length}'),
          const SizedBox(width: 8),
          Icon(open ? Icons.expand_less : Icons.expand_more),
        ],
      ),
      onTap: onToggle,
    );
  }
}
```

- [ ] **Step 4: Run the tests to check they pass**

Run: `flutter test test/features/presets/ test/features/composer/`
Expected: all pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/presets/view/presets_screen.dart test/features/presets/presets_screen_test.dart
git commit -m "feat: the Presets screen lists presets by group

Each group is a section that opens and closes, with a count and a
checkbox that ticks all of its presets for export."
```

---

### Task 6: Group headers and group search in the preset picker

**Files:**
- Modify: `lib/features/presets/view/preset_picker.dart`
- Test: `test/features/presets/preset_picker_test.dart`

**Interfaces:**
- Consumes: `PresetsState.groups`, `PresetGroup`, and `Preset.group` (Tasks 1 and 3).
- Produces: the picker lists a disabled header entry (value `'group:$key'`, label = group name) before each group's presets.

- [ ] **Step 1: Write the failing tests**

In `test/features/presets/preset_picker_test.dart`, change the end of `'my presets are listed before the built-in ones'` (after the menu opens) to:

```dart
    double top(Finder finder) => tester.getTopLeft(finder).dy;
    expect(top(menuEntry('No group')), lessThan(top(menuEntry('Mine'))));
    expect(top(menuEntry('Mine')), lessThan(top(menuEntry('6amMart'))));
```

Add:

```dart
  testWidgets('presets are listed under their group headers', (tester) async {
    await pumpAppWithProject(tester);
    await tester.tap(searchField);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(menuEntry('6amMart')).dy,
      lessThan(
        tester.getTopLeft(menuEntry('User app · Order status (built-in)')).dy,
      ),
    );
  });

  testWidgets('the search matches group names and hides empty groups', (
    tester,
  ) async {
    await pumpAppWithProject(tester);
    await search(tester, '6ammart chat');
    expect(menuEntry('6amMart'), findsOneWidget);
    expect(menuEntry('User app · Chat message (built-in)'), findsOneWidget);
    expect(menuEntry('Delivery app · Chat message (built-in)'), findsOneWidget);
    expect(menuEntry('Store app · Chat message (built-in)'), findsOneWidget);
    expect(menuEntry('Generic'), findsNothing);

    await tester.enterText(searchField, 'generic');
    await tester.pumpAndSettle();
    expect(menuEntry('Generic'), findsOneWidget);
    expect(menuEntry('Simple notification (built-in)'), findsOneWidget);
    expect(menuEntry('Data only (silent / background) (built-in)'), findsOneWidget);
    expect(menuEntry('6amMart'), findsNothing);

    await tester.enterText(searchField, 'zzz');
    await tester.pumpAndSettle();
    expect(menuEntry('Generic'), findsNothing);
    expect(menuEntry('6amMart'), findsNothing);
  });

  testWidgets('a group header cannot be picked', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    await tester.tap(searchField);
    await tester.pumpAndSettle();
    expect(
      tester.widget<MenuItemButton>(menuEntry('6amMart')).onPressed,
      isNull,
    );
    await tester.tap(menuEntry('6amMart'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(composer.state.preset, isNull);
  });
```

- [ ] **Step 2: Run the tests to check they fail**

Run: `flutter test test/features/presets/preset_picker_test.dart`
Expected: FAIL. No menu entry has the text "6amMart" or "No group".

- [ ] **Step 3: Add the headers and the group search**

In `lib/features/presets/view/preset_picker.dart`, add the import
`import 'package:fcm_studio/features/presets/domain/preset_groups.dart';`.

In `PresetPicker.build`, pass the groups:

```dart
            _PresetSearchField(
              groups: presets.groups,
              selected: current == null ? null : presets.byId(current.id),
              isDirty: composer.isDirty,
            ),
```

In `_PresetSearchField`, replace `presets` with:

```dart
  const _PresetSearchField({
    required this.groups,
    required this.selected,
    required this.isDirty,
  });

  final List<PresetGroup> groups;
```

In `_PresetSearchFieldState`, replace the static `_matching` with:

```dart
  /// Keeps the presets whose group and label hold every typed word, in any
  /// order, each under its group's header. A header with no match under it
  /// is left out.
  List<DropdownMenuEntry<String>> _matching(
    List<DropdownMenuEntry<String>> entries,
    String filter,
  ) {
    final words = filter
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    final groupOf = {
      for (final group in widget.groups)
        for (final preset in group.presets) preset.id: preset.group,
    };
    final result = <DropdownMenuEntry<String>>[];
    DropdownMenuEntry<String>? header;
    for (final entry in entries) {
      // Headers are the only disabled entries.
      if (!entry.enabled) {
        header = entry;
        continue;
      }
      final text = '${groupOf[entry.value] ?? ''} ${entry.label}'.toLowerCase();
      if (words.every(text.contains)) {
        if (header != null) {
          result.add(header);
          header = null;
        }
        result.add(entry);
      }
    }
    return result;
  }
```

In `build`, replace `dropdownMenuEntries: [...]` with:

```dart
      dropdownMenuEntries: [
        for (final group in widget.groups) ...[
          // A header: disabled, so it can't be highlighted or picked.
          DropdownMenuEntry(
            value: 'group:${group.key}',
            label: group.name,
            enabled: false,
            labelWidget: Text(
              group.name,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          for (final preset in group.presets)
            DropdownMenuEntry(
              value: preset.id,
              label: PresetPicker._label(preset),
            ),
        ],
      ],
```

and add `final theme = Theme.of(context);` as the first line of `build`. `_open` already ignores an id that `byId` can't find, so it needs no change.

- [ ] **Step 4: Run the tests to check they pass**

Run: `flutter test test/features/presets/ test/features/composer/`
Expected: all pass. The earlier picker tests (`'typed words match in any order, ignoring case'`, the switching test) still pass unchanged.

- [ ] **Step 5: Commit**

```bash
git add lib/features/presets/view/preset_picker.dart test/features/presets/preset_picker_test.dart
git commit -m "feat: the preset picker shows group headers and searches groups

Typed words match a preset's group as well as its name, so
\"6ammart chat\" lists the three 6amMart chat messages. A group with no
match loses its header."
```

---

### Task 7: README, spec status, and the full check

**Files:**
- Modify: `README.md`, `docs/superpowers/specs/2026-10-06-preset-groups-design.md`

**Interfaces:**
- Consumes: the finished behaviour of Tasks 1–6.

- [ ] **Step 1: Update the feature list**

In `README.md`, under `- **Presets.**` (near line 38), add a bullet after the "Your own presets…" one:

```markdown
  - Grouped by product (6amMart, Generic, or groups you make), with a search over group and name.
```

- [ ] **Step 2: Update Composer → Preset**

In the `#### Preset` section (near line 163), replace the **Searching**, **Order** and **Save as preset…** bullets with:

```markdown
- **Searching:** type words in any order, ignoring case. Words match a preset's group as well as its name. For example, `store chat` finds "Store app · Chat message", and `6ammart chat` finds the three 6amMart chat messages.
- **Order:** presets are listed under their group's header, in the same order as the Presets screen ([section 4](#4-presets)).
```

```markdown
- **Save as preset…** creates a new preset and asks for its name, description and group. The group starts as the loaded preset's group. **Update preset** overwrites the loaded one.
```

- [ ] **Step 3: Update section 4, Presets**

Replace the text from `#### Built-in presets` up to (not including) `#### Export and import` with:

```markdown
#### Built-in presets

Built-in presets are read-only. Use **Duplicate** to make an editable copy; the copy stays in the same group.

- **Generic** group: Simple notification, Notification with image, Notification + data, Data only (silent / background).
- **6amMart** group (23 presets): named "User app · …", "Delivery app · …" and "Store app · …", plus two for all three apps, "Admin push notification (topic)" and "Maintenance mode (silent)".
  - They copy the real payloads of the 6amMart backend, including every key it sends (empty where it sends nothing), `channel_id: "6ammart"` and the sound `notification.wav`.
  - Together they cover all 35 `data.type` values the backend sends. A preset that covers several types has a **Type** choice list.

#### Groups

Every preset can have a group, for example the product it's for.

- Set it in **Save as preset…** or **Edit details…**. The field suggests the groups you already use.
- Groups ignore case, so "6amMart" and "6ammart" are one group.
- Exports carry the group, so an imported file is grouped the same way.

#### The Presets screen

The screen lists presets by group. Click a group's header to close or open its section. The order is:
1. groups that hold your presets, A→Z;
2. **No group**;
3. the other (built-in) groups, A→Z.

Inside a group, your presets come first. Each preset's menu has:
- **Open in composer**
- **Duplicate**
- **Edit details…** (name, description and group)
- **Export…**
- **Delete…**
```

In `#### Export and import`, change the first **Export** bullet to:

```markdown
- Tick presets, then click **Export N**. A group's checkbox ticks all of its presets. With nothing ticked, **Export all** exports everything, built-in presets included.
```

- [ ] **Step 4: Mark the spec implemented**

In `docs/superpowers/specs/2026-10-06-preset-groups-design.md`, change the status line to:

```markdown
**Status:** Designed and implemented 2026-10-06 (code with tests).
```

- [ ] **Step 5: Run the full check**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add README.md docs/superpowers/specs/2026-10-06-preset-groups-design.md
git commit -m "docs: preset groups in the README

Covers the built-in groups, setting a group, the grouped Presets
screen and picker, and the group checkbox for export."
```
