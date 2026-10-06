# FCM Studio: preset groups

**Status:** Designed and implemented 2026-10-06 (code with tests).

**Builds on:** [2026-10-03-fcm-studio-design.md](2026-10-03-fcm-studio-design.md) (main spec, §5.5 layout and §6 presets). This document does not repeat it.

## 1. Purpose

The preset list is flat: your presets, then 27 built-in ones in a row. Finding one means scrolling or guessing a word of its name. Users work on several products (for example 6amMart and their own apps), and want the presets for one product together.

This change gives every preset an optional **group**, and lists presets by group on the Presets screen and in the composer's preset picker.

**Success test:**
- The Presets screen shows a **6amMart** section with all 23 6amMart presets and a **Generic** section with the 4 generic ones.
- Typing `6ammart chat` in the picker lists the three "Chat message" presets under a 6amMart header.
- A preset saved with the group "StackFood" shows under a StackFood header in both places, and keeps its group when exported and imported.

## 2. Decisions

These were made in chat on 2026-10-06.

- **A group is a name the user types**, not a link to a Firebase project.
  - It travels with exported presets, so a shared file groups the same way for everyone.
  - Rejected: grouping by Firebase project. Project ids are local to one install, so the link would break when presets are shared.
- **The group is a field on the preset** (approach A).
  - Rejected:
    - (B) a separate group entity with its own store: it allows empty groups and a manual order, but export, import and a management screen would all have to handle it;
    - (C) deriving the group from a name prefix such as "6amMart · ": renaming a preset would move it.
- **Built-in groups follow the product, not the app.** All 23 6amMart presets (user, delivery and store app) are in one group, **6amMart**. The 4 generic presets are in **Generic**. "User app · …", "Delivery app · …" and "Store app · …" stay in the names, so the app is still visible inside the group.
- **Groups are the top level** on the Presets screen, not nested under "My presets" and "Built-in". One group can hold both your presets and built-in ones.
- **The picker shows group headers** in its one list, and the search matches group names too.

## 3. Data

### 3.1 The `group` field

- `Preset` gets `final String group`, default `''`. `''` means "No group".
- The value is stored trimmed.
- `fromJson` reads `group` when it's a string. A missing or non-string value reads as `''`, so no record is ever skipped because of it.
- `toJson`, `copyWith` and `props` include it.
- `kPresetSchemaVersion` stays 1. The field is optional and additive, so stored records need no migration.

### 3.2 Comparing groups

- Two presets are in the same group when their groups are equal after trimming and lower-casing, the same rule as names (`PresetCodec.normalizeName`).
- A group's display name is the spelling used by the first preset in the group, in the order of §5.2.

### 3.3 What stays the same

- **Names stay unique across all groups.** `PresetsState.nameTaken` and the import conflict rules in `PresetCodec.preview` and `PresetCodec.resolve` don't change.
- **Duplicate** keeps the group: `copyWith` copies it.
- **Export and import:** `PresetCodec.encode` writes `toJson`, so `group` is in the file. The file format version stays 1. An older FCM Studio ignores the unknown key and imports the preset with no group.

### 3.4 Grouping helper

A pure function in a new file, `lib/features/presets/domain/preset_groups.dart`, does all ordering. The screen and the picker both use it.

```dart
class PresetGroup {
  final String key;          // normalized group; '' for No group
  final String name;         // display name; 'No group' for ''
  final List<Preset> presets; // in display order (§5.2)
}

List<PresetGroup> groupPresets({
  required List<Preset> userPresets, // sorted by name, as PresetsState holds them
  required List<Preset> builtIns,    // in file order
});
```

`PresetsState` exposes:
- `groups`: `groupPresets(userPresets: userPresets, builtIns: builtIns)`;
- `groupNames`: every distinct group display name except No group, A→Z, for autocomplete.

## 4. Built-in presets

In [assets/presets/builtin.json](../../../assets/presets/builtin.json):

- `"group": "Generic"` on `builtin.simple`, `builtin.image`, `builtin.notification_data` and `builtin.data_only`.
- `"group": "6amMart"` on all 23 `builtin.6ammart.*` presets.
- The two "6amMart · " names lose that prefix, because the group now says it:
  - `builtin.6ammart.all.push_notification`: "Admin push notification (topic)";
  - `builtin.6ammart.all.maintenance`: "Maintenance mode (silent)".
- Ids don't change, so nothing that refers to a built-in by id is affected.

## 5. The Presets screen

### 5.1 Sections

- One section per group, from `PresetsState.groups`.
- The section header is a row with:
  - an arrow that shows whether the section is open;
  - a checkbox that ticks every preset in the group for export (§5.3);
  - the group's name;
  - the number of presets in it.
- Tapping the header (outside the checkbox) opens or closes the section.
- Every section is open when the screen opens. Which sections are closed lives in the screen's state only, so it resets when the screen is rebuilt from scratch.
- Preset tiles don't change: checkbox, name, lock icon for built-in ones, description and variable count, and the actions menu.
- When you have no presets of your own, the existing hint stays at the top: "No presets yet. Save one from the composer, or import a file."
- Keys: `ValueKey('preset-group-$key')` on the header and `ValueKey('preset-group-check-$key')` on its checkbox. No group uses the key `''`.

### 5.2 Order

**Groups:**
1. named groups that hold at least one of your presets, A→Z;
2. No group, when it has any presets;
3. the other groups (built-in only), A→Z: 6amMart, then Generic.

Built-in presets all have a group, so No group only ever holds your presets. Putting it before the built-in-only groups keeps your ungrouped presets, which are all of them right after this change ships, near the top.

**Presets inside a group:** your presets A→Z, then built-in ones in file order.

### 5.3 Selecting a group for export

- The group checkbox is ticked when every preset in the group is ticked, shows a dash when some are, and is empty when none are.
- Clicking it when every preset is ticked unticks them all. Otherwise it ticks them all.
- Export works as before: **Export N** exports the ticked presets, **Export all** exports everything.

### 5.4 Edit details

- The menu item **Rename…** becomes **Edit details…**. It opens the details dialog (§7) with the name, description and group.
- `PresetAction.edit` keeps its name.

## 6. The composer's preset picker

- The entries come from `PresetsState.groups`, in the same order as §5.2.
- Each group starts with a header entry:
  - It's a `DropdownMenuEntry` with `enabled: false`, the value `'group:$key'`, and a `labelWidget` styled as a section label.
  - Keyboard navigation skips disabled entries; this is checked for Flutter 3.44.
  - `_open` already ignores an id that `PresetsState.byId` can't find, so a header can't load anything.
- **Search** keeps the "every typed word, in any order" rule. Each word may match the preset's group or its label, for example `6ammart chat`.
- A header is shown only when at least one preset under it matches.
- The field still shows the loaded preset as `• Name (built-in)`. Names are unique, so the group isn't needed there.

## 7. Setting a group

### 7.1 The details dialog

- `PresetDetailsDialog` gets a third field, **Group (optional)**, below the description.
- The field suggests the existing groups (`PresetsState.groupNames`) that contain the typed text, ignoring case. An exact match isn't suggested. This keeps "6amMart" and "6ammart" from becoming two groups by accident.
- The dialog takes `group` (initial value) and `groups` (suggestions).
- It returns `({String name, String description, String group})`, with the group trimmed.
- Key: `PresetDetailsDialog.groupKey`.

### 7.2 Where it's used

| Caller | Group shown at first |
|---|---|
| Composer, **Save as preset…** (and Cmd/Ctrl+S with no user preset loaded) | The loaded preset's group, or empty |
| History, **Save as preset…** | Empty |
| Presets screen, **Edit details…** | The preset's group |

### 7.3 Cubit

- `PresetsCubit.saveAs` takes `String group = ''`.
- `PresetsCubit.rename` takes `required String group`.
- Both store it trimmed.
- `update` (Update preset) doesn't touch the group, just as it keeps the name and description.

## 8. Errors

- A record with a missing or wrong-typed `group` loads with No group (§3.1). It is never skipped.
- Nothing new can fail: storage errors go to the error banner as before.

## 9. Testing

Tests go in the existing files under `test/features/presets/`, plus one new file for the grouping helper.

- **`Preset`:**
  - `group` survives `toJson` → `fromJson`;
  - a missing or non-string `group` reads as `''`;
  - the value is trimmed.
- **`PresetCodec`:**
  - an export carries `group`;
  - importing it keeps the group.
- **`groupPresets`** (new `preset_groups_test.dart`):
  - group order (§5.2), including No group's place;
  - order inside a group;
  - groups that differ only in case are merged, and the display name is the first preset's spelling.
- **`PresetsCubit`:**
  - `saveAs` and `rename` store the group;
  - `duplicate` keeps it;
  - `update` leaves it unchanged.
- **Built-ins (`sixammart_presets_test.dart`):**
  - every `builtin.6ammart.*` preset has the group `6amMart`;
  - the user, delivery and store names keep their app prefix;
  - the two `all` presets have no "6amMart · " prefix;
  - the generic presets have the group `Generic`.
- **Presets screen:**
  - sections in order, with counts;
  - closing and opening a section;
  - the group checkbox ticks and unticks its presets and shows the dash;
  - **Edit details…** changes the group, and the preset moves to the new section.
- **Picker:**
  - group headers are shown;
  - `6ammart chat` finds the three chat presets;
  - a group with no match loses its header;
  - a header can't be selected.
- **Details dialog:**
  - the Group field is pre-filled;
  - it suggests existing groups;
  - the result carries the trimmed group.

## 10. README

- **Composer → Preset:**
  - the list is grouped;
  - the search also matches group names;
  - **Save as preset…** asks for a group.
- **4. Presets:**
  - built-in presets are in the groups 6amMart and Generic;
  - the screen lists presets by group;
  - the group checkbox for export;
  - **Rename…** becomes **Edit details…**.

## 11. Out of scope

- Renaming a whole group in one step. Today you edit each preset's group.
- A manual group order, empty groups, or groups inside groups.
- Linking presets or groups to Firebase projects.
- Remembering closed sections after the screen is rebuilt.
