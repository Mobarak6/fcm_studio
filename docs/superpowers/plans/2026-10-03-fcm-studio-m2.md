# FCM Studio M2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Take FCM Studio from M1 to the M2 milestone: Form tab, variables, presets (built-in, editor, import/export), saved targets, history, dry run, copy as cURL and the production safeguard. M2 is done when the success test works with a pasted token: pick a project, pick a preset, paste a token, send, and see the notification in under 30 seconds.

**Architecture:** The composer's JSON template stays the single source of truth. The Form tab edits it through pure `TemplateEdits` functions, and the JSON editor follows those edits. `MessageRenderer` gains `{{placeholder}}` substitution. A new `MessageSender` service sends a rendered request and records it in history; the composer and History → Resend both use it. Presets, saved targets and history each get a sembast store, a repository and a Cubit. A `NavigationRail` shell switches between Composer, Presets, Targets and History.

**Tech Stack:** Flutter 3.44 / Dart 3.12, `flutter_bloc`, `equatable`, `sembast`, `file_selector` (open, save and web download), `re_editor`, `url_launcher`. **No new packages.**

**Spec:** `docs/superpowers/specs/2026-10-03-fcm-studio-design.md`. Read §4.3, §5, §6, §7, §8.3, §10 and §11 before starting. The M0/M1 plan (`docs/superpowers/plans/2026-10-03-fcm-studio-m0-m1.md`) shows the conventions the existing code follows.

## Before you start

- Branch from the M1 work: `git switch -c feat/m2` (the current branch is `feat/m0-m1`).
- `flutter test` must pass and `flutter analyze` must say `No issues found!` before Task 1 (127 tests at the time of writing).

## Global Constraints

- Project root: `/Users/mobarak/Documents/learn/fcm_studio`. Package `fcm_studio`. Platforms: **macOS, Windows, web only**.
- Use package imports (`package:fcm_studio/...`) in `lib/`, `test/` and `tool/`. Tests import helpers with relative paths, as the existing tests do.
- State: `flutter_bloc` Cubits. States extend `Equatable`. Models are hand-written (`fromJson`/`toJson`/`copyWith`), **no code generation**.
- Constructors take private fields through private named parameters, as the existing code does: `ProjectAuthRegistry({required this._repository, this._clock = const SystemClock()})` is called as `ProjectAuthRegistry(repository: …, clock: …)`.
- Lints: `flutter_lints` plus `strict-casts`, `strict-inference`, `strict-raw-types`, `always_declare_return_types`, `avoid_dynamic_calls`, `prefer_final_locals`, `prefer_single_quotes`, `unawaited_futures`. Always write type arguments (`Map<String, Object?>`, `showDialog<bool>`, `Future<void>.delayed`). `child:`/`children:` go last in widget constructors. Always use braces in `if`/`for`.
- Each task ends with `dart format lib test`, `flutter analyze` reporting **No issues found!**, and `flutter test` passing. If the analyzer reports lint infos, `dart fix --apply` fixes most of them.
- Secrets never go into sembast, logs, history, exports or UI text. **History never stores an access token.** Text from errors passes through `redact()`.
- FCM sends are never retried automatically. "Retry" is a button the user presses.
- `validate_only` goes into the request body only for dry runs.
- Every stored record carries a `schemaVersion` (1 for the new stores). There are no migrations yet.
- Navigation is a `NavigationRail` with an `IndexedStack`. No router package.
- macOS: App Sandbox stays off; no new entitlements are needed (saving files works without the sandbox).
- Commit at the end of each task with the message given there. End every commit message with the line `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`.

### Decisions where the spec is silent

These are decided here so every task agrees. The user reviews them with the plan.

1. **Dry runs skip the production confirmation.** They deliver nothing, so there is nothing to protect.
2. **Built-in placeholders** (`{{now_iso}}`, `{{now_ms}}`, `{{uuid}}`) get one value per render, so `{{uuid}}` used twice gives the same id twice. The preview shows sample values. Send renders again, so every send (and every Retry) gets fresh values.
3. **Placeholders are replaced in string values only**, not in object keys.
4. **An optional number or boolean variable that is empty removes its field** (for example no `badge`), with a note in the preview.
5. **Switching from Data only back to Notification + data** adds an empty `notification` first and removes the three background settings that Data only added.
6. **Form edits rewrite the JSON** with 2-space indentation.
7. **Exports never include built-in presets**, because every install has them. On import, **one conflict choice** (Keep both, Replace or Skip) applies to every name clash in the file. Names are compared ignoring case.
8. **The saved-target star toggles**: hollow means not saved; tapping a filled star removes the saved target.
9. **The unsaved-changes dot and the "Discard unsaved changes?" question** apply only while a preset is loaded.

## Review Focus

These inputs are the most likely to cause trouble for someone using the app. Each one has a test in the task named.

1. **Importing the wrong file**: `google-services.json`, a presets file from a newer FCM Studio, or a preset whose template sets `token`. The user needs a message saying what is wrong, and nothing may be imported. *Task 4 ("explains files that are not preset exports", "names the preset that is invalid") and Task 16 ("a newer presets file is explained and nothing is imported").*
2. **Sending to a production project without pressing Send**: Cmd/Ctrl+Enter, Retry and History → Resend. Every path must ask first. *Task 15 ("Ctrl+Enter on a prod project asks before sending", "Retry on a prod project asks again") and Task 17 ("Resend asks first for a production project").*
3. **A variable value that doesn't fit its type**: `12a` for a number, or an empty optional badge. Send must be disabled with a message, or the field dropped. It must never crash or send `"badge": "12a"`. *Task 1 ("a value that is not a number blocks sending instead of crashing", "an empty optional typed placeholder removes its field").*
4. **Renaming a data key in the Form to one that already exists.** The form must refuse with "Duplicate key" and must not silently drop the other entry. *Task 12 ("a data key that already exists is refused and both entries are kept").*
5. **History for a send that failed before FCM answered** (no HTTP status), **or for a project that was removed since.** The entry must still be recorded and shown, and Resend must be disabled with the reason. *Task 7 ("a failure before FCM answers is still recorded") and Task 17 ("Resend is off when the project was removed").*

## Not in this plan (M3 and later)

- adb, the Devices screen, **From device…**, device-sourced saved targets and the sender-ID check (M3).
- The Settings screen (M3, for the adb path).
- Google sign-in (M4). Release builds and the README (M5).

## File map

New files:

| File | Responsibility |
|---|---|
| `lib/core/utils/ids.dart` | `newUuid()` and the `IdGenerator` type |
| `lib/core/utils/shorten.dart` | `shortenMiddle()` for tokens in lists |
| `lib/core/utils/time_format.dart` | `formatLocalTime()` for lists |
| `lib/core/fcm/curl_builder.dart` | bash `curl` command for a send |
| `lib/core/platform/file_access.dart` | open/save text files (desktop dialog, web download) |
| `lib/features/presets/domain/variable_def.dart` | `VariableDef`, `VariableType` |
| `lib/features/presets/domain/preset.dart` | `Preset` model |
| `lib/features/presets/domain/preset_codec.dart` | export format, import checks and conflict resolution |
| `lib/features/presets/data/presets_repository.dart` | built-in asset + user presets store |
| `lib/features/presets/cubit/presets_state.dart`, `presets_cubit.dart` | presets list and actions |
| `lib/features/presets/view/*.dart` | presets screen, picker, dialogs, actions |
| `lib/features/composer/domain/placeholders.dart` | placeholder substitution (spec §5.2 step 1) |
| `lib/features/composer/domain/template_edits.dart` | pure Form-tab edits on the template |
| `lib/features/composer/domain/json_locator.dart` | finds a field's line in the JSON text |
| `lib/features/composer/domain/send_confirmation.dart` | production safeguard decision |
| `lib/features/composer/data/message_sender.dart` | send + record history; cURL |
| `lib/features/composer/view/*.dart` (new) | Form tab, editor tabs, variables section, prod banner, confirmation dialog, synced text field |
| `lib/features/targets/**` | saved targets: model, repository, cubit, screen |
| `lib/features/history/**` | history: model, filter, repository, cubit, screen |
| `lib/app/app_error_cubit.dart`, `app_error_banner.dart` | app-wide dismissible error (spec §11) |
| `lib/app/navigation_cubit.dart`, `shell.dart` | `NavigationRail` shell |
| `lib/app/widgets/prompt_dialog.dart` | one-field text dialog |
| `assets/presets/builtin.json` | the four built-in presets |

Changed files: `pubspec.yaml` (asset), `lib/main.dart`, `lib/app/app.dart`, `lib/app/dependencies.dart`, `lib/features/composer/domain/target.dart`, `message_renderer.dart`, `composer_state.dart`, `composer_cubit.dart`, and the composer views. Test helpers in `test/helpers/` grow with the tasks.

---

### Task 1: Variables and placeholder substitution

**Files:**
- Create: `lib/core/utils/ids.dart`, `lib/features/presets/domain/variable_def.dart`, `lib/features/composer/domain/placeholders.dart`
- Modify: `lib/features/composer/domain/target.dart`, `lib/features/composer/domain/message_renderer.dart`
- Test: `test/core/utils/ids_test.dart`, `test/features/presets/variable_def_test.dart`, `test/features/composer/message_renderer_test.dart`, `test/features/composer/target_test.dart`

**Interfaces:**
- Consumes: `Clock`/`SystemClock` (`lib/core/utils/clock.dart`), `RenderIssue`, `Target`, `FcmRules` (existing), `FixedClock` (`test/helpers/fixed_clock.dart`).
- Produces:
  - `typedef IdGenerator = String Function();` and `String newUuid()`.
  - `enum VariableType { text, multiline, number, boolean, enumeration }` with `jsonName` (`'enum'` for `enumeration`) and `static VariableType fromJson(Object?)`.
  - `class VariableDef({required String key, String? label, VariableType type, List<String> options, bool required, String defaultValue})` with `fromJson` (throws `FormatException`), `toJson()`, `String? get problem`, `static final RegExp keyPattern`.
  - `Target.normalized` (`String`): the token without whitespace and quotes, the topic without `/topics/`, the trimmed condition.
  - `class BuiltinValues`, `abstract final class Placeholders` (`pattern`, `wholeKey()`, `keysIn()`), `class PlaceholderSubstitution`.
  - `MessageRenderer({Clock clock, IdGenerator newId})` (still `const`), and `render({required template, required target, List<VariableDef> variables = const [], Map<String, String> values = const {}, bool validateOnly = false})`.
  - `RenderResult.undefinedPlaceholders` (`List<String>`): placeholder keys that are neither defined nor built in, in order of first use.

- [ ] **Step 1: Write the failing tests**

`test/core/utils/ids_test.dart`:
```dart
import 'package:fcm_studio/core/utils/ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('newUuid returns distinct version 4 UUIDs', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final ids = {for (var i = 0; i < 100; i++) newUuid()};
    expect(ids, hasLength(100));
    expect(ids.every(pattern.hasMatch), isTrue);
  });
}
```

`test/features/presets/variable_def_test.dart`:
```dart
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round-trips through JSON, with "enum" as the type name', () {
    const variable = VariableDef(
      key: 'size',
      label: 'Size',
      type: VariableType.enumeration,
      options: ['small', 'large'],
      required: true,
      defaultValue: 'small',
    );
    final json = variable.toJson();
    expect(json['type'], 'enum');
    expect(VariableDef.fromJson(json), variable);
  });

  test('the label defaults to the key', () {
    expect(const VariableDef(key: 'title').label, 'title');
    expect(VariableDef.fromJson({'key': 'title'}).label, 'title');
  });

  test('rejects invalid keys, enums without options and bad defaults', () {
    for (final json in <Map<String, Object?>>[
      {'key': '1abc'},
      {'key': 'has space'},
      {'key': 'size', 'type': 'enum'},
      {'key': 'badge', 'type': 'number', 'defaultValue': 'lots'},
      {'key': 'on', 'type': 'boolean', 'defaultValue': 'yes'},
      {'key': 'x', 'type': 'colour'},
      {'label': 'no key'},
    ]) {
      expect(
        () => VariableDef.fromJson(json),
        throwsFormatException,
        reason: '$json',
      );
    }
  });
}
```

Add this test to the end of `main()` in `test/features/composer/target_test.dart`:
```dart
  test('normalized is the value that goes to FCM', () {
    expect(const TokenTarget(' "abc def" ').normalized, 'abcdef');
    expect(const TopicTarget('/topics/news').normalized, 'news');
    expect(
      const ConditionTarget("  'a' in topics ").normalized,
      "'a' in topics",
    );
  });
```

In `test/features/composer/message_renderer_test.dart`, add these imports:
```dart
import 'package:fcm_studio/features/presets/domain/variable_def.dart';

import '../../helpers/fixed_clock.dart';
```
and add this group at the end of `main()` (it uses the file's existing `notification` constant and `message()` helper):
```dart
  group('placeholders', () {
    final clock = FixedClock(DateTime.utc(2026, 10, 3, 12));
    final placeholderRenderer = MessageRenderer(
      clock: clock,
      newId: () => 'id-1',
    );
    const title = VariableDef(key: 'title', label: 'Title', required: true);
    const badge = VariableDef(
      key: 'badge',
      label: 'Badge',
      type: VariableType.number,
    );
    const urgent = VariableDef(
      key: 'urgent',
      type: VariableType.boolean,
      defaultValue: 'false',
    );

    RenderResult renderWith(
      Map<String, Object?> template,
      Map<String, String> values,
    ) => placeholderRenderer.render(
      template: template,
      target: const TopicTarget('news'),
      variables: const [title, badge, urgent],
      values: values,
    );

    test('fills placeholders from values, then from defaults', () {
      final result = renderWith(
        {
          'notification': {'title': '{{title}}', 'body': 'Urgent: {{ urgent }}'},
        },
        {'title': 'Hi'},
      );
      expect(message(result)['notification'], {
        'title': 'Hi',
        'body': 'Urgent: false',
      });
    });

    test('a lone number or boolean placeholder keeps its type', () {
      final result = renderWith(
        {
          'notification': notification,
          'apns': {
            'payload': {
              'aps': {'badge': '{{badge}}'},
            },
          },
          'android': {'direct_boot_ok': '{{urgent}}'},
        },
        {'badge': '3', 'urgent': 'true'},
      );
      expect(message(result)['apns'], {
        'payload': {
          'aps': {'badge': 3},
        },
      });
      expect(message(result)['android'], {'direct_boot_ok': true});
    });

    test('a placeholder inside longer text is inserted as text', () {
      final result = renderWith(
        {
          'notification': {'title': 'You have {{badge}} new'},
        },
        {'badge': '3'},
      );
      expect(message(result)['notification'], {'title': 'You have 3 new'});
    });

    test('built-in values need no definition', () {
      final result = renderWith({
        'notification': notification,
        'data': {'at': '{{now_iso}}', 'ms': '{{now_ms}}', 'id': '{{uuid}}'},
      }, {});
      expect(message(result)['data'], {
        'at': '2026-10-03T12:00:00.000Z',
        'ms': '${clock.now().millisecondsSinceEpoch}',
        'id': 'id-1',
      });
      expect(result.notes.map((n) => n.path), contains('placeholders'));
    });

    test('an unknown placeholder blocks sending and is listed once', () {
      final result = renderWith({
        'notification': notification,
        'data': {'order': '{{order_id}}', 'again': '{{order_id}}'},
      }, {});
      expect(result.canSend, isFalse);
      expect(result.errors.single.path, 'data.order');
      expect(
        result.errors.single.message,
        'Unknown placeholder {{order_id}}. Add it under Variables.',
      );
      expect(result.undefinedPlaceholders, ['order_id']);
    });

    test('an empty required value blocks sending', () {
      final result = renderWith(
        {
          'notification': {'title': '{{title}}'},
        },
        {'title': '  '},
      );
      expect(result.errors.single.message, 'Fill in "Title" ({{title}}).');
    });

    test('a value that is not a number blocks sending instead of crashing', () {
      final result = renderWith(
        {
          'notification': notification,
          'apns': {
            'payload': {
              'aps': {'badge': '{{badge}}'},
            },
          },
        },
        {'badge': '12a'},
      );
      expect(result.canSend, isFalse);
      expect(
        result.errors.single.message,
        '"Badge" must be a number, not "12a".',
      );
    });

    test('an empty optional typed placeholder removes its field', () {
      final result = renderWith({
        'notification': notification,
        'apns': {
          'payload': {
            'aps': {'badge': '{{badge}}', 'sound': 'default'},
          },
        },
      }, {});
      expect(message(result)['apns'], {
        'payload': {
          'aps': {'sound': 'default'},
        },
      });
      expect(
        result.notes.map((n) => n.message),
        contains('Removed because {{badge}} is empty.'),
      );
    });
  });
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/core/utils/ids_test.dart test/features/presets/variable_def_test.dart test/features/composer/target_test.dart test/features/composer/message_renderer_test.dart`
Expected: FAIL, compilation errors (`ids.dart`, `variable_def.dart` don't exist; `normalized` is not defined).

- [ ] **Step 3: Implement**

`lib/core/utils/ids.dart`:
```dart
import 'dart:math';

/// Creates a new unique id. Injected so tests get predictable ids.
typedef IdGenerator = String Function();

final Random _random = Random.secure();

/// A random version 4 UUID, e.g. `3f2b8c1e-9d4a-4f6b-8e2a-1c3d5e7f9a0b`.
String newUuid() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
```

`lib/features/presets/domain/variable_def.dart`:
```dart
import 'package:equatable/equatable.dart';

/// How a variable is edited in the Form tab, and how a lone placeholder is typed.
enum VariableType {
  text('text'),
  multiline('multiline'),
  number('number'),
  boolean('boolean'),
  enumeration('enum');

  const VariableType(this.jsonName);

  /// The name used in preset files. `enum` is a Dart keyword, hence [enumeration].
  final String jsonName;

  static VariableType fromJson(Object? name) => values.firstWhere(
    (type) => type.jsonName == name,
    orElse: () => throw FormatException('Unknown variable type "$name".'),
  );
}

/// A value the user fills in, used in a template as `{{key}}` (spec §6).
class VariableDef extends Equatable {
  const VariableDef({
    required this.key,
    String? label,
    this.type = VariableType.text,
    this.options = const [],
    this.required = false,
    this.defaultValue = '',
  }) : label = label ?? key;

  /// Reads a definition. Throws [FormatException] that says what is wrong.
  factory VariableDef.fromJson(Map<String, Object?> json) {
    final key = json['key'];
    if (key is! String) {
      throw const FormatException('A variable has no "key".');
    }
    final label = json['label'];
    final options = json['options'];
    final defaultValue = json['defaultValue'];
    final variable = VariableDef(
      key: key,
      label: label is String && label.trim().isNotEmpty ? label : key,
      type: json.containsKey('type')
          ? VariableType.fromJson(json['type'])
          : VariableType.text,
      options: options is List<Object?>
          ? [for (final option in options) '$option']
          : const [],
      required: json['required'] == true,
      defaultValue: defaultValue == null ? '' : '$defaultValue',
    );
    final problem = variable.problem;
    if (problem != null) {
      throw FormatException(problem);
    }
    return variable;
  }

  static final RegExp keyPattern = RegExp(r'^[a-zA-Z_][a-zA-Z0-9_]*$');

  final String key;
  final String label;
  final VariableType type;

  /// The choices of a [VariableType.enumeration]; empty for other types.
  final List<String> options;
  final bool required;
  final String defaultValue;

  /// Why this definition is invalid, or null when it is fine.
  String? get problem {
    if (!keyPattern.hasMatch(key)) {
      return 'Variable key "$key" must start with a letter or _ and contain '
          'only letters, digits and _.';
    }
    if (type == VariableType.enumeration && options.isEmpty) {
      return 'Variable "$key" is a choice list but has no options.';
    }
    if (type == VariableType.number &&
        defaultValue.isNotEmpty &&
        num.tryParse(defaultValue) == null) {
      return 'The default value of "$key" must be a number.';
    }
    if (type == VariableType.boolean &&
        defaultValue.isNotEmpty &&
        defaultValue != 'true' &&
        defaultValue != 'false') {
      return 'The default value of "$key" must be true or false.';
    }
    return null;
  }

  Map<String, Object?> toJson() => {
    'key': key,
    'label': label,
    'type': type.jsonName,
    if (type == VariableType.enumeration) 'options': options,
    'required': required,
    'defaultValue': defaultValue,
  };

  @override
  List<Object?> get props => [
    key,
    label,
    type,
    options,
    required,
    defaultValue,
  ];
}
```

In `lib/features/composer/domain/target.dart`, add to `sealed class Target` (after `TargetKind get kind;`):
```dart
  /// The value as it goes to FCM: what [toMessageField] puts in the message.
  String get normalized;
```
and implement it in the three subclasses:
```dart
  // TokenTarget
  @override
  String get normalized => token;
```
```dart
  // TopicTarget
  @override
  String get normalized => name;
```
```dart
  // ConditionTarget
  @override
  String get normalized => expression;
```

`lib/features/composer/domain/placeholders.dart`:
```dart
import 'package:fcm_studio/features/composer/domain/render_issue.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';

/// Values of the built-in placeholders `{{now_iso}}`, `{{now_ms}}` and
/// `{{uuid}}`. Each has one value per render, so `{{uuid}}` used twice gives
/// the same id twice.
class BuiltinValues {
  const BuiltinValues({required this.now, required this.uuid});

  static const names = {'now_iso', 'now_ms', 'uuid'};

  final DateTime now;
  final String uuid;

  String? valueOf(String name) => switch (name) {
    'now_iso' => now.toUtc().toIso8601String(),
    'now_ms' => '${now.millisecondsSinceEpoch}',
    'uuid' => uuid,
    _ => null,
  };
}

abstract final class Placeholders {
  /// `{{key}}`, with optional spaces inside the braces.
  static final RegExp pattern = RegExp(
    r'\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}',
  );
  static final RegExp _whole = RegExp(
    r'^\{\{\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*\}\}$',
  );

  /// The key when [text] is exactly one placeholder, otherwise null.
  static String? wholeKey(String text) => _whole.firstMatch(text)?.group(1);

  /// Every placeholder key in the string values of [value], in order of first use.
  static List<String> keysIn(Object? value) {
    final keys = <String>{};
    void visit(Object? node) {
      switch (node) {
        case final String text:
          for (final match in pattern.allMatches(text)) {
            keys.add(match.group(1)!);
          }
        case final Map<String, Object?> map:
          map.values.forEach(visit);
        case final List<Object?> list:
          list.forEach(visit);
      }
    }

    visit(value);
    return keys.toList();
  }
}

/// Marks a value to be left out of its object.
const Object _remove = Object();

/// Step 1 of the rendering pipeline (spec §5.2): replaces `{{key}}` in string
/// values (not in keys), recursively. Problems go into [errors] and [notes].
class PlaceholderSubstitution {
  PlaceholderSubstitution({
    required this.definitions,
    required this.values,
    required this.builtins,
    required this.notes,
    required this.errors,
  });

  final Map<String, VariableDef> definitions;
  final Map<String, String> values;
  final BuiltinValues builtins;
  final List<RenderIssue> notes;
  final List<RenderIssue> errors;

  /// Each problem is reported once per key, at its first use.
  final Set<String> _reported = {};

  Map<String, Object?> apply(Map<String, Object?> template) =>
      _map(template, '');

  Map<String, Object?> _map(Map<String, Object?> map, String path) {
    final result = <String, Object?>{};
    map.forEach((key, value) {
      final substituted = _value(value, path.isEmpty ? key : '$path.$key');
      if (!identical(substituted, _remove)) {
        result[key] = substituted;
      }
    });
    return result;
  }

  Object? _value(Object? value, String path) {
    switch (value) {
      case final String text:
        return _string(text, path);
      case final Map<String, Object?> map:
        return _map(map, path);
      case final List<Object?> list:
        final result = <Object?>[];
        for (final (index, item) in list.indexed) {
          final substituted = _value(item, '$path[$index]');
          if (!identical(substituted, _remove)) {
            result.add(substituted);
          }
        }
        return result;
      default:
        return value;
    }
  }

  Object? _string(String text, String path) {
    final definition = definitions[Placeholders.wholeKey(text)];
    if (definition != null &&
        (definition.type == VariableType.number ||
            definition.type == VariableType.boolean)) {
      return _typed(definition, text, path);
    }
    return text.replaceAllMapped(
      Placeholders.pattern,
      (match) => _text(match.group(1)!, path) ?? match.group(0)!,
    );
  }

  /// The text for `{{key}}`, or null after reporting why it can't be filled.
  /// A definition wins over a built-in with the same name.
  String? _text(String key, String path) {
    final definition = definitions[key];
    if (definition == null) {
      final builtin = builtins.valueOf(key);
      if (builtin == null) {
        _error(key, path, 'Unknown placeholder {{$key}}. Add it under Variables.');
      }
      return builtin;
    }
    final value = values[key] ?? definition.defaultValue;
    if (definition.required && value.trim().isEmpty) {
      _error(key, path, 'Fill in "${definition.label}" ({{$key}}).');
      return null;
    }
    return value;
  }

  /// A string that is exactly one number or boolean placeholder becomes that
  /// type, so `apns.payload.aps.badge` stays an integer.
  Object? _typed(VariableDef definition, String original, String path) {
    final key = definition.key;
    final text = (values[key] ?? definition.defaultValue).trim();
    if (text.isEmpty) {
      if (definition.required) {
        _error(key, path, 'Fill in "${definition.label}" ({{$key}}).');
        return original;
      }
      notes.add(RenderIssue(path, 'Removed because {{$key}} is empty.'));
      return _remove;
    }
    if (definition.type == VariableType.boolean) {
      if (text == 'true' || text == 'false') {
        return text == 'true';
      }
      _error(
        key,
        path,
        '"${definition.label}" must be true or false, not "$text".',
      );
      return original;
    }
    final number = num.tryParse(text);
    if (number == null) {
      _error(key, path, '"${definition.label}" must be a number, not "$text".');
      return original;
    }
    return number;
  }

  void _error(String key, String path, String message) {
    if (_reported.add(key)) {
      errors.add(RenderIssue(path, message));
    }
  }
}
```

Replace `lib/features/composer/domain/message_renderer.dart` with:
```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/core/utils/ids.dart';
import 'package:fcm_studio/features/composer/domain/fcm_rules.dart';
import 'package:fcm_studio/features/composer/domain/placeholders.dart';
import 'package:fcm_studio/features/composer/domain/render_issue.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';

export 'package:fcm_studio/features/composer/domain/render_issue.dart';

class RenderResult extends Equatable {
  const RenderResult({
    this.request,
    this.notes = const [],
    this.warnings = const [],
    this.errors = const [],
    this.undefinedPlaceholders = const [],
  });

  /// The exact body for `messages:send`. Null when there are errors.
  final Map<String, Object?>? request;
  final List<RenderIssue> notes;
  final List<RenderIssue> warnings;
  final List<RenderIssue> errors;

  /// Placeholder keys the template uses that are neither defined nor built
  /// in, in order of first use. The Variables quick fix offers to add them.
  final List<String> undefinedPlaceholders;

  bool get canSend => request != null && errors.isEmpty;

  @override
  List<Object?> get props => [
    request,
    notes,
    warnings,
    errors,
    undefinedPlaceholders,
  ];
}

/// Turns a template, its variables and a target into the request body FCM
/// expects (spec §5.2).
class MessageRenderer {
  const MessageRenderer({
    this._clock = const SystemClock(),
    this._newId = newUuid,
  });

  final Clock _clock;
  final IdGenerator _newId;

  RenderResult render({
    required Map<String, Object?> template,
    required Target target,
    List<VariableDef> variables = const [],
    Map<String, String> values = const {},
    bool validateOnly = false,
  }) {
    final notes = <RenderIssue>[];
    final warnings = <RenderIssue>[];
    final errors = <RenderIssue>[];

    for (final field in Target.messageFields) {
      if (template.containsKey(field)) {
        errors.add(
          RenderIssue(
            field,
            'Remove "$field" from the JSON and set the target in the Target field instead.',
          ),
        );
      }
    }
    errors.addAll(target.validate());

    final definitions = {for (final v in variables) v.key: v};
    final usedKeys = Placeholders.keysIn(template);
    final undefined = [
      for (final key in usedKeys)
        if (!definitions.containsKey(key) &&
            !BuiltinValues.names.contains(key))
          key,
    ];
    if (usedKeys.any(BuiltinValues.names.contains)) {
      notes.add(
        const RenderIssue(
          'placeholders',
          '{{now_iso}}, {{now_ms}} and {{uuid}} get new values each time you send.',
        ),
      );
    }

    final body = PlaceholderSubstitution(
      definitions: definitions,
      values: values,
      builtins: BuiltinValues(now: _clock.now(), uuid: _newId()),
      notes: notes,
      errors: errors,
    ).apply(template)..removeWhere((key, _) => Target.messageFields.contains(key));

    final data = body['data'];
    if (data != null) {
      if (data is Map<String, Object?>) {
        body['data'] = _stringifyData(data, notes, warnings, errors);
      } else {
        errors.add(
          const RenderIssue(
            'data',
            '"data" must be an object of string values.',
          ),
        );
      }
    }
    if (!body.containsKey('notification') && body.containsKey('data')) {
      _checkBackgroundDelivery(body, warnings);
    }

    final message = <String, Object?>{...target.toMessageField(), ...body};
    final size = utf8.encode(jsonEncode(message)).length;
    if (size > FcmRules.maxPayloadBytes) {
      warnings.add(
        RenderIssue(
          'message',
          'The message is $size bytes. FCM may reject payloads over ${FcmRules.maxPayloadBytes} bytes.',
        ),
      );
    }

    if (errors.isNotEmpty) {
      return RenderResult(
        notes: notes,
        warnings: warnings,
        errors: errors,
        undefinedPlaceholders: undefined,
      );
    }
    return RenderResult(
      request: {if (validateOnly) 'validate_only': true, 'message': message},
      notes: notes,
      warnings: warnings,
      undefinedPlaceholders: undefined,
    );
  }
```
Keep the two existing static helpers `_stringifyData` and `_checkBackgroundDelivery` unchanged below `render`, then close the class.

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/core/utils/ids_test.dart test/features/presets/variable_def_test.dart test/features/composer/target_test.dart test/features/composer/message_renderer_test.dart`
Expected: PASS. Then run `flutter test` (everything passes) and `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/core/utils/ids.dart lib/features/presets/domain/variable_def.dart lib/features/composer/domain/placeholders.dart lib/features/composer/domain/target.dart lib/features/composer/domain/message_renderer.dart test/core/utils/ids_test.dart test/features/presets/variable_def_test.dart test/features/composer/target_test.dart test/features/composer/message_renderer_test.dart
git commit -m "feat: fill {{placeholders}} from variables and built-in values"
```

---

### Task 2: Template edits and the JSON locator

Pure functions for the Form tab (spec §5.3) and for "Show in JSON" on an `INVALID_ARGUMENT` field (spec §8.2).

**Files:**
- Create: `lib/features/composer/domain/template_edits.dart`, `lib/features/composer/domain/json_locator.dart`
- Test: `test/features/composer/template_edits_test.dart`, `test/features/composer/json_locator_test.dart`

**Interfaces:**
- Produces:
  - `abstract final class TemplateEdits` with `copy`, `read(template, List<String> path) → Object?`, `write(template, path, Object? value) → Map` (null or `''` removes the key and prunes emptied objects, except a top-level `notification`), `isDataOnly`, `toDataOnly`, `toNotification`, `dataEntries(template) → List<MapEntry<String, Object?>>`, `withData(template, entries)`. Every function returns a new map.
  - `abstract final class JsonLocator` with `resolve(String fieldPath, Map<String, Object?> template) → List<String>` and `lineOf(String text, List<String> path) → int?` (1-based; falls back to the closest existing ancestor).

- [ ] **Step 1: Write the failing tests**

`test/features/composer/template_edits_test.dart`:
```dart
import 'package:fcm_studio/features/composer/domain/template_edits.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const template = <String, Object?>{
    'notification': {'title': 'Hi'},
    'fcm_options': {'analytics_label': 'x'},
  };

  test('read follows the path and returns null when it is missing', () {
    expect(TemplateEdits.read(template, ['notification', 'title']), 'Hi');
    expect(TemplateEdits.read(template, ['android', 'priority']), isNull);
    expect(
      TemplateEdits.read(template, ['notification', 'title', 'x']),
      isNull,
    );
  });

  test('write creates objects on the way and keeps other fields', () {
    final result = TemplateEdits.write(template, [
      'android',
      'notification',
      'channel_id',
    ], 'orders');
    expect(result, {
      'notification': {'title': 'Hi'},
      'fcm_options': {'analytics_label': 'x'},
      'android': {
        'notification': {'channel_id': 'orders'},
      },
    });
    expect(template.containsKey('android'), isFalse);
  });

  test('an empty value removes the key and the objects it leaves empty', () {
    final withTtl = TemplateEdits.write(template, ['android', 'ttl'], '60s');
    expect(TemplateEdits.write(withTtl, ['android', 'ttl'], ''), template);
  });

  test('an emptied notification stays, so the message type does not change', () {
    final result = TemplateEdits.write(template, ['notification', 'title'], null);
    expect(result['notification'], <String, Object?>{});
    expect(TemplateEdits.isDataOnly(result), isFalse);
  });

  test('data only removes the notification and sets background delivery', () {
    final result = TemplateEdits.toDataOnly(template);
    expect(TemplateEdits.isDataOnly(result), isTrue);
    expect(result, {
      'fcm_options': {'analytics_label': 'x'},
      'android': {'priority': 'high'},
      'apns': {
        'headers': {'apns-priority': '5', 'apns-push-type': 'background'},
        'payload': {
          'aps': {'content-available': 1},
        },
      },
    });
  });

  test('switching back adds an empty notification and undoes the background settings', () {
    final result = TemplateEdits.toNotification(
      TemplateEdits.toDataOnly(template),
    );
    expect(result.keys.first, 'notification');
    expect(result, {
      'notification': {'title': '', 'body': ''},
      'fcm_options': {'analytics_label': 'x'},
      'android': {'priority': 'high'},
    });
  });

  test('withData keeps the order and removes data when empty', () {
    final result = TemplateEdits.withData(template, const [
      MapEntry('b', '2'),
      MapEntry('a', '1'),
    ]);
    expect(TemplateEdits.dataEntries(result).map((e) => e.key), ['b', 'a']);
    expect(
      TemplateEdits.withData(result, const []).containsKey('data'),
      isFalse,
    );
  });
}
```

`test/features/composer/json_locator_test.dart`:
```dart
import 'dart:convert';

import 'package:fcm_studio/features/composer/domain/json_locator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const text = '''
{
  "notification": {
    "title": "Hi",
    "body": "the \\"click_action\\" word"
  },
  "data": {
    "order_id": "42",
    "kind": "x"
  },
  "android": {
    "notification": {
      "click_action": "OPEN"
    }
  }
}''';
  final template = jsonDecode(text) as Map<String, Object?>;

  test('finds the line of a key', () {
    expect(JsonLocator.lineOf(text, ['data', 'kind']), 8);
    expect(
      JsonLocator.lineOf(text, ['android', 'notification', 'click_action']),
      12,
    );
  });

  test('falls back to the closest key that exists', () {
    expect(
      JsonLocator.lineOf(text, ['android', 'notification', 'color']),
      11,
    );
    expect(JsonLocator.lineOf(text, ['apns', 'headers']), isNull);
  });

  test('ignores key-like text inside string values', () {
    expect(JsonLocator.lineOf(text, ['notification', 'click_action']), 2);
  });

  test('turns FCM field paths into template keys', () {
    expect(JsonLocator.resolve('message.data[1].value', template), [
      'data',
      'kind',
    ]);
    expect(
      JsonLocator.resolve('message.android.notification.clickAction', template),
      ['android', 'notification', 'click_action'],
    );
    expect(JsonLocator.resolve('message.apns.payload', template), isEmpty);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/composer/template_edits_test.dart test/features/composer/json_locator_test.dart`
Expected: FAIL, compilation errors (the files don't exist).

- [ ] **Step 3: Implement**

`lib/features/composer/domain/template_edits.dart`:
```dart
import 'dart:convert';

/// Pure edits on a message template, used by the Form tab (spec §5.3).
/// Every function returns a new map and keeps the fields it doesn't touch.
abstract final class TemplateEdits {
  /// Top-level objects that stay even when empty: removing `notification`
  /// would turn the message into a data-only one.
  static const keepWhenEmpty = {'notification'};

  /// The settings "Data only" adds for background delivery (spec §5.3).
  static const _backgroundSettings = <(List<String>, Object)>[
    (['apns', 'headers', 'apns-priority'], '5'),
    (['apns', 'headers', 'apns-push-type'], 'background'),
    (['apns', 'payload', 'aps', 'content-available'], 1),
  ];

  /// A deep, modifiable copy.
  static Map<String, Object?> copy(Map<String, Object?> template) =>
      jsonDecode(jsonEncode(template)) as Map<String, Object?>;

  /// The value at [path], or null when any part of it is missing.
  static Object? read(Map<String, Object?> template, List<String> path) {
    Object? node = template;
    for (final key in path) {
      if (node is! Map<String, Object?>) {
        return null;
      }
      node = node[key];
    }
    return node;
  }

  /// Sets [value] at [path], creating objects on the way. A null or empty
  /// string removes the key, and objects left empty by that are removed too.
  static Map<String, Object?> write(
    Map<String, Object?> template,
    List<String> path,
    Object? value,
  ) {
    final result = copy(template);
    _write(result, path, value, topLevel: true);
    return result;
  }

  static bool _isEmptyValue(Object? value) => value == null || value == '';

  static void _write(
    Map<String, Object?> map,
    List<String> path,
    Object? value, {
    required bool topLevel,
  }) {
    final key = path.first;
    if (path.length == 1) {
      if (_isEmptyValue(value)) {
        map.remove(key);
      } else {
        map[key] = value;
      }
      return;
    }
    if (map[key] is! Map<String, Object?>) {
      if (_isEmptyValue(value)) {
        return;
      }
      map[key] = <String, Object?>{};
    }
    final child = map[key]! as Map<String, Object?>;
    _write(child, path.sublist(1), value, topLevel: false);
    if (child.isEmpty && !(topLevel && keepWhenEmpty.contains(key))) {
      map.remove(key);
    }
  }

  static bool isDataOnly(Map<String, Object?> template) =>
      !template.containsKey('notification');

  /// Switches to a data-only (background) message.
  static Map<String, Object?> toDataOnly(Map<String, Object?> template) {
    var result = copy(template)..remove('notification');
    result = write(result, ['android', 'priority'], 'high');
    for (final (path, value) in _backgroundSettings) {
      result = write(result, path, value);
    }
    return result;
  }

  /// Switches back to a visible notification: adds an empty `notification`
  /// first and removes the background settings that [toDataOnly] added.
  static Map<String, Object?> toNotification(Map<String, Object?> template) {
    if (!isDataOnly(template)) {
      return copy(template);
    }
    var result = <String, Object?>{
      'notification': <String, Object?>{'title': '', 'body': ''},
      ...copy(template),
    };
    for (final (path, value) in _backgroundSettings) {
      if (read(result, path) == value) {
        result = write(result, path, null);
      }
    }
    return result;
  }

  /// The `data` entries in order; empty when `data` is missing or not an object.
  static List<MapEntry<String, Object?>> dataEntries(
    Map<String, Object?> template,
  ) {
    final data = template['data'];
    return data is Map<String, Object?> ? data.entries.toList() : const [];
  }

  /// Replaces `data` with [entries] in their order. No entries removes `data`.
  static Map<String, Object?> withData(
    Map<String, Object?> template,
    List<MapEntry<String, Object?>> entries,
  ) {
    final result = copy(template);
    if (entries.isEmpty) {
      result.remove('data');
    } else {
      result['data'] = Map<String, Object?>.fromEntries(entries);
    }
    return result;
  }
}
```

`lib/features/composer/domain/json_locator.dart`:
```dart
/// Finds where a field is in the JSON editor's text, for "Show in JSON".
abstract final class JsonLocator {
  static final RegExp _segment = RegExp(r'^([A-Za-z0-9_\-]+)(?:\[(\d+)\])?$');

  /// Turns an FCM field path such as `message.android.notification.color` or
  /// `message.data[0].value` into keys of [template]. `data[0]` is the first
  /// entry of the `data` object. Stops at the first part that doesn't exist.
  static List<String> resolve(String fieldPath, Map<String, Object?> template) {
    final path = fieldPath.startsWith('message.')
        ? fieldPath.substring('message.'.length)
        : fieldPath;
    final result = <String>[];
    Object? node = template;
    for (final part in path.split('.')) {
      final match = _segment.firstMatch(part);
      final key = match == null ? null : _findKey(node, match.group(1)!);
      if (match == null || key == null) {
        break;
      }
      result.add(key);
      node = (node as Map<String, Object?>)[key];
      final index = match.group(2);
      if (index == null) {
        continue;
      }
      final i = int.parse(index);
      if (node is Map<String, Object?>) {
        final keys = node.keys.toList();
        if (i < keys.length) {
          result.add(keys[i]);
        }
        // What follows (`.key`, `.value`) belongs to the map entry.
        return result;
      }
      if (node is! List<Object?> || i >= node.length) {
        break;
      }
      result.add('$i');
      node = node[i];
    }
    return result;
  }

  /// FCM reports proto names (`click_action`); the JSON may use either form.
  static String? _findKey(Object? node, String name) {
    if (node is! Map<String, Object?>) {
      return null;
    }
    for (final candidate in [name, _camel(name), _snake(name)]) {
      if (node.containsKey(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  static String _camel(String name) => name.replaceAllMapped(
    RegExp('_([a-z])'),
    (m) => m[1]!.toUpperCase(),
  );

  static String _snake(String name) => name.replaceAllMapped(
    RegExp('[A-Z]'),
    (m) => '_${m[0]!.toLowerCase()}',
  );

  /// The 1-based line of the key at [path] in [text], or of its closest
  /// ancestor that exists. Null when not even the first key exists.
  /// Array items are addressed by their index as a string.
  static int? lineOf(String text, List<String> path) {
    if (path.isEmpty) {
      return null;
    }
    final frames = <_Frame>[];
    var line = 1;
    int? bestLine;
    var bestLength = 0;
    var i = 0;
    while (i < text.length) {
      final char = text[i];
      if (char == '"') {
        final buffer = StringBuffer();
        i++;
        while (i < text.length && text[i] != '"') {
          if (text[i] == r'\' && i + 1 < text.length) {
            buffer.write(text[i + 1]);
            i += 2;
          } else {
            buffer.write(text[i]);
            i++;
          }
        }
        final frame = frames.lastOrNull;
        if (frame != null && frame.isObject && frame.expectingKey) {
          frame
            ..key = buffer.toString()
            ..expectingKey = false;
          final current = [for (final f in frames) f.segment];
          if (current.length > bestLength && _startsWith(path, current)) {
            bestLength = current.length;
            bestLine = line;
            if (bestLength == path.length) {
              return line;
            }
          }
        }
      } else if (char == '\n') {
        line++;
      } else if (char == '{' || char == '[') {
        frames.add(_Frame(isObject: char == '{'));
      } else if (char == '}' || char == ']') {
        if (frames.isNotEmpty) {
          frames.removeLast();
        }
      } else if (char == ',') {
        final frame = frames.lastOrNull;
        if (frame != null) {
          if (frame.isObject) {
            frame.expectingKey = true;
          } else {
            frame.index++;
          }
        }
      }
      i++;
    }
    return bestLine;
  }

  static bool _startsWith(List<String> path, List<String> prefix) {
    if (prefix.length > path.length) {
      return false;
    }
    for (var i = 0; i < prefix.length; i++) {
      if (path[i] != prefix[i]) {
        return false;
      }
    }
    return true;
  }
}

/// An object or array the scanner is inside.
class _Frame {
  _Frame({required this.isObject});

  final bool isObject;
  bool expectingKey = true;
  String key = '';
  int index = 0;

  String get segment => isObject ? key : '$index';
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/features/composer/template_edits_test.dart test/features/composer/json_locator_test.dart`
Expected: PASS (7 + 4 tests). Then `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/features/composer/domain/template_edits.dart lib/features/composer/domain/json_locator.dart test/features/composer/template_edits_test.dart test/features/composer/json_locator_test.dart
git commit -m "feat: add template edits for the form and a JSON field locator"
```

---

### Task 3: cURL, token shortening and the production safeguard rule

**Files:**
- Create: `lib/core/utils/shorten.dart`, `lib/core/fcm/curl_builder.dart`, `lib/features/composer/domain/send_confirmation.dart`
- Test: `test/core/utils/shorten_test.dart`, `test/core/fcm/curl_builder_test.dart`, `test/features/composer/send_confirmation_test.dart`

**Interfaces:**
- Consumes: `FcmClient.sendUri` (existing), `Project`/`ProjectEnvironment` (existing), `Target` subclasses.
- Produces:
  - `String shortenMiddle(String value, {int head = 6, int tail = 4})`.
  - `abstract final class CurlBuilder` with `tokenVariable` (`r'$FCM_ACCESS_TOKEN'`), `build({required String projectId, required Map<String, Object?> body, String? accessToken, Map<String, String> extraHeaders = const {}}) → String` and `quote(String) → String`.
  - `class SendConfirmation({required projectId, required audience, required requiresTypedProjectId})` with `static SendConfirmation? forSend({required Project project, required Target target, required bool validateOnly})`.

- [ ] **Step 1: Write the failing tests**

`test/core/utils/shorten_test.dart`:
```dart
import 'package:fcm_studio/core/utils/shorten.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shortens long values in the middle and leaves short ones alone', () {
    expect(shortenMiddle('fAbC12345678909xYz'), 'fAbC12…9xYz');
    expect(shortenMiddle('news'), 'news');
  });
}
```

`test/core/fcm/curl_builder_test.dart`:
```dart
import 'dart:io';

import 'package:fcm_studio/core/fcm/curl_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const body = {
    'message': {'topic': 'news'},
  };

  test('builds a bash command that reads the token from a variable', () {
    final command = CurlBuilder.build(projectId: 'demo-project', body: body);
    expect(
      command,
      "curl -X POST 'https://fcm.googleapis.com/v1/projects/demo-project/messages:send' \\\n"
      '  -H "Authorization: Bearer \$FCM_ACCESS_TOKEN" \\\n'
      "  -H 'Content-Type: application/json; charset=utf-8' \\\n"
      """  -d '{"message":{"topic":"news"}}'""",
    );
  });

  test('can include the access token and extra headers', () {
    final command = CurlBuilder.build(
      projectId: 'demo-project',
      body: body,
      accessToken: 'ya29.abc',
      extraHeaders: {'x-goog-user-project': 'demo-project'},
    );
    expect(command, contains("-H 'Authorization: Bearer ya29.abc'"));
    expect(command, contains("-H 'x-goog-user-project: demo-project'"));
  });

  test('escapes single quotes in the body', () {
    final command = CurlBuilder.build(
      projectId: 'demo-project',
      body: {
        'message': {
          'notification': {'title': "it's"},
        },
      },
    );
    expect(
      command,
      contains(r"""-d '{"message":{"notification":{"title":"it'\''s"}}}'"""),
    );
  });

  test(
    'quoting survives bash',
    () async {
      const tricky = 'it\'s a "test" with \$HOME and \\n';
      final result = await Process.run('bash', [
        '-c',
        'printf %s ${CurlBuilder.quote(tricky)}',
      ]);
      expect(result.stdout, tricky);
    },
    skip: Platform.isWindows ? 'needs bash' : false,
  );
}
```

`test/features/composer/send_confirmation_test.dart`:
```dart
import 'package:fcm_studio/features/composer/domain/send_confirmation.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/project_fixture.dart';

void main() {
  final prod = testProject.copyWith(environment: ProjectEnvironment.prod);

  test('dev and staging projects send without asking', () {
    for (final environment in [
      ProjectEnvironment.dev,
      ProjectEnvironment.staging,
    ]) {
      expect(
        SendConfirmation.forSend(
          project: testProject.copyWith(environment: environment),
          target: const TopicTarget('news'),
          validateOnly: false,
        ),
        isNull,
      );
    }
  });

  test('a prod dry run sends without asking, because nothing is delivered', () {
    expect(
      SendConfirmation.forSend(
        project: prod,
        target: const TopicTarget('news'),
        validateOnly: true,
      ),
      isNull,
    );
  });

  test('a prod token send asks, without typing the project ID', () {
    final confirmation = SendConfirmation.forSend(
      project: prod,
      target: const TokenTarget('fAbC12345678909xYz'),
      validateOnly: false,
    );
    expect(confirmation?.audience, 'one device (token fAbC12…9xYz)');
    expect(confirmation?.requiresTypedProjectId, isFalse);
  });

  test('prod topic and condition sends name the audience and need the project ID', () {
    final topic = SendConfirmation.forSend(
      project: prod,
      target: const TopicTarget('/topics/all_zone_store'),
      validateOnly: false,
    );
    expect(topic?.audience, 'every device subscribed to `all_zone_store`');
    expect(topic?.requiresTypedProjectId, isTrue);
    expect(topic?.projectId, 'demo-project');

    final condition = SendConfirmation.forSend(
      project: prod,
      target: const ConditionTarget("'a' in topics"),
      validateOnly: false,
    );
    expect(condition?.audience, "every device matching `'a' in topics`");
    expect(condition?.requiresTypedProjectId, isTrue);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/core/utils/shorten_test.dart test/core/fcm/curl_builder_test.dart test/features/composer/send_confirmation_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement**

`lib/core/utils/shorten.dart`:
```dart
/// Shortens a long value for lists, e.g. `fAbC12…9xYz`. Short values are
/// returned unchanged.
String shortenMiddle(String value, {int head = 6, int tail = 4}) =>
    value.length <= head + tail + 1
    ? value
    : '${value.substring(0, head)}…${value.substring(value.length - tail)}';
```

`lib/core/fcm/curl_builder.dart`:
```dart
import 'dart:convert';

import 'package:fcm_studio/core/fcm/fcm_client.dart';

/// Builds a bash `curl` command for an FCM send (spec §8.3). Only bash quoting
/// is supported; on Windows it works in Git Bash or WSL.
abstract final class CurlBuilder {
  static const tokenVariable = r'$FCM_ACCESS_TOKEN';

  /// With [accessToken] null, the command reads the token from
  /// `$FCM_ACCESS_TOKEN` (double-quoted, so bash expands it).
  static String build({
    required String projectId,
    required Map<String, Object?> body,
    String? accessToken,
    Map<String, String> extraHeaders = const {},
  }) {
    final authorization = accessToken == null
        ? '"Authorization: Bearer $tokenVariable"'
        : quote('Authorization: Bearer $accessToken');
    return [
      'curl -X POST ${quote(FcmClient.sendUri(projectId).toString())}',
      '-H $authorization',
      "-H 'Content-Type: application/json; charset=utf-8'",
      for (final header in extraHeaders.entries)
        '-H ${quote('${header.key}: ${header.value}')}',
      '-d ${quote(jsonEncode(body))}',
    ].join(' \\\n  ');
  }

  /// Single-quotes [value] for bash. A `'` inside becomes `'\''`.
  static String quote(String value) => "'${value.replaceAll("'", r"'\''")}'";
}
```

`lib/features/composer/domain/send_confirmation.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/utils/shorten.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

/// What the production safeguard asks before a send (spec §4.3).
class SendConfirmation extends Equatable {
  const SendConfirmation({
    required this.projectId,
    required this.audience,
    required this.requiresTypedProjectId,
  });

  final String projectId;

  /// Who receives the message, e.g. "every device subscribed to `news`".
  final String audience;

  /// True for topic and condition sends: the user must type the project ID.
  final bool requiresTypedProjectId;

  /// Null when no confirmation is needed: the project is not prod, or it is a
  /// dry run, which delivers nothing.
  static SendConfirmation? forSend({
    required Project project,
    required Target target,
    required bool validateOnly,
  }) {
    if (project.environment != ProjectEnvironment.prod || validateOnly) {
      return null;
    }
    return switch (target) {
      TokenTarget(:final token) => SendConfirmation(
        projectId: project.id,
        audience: 'one device (token ${shortenMiddle(token)})',
        requiresTypedProjectId: false,
      ),
      TopicTarget(:final name) => SendConfirmation(
        projectId: project.id,
        audience: 'every device subscribed to `$name`',
        requiresTypedProjectId: true,
      ),
      ConditionTarget(:final expression) => SendConfirmation(
        projectId: project.id,
        audience: 'every device matching `$expression`',
        requiresTypedProjectId: true,
      ),
    };
  }

  @override
  List<Object?> get props => [projectId, audience, requiresTypedProjectId];
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/core/utils/shorten_test.dart test/core/fcm/curl_builder_test.dart test/features/composer/send_confirmation_test.dart`
Expected: PASS. Then `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/core/utils/shorten.dart lib/core/fcm/curl_builder.dart lib/features/composer/domain/send_confirmation.dart test/core/utils/shorten_test.dart test/core/fcm/curl_builder_test.dart test/features/composer/send_confirmation_test.dart
git commit -m "feat: build curl commands and decide when a prod send needs confirming"
```

---

### Task 4: Presets model, file format and the built-in presets

**Files:**
- Create: `lib/features/presets/domain/preset.dart`, `lib/features/presets/domain/preset_codec.dart`, `assets/presets/builtin.json`
- Test: `test/features/presets/preset_codec_test.dart`

**Interfaces:**
- Consumes: `VariableDef` (Task 1), `Target.messageFields` (existing), `IdGenerator` (Task 1), `MessageRenderer` (Task 1, in a test).
- Produces:
  - `const kPresetSchemaVersion = 1;`
  - `class Preset({required id, required name, required Map<String, Object?> template, required DateTime createdAt, required DateTime updatedAt, String description = '', List<VariableDef> variables = const [], bool builtIn = false})` with `fromJson` (throws `FormatException`), `toJson()`, `copyWith(...)`.
  - `class PresetFormatException(String message)`, `enum ImportConflictChoice { keepBoth, replace, skip }`, `class ImportPreview({required List<Preset> incoming, required List<String> conflicts})`.
  - `abstract final class PresetCodec` with `format`, `version`, `fileExtension`, `encode(presets, {required exportedAt})`, `decode(text)`, `preview({existing, incoming})`, `resolve({existing, incoming, choice, newId, now})`, `uniqueName(name, Set<String> taken)`, `normalizeName(name)`.
  - Built-in preset ids: `builtin.simple`, `builtin.image`, `builtin.notification_data`, `builtin.data_only`.

- [ ] **Step 1: Add the built-in presets file**

`assets/presets/builtin.json` (the same format as an export; `PresetsRepository` marks these presets built-in in Task 9):
```json
{
  "format": "fcm-studio.presets",
  "version": 1,
  "exportedAt": "2026-10-03T00:00:00.000Z",
  "presets": [
    {
      "id": "builtin.simple",
      "name": "Simple notification",
      "description": "A title and a body.",
      "variables": [
        {"key": "title", "label": "Title", "type": "text", "required": true, "defaultValue": "Hello from FCM Studio"},
        {"key": "body", "label": "Body", "type": "multiline", "required": false, "defaultValue": "If you can read this, it works."}
      ],
      "template": {
        "notification": {"title": "{{title}}", "body": "{{body}}"}
      },
      "createdAt": "2026-10-03T00:00:00.000Z",
      "updatedAt": "2026-10-03T00:00:00.000Z"
    },
    {
      "id": "builtin.image",
      "name": "Notification with image",
      "description": "A notification with a large image. iOS needs a notification service extension to show it.",
      "variables": [
        {"key": "title", "label": "Title", "type": "text", "required": true, "defaultValue": "Hello from FCM Studio"},
        {"key": "body", "label": "Body", "type": "multiline", "required": false, "defaultValue": "This one has a picture."},
        {"key": "image_url", "label": "Image URL (https)", "type": "text", "required": true, "defaultValue": ""}
      ],
      "template": {
        "notification": {"title": "{{title}}", "body": "{{body}}", "image": "{{image_url}}"},
        "apns": {
          "payload": {"aps": {"mutable-content": 1}},
          "fcm_options": {"image": "{{image_url}}"}
        }
      },
      "createdAt": "2026-10-03T00:00:00.000Z",
      "updatedAt": "2026-10-03T00:00:00.000Z"
    },
    {
      "id": "builtin.notification_data",
      "name": "Notification + data",
      "description": "A notification plus key/value data the app reads when it is tapped.",
      "variables": [
        {"key": "title", "label": "Title", "type": "text", "required": true, "defaultValue": "Your order has shipped"},
        {"key": "body", "label": "Body", "type": "multiline", "required": false, "defaultValue": "Tap to see the details."},
        {"key": "type", "label": "Type", "type": "text", "required": false, "defaultValue": "order_update"},
        {"key": "id", "label": "ID", "type": "text", "required": false, "defaultValue": "42"}
      ],
      "template": {
        "notification": {"title": "{{title}}", "body": "{{body}}"},
        "data": {"type": "{{type}}", "id": "{{id}}", "sent_at": "{{now_iso}}"},
        "android": {"priority": "high"}
      },
      "createdAt": "2026-10-03T00:00:00.000Z",
      "updatedAt": "2026-10-03T00:00:00.000Z"
    },
    {
      "id": "builtin.data_only",
      "name": "Data only (silent / background)",
      "description": "No visible notification. The app receives the data in the background.",
      "variables": [
        {"key": "type", "label": "Type", "type": "text", "required": false, "defaultValue": "sync"}
      ],
      "template": {
        "data": {"type": "{{type}}", "sent_at": "{{now_iso}}"},
        "android": {"priority": "high"},
        "apns": {
          "headers": {"apns-priority": "5", "apns-push-type": "background"},
          "payload": {"aps": {"content-available": 1}}
        }
      },
      "createdAt": "2026-10-03T00:00:00.000Z",
      "updatedAt": "2026-10-03T00:00:00.000Z"
    }
  ]
}
```

- [ ] **Step 2: Write the failing tests** `test/features/presets/preset_codec_test.dart`

```dart
import 'dart:convert';
import 'dart:io';

import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final created = DateTime.utc(2026, 10, 3);
  final preset = Preset(
    id: 'p1',
    name: 'Order update',
    description: 'Tells the user about an order',
    variables: const [
      VariableDef(key: 'order_id', label: 'Order', required: true),
    ],
    template: const {
      'notification': {'title': 'Order {{order_id}}'},
    },
    createdAt: created,
    updatedAt: created,
  );

  String exportOf(List<Object?> presets, {Object? version = 1}) => jsonEncode({
    'format': PresetCodec.format,
    'version': version,
    'exportedAt': '2026-10-03T00:00:00.000Z',
    'presets': presets,
  });

  Matcher formatError(Object message) => throwsA(
    isA<PresetFormatException>().having((e) => e.message, 'message', message),
  );

  test('round-trips presets through an export file', () {
    final text = PresetCodec.encode([
      preset.copyWith(builtIn: true),
    ], exportedAt: created);
    final json = jsonDecode(text) as Map<String, Object?>;
    expect(json['format'], 'fcm-studio.presets');
    expect(json['version'], 1);
    expect(PresetCodec.decode(text), [preset]);
  });

  test('explains files that are not preset exports', () {
    expect(
      () => PresetCodec.decode('not json'),
      formatError('This file is not valid JSON.'),
    );
    expect(
      () => PresetCodec.decode(
        jsonEncode({'project_info': <String, Object?>{}, 'client': <Object?>[]}),
      ),
      formatError(contains('not an FCM Studio presets file')),
    );
    expect(
      () => PresetCodec.decode(exportOf([], version: 2)),
      formatError(
        'This file was made by a newer FCM Studio (format version 2). '
        'Update FCM Studio to import it.',
      ),
    );
    expect(
      () => PresetCodec.decode(
        jsonEncode({'format': PresetCodec.format, 'version': 1}),
      ),
      formatError('The file has no "presets" list.'),
    );
  });

  test('names the preset that is invalid', () {
    final withToken = {
      ...preset.toJson(),
      'template': {'token': 'abc', 'notification': <String, Object?>{}},
    };
    expect(
      () => PresetCodec.decode(exportOf([preset.toJson(), withToken])),
      formatError(
        'Preset 2: "Order update" sets "token" in its template; '
        'the target is never part of a preset.',
      ),
    );
    final badKey = {
      ...preset.toJson(),
      'variables': [
        {'key': '1st'},
      ],
    };
    expect(
      () => PresetCodec.decode(exportOf([badKey])),
      formatError(contains('Preset 1: "Order update": Variable key "1st"')),
    );
    final twice = {
      ...preset.toJson(),
      'variables': [
        {'key': 'a'},
        {'key': 'a'},
      ],
    };
    expect(
      () => PresetCodec.decode(exportOf([twice])),
      formatError(contains('defines the variable "a" twice')),
    );
  });

  test('the built-in presets are valid and render with their defaults', () {
    final presets = PresetCodec.decode(
      File('assets/presets/builtin.json').readAsStringSync(),
    );
    expect(presets.map((p) => p.name), [
      'Simple notification',
      'Notification with image',
      'Notification + data',
      'Data only (silent / background)',
    ]);
    for (final p in presets) {
      final result = const MessageRenderer().render(
        template: p.template,
        target: const TopicTarget('news'),
        variables: p.variables,
        values: {for (final v in p.variables) v.key: v.defaultValue},
      );
      if (p.id == 'builtin.image') {
        expect(
          result.errors.single.message,
          'Fill in "Image URL (https)" ({{image_url}}).',
        );
      } else {
        expect(result.errors, isEmpty, reason: p.name);
      }
    }
  });

  group('import', () {
    var counter = 0;
    String newId() => 'new-${++counter}';
    setUp(() => counter = 0);

    Preset named(String name, {bool builtIn = false, String? id}) =>
        preset.copyWith(id: id ?? name, name: name, builtIn: builtIn);

    test('lists name conflicts, ignoring case', () {
      final preview = PresetCodec.preview(
        existing: [named('Order update')],
        incoming: [named('order UPDATE'), named('Other')],
      );
      expect(preview.conflicts, ['order UPDATE']);
    });

    test('keep both adds " (2)", or the next free number', () {
      final result = PresetCodec.resolve(
        existing: [named('A'), named('A (2)')],
        incoming: [named('A')],
        choice: ImportConflictChoice.keepBoth,
        newId: newId,
        now: created,
      );
      expect(result.single.name, 'A (3)');
      expect(result.single.id, 'new-1');
    });

    test('replace overwrites the user preset with the same name', () {
      final result = PresetCodec.resolve(
        existing: [named('A', id: 'mine')],
        incoming: [named('A')],
        choice: ImportConflictChoice.replace,
        newId: newId,
        now: created,
      );
      expect(result.single.id, 'mine');
      expect(result.single.name, 'A');
    });

    test('built-in presets are never replaced', () {
      final result = PresetCodec.resolve(
        existing: [named('A', builtIn: true)],
        incoming: [named('A')],
        choice: ImportConflictChoice.replace,
        newId: newId,
        now: created,
      );
      expect(result.single.name, 'A (2)');
      expect(result.single.builtIn, isFalse);
    });

    test('skip leaves conflicting presets out', () {
      final result = PresetCodec.resolve(
        existing: [named('A')],
        incoming: [named('A'), named('B')],
        choice: ImportConflictChoice.skip,
        newId: newId,
        now: created,
      );
      expect(result.map((p) => p.name), ['B']);
    });

    test('imported presets get new ids and are never built-in', () {
      final result = PresetCodec.resolve(
        existing: const [],
        incoming: [named('B', builtIn: true, id: 'x')],
        choice: ImportConflictChoice.keepBoth,
        newId: newId,
        now: created,
      );
      expect(result.single.id, 'new-1');
      expect(result.single.builtIn, isFalse);
      expect(result.single.updatedAt, created);
    });
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/presets/preset_codec_test.dart`
Expected: FAIL, compilation errors (`preset.dart` and `preset_codec.dart` don't exist).

- [ ] **Step 4: Implement**

`lib/features/presets/domain/preset.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';

/// Written into every stored preset record, for future migrations.
const kPresetSchemaVersion = 1;

/// A saved message template with its variables (spec §6).
class Preset extends Equatable {
  const Preset({
    required this.id,
    required this.name,
    required this.template,
    required this.createdAt,
    required this.updatedAt,
    this.description = '',
    this.variables = const [],
    this.builtIn = false,
  });

  /// Reads a preset. Throws [FormatException] with a message that names the problem.
  factory Preset.fromJson(Map<String, Object?> json) {
    final name = json['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const FormatException('it has no "name".');
    }
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw FormatException('"$name" has no "id".');
    }
    final template = json['template'];
    if (template is! Map<String, Object?>) {
      throw FormatException('"$name" has no "template" object.');
    }
    for (final field in Target.messageFields) {
      if (template.containsKey(field)) {
        throw FormatException(
          '"$name" sets "$field" in its template; '
          'the target is never part of a preset.',
        );
      }
    }
    final rawVariables = json['variables'] ?? const <Object?>[];
    if (rawVariables is! List<Object?>) {
      throw FormatException('"$name": "variables" must be a list.');
    }
    final variables = <VariableDef>[];
    for (final raw in rawVariables) {
      if (raw is! Map<String, Object?>) {
        throw FormatException('"$name": each variable must be an object.');
      }
      final VariableDef variable;
      try {
        variable = VariableDef.fromJson(raw);
      } on FormatException catch (e) {
        throw FormatException('"$name": ${e.message}');
      }
      if (variables.any((v) => v.key == variable.key)) {
        throw FormatException(
          '"$name" defines the variable "${variable.key}" twice.',
        );
      }
      variables.add(variable);
    }
    final description = json['description'];
    return Preset(
      id: id,
      name: name.trim(),
      description: description is String ? description : '',
      variables: variables,
      template: template,
      builtIn: json['builtIn'] == true,
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
    );
  }

  final String id;
  final String name;
  final String description;
  final List<VariableDef> variables;

  /// The FCM `message` object without the target.
  final Map<String, Object?> template;

  /// Shipped with the app; read-only, but can be duplicated.
  final bool builtIn;
  final DateTime createdAt;
  final DateTime updatedAt;

  static DateTime _date(Object? value) =>
      (value is String ? DateTime.tryParse(value) : null)?.toUtc() ??
      DateTime.utc(1970);

  Preset copyWith({
    String? id,
    String? name,
    String? description,
    List<VariableDef>? variables,
    Map<String, Object?>? template,
    bool? builtIn,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Preset(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    variables: variables ?? this.variables,
    template: template ?? this.template,
    builtIn: builtIn ?? this.builtIn,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': kPresetSchemaVersion,
    'id': id,
    'name': name,
    'description': description,
    'variables': [for (final v in variables) v.toJson()],
    'template': template,
    'builtIn': builtIn,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };

  @override
  List<Object?> get props => [
    id,
    name,
    description,
    variables,
    template,
    builtIn,
    createdAt,
    updatedAt,
  ];
}
```

`lib/features/presets/domain/preset_codec.dart`:
```dart
import 'dart:convert';

import 'package:fcm_studio/core/utils/ids.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';

class PresetFormatException implements Exception {
  const PresetFormatException(this.message);

  final String message;

  @override
  String toString() => 'PresetFormatException: $message';
}

/// What to do with an imported preset whose name already exists (spec §6).
enum ImportConflictChoice { keepBoth, replace, skip }

/// A read import file, and the names in it that already exist.
class ImportPreview {
  const ImportPreview({required this.incoming, required this.conflicts});

  final List<Preset> incoming;
  final List<String> conflicts;
}

/// The `*.fcmpresets.json` export format and the import rules (spec §6).
abstract final class PresetCodec {
  static const format = 'fcm-studio.presets';
  static const version = 1;
  static const fileExtension = '.fcmpresets.json';

  /// An export file. Presets hold no credentials, targets or history.
  static String encode(List<Preset> presets, {required DateTime exportedAt}) =>
      const JsonEncoder.withIndent('  ').convert({
        'format': format,
        'version': version,
        'exportedAt': exportedAt.toUtc().toIso8601String(),
        'presets': [
          for (final preset in presets)
            preset.toJson()
              ..remove('schemaVersion')
              ..['builtIn'] = false,
        ],
      });

  /// Reads an export file. Throws [PresetFormatException] that says what is wrong.
  static List<Preset> decode(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } on FormatException {
      throw const PresetFormatException('This file is not valid JSON.');
    }
    if (decoded is! Map<String, Object?> || decoded['format'] != format) {
      throw const PresetFormatException(
        'This is not an FCM Studio presets file '
        '(expected "format": "fcm-studio.presets").',
      );
    }
    final fileVersion = decoded['version'];
    if (fileVersion is! int || fileVersion < 1) {
      throw const PresetFormatException('The file has no valid format version.');
    }
    if (fileVersion > version) {
      throw PresetFormatException(
        'This file was made by a newer FCM Studio (format version $fileVersion). '
        'Update FCM Studio to import it.',
      );
    }
    final presets = decoded['presets'];
    if (presets is! List<Object?>) {
      throw const PresetFormatException('The file has no "presets" list.');
    }
    final result = <Preset>[];
    for (final (index, raw) in presets.indexed) {
      if (raw is! Map<String, Object?>) {
        throw PresetFormatException('Preset ${index + 1} is not an object.');
      }
      try {
        result.add(Preset.fromJson(raw));
      } on FormatException catch (e) {
        throw PresetFormatException('Preset ${index + 1}: ${e.message}');
      }
    }
    return result;
  }

  /// Lists the incoming names that already exist, ignoring case.
  static ImportPreview preview({
    required List<Preset> existing,
    required List<Preset> incoming,
  }) {
    final names = {for (final p in existing) normalizeName(p.name)};
    return ImportPreview(
      incoming: incoming,
      conflicts: [
        for (final p in incoming)
          if (names.contains(normalizeName(p.name))) p.name,
      ],
    );
  }

  /// The presets to store for an import. Each gets a new id and is never
  /// built-in. A name clash is kept with " (2)", replaces the user's preset,
  /// or is skipped. Built-in presets are never replaced: a clash with one is
  /// kept as a copy.
  static List<Preset> resolve({
    required List<Preset> existing,
    required List<Preset> incoming,
    required ImportConflictChoice choice,
    required IdGenerator newId,
    required DateTime now,
  }) {
    final taken = {for (final p in existing) normalizeName(p.name): p};
    final result = <Preset>[];
    for (final preset in incoming) {
      final clash = taken[normalizeName(preset.name)];
      if (clash != null && choice == ImportConflictChoice.skip) {
        continue;
      }
      final replaced =
          clash != null &&
              choice == ImportConflictChoice.replace &&
              !clash.builtIn
          ? clash
          : null;
      final stored = preset.copyWith(
        id: replaced?.id ?? newId(),
        name: clash == null || replaced != null
            ? preset.name
            : uniqueName(preset.name, taken.keys.toSet()),
        builtIn: false,
        createdAt: replaced?.createdAt ?? preset.createdAt,
        updatedAt: now,
      );
      taken[normalizeName(stored.name)] = stored;
      result.add(stored);
    }
    return result;
  }

  /// [name], or `name (2)`, `name (3)`… whichever is not in [taken]
  /// (a set of [normalizeName]d names).
  static String uniqueName(String name, Set<String> taken) {
    if (!taken.contains(normalizeName(name))) {
      return name;
    }
    var n = 2;
    while (taken.contains(normalizeName('$name ($n)'))) {
      n++;
    }
    return '$name ($n)';
  }

  /// How names are compared: trimmed and lower-cased.
  static String normalizeName(String name) => name.trim().toLowerCase();
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/features/presets/preset_codec_test.dart`
Expected: PASS (5 tests + 6 in the import group). Then `flutter analyze` (No issues found!).

- [ ] **Step 6: Commit**

```bash
dart format lib test
git add assets/presets/builtin.json lib/features/presets/domain/preset.dart lib/features/presets/domain/preset_codec.dart test/features/presets/preset_codec_test.dart
git commit -m "feat: add presets, their export format and the four built-in presets"
```

---

### Task 5: Saved targets: model and repository

**Files:**
- Create: `lib/features/targets/domain/saved_target.dart`, `lib/features/targets/data/targets_repository.dart`
- Test: `test/features/targets/saved_target_test.dart`, `test/features/targets/targets_repository_test.dart`

**Interfaces:**
- Consumes: `AppDatabase` (existing), `Target`/`TargetKind`/`Target.normalized` (Task 1), `shortenMiddle` (Task 3).
- Produces:
  - `enum TargetSourceKind { manual, device, history }`, `class TargetSource({kind = manual, serial, model, package})` with `fromJson`/`toJson`.
  - `class SavedTarget({required id, required label, required TargetKind kind, required String value, required DateTime lastUsedAt, String? projectId, String? senderId, TargetSource source})` with `fromJson`, `toJson`, `copyWith({label, lastUsedAt})`, `displayValue`, `matches(Target)`, `static orderFor(List<SavedTarget>, String? projectId)`, `static defaultLabel(Target)`.
  - `class TargetsRepository({required AppDatabase database})` with `Stream<void> changes`, `loadAll()` (newest first), `save`, `remove(id)`, `findMatching(Target)`, `markUsed(Target, DateTime)`.

- [ ] **Step 1: Write the failing tests**

`test/features/targets/saved_target_test.dart`:
```dart
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 3, 9);

  SavedTarget saved(
    String id, {
    TargetKind kind = TargetKind.token,
    String value = 'tok',
    String? projectId,
    Duration age = Duration.zero,
  }) => SavedTarget(
    id: id,
    label: 'Label $id',
    kind: kind,
    value: value,
    projectId: projectId,
    lastUsedAt: t0.subtract(age),
  );

  test('round-trips every field, including a device source', () {
    final target = SavedTarget(
      id: 'a',
      label: 'Redmi · com.example (debug)',
      kind: TargetKind.token,
      value: 'tok',
      projectId: 'demo-project',
      senderId: '123456789012',
      source: const TargetSource(
        kind: TargetSourceKind.device,
        serial: 'SER',
        model: 'Redmi',
        package: 'com.example',
      ),
      lastUsedAt: t0,
    );
    expect(SavedTarget.fromJson(target.toJson()), target);
  });

  test('matches a target by its normalised value', () {
    final target = saved('a', value: 'abc:APA91b');
    expect(target.matches(const TokenTarget(' "abc:APA91b" ')), isTrue);
    expect(target.matches(const TopicTarget('abc:APA91b')), isFalse);
  });

  test('orderFor puts the current project first, each group newest first', () {
    final ordered = SavedTarget.orderFor([
      saved('other-new', projectId: 'other'),
      saved(
        'mine-old',
        projectId: 'demo-project',
        age: const Duration(days: 2),
      ),
      saved('mine-new', projectId: 'demo-project'),
      saved('none', age: const Duration(days: 1)),
    ], 'demo-project');
    expect(ordered.map((t) => t.id), [
      'mine-new',
      'mine-old',
      'other-new',
      'none',
    ]);
  });

  test('tokens are shortened for display; topics are shown in full', () {
    expect(saved('a', value: 'fAbC12345678909xYz').displayValue, 'fAbC12…9xYz');
    expect(
      saved('b', kind: TargetKind.topic, value: 'news').displayValue,
      'news',
    );
  });

  test('default labels', () {
    expect(
      SavedTarget.defaultLabel(const TokenTarget('fAbC12345678909xYz')),
      'Token fAbC12…9xYz',
    );
    expect(SavedTarget.defaultLabel(const TopicTarget('news')), 'Topic news');
    expect(
      SavedTarget.defaultLabel(const ConditionTarget("'a' in topics")),
      "'a' in topics",
    );
  });
}
```

`test/features/targets/targets_repository_test.dart`:
```dart
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;
  late TargetsRepository repository;
  final t0 = DateTime.utc(2026, 10, 3, 9);

  setUp(() async {
    database = await AppDatabase.inMemory();
    repository = TargetsRepository(database: database);
  });

  tearDown(() => database.close());

  SavedTarget topic(String id, String name, {Duration age = Duration.zero}) =>
      SavedTarget(
        id: id,
        label: id,
        kind: TargetKind.topic,
        value: name,
        lastUsedAt: t0.subtract(age),
      );

  test('saves and loads targets, newest first', () async {
    await repository.save(topic('old', 'a', age: const Duration(hours: 1)));
    await repository.save(topic('new', 'b'));
    expect((await repository.loadAll()).map((t) => t.id), ['new', 'old']);
  });

  test('finds a saved target by its normalised value', () async {
    await repository.save(topic('a', 'news'));
    expect(
      (await repository.findMatching(const TopicTarget('/topics/news')))?.id,
      'a',
    );
    expect(await repository.findMatching(const TopicTarget('sport')), isNull);
  });

  test('markUsed updates lastUsedAt and announces the change', () async {
    await repository.save(topic('a', 'news'));
    final changed = repository.changes.first;
    final later = t0.add(const Duration(hours: 1));
    await repository.markUsed(const TopicTarget('news'), later);
    await changed;
    expect((await repository.loadAll()).single.lastUsedAt, later);
  });

  test('remove deletes the target', () async {
    await repository.save(topic('a', 'news'));
    await repository.remove('a');
    expect(await repository.loadAll(), isEmpty);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/targets`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement**

`lib/features/targets/domain/saved_target.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/utils/shorten.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';

/// Written into every stored saved-target record, for future migrations.
const kSavedTargetSchemaVersion = 1;

enum TargetSourceKind { manual, device, history }

/// Where a saved target came from (spec §7.1). M2 creates manual targets;
/// device targets, with serial, model and package, arrive in M3.
class TargetSource extends Equatable {
  const TargetSource({
    this.kind = TargetSourceKind.manual,
    this.serial,
    this.model,
    this.package,
  });

  factory TargetSource.fromJson(Map<String, Object?> json) => TargetSource(
    kind: TargetSourceKind.values.byName(json['kind']! as String),
    serial: json['serial'] as String?,
    model: json['model'] as String?,
    package: json['package'] as String?,
  );

  final TargetSourceKind kind;
  final String? serial;
  final String? model;
  final String? package;

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'serial': serial,
    'model': model,
    'package': package,
  };

  @override
  List<Object?> get props => [kind, serial, model, package];
}

/// A token, topic or condition the user saved (spec §7.1).
class SavedTarget extends Equatable {
  const SavedTarget({
    required this.id,
    required this.label,
    required this.kind,
    required this.value,
    required this.lastUsedAt,
    this.projectId,
    this.senderId,
    this.source = const TargetSource(),
  });

  factory SavedTarget.fromJson(Map<String, Object?> json) => SavedTarget(
    id: json['id']! as String,
    label: json['label']! as String,
    kind: TargetKind.values.byName(json['kind']! as String),
    value: json['value']! as String,
    projectId: json['projectId'] as String?,
    senderId: json['senderId'] as String?,
    source: TargetSource.fromJson(json['source']! as Map<String, Object?>),
    lastUsedAt: DateTime.parse(json['lastUsedAt']! as String),
  );

  final String id;
  final String label;
  final TargetKind kind;

  /// The normalised value (see [Target.normalized]).
  final String value;

  /// The project the target was saved for, if any.
  final String? projectId;

  /// The token's FCM sender ID, when known (device targets, M3).
  final String? senderId;
  final TargetSource source;
  final DateTime lastUsedAt;

  /// Tokens shortened, e.g. `fAbC12…9xYz`; topics and conditions in full.
  String get displayValue =>
      kind == TargetKind.token ? shortenMiddle(value) : value;

  bool matches(Target target) =>
      target.kind == kind && target.normalized == value;

  SavedTarget copyWith({String? label, DateTime? lastUsedAt}) => SavedTarget(
    id: id,
    label: label ?? this.label,
    kind: kind,
    value: value,
    projectId: projectId,
    senderId: senderId,
    source: source,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );

  Map<String, Object?> toJson() => {
    'schemaVersion': kSavedTargetSchemaVersion,
    'id': id,
    'label': label,
    'kind': kind.name,
    'value': value,
    'projectId': projectId,
    'senderId': senderId,
    'source': source.toJson(),
    'lastUsedAt': lastUsedAt.toUtc().toIso8601String(),
  };

  /// The autocomplete order: the current project's targets first, then the
  /// rest, each newest first (spec §7.1).
  static List<SavedTarget> orderFor(
    List<SavedTarget> targets,
    String? projectId,
  ) {
    final current = <SavedTarget>[];
    final others = <SavedTarget>[];
    for (final target in targets) {
      if (projectId != null && target.projectId == projectId) {
        current.add(target);
      } else {
        others.add(target);
      }
    }
    int newestFirst(SavedTarget a, SavedTarget b) =>
        b.lastUsedAt.compareTo(a.lastUsedAt);
    current.sort(newestFirst);
    others.sort(newestFirst);
    return [...current, ...others];
  }

  /// The label offered when the user saves [target].
  static String defaultLabel(Target target) => switch (target) {
    TokenTarget(:final token) => 'Token ${shortenMiddle(token)}',
    TopicTarget(:final name) => 'Topic $name',
    ConditionTarget(:final expression) => expression,
  };

  @override
  List<Object?> get props => [
    id,
    label,
    kind,
    value,
    projectId,
    senderId,
    source,
    lastUsedAt,
  ];
}
```

`lib/features/targets/data/targets_repository.dart`:
```dart
import 'dart:async';

import 'package:fcm_studio/core/storage/app_database.dart';
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

  /// All saved targets, most recently used first.
  Future<List<SavedTarget>> loadAll() async {
    final records = await _store.find(_db);
    return records.map((record) => SavedTarget.fromJson(record.value)).toList()
      ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
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
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/features/targets`
Expected: PASS (5 + 4 tests). Then `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/features/targets test/features/targets
git commit -m "feat: store saved targets and order them for the autocomplete"
```

---

### Task 6: History: model, filter and repository

**Files:**
- Create: `lib/features/history/domain/history_entry.dart`, `lib/features/history/domain/history_filter.dart`, `lib/features/history/data/history_repository.dart`, `test/helpers/history_fixture.dart`
- Test: `test/features/history/history_entry_test.dart`, `test/features/history/history_repository_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `ProjectEnvironment`, `Target`/`TargetKind` (existing); `successBody`/`unregisteredBody` (`test/helpers/fcm_fixtures.dart`), `testProjectId` (`test/helpers/service_account_fixture.dart`).
- Produces:
  - `class HistoryTarget({required TargetKind kind, required String value, String? label})` with `toTarget()`.
  - `sealed class HistoryOutcome` with `HistorySuccess(String messageName)` and `HistoryFailure({required String code, required String explanation})`.
  - `class HistoryEntry({required id, required sentAt, required projectId, required environment, required HistoryTarget target, required Map<String, Object?> request, required bool validateOnly, required HistoryOutcome outcome, required Duration duration, String? presetName, int? httpStatus, String? responseBody})` with `fromJson`, `toJson`, `succeeded`, `template`.
  - `enum OutcomeFilter { all, success, failure }`, `enum ModeFilter { all, real, dryRun }`, `class HistoryFilter({String? projectId, outcome, mode, query})` with `matches(entry)` and `copyWith`.
  - `class HistoryRepository({required AppDatabase database, int maxEntries = 1000})` with `changes`, `add` (trims the oldest beyond `maxEntries`), `loadAll` (newest first), `clear`.
  - Test helper `HistoryEntry historyEntry(String id, {DateTime? sentAt, String projectId, bool ok, bool dryRun, String value, String? presetName, ProjectEnvironment environment})`.

- [ ] **Step 1: Add the test fixture** `test/helpers/history_fixture.dart`

```dart
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

import 'fcm_fixtures.dart';
import 'service_account_fixture.dart';

HistoryEntry historyEntry(
  String id, {
  DateTime? sentAt,
  String projectId = testProjectId,
  bool ok = true,
  bool dryRun = false,
  String value = 'abc:APA91bxyz',
  String? presetName,
  ProjectEnvironment environment = ProjectEnvironment.dev,
}) => HistoryEntry(
  id: id,
  sentAt: sentAt ?? DateTime.utc(2026, 10, 3, 9),
  projectId: projectId,
  environment: environment,
  target: HistoryTarget(kind: TargetKind.token, value: value, label: 'Redmi'),
  presetName: presetName,
  request: {
    if (dryRun) 'validate_only': true,
    'message': {
      'token': value,
      'notification': {'title': 'Order shipped'},
    },
  },
  validateOnly: dryRun,
  httpStatus: ok ? 200 : 404,
  outcome: ok
      ? const HistorySuccess('projects/demo-project/messages/0:1')
      : const HistoryFailure(
          code: 'UNREGISTERED',
          explanation: 'Token is no longer valid',
        ),
  responseBody: ok ? successBody : unregisteredBody,
  duration: const Duration(milliseconds: 120),
);
```

- [ ] **Step 2: Write the failing tests**

`test/features/history/history_entry_test.dart`:
```dart
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/history/domain/history_filter.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/history_fixture.dart';

void main() {
  test('round-trips success and failure entries through JSON', () {
    for (final entry in [
      historyEntry('a'),
      historyEntry('b', ok: false, dryRun: true, presetName: 'Promo'),
    ]) {
      expect(HistoryEntry.fromJson(entry.toJson()), entry);
    }
  });

  test('a failure before FCM answered has no status and still round-trips', () {
    final entry = HistoryEntry(
      id: 'n',
      sentAt: DateTime.utc(2026, 10, 3),
      projectId: 'demo-project',
      environment: ProjectEnvironment.prod,
      target: const HistoryTarget(kind: TargetKind.topic, value: 'news'),
      request: const {
        'message': {'topic': 'news'},
      },
      validateOnly: false,
      outcome: const HistoryFailure(code: 'NETWORK', explanation: 'Network error'),
      duration: Duration.zero,
    );
    expect(HistoryEntry.fromJson(entry.toJson()), entry);
    expect(entry.succeeded, isFalse);
  });

  test('template is the stored message without its target', () {
    expect(historyEntry('a').template, {
      'notification': {'title': 'Order shipped'},
    });
  });

  group('filter', () {
    final entries = [
      historyEntry('ok', presetName: 'Promo'),
      historyEntry('failed', ok: false),
      historyEntry('dry', dryRun: true),
      historyEntry('other', projectId: 'other-project'),
    ];

    List<String> ids(HistoryFilter filter) => [
      for (final e in entries)
        if (filter.matches(e)) e.id,
    ];

    test('by project', () {
      expect(ids(const HistoryFilter(projectId: 'other-project')), ['other']);
    });

    test('by outcome', () {
      expect(ids(const HistoryFilter(outcome: OutcomeFilter.failure)), [
        'failed',
      ]);
      expect(ids(const HistoryFilter(outcome: OutcomeFilter.success)), [
        'ok',
        'dry',
        'other',
      ]);
    });

    test('by dry run or real', () {
      expect(ids(const HistoryFilter(mode: ModeFilter.dryRun)), ['dry']);
      expect(ids(const HistoryFilter(mode: ModeFilter.real)), [
        'ok',
        'failed',
        'other',
      ]);
    });

    test('text search covers the target, the preset and the body', () {
      expect(ids(const HistoryFilter(query: 'promo')), ['ok']);
      expect(ids(const HistoryFilter(query: 'REDMI')), hasLength(4));
      expect(ids(const HistoryFilter(query: 'shipped')), hasLength(4));
      expect(ids(const HistoryFilter(query: 'nothing like this')), isEmpty);
    });
  });
}
```

`test/features/history/history_repository_test.dart`:
```dart
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/history_fixture.dart';

void main() {
  late AppDatabase database;

  setUp(() async => database = await AppDatabase.inMemory());
  tearDown(() => database.close());

  DateTime at(int minute) => DateTime.utc(2026, 10, 3, 9, minute);

  test('loads entries newest first', () async {
    final repository = HistoryRepository(database: database);
    await repository.add(historyEntry('old', sentAt: at(1)));
    await repository.add(historyEntry('new', sentAt: at(2)));
    expect((await repository.loadAll()).map((e) => e.id), ['new', 'old']);
  });

  test('keeps only the newest entries', () async {
    final repository = HistoryRepository(database: database, maxEntries: 3);
    for (var i = 1; i <= 5; i++) {
      await repository.add(historyEntry('e$i', sentAt: at(i)));
    }
    expect((await repository.loadAll()).map((e) => e.id), ['e5', 'e4', 'e3']);
  });

  test('clear removes everything and announces it', () async {
    final repository = HistoryRepository(database: database);
    await repository.add(historyEntry('a'));
    final changed = repository.changes.first;
    await repository.clear();
    await changed;
    expect(await repository.loadAll(), isEmpty);
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/history`
Expected: FAIL, compilation errors.

- [ ] **Step 4: Implement**

`lib/features/history/domain/history_entry.dart`:
```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

/// Written into every stored history record, for future migrations.
const kHistorySchemaVersion = 1;

/// Who a history entry was sent to.
class HistoryTarget extends Equatable {
  const HistoryTarget({required this.kind, required this.value, this.label});

  factory HistoryTarget.fromJson(Map<String, Object?> json) => HistoryTarget(
    kind: TargetKind.values.byName(json['kind']! as String),
    value: json['value']! as String,
    label: json['label'] as String?,
  );

  final TargetKind kind;

  /// The normalised value that was sent.
  final String value;

  /// The saved target's label at the time of sending, if it was saved.
  final String? label;

  Target toTarget() => Target.of(kind, value);

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'value': value,
    'label': label,
  };

  @override
  List<Object?> get props => [kind, value, label];
}

sealed class HistoryOutcome extends Equatable {
  const HistoryOutcome();

  factory HistoryOutcome.fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'success' => HistorySuccess(json['messageName']! as String),
        'error' => HistoryFailure(
          code: json['code']! as String,
          explanation: json['explanation']! as String,
        ),
        final kind => throw FormatException('Unknown history outcome: $kind'),
      };

  Map<String, Object?> toJson();
}

final class HistorySuccess extends HistoryOutcome {
  const HistorySuccess(this.messageName);

  final String messageName;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'success',
    'messageName': messageName,
  };

  @override
  List<Object?> get props => [messageName];
}

final class HistoryFailure extends HistoryOutcome {
  const HistoryFailure({required this.code, required this.explanation});

  /// e.g. `UNREGISTERED`, `HTTP 502`, `NETWORK`, `AUTH`.
  final String code;

  /// The explanation's title, e.g. "Token is no longer valid".
  final String explanation;

  @override
  Map<String, Object?> toJson() => {
    'kind': 'error',
    'code': code,
    'explanation': explanation,
  };

  @override
  List<Object?> get props => [code, explanation];
}

/// One send attempt (spec §7.2). Never holds an access token.
class HistoryEntry extends Equatable {
  const HistoryEntry({
    required this.id,
    required this.sentAt,
    required this.projectId,
    required this.environment,
    required this.target,
    required this.request,
    required this.validateOnly,
    required this.outcome,
    required this.duration,
    this.presetName,
    this.httpStatus,
    this.responseBody,
  });

  factory HistoryEntry.fromJson(Map<String, Object?> json) => HistoryEntry(
    id: json['id']! as String,
    sentAt: DateTime.parse(json['sentAt']! as String),
    projectId: json['projectId']! as String,
    environment: ProjectEnvironment.values.byName(
      json['environment']! as String,
    ),
    target: HistoryTarget.fromJson(json['target']! as Map<String, Object?>),
    presetName: json['presetName'] as String?,
    request: json['request']! as Map<String, Object?>,
    validateOnly: json['validateOnly']! as bool,
    httpStatus: json['httpStatus'] as int?,
    outcome: HistoryOutcome.fromJson(json['outcome']! as Map<String, Object?>),
    responseBody: json['responseBody'] as String?,
    duration: Duration(milliseconds: json['durationMs']! as int),
  );

  final String id;
  final DateTime sentAt;
  final String projectId;
  final ProjectEnvironment environment;
  final HistoryTarget target;
  final String? presetName;

  /// The exact body that was sent to `messages:send`.
  final Map<String, Object?> request;
  final bool validateOnly;

  /// Null when the send failed before FCM answered.
  final int? httpStatus;
  final HistoryOutcome outcome;
  final String? responseBody;
  final Duration duration;

  bool get succeeded => outcome is HistorySuccess;

  /// The stored message without its target, ready to become a composer template.
  Map<String, Object?> get template {
    final message = request['message'];
    if (message is! Map<String, Object?>) {
      return {};
    }
    return jsonDecode(jsonEncode(message)) as Map<String, Object?>
      ..removeWhere((key, _) => Target.messageFields.contains(key));
  }

  Map<String, Object?> toJson() => {
    'schemaVersion': kHistorySchemaVersion,
    'id': id,
    'sentAt': sentAt.toUtc().toIso8601String(),
    'projectId': projectId,
    'environment': environment.name,
    'target': target.toJson(),
    'presetName': presetName,
    'request': request,
    'validateOnly': validateOnly,
    'httpStatus': httpStatus,
    'outcome': outcome.toJson(),
    'responseBody': responseBody,
    'durationMs': duration.inMilliseconds,
  };

  @override
  List<Object?> get props => [
    id,
    sentAt,
    projectId,
    environment,
    target,
    presetName,
    request,
    validateOnly,
    httpStatus,
    outcome,
    responseBody,
    duration,
  ];
}
```

`lib/features/history/domain/history_filter.dart`:
```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';

enum OutcomeFilter { all, success, failure }

enum ModeFilter { all, real, dryRun }

/// The History screen's filters (spec §7.2).
class HistoryFilter extends Equatable {
  const HistoryFilter({
    this.projectId,
    this.outcome = OutcomeFilter.all,
    this.mode = ModeFilter.all,
    this.query = '',
  });

  /// Null shows every project.
  final String? projectId;
  final OutcomeFilter outcome;
  final ModeFilter mode;

  /// Searches the target, the preset name and the request body.
  final String query;

  bool matches(HistoryEntry entry) {
    if (projectId != null && entry.projectId != projectId) {
      return false;
    }
    final outcomeMatches = switch (outcome) {
      OutcomeFilter.all => true,
      OutcomeFilter.success => entry.succeeded,
      OutcomeFilter.failure => !entry.succeeded,
    };
    final modeMatches = switch (mode) {
      ModeFilter.all => true,
      ModeFilter.real => !entry.validateOnly,
      ModeFilter.dryRun => entry.validateOnly,
    };
    if (!outcomeMatches || !modeMatches) {
      return false;
    }
    final text = query.trim().toLowerCase();
    if (text.isEmpty) {
      return true;
    }
    return [
      entry.target.value,
      entry.target.label ?? '',
      entry.presetName ?? '',
      jsonEncode(entry.request),
    ].join('\n').toLowerCase().contains(text);
  }

  HistoryFilter copyWith({
    String? Function()? projectId,
    OutcomeFilter? outcome,
    ModeFilter? mode,
    String? query,
  }) => HistoryFilter(
    projectId: projectId != null ? projectId() : this.projectId,
    outcome: outcome ?? this.outcome,
    mode: mode ?? this.mode,
    query: query ?? this.query,
  );

  @override
  List<Object?> get props => [projectId, outcome, mode, query];
}
```

`lib/features/history/data/history_repository.dart`:
```dart
import 'dart:async';

import 'package:fcm_studio/core/storage/app_database.dart';
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

  /// Newest first.
  Future<List<HistoryEntry>> loadAll() async {
    final records = await _store.find(
      _db,
      finder: Finder(sortOrders: [SortOrder('sentAt', false)]),
    );
    return records.map((record) => HistoryEntry.fromJson(record.value)).toList();
  }

  Future<void> clear() async {
    await _store.delete(_db);
    _changes.add(null);
  }
}
```

`sentAt` is stored as an ISO-8601 UTC string, so sorting the strings sorts by time.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/features/history`
Expected: PASS (3 + 4 filter tests, 3 repository tests). Then `flutter analyze` (No issues found!).

- [ ] **Step 6: Commit**

```bash
dart format lib test
git add lib/features/history test/features/history test/helpers/history_fixture.dart
git commit -m "feat: store send history with filters and a 1,000-entry cap"
```

---

### Task 7: `MessageSender`: send, record history, and cURL

**Files:**
- Create: `lib/features/composer/data/message_sender.dart`, `test/helpers/sender_fixture.dart`
- Test: `test/features/composer/message_sender_test.dart`

**Interfaces:**
- Consumes: `FcmClient`, `FcmSendResult`/`FcmSendSuccess`/`FcmSendFailure`, `FcmError`/`FcmTransportError`, `FcmErrorExplainer`/`ErrorExplanation`, `AuthException`, `AccessTokenResolver`, `Project`, `redact` (existing); `IdGenerator`/`newUuid` (Task 1); `CurlBuilder` (Task 3); `TargetsRepository`/`SavedTarget` (Task 5); `HistoryRepository`, `HistoryEntry`, `HistoryTarget`, `HistorySuccess`, `HistoryFailure` (Task 6); test helpers `fakeGoogle`, `FakeResolver`, `FixedClock`, `testProject`, `unregisteredBody`.
- Produces:
  - `class SendOutcome({required FcmSendResult result, ErrorExplanation? explanation, String? historyError})`.
  - `class MessageSender({required FcmClient fcmClient, required AccessTokenResolver auth, required HistoryRepository history, required TargetsRepository targets, Clock clock, IdGenerator newId, FcmErrorExplainer explainer})` with `Future<SendOutcome> send({required Project project, required Map<String, Object?> request, required Target target, String? presetName})` (never throws) and `Future<String> curl({required Project project, required Map<String, Object?> request, required bool includeAccessToken})` (throws `AuthException` only when a token is needed and the key is missing).
  - Test helper `MessageSender buildSender(AppDatabase database, {http.Client? client, AccessTokenResolver? auth, HistoryRepository? history, TargetsRepository? targets})`.

- [ ] **Step 1: Add the test helper** `test/helpers/sender_fixture.dart`

```dart
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/composer/data/message_sender.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:http/http.dart' as http;

import 'fake_google.dart';
import 'fake_token_provider.dart';

MessageSender buildSender(
  AppDatabase database, {
  http.Client? client,
  AccessTokenResolver? auth,
  HistoryRepository? history,
  TargetsRepository? targets,
}) => MessageSender(
  fcmClient: FcmClient(httpClient: client ?? fakeGoogle()),
  auth: auth ?? FakeResolver(),
  history: history ?? HistoryRepository(database: database),
  targets: targets ?? TargetsRepository(database: database),
);
```

- [ ] **Step 2: Write the failing tests** `test/features/composer/message_sender_test.dart`

```dart
import 'dart:convert';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/composer/data/message_sender.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/fake_google.dart';
import '../../helpers/fake_token_provider.dart';
import '../../helpers/fcm_fixtures.dart';
import '../../helpers/fixed_clock.dart';
import '../../helpers/project_fixture.dart';

class _BrokenHistory extends HistoryRepository {
  _BrokenHistory(AppDatabase database) : super(database: database);

  @override
  Future<void> add(HistoryEntry entry) => Future.error(StateError('disk full'));
}

void main() {
  const token = 'abc:APA91bxyz';
  const request = {
    'message': {
      'token': token,
      'notification': {'title': 'Hi'},
    },
  };
  final clock = FixedClock(DateTime.utc(2026, 10, 3, 9));
  late AppDatabase database;
  late HistoryRepository history;
  late TargetsRepository targets;

  setUp(() async {
    database = await AppDatabase.inMemory();
    history = HistoryRepository(database: database);
    targets = TargetsRepository(database: database);
  });

  tearDown(() => database.close());

  MessageSender build({
    http.Client? client,
    AccessTokenResolver? auth,
    HistoryRepository? historyRepository,
  }) => MessageSender(
    fcmClient: FcmClient(httpClient: client ?? fakeGoogle()),
    auth: auth ?? FakeResolver(),
    history: historyRepository ?? history,
    targets: targets,
    clock: clock,
    newId: () => 'entry-1',
  );

  test('a successful send is recorded in history', () async {
    final outcome = await build().send(
      project: testProject,
      request: request,
      target: const TokenTarget(token),
      presetName: 'Simple notification',
    );
    expect(outcome.result, isA<FcmSendSuccess>());
    expect(outcome.explanation, isNull);

    final entry = (await history.loadAll()).single;
    expect(entry.id, 'entry-1');
    expect(entry.sentAt, clock.now());
    expect(entry.projectId, 'demo-project');
    expect(
      entry.outcome,
      const HistorySuccess('projects/demo-project/messages/0:1'),
    );
    expect(
      entry.target,
      const HistoryTarget(kind: TargetKind.token, value: token),
    );
    expect(entry.presetName, 'Simple notification');
    expect(entry.validateOnly, isFalse);
    expect(entry.httpStatus, 200);
    expect(entry.request, request);
  });

  test('a failed send is recorded with its code and explanation', () async {
    final outcome = await build(
      client: fakeGoogle(fcmStatus: 404, fcmBody: unregisteredBody),
    ).send(project: testProject, request: request, target: const TokenTarget(token));
    expect(outcome.explanation?.title, 'Token is no longer valid');
    final entry = (await history.loadAll()).single;
    expect(
      entry.outcome,
      const HistoryFailure(
        code: 'UNREGISTERED',
        explanation: 'Token is no longer valid',
      ),
    );
    expect(entry.httpStatus, 404);
  });

  test('a failure before FCM answers is still recorded', () async {
    final outcome = await build(
      auth: FakeResolver(error: const AuthException('Key missing')),
    ).send(project: testProject, request: request, target: const TokenTarget(token));
    expect(outcome.explanation?.title, 'Could not get an access token');
    final entry = (await history.loadAll()).single;
    expect(entry.httpStatus, isNull);
    expect(
      entry.outcome,
      const HistoryFailure(
        code: 'AUTH',
        explanation: 'Could not get an access token',
      ),
    );
  });

  test('dry runs are recorded as dry runs', () async {
    await build().send(
      project: testProject,
      request: {'validate_only': true, ...request},
      target: const TokenTarget(token),
    );
    expect((await history.loadAll()).single.validateOnly, isTrue);
  });

  test('no access token is ever stored', () async {
    await build().send(
      project: testProject,
      request: request,
      target: const TokenTarget(token),
    );
    final stored = jsonEncode((await history.loadAll()).single.toJson());
    expect(stored, isNot(contains('token-1')));
    expect(stored, isNot(contains('Bearer')));
  });

  test('a saved target labels the entry and is marked as used', () async {
    await targets.save(
      SavedTarget(
        id: 't',
        label: 'Redmi',
        kind: TargetKind.token,
        value: token,
        lastUsedAt: DateTime.utc(2026),
      ),
    );
    await build().send(
      project: testProject,
      request: request,
      target: const TokenTarget(token),
    );
    expect((await history.loadAll()).single.target.label, 'Redmi');
    expect((await targets.loadAll()).single.lastUsedAt, clock.now());
  });

  test('a history write that fails still returns the send result', () async {
    final outcome = await build(
      historyRepository: _BrokenHistory(database),
    ).send(project: testProject, request: request, target: const TokenTarget(token));
    expect(outcome.result, isA<FcmSendSuccess>());
    expect(outcome.historyError, contains('disk full'));
  });

  test('curl includes a current access token only when asked', () async {
    final sender = build();
    expect(
      await sender.curl(
        project: testProject,
        request: request,
        includeAccessToken: true,
      ),
      contains("-H 'Authorization: Bearer token-1'"),
    );
    expect(
      await sender.curl(
        project: testProject,
        request: request,
        includeAccessToken: false,
      ),
      contains(r'Bearer $FCM_ACCESS_TOKEN'),
    );
  });

  test('curl with the placeholder works without the key', () async {
    final sender = build(
      auth: FakeResolver(error: const AuthException('Key missing')),
    );
    expect(
      await sender.curl(
        project: testProject,
        request: request,
        includeAccessToken: false,
      ),
      contains(r'$FCM_ACCESS_TOKEN'),
    );
    await expectLater(
      sender.curl(
        project: testProject,
        request: request,
        includeAccessToken: true,
      ),
      throwsA(isA<AuthException>()),
    );
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/composer/message_sender_test.dart`
Expected: FAIL, compilation error (`message_sender.dart` doesn't exist).

- [ ] **Step 4: Implement** `lib/features/composer/data/message_sender.dart`

```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/curl_builder.dart';
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_error_explainer.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/core/utils/ids.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';

/// The result of [MessageSender.send].
class SendOutcome extends Equatable {
  const SendOutcome({required this.result, this.explanation, this.historyError});

  final FcmSendResult result;

  /// A plain-language explanation of a failure; null on success.
  final ErrorExplanation? explanation;

  /// Set when the send happened but could not be saved to history.
  final String? historyError;

  @override
  List<Object?> get props => [result, explanation, historyError];
}

/// Sends a rendered request for a project and records the attempt in history
/// (spec §7.2). The composer and History → Resend both use it.
class MessageSender {
  MessageSender({
    required FcmClient fcmClient,
    required this._auth,
    required this._history,
    required this._targets,
    this._clock = const SystemClock(),
    this._newId = newUuid,
    this._explainer = const FcmErrorExplainer(),
  }) : _fcm = fcmClient;

  final FcmClient _fcm;
  final AccessTokenResolver _auth;
  final HistoryRepository _history;
  final TargetsRepository _targets;
  final Clock _clock;
  final IdGenerator _newId;
  final FcmErrorExplainer _explainer;

  /// Sends [request] and records it. Never throws: every failure becomes an
  /// [FcmSendFailure] with an explanation.
  Future<SendOutcome> send({
    required Project project,
    required Map<String, Object?> request,
    required Target target,
    String? presetName,
  }) async {
    final sentAt = _clock.now();
    FcmSendResult result;
    try {
      final auth = await _auth.providerFor(project);
      result = await _fcm.send(projectId: project.id, body: request, auth: auth);
    } on AuthException catch (e) {
      result = FcmSendFailure(
        error: FcmError(transport: FcmTransportError.auth, message: e.message),
        duration: Duration.zero,
      );
    } catch (e) {
      // e.g. a denied Keychain prompt: the send must still end.
      result = FcmSendFailure(
        error: FcmError(
          transport: FcmTransportError.unexpected,
          message: redact('$e'),
        ),
        duration: Duration.zero,
      );
    }
    final explanation = switch (result) {
      FcmSendFailure(:final error) => _explainer.explain(
        error,
        projectId: project.id,
      ),
      FcmSendSuccess() => null,
    };

    String? historyError;
    try {
      final saved = await _targets.findMatching(target);
      final responseBody = result.responseBody;
      await _history.add(
        HistoryEntry(
          id: _newId(),
          sentAt: sentAt,
          projectId: project.id,
          environment: project.environment,
          target: HistoryTarget(
            kind: target.kind,
            value: target.normalized,
            label: saved?.label,
          ),
          presetName: presetName,
          request: request,
          validateOnly: request['validate_only'] == true,
          httpStatus: result.httpStatus,
          outcome: switch (result) {
            FcmSendSuccess(:final messageName) => HistorySuccess(messageName),
            FcmSendFailure(:final error) => HistoryFailure(
              code: _code(error),
              explanation: explanation?.title ?? 'Send failed',
            ),
          },
          responseBody: responseBody == null ? null : redact(responseBody),
          duration: result.duration,
        ),
      );
      if (saved != null) {
        await _targets.markUsed(target, sentAt);
      }
    } catch (e) {
      historyError = 'Could not save this send to history: ${redact('$e')}';
    }
    return SendOutcome(
      result: result,
      explanation: explanation,
      historyError: historyError,
    );
  }

  /// A bash curl command for [request] (spec §8.3). With
  /// [includeAccessToken] it fetches a current token, which needs the key.
  Future<String> curl({
    required Project project,
    required Map<String, Object?> request,
    required bool includeAccessToken,
  }) async {
    AccessTokenProvider? auth;
    try {
      auth = await _auth.providerFor(project);
    } on AuthException {
      if (includeAccessToken) {
        rethrow;
      }
    }
    final token = includeAccessToken ? (await auth!.getToken()).value : null;
    return CurlBuilder.build(
      projectId: project.id,
      body: request,
      accessToken: token,
      extraHeaders: auth?.extraHeaders(project.id) ?? const {},
    );
  }

  static String _code(FcmError error) =>
      error.fcmErrorCode ??
      error.status ??
      switch (error.transport) {
        FcmTransportError.none =>
          error.httpStatus == null ? 'ERROR' : 'HTTP ${error.httpStatus}',
        final transport => transport.name.toUpperCase(),
      };
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/features/composer/message_sender_test.dart`
Expected: PASS (9 tests). Then `flutter analyze` (No issues found!).

- [ ] **Step 6: Commit**

```bash
dart format lib test
git add lib/features/composer/data/message_sender.dart test/helpers/sender_fixture.dart test/features/composer/message_sender_test.dart
git commit -m "feat: send through one service that records every attempt in history"
```

---

### Task 8: `ComposerCubit` for M2

The composer gains variables, dry run, preset tracking (with the unsaved-changes dot), Form edits, "Open in composer" from history, and "Show in JSON". It now sends through `MessageSender`, so this task also wires `MessageSender` into `AppDependencies`.

**Files:**
- Modify: `lib/features/composer/cubit/composer_state.dart`, `lib/features/composer/cubit/composer_cubit.dart`, `lib/app/dependencies.dart`, `lib/app/app.dart`
- Test: `test/features/composer/composer_cubit_test.dart` (rewritten)

**Interfaces:**
- Consumes: `MessageSender`/`SendOutcome` (Task 7), `MessageRenderer`/`RenderResult.undefinedPlaceholders` (Task 1), `TemplateEdits`, `JsonLocator` (Task 2), `Preset` (Task 4), `VariableDef` (Task 1), `HistoryRepository` (Task 6), `TargetsRepository` (Task 5); test helpers `buildSender` (Task 7), `fakeGoogle`, `FakeResolver`, `testProject`, `successBody`, `unregisteredBody`.
- Produces:
  - `class JsonFocusRequest(int line, int serial)`.
  - `ComposerState` gains `variables`, `values`, `validateOnly`, `preset`, `lastSentDryRun`, `lastHistoryError`, `jsonFocus`, and the getters `Target get target` and `bool get isDirty`.
  - `ComposerCubit({required MessageSender sender, MessageRenderer renderer})` with `updateTemplateText`, `setTargetKind`, `setTargetValue`, `setTarget(TargetKind, String)`, `setValidateOnly(bool)`, `setVariableValue(String key, String value)`, `setVariables(List<VariableDef>)`, `addMissingVariables()`, `setField(List<String> path, Object? value)`, `setDataOnly(bool)`, `setDataEntries(List<MapEntry<String, Object?>>)`, `loadPreset(Preset)`, `presetSaved(Preset)`, `detachPreset(String id)`, `openMessage({required template, required Target target})`, `showField(String fieldPath)`, `Future<void> send(Project)`, `Future<String?> curl(Project, {required bool includeAccessToken})`, `static parseTemplate`, `static defaultTemplate`.
  - `AppDependencies` gains `historyRepository`, `targetsRepository` and `messageSender`, and loses `fcmClient`.

- [ ] **Step 1: Write the failing tests.** Replace `test/features/composer/composer_cubit_test.dart` with:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/composer/domain/template_edits.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_google.dart';
import '../../helpers/fake_token_provider.dart';
import '../../helpers/fcm_fixtures.dart';
import '../../helpers/project_fixture.dart';
import '../../helpers/sender_fixture.dart';

void main() {
  const token = 'abc:APA91bxyz';
  late AppDatabase database;

  setUp(() async => database = await AppDatabase.inMemory());
  tearDown(() => database.close());

  ComposerCubit build({
    http.Client? client,
    FakeResolver? auth,
    MessageRenderer renderer = const MessageRenderer(),
  }) => ComposerCubit(
    sender: buildSender(database, client: client, auth: auth),
    renderer: renderer,
  );

  Map<String, Object?> messageOf(ComposerCubit cubit) =>
      cubit.state.render.request!['message']! as Map<String, Object?>;

  final preset = Preset(
    id: 'p1',
    name: 'Order update',
    variables: const [
      VariableDef(
        key: 'order_id',
        label: 'Order',
        required: true,
        defaultValue: '42',
      ),
    ],
    template: const {
      'notification': {'title': 'Order {{order_id}}'},
    },
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
  );

  test('starts with the default template and asks for a token', () {
    final cubit = build();
    expect(cubit.state.template, isNotNull);
    expect(cubit.state.render.errors.single.message, 'Enter a device token.');
    expect(cubit.state.canSend, isFalse);
  });

  test('reports invalid JSON with its line number', () {
    final cubit = build()..updateTemplateText('{\n  "data": {},\n}');
    expect(cubit.state.template, isNull);
    expect(cubit.state.jsonError, contains('line 3'));
    expect(cubit.state.canSend, isFalse);
  });

  test('rejects a top-level value that is not an object', () {
    final cubit = build()..updateTemplateText('[]');
    expect(cubit.state.jsonError, contains('must be a JSON object'));
  });

  test('rejects empty text', () {
    final cubit = build()..updateTemplateText('   ');
    expect(cubit.state.jsonError, contains('empty'));
  });

  test('renders the request once a token is entered', () {
    final cubit = build()..setTargetValue(token);
    expect(cubit.state.canSend, isTrue);
    expect(messageOf(cubit)['token'], token);
  });

  test('switching to topic re-renders with the same value', () {
    final cubit = build()
      ..setTargetValue('/topics/news')
      ..setTargetKind(TargetKind.topic);
    expect(messageOf(cubit)['topic'], 'news');
  });

  test('sends, stores the result and records it in history', () async {
    final cubit = build()..setTargetValue(token);
    await cubit.send(testProject);
    expect(cubit.state.sendStatus, SendStatus.done);
    expect(cubit.state.lastResult, isA<FcmSendSuccess>());
    expect(cubit.state.lastExplanation, isNull);
    expect(cubit.state.lastSentDryRun, isFalse);
    expect(await HistoryRepository(database: database).loadAll(), hasLength(1));
  });

  test('explains a failed send', () async {
    final cubit = build(
      client: fakeGoogle(fcmStatus: 404, fcmBody: unregisteredBody),
    )..setTargetValue(token);
    await cubit.send(testProject);
    expect(cubit.state.lastResult, isA<FcmSendFailure>());
    expect(cubit.state.lastExplanation?.title, 'Token is no longer valid');
  });

  test('explains a missing key instead of throwing', () async {
    final cubit = build(
      auth: FakeResolver(
        error: const AuthException(
          'The service account key for demo-project is not available in this session. '
          'Add the project again with the same key file.',
        ),
      ),
    )..setTargetValue(token);

    await cubit.send(testProject);

    expect(
      cubit.state.lastResult,
      isA<FcmSendFailure>().having(
        (r) => r.error.transport,
        'transport',
        FcmTransportError.auth,
      ),
    );
    expect(cubit.state.lastExplanation?.title, 'Could not get an access token');
    expect(
      cubit.state.lastExplanation?.explanation,
      contains('Add the project again'),
    );
  });

  test('ignores Send while a send is in progress', () async {
    final gate = Completer<http.Response>();
    var requests = 0;
    final cubit = build(
      client: MockClient((_) {
        requests++;
        return gate.future;
      }),
    )..setTargetValue(token);

    final first = cubit.send(testProject);
    await Future<void>.delayed(Duration.zero);
    await cubit.send(testProject);
    gate.complete(http.Response(successBody, 200));
    await first;

    expect(requests, 1);
    expect(cubit.state.lastResult, isA<FcmSendSuccess>());
  });

  test('does not send when the message has errors', () async {
    var requests = 0;
    final cubit = build(
      client: MockClient((_) async {
        requests++;
        return http.Response(successBody, 200);
      }),
    );
    await cubit.send(testProject);
    expect(requests, 0);
    expect(cubit.state.sendStatus, SendStatus.idle);
  });

  test('an unexpected failure ends the send instead of leaving it stuck', () async {
    final cubit = build(
      auth: FakeResolver(error: Exception('Keychain access denied')),
    )..setTargetValue(token);

    await cubit.send(testProject);

    expect(cubit.state.sendStatus, SendStatus.done);
    expect(
      cubit.state.lastResult,
      isA<FcmSendFailure>()
          .having(
            (r) => r.error.transport,
            'transport',
            FcmTransportError.unexpected,
          )
          .having(
            (r) => r.error.message,
            'message',
            contains('Keychain access denied'),
          ),
    );
    expect(cubit.state.canSend, isTrue);
  });

  group('variables and presets', () {
    test('loading a preset sets the template, variables and default values', () {
      final cubit = build()
        ..setTargetValue(token)
        ..loadPreset(preset);
      expect(cubit.state.preset, preset);
      expect(cubit.state.values, {'order_id': '42'});
      expect(messageOf(cubit)['notification'], {'title': 'Order 42'});
      expect(cubit.state.isDirty, isFalse);
    });

    test('values re-render; template edits make the preset dirty until saved', () {
      final cubit = build()
        ..setTargetValue(token)
        ..loadPreset(preset)
        ..setVariableValue('order_id', '7');
      expect(messageOf(cubit)['notification'], {'title': 'Order 7'});
      expect(cubit.state.isDirty, isFalse, reason: 'values are not saved');

      cubit.setField(['notification', 'body'], 'Shipped');
      expect(cubit.state.isDirty, isTrue);

      cubit.presetSaved(preset.copyWith(template: cubit.state.template));
      expect(cubit.state.isDirty, isFalse);
    });

    test('changing the variables makes the preset dirty', () {
      final cubit = build()
        ..loadPreset(preset)
        ..setVariables(const [VariableDef(key: 'order_id')]);
      expect(cubit.state.isDirty, isTrue);
    });

    test('the quick fix defines placeholders that have no variable', () {
      final cubit = build()
        ..updateTemplateText('{"notification": {"title": "{{a}} {{b}}"}}');
      expect(cubit.state.render.undefinedPlaceholders, ['a', 'b']);
      cubit.addMissingVariables();
      expect(cubit.state.variables.map((v) => v.key), ['a', 'b']);
      expect(cubit.state.render.undefinedPlaceholders, isEmpty);
    });

    test('setVariables keeps the values of keys that still exist', () {
      final cubit = build()
        ..loadPreset(preset)
        ..setVariableValue('order_id', '7')
        ..setVariables(const [
          VariableDef(key: 'order_id'),
          VariableDef(key: 'extra', defaultValue: 'x'),
        ]);
      expect(cubit.state.values, {'order_id': '7', 'extra': 'x'});
    });

    test('detachPreset forgets a deleted preset', () {
      final cubit = build()
        ..loadPreset(preset)
        ..detachPreset('other')
        ..detachPreset('p1');
      expect(cubit.state.preset, isNull);
    });
  });

  group('form edits', () {
    test('setField updates the template and rewrites the JSON text', () {
      final cubit = build()..setField(['android', 'priority'], 'high');
      expect(cubit.state.template!['android'], {'priority': 'high'});
      expect(cubit.state.templateText, contains('"priority": "high"'));
      expect(
        ComposerCubit.parseTemplate(cubit.state.templateText).$1,
        cubit.state.template,
      );
    });

    test('form edits are ignored while the JSON is invalid', () {
      final cubit = build()
        ..updateTemplateText('{')
        ..setField(['android', 'priority'], 'high');
      expect(cubit.state.templateText, '{');
    });

    test('the data-only switch goes both ways', () {
      final cubit = build()..setDataOnly(true);
      expect(TemplateEdits.isDataOnly(cubit.state.template!), isTrue);
      cubit.setDataOnly(false);
      expect(TemplateEdits.isDataOnly(cubit.state.template!), isFalse);
    });

    test('setDataEntries replaces data in order', () {
      final cubit = build()
        ..setDataEntries(const [MapEntry('b', '2'), MapEntry('a', '1')]);
      expect(
        TemplateEdits.dataEntries(cubit.state.template!).map((e) => e.key),
        ['b', 'a'],
      );
    });
  });

  group('sending', () {
    test('a dry run adds validate_only and is recorded as one', () async {
      final cubit = build()
        ..setTargetValue(token)
        ..setValidateOnly(true);
      expect(cubit.state.render.request!['validate_only'], isTrue);
      await cubit.send(testProject);
      expect(cubit.state.lastSentDryRun, isTrue);
      expect(
        (await HistoryRepository(database: database).loadAll()).single.validateOnly,
        isTrue,
      );
    });

    test('built-in placeholders get fresh values for each send', () async {
      var n = 0;
      final requests = <http.Request>[];
      final cubit =
          build(
              renderer: MessageRenderer(newId: () => 'id-${++n}'),
              client: fakeGoogle(onFcmRequest: requests.add),
            )
            ..updateTemplateText(
              '{"data": {"id": "{{uuid}}"}, "android": {"priority": "high"}}',
            )
            ..setTargetValue(token);
      final previewId = (messageOf(cubit)['data']! as Map<String, Object?>)['id'];
      await cubit.send(testProject);
      final sent = jsonDecode(requests.single.body) as Map<String, Object?>;
      final sentMessage = sent['message']! as Map<String, Object?>;
      expect((sentMessage['data']! as Map<String, Object?>)['id'], isNot(previewId));
    });

    test('the preset name goes into history', () async {
      final cubit = build()
        ..setTargetValue(token)
        ..loadPreset(preset);
      await cubit.send(testProject);
      expect(
        (await HistoryRepository(database: database).loadAll()).single.presetName,
        'Order update',
      );
    });

    test('curl returns a command for the current request', () async {
      final cubit = build()..setTargetValue(token);
      expect(
        await cubit.curl(testProject, includeAccessToken: false),
        contains(r'$FCM_ACCESS_TOKEN'),
      );
      cubit.setTargetValue('');
      expect(await cubit.curl(testProject, includeAccessToken: false), isNull);
    });
  });

  test('openMessage loads a stored message with its target and no variables', () {
    final cubit = build()
      ..loadPreset(preset)
      ..openMessage(
        template: const {
          'notification': {'title': 'Old'},
        },
        target: const TopicTarget('news'),
      );
    expect(cubit.state.preset, isNull);
    expect(cubit.state.variables, isEmpty);
    expect(cubit.state.targetKind, TargetKind.topic);
    expect(cubit.state.targetValue, 'news');
    expect(cubit.state.template, {
      'notification': {'title': 'Old'},
    });
  });

  test('showField asks the JSON editor to show the line of the field', () {
    final cubit = build()
      ..updateTemplateText('{\n  "data": {\n    "a": "1"\n  }\n}')
      ..showField('message.data[0].value');
    expect(cubit.state.jsonFocus?.line, 3);
    final first = cubit.state.jsonFocus;
    cubit.showField('message.data[0].value');
    expect(cubit.state.jsonFocus, isNot(first), reason: 'a repeat is a new request');
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/composer/composer_cubit_test.dart`
Expected: FAIL, compilation errors (`sender:` is not a parameter, `loadPreset` doesn't exist, …).

- [ ] **Step 3: Implement the state.** Replace `lib/features/composer/cubit/composer_state.dart` with:

```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/fcm/fcm_error_explainer.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter/foundation.dart' show listEquals;

enum SendStatus { idle, sending, done }

/// Asks the JSON editor to show [line] (1-based). [serial] makes a repeated
/// request for the same line a new one.
class JsonFocusRequest extends Equatable {
  const JsonFocusRequest(this.line, this.serial);

  final int line;
  final int serial;

  @override
  List<Object?> get props => [line, serial];
}

class ComposerState extends Equatable {
  const ComposerState({
    required this.templateText,
    this.template,
    this.jsonError,
    this.targetKind = TargetKind.token,
    this.targetValue = '',
    this.variables = const [],
    this.values = const {},
    this.validateOnly = false,
    this.preset,
    this.render = const RenderResult(),
    this.sendStatus = SendStatus.idle,
    this.lastResult,
    this.lastExplanation,
    this.lastSentDryRun = false,
    this.lastHistoryError,
    this.jsonFocus,
  });

  /// Exactly what is in the JSON editor.
  final String templateText;

  /// [templateText] parsed. Null while the JSON is invalid.
  final Map<String, Object?>? template;
  final String? jsonError;
  final TargetKind targetKind;
  final String targetValue;

  /// The variable definitions; the template uses them as `{{key}}`.
  final List<VariableDef> variables;

  /// The user's value for each variable key.
  final Map<String, String> values;

  /// Dry run: FCM validates the message but delivers nothing.
  final bool validateOnly;

  /// The preset the composer was loaded from or last saved to.
  final Preset? preset;
  final RenderResult render;
  final SendStatus sendStatus;
  final FcmSendResult? lastResult;
  final ErrorExplanation? lastExplanation;

  /// Whether [lastResult] came from a dry run.
  final bool lastSentDryRun;

  /// Set when the last send worked but could not be saved to history.
  final String? lastHistoryError;
  final JsonFocusRequest? jsonFocus;

  Target get target => Target.of(targetKind, targetValue);

  bool get canSend =>
      template != null && render.canSend && sendStatus != SendStatus.sending;

  /// True when the template or the variables differ from [preset] (the dot,
  /// spec §6). Variable values don't count.
  bool get isDirty {
    final preset = this.preset;
    if (preset == null) {
      return false;
    }
    final template = this.template;
    return template == null ||
        jsonEncode(template) != jsonEncode(preset.template) ||
        !listEquals(variables, preset.variables);
  }

  static const Object _unset = Object();

  ComposerState copyWith({
    String? templateText,
    Object? template = _unset,
    Object? jsonError = _unset,
    TargetKind? targetKind,
    String? targetValue,
    List<VariableDef>? variables,
    Map<String, String>? values,
    bool? validateOnly,
    Object? preset = _unset,
    RenderResult? render,
    SendStatus? sendStatus,
    Object? lastResult = _unset,
    Object? lastExplanation = _unset,
    bool? lastSentDryRun,
    Object? lastHistoryError = _unset,
    Object? jsonFocus = _unset,
  }) {
    return ComposerState(
      templateText: templateText ?? this.templateText,
      template: identical(template, _unset)
          ? this.template
          : template as Map<String, Object?>?,
      jsonError: identical(jsonError, _unset)
          ? this.jsonError
          : jsonError as String?,
      targetKind: targetKind ?? this.targetKind,
      targetValue: targetValue ?? this.targetValue,
      variables: variables ?? this.variables,
      values: values ?? this.values,
      validateOnly: validateOnly ?? this.validateOnly,
      preset: identical(preset, _unset) ? this.preset : preset as Preset?,
      render: render ?? this.render,
      sendStatus: sendStatus ?? this.sendStatus,
      lastResult: identical(lastResult, _unset)
          ? this.lastResult
          : lastResult as FcmSendResult?,
      lastExplanation: identical(lastExplanation, _unset)
          ? this.lastExplanation
          : lastExplanation as ErrorExplanation?,
      lastSentDryRun: lastSentDryRun ?? this.lastSentDryRun,
      lastHistoryError: identical(lastHistoryError, _unset)
          ? this.lastHistoryError
          : lastHistoryError as String?,
      jsonFocus: identical(jsonFocus, _unset)
          ? this.jsonFocus
          : jsonFocus as JsonFocusRequest?,
    );
  }

  @override
  List<Object?> get props => [
    templateText,
    template,
    jsonError,
    targetKind,
    targetValue,
    variables,
    values,
    validateOnly,
    preset,
    render,
    sendStatus,
    lastResult,
    lastExplanation,
    lastSentDryRun,
    lastHistoryError,
    jsonFocus,
  ];
}
```

- [ ] **Step 4: Implement the cubit.** Replace `lib/features/composer/cubit/composer_cubit.dart` with:

```dart
import 'dart:convert';

import 'package:fcm_studio/features/composer/cubit/composer_state.dart';
import 'package:fcm_studio/features/composer/data/message_sender.dart';
import 'package:fcm_studio/features/composer/domain/json_locator.dart';
import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/composer/domain/template_edits.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/composer/cubit/composer_state.dart';

class ComposerCubit extends Cubit<ComposerState> {
  ComposerCubit({
    required this._sender,
    this._renderer = const MessageRenderer(),
  }) : super(_renderedWith(_parsed(defaultTemplate), _renderer));

  static const defaultTemplate = '''
{
  "notification": {
    "title": "Hello from FCM Studio",
    "body": "If you can read this, it works."
  },
  "data": {
    "source": "fcm_studio"
  }
}
''';

  /// Form edits and loaded presets rewrite the JSON with this indentation.
  static const _encoder = JsonEncoder.withIndent('  ');

  final MessageSender _sender;
  final MessageRenderer _renderer;
  int _focusSerial = 0;

  void updateTemplateText(String text) {
    if (text == state.templateText) {
      return;
    }
    final (template, error) = parseTemplate(text);
    emit(
      _rendered(
        state.copyWith(templateText: text, template: template, jsonError: error),
      ),
    );
  }

  void setTargetKind(TargetKind kind) {
    if (kind == state.targetKind) {
      return;
    }
    emit(_rendered(state.copyWith(targetKind: kind)));
  }

  void setTargetValue(String value) {
    emit(_rendered(state.copyWith(targetValue: value)));
  }

  /// Sets both parts of the target, e.g. from a saved target or history.
  void setTarget(TargetKind kind, String value) {
    emit(_rendered(state.copyWith(targetKind: kind, targetValue: value)));
  }

  void setValidateOnly(bool value) {
    if (value == state.validateOnly) {
      return;
    }
    emit(_rendered(state.copyWith(validateOnly: value)));
  }

  void setVariableValue(String key, String value) {
    emit(_rendered(state.copyWith(values: {...state.values, key: value})));
  }

  /// Replaces the variable definitions, keeping the values of keys that
  /// still exist and using the default for new ones.
  void setVariables(List<VariableDef> variables) {
    final values = {
      for (final v in variables) v.key: state.values[v.key] ?? v.defaultValue,
    };
    emit(_rendered(state.copyWith(variables: variables, values: values)));
  }

  /// Quick fix: defines every undefined placeholder as a text variable.
  void addMissingVariables() {
    final missing = state.render.undefinedPlaceholders;
    if (missing.isEmpty) {
      return;
    }
    setVariables([
      ...state.variables,
      for (final key in missing) VariableDef(key: key),
    ]);
  }

  /// Form tab: sets one field. Ignored while the JSON is invalid, because the
  /// form is read-only then.
  void setField(List<String> path, Object? value) =>
      _editTemplate((template) => TemplateEdits.write(template, path, value));

  void setDataOnly(bool dataOnly) => _editTemplate(
    (template) => dataOnly
        ? TemplateEdits.toDataOnly(template)
        : TemplateEdits.toNotification(template),
  );

  void setDataEntries(List<MapEntry<String, Object?>> entries) =>
      _editTemplate((template) => TemplateEdits.withData(template, entries));

  void _editTemplate(
    Map<String, Object?> Function(Map<String, Object?> template) edit,
  ) {
    final template = state.template;
    if (template == null) {
      return;
    }
    final updated = edit(template);
    emit(
      _rendered(
        state.copyWith(
          templateText: _encoder.convert(updated),
          template: updated,
          jsonError: null,
        ),
      ),
    );
  }

  /// Loads [preset]: its template, its variables and their default values.
  void loadPreset(Preset preset) {
    emit(
      _rendered(
        state.copyWith(
          templateText: _encoder.convert(preset.template),
          template: TemplateEdits.copy(preset.template),
          jsonError: null,
          variables: preset.variables,
          values: {for (final v in preset.variables) v.key: v.defaultValue},
          preset: preset,
        ),
      ),
    );
  }

  /// Records that the current template was saved as [preset] (clears the dot).
  void presetSaved(Preset preset) => emit(state.copyWith(preset: preset));

  /// Forgets the loaded preset if it is [presetId], e.g. after it was deleted.
  void detachPreset(String presetId) {
    if (state.preset?.id == presetId) {
      emit(state.copyWith(preset: null));
    }
  }

  /// History → Open in composer: the stored message becomes the template,
  /// with no variables (spec §7.2).
  void openMessage({
    required Map<String, Object?> template,
    required Target target,
  }) {
    emit(
      _rendered(
        state.copyWith(
          templateText: _encoder.convert(template),
          template: TemplateEdits.copy(template),
          jsonError: null,
          variables: const [],
          values: const {},
          preset: null,
          targetKind: target.kind,
          targetValue: target.normalized,
        ),
      ),
    );
  }

  /// "Show in JSON" for an FCM field violation such as `message.data[0].value`.
  void showField(String fieldPath) {
    final template = state.template;
    if (template == null) {
      return;
    }
    final line = JsonLocator.lineOf(
      state.templateText,
      JsonLocator.resolve(fieldPath, template),
    );
    if (line == null) {
      return;
    }
    emit(state.copyWith(jsonFocus: JsonFocusRequest(line, ++_focusSerial)));
  }

  /// Sends the rendered request. Does nothing while a send is in progress.
  Future<void> send(Project project) async {
    if (!state.canSend) {
      return;
    }
    // Render again so {{now_*}} and {{uuid}} get fresh values for this send.
    final fresh = _rendered(state);
    final request = fresh.render.request;
    if (request == null) {
      emit(fresh);
      return;
    }
    emit(
      fresh.copyWith(
        sendStatus: SendStatus.sending,
        lastResult: null,
        lastExplanation: null,
        lastHistoryError: null,
        lastSentDryRun: fresh.validateOnly,
      ),
    );
    final outcome = await _sender.send(
      project: project,
      request: request,
      target: fresh.target,
      presetName: fresh.preset?.name,
    );
    if (isClosed) {
      return;
    }
    emit(
      state.copyWith(
        sendStatus: SendStatus.done,
        lastResult: outcome.result,
        lastExplanation: outcome.explanation,
        lastHistoryError: outcome.historyError,
      ),
    );
  }

  /// A curl command for the current request, or null when there is none.
  Future<String?> curl(Project project, {required bool includeAccessToken}) {
    final request = state.render.request;
    if (request == null) {
      return Future.value();
    }
    return _sender.curl(
      project: project,
      request: request,
      includeAccessToken: includeAccessToken,
    );
  }

  /// Parses editor text. Returns the template, or an error message with line and column.
  static (Map<String, Object?>?, String?) parseTemplate(String text) {
    if (text.trim().isEmpty) {
      return (null, 'The message JSON is empty. Start with {}.');
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) {
        return (decoded, null);
      }
      return (null, 'The top level must be a JSON object ({ ... }).');
    } on FormatException catch (e) {
      return (null, _describeFormatError(e, text));
    }
  }

  static String _describeFormatError(FormatException e, String text) {
    final offset = e.offset;
    if (offset == null) {
      return 'Invalid JSON: ${e.message}';
    }
    final before = text.substring(0, offset.clamp(0, text.length));
    final line = '\n'.allMatches(before).length + 1;
    final column = before.length - (before.lastIndexOf('\n') + 1) + 1;
    return 'Invalid JSON at line $line, column $column: ${e.message}';
  }

  static ComposerState _parsed(String text) {
    final (template, error) = parseTemplate(text);
    return ComposerState(
      templateText: text,
      template: template,
      jsonError: error,
    );
  }

  ComposerState _rendered(ComposerState state) =>
      _renderedWith(state, _renderer);

  static ComposerState _renderedWith(
    ComposerState state,
    MessageRenderer renderer,
  ) {
    final template = state.template;
    if (template == null) {
      return state.copyWith(render: const RenderResult());
    }
    return state.copyWith(
      render: renderer.render(
        template: template,
        target: state.target,
        variables: state.variables,
        values: state.values,
        validateOnly: state.validateOnly,
      ),
    );
  }
}
```

- [ ] **Step 5: Wire `MessageSender` into the app.** Replace `lib/app/dependencies.dart` with:

```dart
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/features/composer/data/message_sender.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Every long-lived service, created once at startup.
class AppDependencies {
  factory AppDependencies({
    required http.Client httpClient,
    required AppDatabase database,
    required SecretStore secrets,
    Clock clock = const SystemClock(),
  }) {
    final projectsRepository = ProjectsRepository(
      database: database,
      secrets: secrets,
    );
    final authRegistry = ProjectAuthRegistry(
      repository: projectsRepository,
      httpClient: httpClient,
      clock: clock,
    );
    final historyRepository = HistoryRepository(database: database);
    final targetsRepository = TargetsRepository(database: database);
    return AppDependencies._(
      httpClient: httpClient,
      database: database,
      clock: clock,
      projectsRepository: projectsRepository,
      authRegistry: authRegistry,
      firebaseProjectsApi: FirebaseProjectsApi(httpClient: httpClient),
      historyRepository: historyRepository,
      targetsRepository: targetsRepository,
      messageSender: MessageSender(
        fcmClient: FcmClient(httpClient: httpClient),
        auth: authRegistry,
        history: historyRepository,
        targets: targetsRepository,
        clock: clock,
      ),
    );
  }

  AppDependencies._({
    required this.httpClient,
    required this.database,
    required this.clock,
    required this.projectsRepository,
    required this.authRegistry,
    required this.firebaseProjectsApi,
    required this.historyRepository,
    required this.targetsRepository,
    required this.messageSender,
  });

  static Future<AppDependencies> create() async => AppDependencies(
    httpClient: http.Client(),
    database: await AppDatabase.open(),
    // On web, keys stay in memory unless the user ticks "Remember on this browser".
    secrets: LayeredSecretStore(
      persistent: FlutterSecureSecretStore(),
      alwaysPersist: !kIsWeb,
    ),
  );

  final http.Client httpClient;
  final AppDatabase database;
  final Clock clock;
  final ProjectsRepository projectsRepository;
  final ProjectAuthRegistry authRegistry;
  final FirebaseProjectsApi firebaseProjectsApi;
  final HistoryRepository historyRepository;
  final TargetsRepository targetsRepository;
  final MessageSender messageSender;
}
```

In `lib/app/app.dart`, replace the `ComposerCubit` provider with:
```dart
        BlocProvider(
          create: (_) => ComposerCubit(sender: dependencies.messageSender),
        ),
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `flutter test test/features/composer/composer_cubit_test.dart`
Expected: PASS. Then run `flutter test`: everything passes, including the existing widget tests, because the composer screen's behaviour hasn't changed. Then `flutter analyze` (No issues found!).

- [ ] **Step 7: Commit**

```bash
dart format lib test
git add lib/features/composer/cubit lib/app/dependencies.dart lib/app/app.dart test/features/composer/composer_cubit_test.dart
git commit -m "feat: add variables, presets, dry run and form edits to the composer"
```

---

### Task 9: Presets repository and `PresetsCubit`

**Files:**
- Create: `lib/features/presets/data/presets_repository.dart`, `lib/features/presets/cubit/presets_state.dart`, `lib/features/presets/cubit/presets_cubit.dart`, `test/helpers/presets_fixture.dart`
- Test: `test/features/presets/presets_cubit_test.dart`

**Interfaces:**
- Consumes: `AppDatabase` (existing), `Preset`, `PresetCodec`, `ImportPreview`, `ImportConflictChoice`, `PresetFormatException` (Task 4), `VariableDef`, `IdGenerator`/`newUuid` (Task 1), `Clock`/`SystemClock`, `FixedClock`.
- Produces:
  - `class PresetsRepository({required AppDatabase database, required Future<String> Function() loadBuiltInJson})` with `static const builtInAsset = 'assets/presets/builtin.json'`, `loadBuiltIns()`, `loadUserPresets()` (sorted by name), `save(Preset)` (throws `StateError` for built-ins), `saveAll(List<Preset>)`, `remove(String id)`.
  - `enum PresetsStatus { initial, loading, ready }` and `class PresetsState` with `builtIns`, `userPresets`, `all`, `byId(id)`, `nameTaken(name, {exceptId})`.
  - `class PresetsCubit({required PresetsRepository repository, Clock clock, IdGenerator newId})` with `load()`, `saveAs({required name, String description = '', required template, required variables})`, `update(preset, {required template, required variables})`, `duplicate(preset)`, `rename(preset, {required name, required description})`, `delete(preset)`, `exportText(List<Preset>)`, `previewImport(String text)`, `applyImport(ImportPreview, ImportConflictChoice) → Future<int>`.
  - Test helper `Future<String> loadBuiltInPresetsFromFile()`.

- [ ] **Step 1: Add the test helper** `test/helpers/presets_fixture.dart`

```dart
import 'dart:io';

/// Reads the bundled built-in presets straight from disk, for tests.
Future<String> loadBuiltInPresetsFromFile() async =>
    File('assets/presets/builtin.json').readAsStringSync();
```

- [ ] **Step 2: Write the failing tests** `test/features/presets/presets_cubit_test.dart`

```dart
import 'dart:convert';

import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/data/presets_repository.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/presets_fixture.dart';

void main() {
  late AppDatabase database;
  late FixedClock clock;
  var ids = 0;

  setUp(() async {
    database = await AppDatabase.inMemory();
    clock = FixedClock(DateTime.utc(2026, 10, 3, 9));
    ids = 0;
  });

  tearDown(() => database.close());

  Future<PresetsCubit> loaded() async {
    final cubit = PresetsCubit(
      repository: PresetsRepository(
        database: database,
        loadBuiltInJson: loadBuiltInPresetsFromFile,
      ),
      clock: clock,
      newId: () => 'id-${++ids}',
    );
    await cubit.load();
    return cubit;
  }

  const template = {
    'notification': {'title': '{{title}}'},
  };
  const variables = [VariableDef(key: 'title')];

  test('loads the four built-in presets as read-only', () async {
    final cubit = await loaded();
    expect(cubit.state.status, PresetsStatus.ready);
    expect(cubit.state.builtIns, hasLength(4));
    expect(cubit.state.builtIns.every((p) => p.builtIn), isTrue);
    expect(cubit.state.userPresets, isEmpty);
    expect(cubit.state.byId('builtin.simple')?.name, 'Simple notification');
  });

  test('Save as stores a new preset that survives a restart', () async {
    final cubit = await loaded();
    final saved = await cubit.saveAs(
      name: ' Order update ',
      template: template,
      variables: variables,
    );
    expect(saved.name, 'Order update');
    expect(saved.id, 'id-1');
    expect(saved.createdAt, clock.now());
    expect(cubit.state.userPresets, [saved]);

    final restarted = await loaded();
    expect(restarted.state.userPresets, [saved]);
  });

  test('Update overwrites a user preset; built-in presets are read-only', () async {
    final cubit = await loaded();
    final saved = await cubit.saveAs(
      name: 'A',
      template: template,
      variables: variables,
    );
    clock.advance(const Duration(minutes: 1));
    final updated = await cubit.update(
      saved,
      template: const {
        'notification': {'title': 'Fixed'},
      },
      variables: const [],
    );
    expect(cubit.state.userPresets.single, updated);
    expect(updated.updatedAt, clock.now());
    expect(updated.createdAt, saved.createdAt);
    await expectLater(
      cubit.update(
        cubit.state.builtIns.first,
        template: template,
        variables: variables,
      ),
      throwsStateError,
    );
  });

  test('duplicate makes an editable copy with a free name', () async {
    final cubit = await loaded();
    final simple = cubit.state.byId('builtin.simple')!;
    final first = await cubit.duplicate(simple);
    final second = await cubit.duplicate(simple);
    expect(first.name, 'Simple notification (copy)');
    expect(second.name, 'Simple notification (copy) (2)');
    expect(first.builtIn, isFalse);
    expect(first.template, simple.template);
  });

  test('rename, nameTaken and delete', () async {
    final cubit = await loaded();
    final saved = await cubit.saveAs(
      name: 'A',
      template: template,
      variables: variables,
    );
    expect(cubit.state.nameTaken('a'), isTrue);
    expect(cubit.state.nameTaken('a', exceptId: saved.id), isFalse);
    expect(cubit.state.nameTaken('SIMPLE NOTIFICATION'), isTrue);

    final renamed = await cubit.rename(saved, name: 'B', description: 'Mine');
    expect(cubit.state.userPresets.single.name, 'B');
    expect(cubit.state.userPresets.single.description, 'Mine');

    await cubit.delete(renamed);
    await cubit.delete(cubit.state.builtIns.first);
    expect(cubit.state.userPresets, isEmpty);
    expect(cubit.state.builtIns, hasLength(4));
  });

  test('export leaves out built-in presets', () async {
    final cubit = await loaded();
    await cubit.saveAs(name: 'A', template: template, variables: variables);
    final text = cubit.exportText(cubit.state.all);
    expect(PresetCodec.decode(text).map((p) => p.name), ['A']);
  });

  test('import with Replace overwrites user presets but never built-in ones', () async {
    final cubit = await loaded();
    final saved = await cubit.saveAs(
      name: 'A',
      template: template,
      variables: variables,
    );
    final file = PresetCodec.encode([
      saved.copyWith(
        template: const {
          'notification': {'title': 'Imported'},
        },
      ),
      saved.copyWith(id: 'x', name: 'Simple notification'),
    ], exportedAt: clock.now());

    final preview = cubit.previewImport(file);
    expect(preview.conflicts, ['A', 'Simple notification']);

    expect(await cubit.applyImport(preview, ImportConflictChoice.replace), 2);
    expect(cubit.state.userPresets.map((p) => p.name), [
      'A',
      'Simple notification (2)',
    ]);
    expect(cubit.state.userPresets.first.template, {
      'notification': {'title': 'Imported'},
    });
    expect(cubit.state.byId('builtin.simple')?.name, 'Simple notification');
  });

  test('a newer presets file is rejected and nothing is imported', () async {
    final cubit = await loaded();
    expect(
      () => cubit.previewImport(
        jsonEncode({'format': PresetCodec.format, 'version': 9, 'presets': []}),
      ),
      throwsA(isA<PresetFormatException>()),
    );
    expect(cubit.state.userPresets, isEmpty);
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/presets/presets_cubit_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 4: Implement**

`lib/features/presets/data/presets_repository.dart`:
```dart
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
      ..sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
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
```

`lib/features/presets/cubit/presets_state.dart`:
```dart
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
```

`lib/features/presets/cubit/presets_cubit.dart`:
```dart
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

  Future<void> load() async {
    emit(state.copyWith(status: PresetsStatus.loading));
    final builtIns = await _repository.loadBuiltIns();
    final userPresets = await _repository.loadUserPresets();
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
  Future<Preset> saveAs({
    required String name,
    required Map<String, Object?> template,
    required List<VariableDef> variables,
    String description = '',
  }) async {
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

  /// "Update preset": overwrites [preset] with the composer's template and
  /// variables. Throws [StateError] for a built-in preset.
  Future<Preset> update(
    Preset preset, {
    required Map<String, Object?> template,
    required List<VariableDef> variables,
  }) async {
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

  Set<String> _takenNames() => {
    for (final p in state.all) PresetCodec.normalizeName(p.name),
  };
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/features/presets/presets_cubit_test.dart`
Expected: PASS (8 tests). Then `flutter analyze` (No issues found!).

- [ ] **Step 6: Commit**

```bash
dart format lib test
git add lib/features/presets/data lib/features/presets/cubit test/helpers/presets_fixture.dart test/features/presets/presets_cubit_test.dart
git commit -m "feat: save, update, duplicate, export and import presets"
```

---

### Task 10: `TargetsCubit` and `HistoryCubit`

**Files:**
- Create: `lib/features/targets/cubit/targets_state.dart`, `lib/features/targets/cubit/targets_cubit.dart`, `lib/features/history/cubit/history_state.dart`, `lib/features/history/cubit/history_cubit.dart`
- Test: `test/features/targets/targets_cubit_test.dart`, `test/features/history/history_cubit_test.dart`

**Interfaces:**
- Consumes: `TargetsRepository`, `SavedTarget` (Task 5); `HistoryRepository`, `HistoryEntry`, `HistoryFilter`, `OutcomeFilter` (Task 6); `MessageSender`, `SendOutcome` (Task 7); `Target`, `Project`; test helpers `buildSender`, `historyEntry`, `fakeGoogle`, `FixedClock`, `testProject`.
- Produces:
  - `class TargetsState({List<SavedTarget> targets})` with `matching(Target) → SavedTarget?`.
  - `class TargetsCubit({required TargetsRepository repository, Clock clock, IdGenerator newId})` with `load()`, `save(Target, {required String label, String? projectId}) → Future<SavedTarget>`, `rename(SavedTarget, String label)`, `remove(SavedTarget)`. Reloads when the repository changes.
  - `enum HistoryStatus { initial, loading, ready }`, `class HistoryState({status, entries, filter})` with `visible` and `projectIds`.
  - `class HistoryCubit({required HistoryRepository repository, required MessageSender sender})` with `load()`, `setFilter(HistoryFilter)`, `clear()`, `resend(HistoryEntry, Project) → Future<SendOutcome>`, `curl(HistoryEntry, Project, {required bool includeAccessToken}) → Future<String>`. Reloads when the repository changes.

- [ ] **Step 1: Write the failing tests**

`test/features/targets/targets_cubit_test.dart`:
```dart
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fixed_clock.dart';

void main() {
  late AppDatabase database;
  late TargetsRepository repository;
  final clock = FixedClock(DateTime.utc(2026, 10, 3, 9));
  var ids = 0;

  setUp(() async {
    database = await AppDatabase.inMemory();
    repository = TargetsRepository(database: database);
    ids = 0;
  });

  tearDown(() => database.close());

  Future<TargetsCubit> loaded() async {
    final cubit = TargetsCubit(
      repository: repository,
      clock: clock,
      newId: () => 't${++ids}',
    );
    await cubit.load();
    addTearDown(cubit.close);
    return cubit;
  }

  test('saves a target, with a default label when none is given', () async {
    final cubit = await loaded();
    final saved = await cubit.save(
      const TopicTarget('/topics/news'),
      label: ' ',
      projectId: 'demo-project',
    );
    expect(saved.label, 'Topic news');
    expect(saved.value, 'news');
    expect(saved.projectId, 'demo-project');
    expect(saved.lastUsedAt, clock.now());
    expect(cubit.state.targets, [saved]);
    expect(cubit.state.matching(const TopicTarget('news')), saved);
  });

  test('rename and remove', () async {
    final cubit = await loaded();
    final saved = await cubit.save(const TopicTarget('news'), label: 'News');
    await cubit.rename(saved, 'Breaking');
    expect(cubit.state.targets.single.label, 'Breaking');
    await cubit.remove(cubit.state.targets.single);
    expect(cubit.state.targets, isEmpty);
  });

  test('picks up changes made elsewhere, e.g. a send marking a target used', () async {
    final cubit = await loaded();
    final next = cubit.stream.first;
    await repository.save(
      SavedTarget(
        id: 'x',
        label: 'X',
        kind: TargetKind.topic,
        value: 'news',
        lastUsedAt: clock.now(),
      ),
    );
    expect((await next).targets.single.id, 'x');
  });
}
```

`test/features/history/history_cubit_test.dart`:
```dart
import 'dart:convert';

import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/history/cubit/history_cubit.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/history/domain/history_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/fake_google.dart';
import '../../helpers/history_fixture.dart';
import '../../helpers/project_fixture.dart';
import '../../helpers/sender_fixture.dart';

void main() {
  late AppDatabase database;
  late HistoryRepository repository;

  setUp(() async {
    database = await AppDatabase.inMemory();
    repository = HistoryRepository(database: database);
  });

  tearDown(() => database.close());

  Future<HistoryCubit> loaded({http.Client? client}) async {
    final cubit = HistoryCubit(
      repository: repository,
      sender: buildSender(database, client: client, history: repository),
    );
    await cubit.load();
    addTearDown(cubit.close);
    return cubit;
  }

  test('loads entries newest first and filters them', () async {
    await repository.add(
      historyEntry('old', sentAt: DateTime.utc(2026, 10, 3, 9)),
    );
    await repository.add(
      historyEntry('failed', ok: false, sentAt: DateTime.utc(2026, 10, 3, 10)),
    );
    final cubit = await loaded();
    expect(cubit.state.status, HistoryStatus.ready);
    expect(cubit.state.entries.map((e) => e.id), ['failed', 'old']);
    expect(cubit.state.projectIds, ['demo-project']);

    cubit.setFilter(const HistoryFilter(outcome: OutcomeFilter.failure));
    expect(cubit.state.visible.map((e) => e.id), ['failed']);
  });

  test('clear empties the history', () async {
    await repository.add(historyEntry('a'));
    final cubit = await loaded();
    await cubit.clear();
    expect(cubit.state.entries, isEmpty);
  });

  test('resend sends the stored request again and records a new entry', () async {
    final requests = <http.Request>[];
    await repository.add(historyEntry('e1'));
    final cubit = await loaded(client: fakeGoogle(onFcmRequest: requests.add));

    final reloaded = cubit.stream.firstWhere((s) => s.entries.length == 2);
    final outcome = await cubit.resend(cubit.state.entries.single, testProject);
    await reloaded;

    expect(outcome.result, isA<FcmSendSuccess>());
    expect(jsonDecode(requests.single.body), historyEntry('e1').request);
  });

  test('curl for an entry', () async {
    await repository.add(historyEntry('e1'));
    final cubit = await loaded();
    expect(
      await cubit.curl(
        cubit.state.entries.single,
        testProject,
        includeAccessToken: false,
      ),
      contains('abc:APA91bxyz'),
    );
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/targets/targets_cubit_test.dart test/features/history/history_cubit_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement**

`lib/features/targets/cubit/targets_state.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';

class TargetsState extends Equatable {
  const TargetsState({this.targets = const []});

  /// Most recently used first.
  final List<SavedTarget> targets;

  /// The saved target for [target], if it is saved.
  SavedTarget? matching(Target target) {
    for (final saved in targets) {
      if (saved.matches(target)) {
        return saved;
      }
    }
    return null;
  }

  @override
  List<Object?> get props => [targets];
}
```

`lib/features/targets/cubit/targets_cubit.dart`:
```dart
import 'dart:async';

import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/core/utils/ids.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/cubit/targets_state.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/targets/cubit/targets_state.dart';

class TargetsCubit extends Cubit<TargetsState> {
  TargetsCubit({
    required this._repository,
    this._clock = const SystemClock(),
    this._newId = newUuid,
  }) : super(const TargetsState()) {
    // Sends change lastUsedAt, so follow every change to the store.
    _subscription = _repository.changes.listen((_) => load());
  }

  final TargetsRepository _repository;
  final Clock _clock;
  final IdGenerator _newId;
  late final StreamSubscription<void> _subscription;

  Future<void> load() async {
    final targets = await _repository.loadAll();
    if (!isClosed) {
      emit(TargetsState(targets: targets));
    }
  }

  /// Saves [target] (the star next to the target field). A blank [label]
  /// becomes [SavedTarget.defaultLabel].
  Future<SavedTarget> save(
    Target target, {
    required String label,
    String? projectId,
  }) async {
    final trimmed = label.trim();
    final saved = SavedTarget(
      id: _newId(),
      label: trimmed.isEmpty ? SavedTarget.defaultLabel(target) : trimmed,
      kind: target.kind,
      value: target.normalized,
      projectId: projectId,
      lastUsedAt: _clock.now(),
    );
    await _repository.save(saved);
    await load();
    return saved;
  }

  Future<void> rename(SavedTarget target, String label) async {
    await _repository.save(target.copyWith(label: label.trim()));
    await load();
  }

  Future<void> remove(SavedTarget target) async {
    await _repository.remove(target.id);
    await load();
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
```

`lib/features/history/cubit/history_state.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/history/domain/history_filter.dart';

enum HistoryStatus { initial, loading, ready }

class HistoryState extends Equatable {
  const HistoryState({
    this.status = HistoryStatus.initial,
    this.entries = const [],
    this.filter = const HistoryFilter(),
  });

  final HistoryStatus status;

  /// Every entry, newest first.
  final List<HistoryEntry> entries;
  final HistoryFilter filter;

  /// The entries that match [filter].
  List<HistoryEntry> get visible => entries.where(filter.matches).toList();

  /// The projects that appear in history, for the project filter.
  List<String> get projectIds =>
      {for (final e in entries) e.projectId}.toList()..sort();

  HistoryState copyWith({
    HistoryStatus? status,
    List<HistoryEntry>? entries,
    HistoryFilter? filter,
  }) => HistoryState(
    status: status ?? this.status,
    entries: entries ?? this.entries,
    filter: filter ?? this.filter,
  );

  @override
  List<Object?> get props => [status, entries, filter];
}
```

`lib/features/history/cubit/history_cubit.dart`:
```dart
import 'dart:async';

import 'package:fcm_studio/features/composer/data/message_sender.dart';
import 'package:fcm_studio/features/history/cubit/history_state.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/history/domain/history_filter.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/history/cubit/history_state.dart';

class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit({required this._repository, required this._sender})
    : super(const HistoryState()) {
    // The composer records sends in the same store.
    _subscription = _repository.changes.listen((_) => load());
  }

  final HistoryRepository _repository;
  final MessageSender _sender;
  late final StreamSubscription<void> _subscription;

  Future<void> load() async {
    final entries = await _repository.loadAll();
    if (!isClosed) {
      emit(state.copyWith(status: HistoryStatus.ready, entries: entries));
    }
  }

  void setFilter(HistoryFilter filter) => emit(state.copyWith(filter: filter));

  Future<void> clear() async {
    await _repository.clear();
    await load();
  }

  /// Sends [entry]'s stored request again, with a current access token
  /// (spec §7.2). The resend gets its own history entry.
  Future<SendOutcome> resend(HistoryEntry entry, Project project) =>
      _sender.send(
        project: project,
        request: entry.request,
        target: entry.target.toTarget(),
        presetName: entry.presetName,
      );

  Future<String> curl(
    HistoryEntry entry,
    Project project, {
    required bool includeAccessToken,
  }) => _sender.curl(
    project: project,
    request: entry.request,
    includeAccessToken: includeAccessToken,
  );

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/features/targets/targets_cubit_test.dart test/features/history/history_cubit_test.dart`
Expected: PASS (3 + 4 tests). Then `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/features/targets/cubit lib/features/history/cubit test/features/targets/targets_cubit_test.dart test/features/history/history_cubit_test.dart
git commit -m "feat: add cubits for saved targets and history, with resend"
```

---

### Task 11: App wiring: file access, error banner and the new cubits

**Files:**
- Modify: `pubspec.yaml`, `lib/main.dart`, `lib/app/app.dart`, `lib/app/dependencies.dart`, `test/helpers/app_harness.dart`, `test/app/app_test.dart`
- Create: `lib/core/platform/file_access.dart`, `lib/app/app_error_cubit.dart`, `lib/app/app_error_banner.dart`, `test/helpers/fake_file_access.dart`
- Test: `test/app/app_error_cubit_test.dart`, `test/app/app_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 7–10; `redact` (existing); `loadBuiltInPresetsFromFile` (Task 9).
- Produces:
  - `abstract interface class FileAccess { Future<String?> openText({required String label, required List<String> extensions}); Future<bool> saveText({required String suggestedName, required String text}); }` and `class PlatformFileAccess implements FileAccess` (const).
  - `class AppErrorCubit extends Cubit<String?>` with `report(Object error, {String? context})` and `dismiss()`.
  - `class AppErrorBanner` with `static const dismissKey`.
  - `AppDependencies` gains `files` and `presetsRepository`, and the factory takes `FileAccess files = const PlatformFileAccess()` and `Future<String> Function()? loadBuiltInPresets`.
  - `FcmStudioApp({required AppDependencies dependencies, AppErrorCubit? errors})` provides `FileAccess` (as a `RepositoryProvider`), `AppErrorCubit`, `ProjectsCubit`, `PresetsCubit`, `TargetsCubit`, `HistoryCubit` and `ComposerCubit`.
  - Test helpers: `buildTestDependencies(tester, {http.Client? client, FileAccess? files})`, `addTestProject(tester) → Future<ProjectsCubit>`, `pumpAppWithProject(tester, {…, FileAccess? files})`, `settleAsync(tester)`, `readCubit` (finds offstage widgets too), `class FakeFileAccess` (`nextOpen`, `saved`).

- [ ] **Step 1: Write the failing tests**

`test/app/app_error_cubit_test.dart`:
```dart
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reports an error redacted, with what was being done, until dismissed', () {
    final cubit = AppErrorCubit()
      ..report(
        Exception('Authorization: Bearer ya29.secret'),
        context: 'Could not save',
      );
    expect(
      cubit.state,
      'Could not save: Exception: Authorization: Bearer [REDACTED]',
    );
    cubit.dismiss();
    expect(cubit.state, isNull);
  });
}
```

Add these imports to `test/app/app_test.dart`:
```dart
import 'package:fcm_studio/app/app_error_banner.dart';
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
```
and these tests at the end of its `main()`:
```dart
  testWidgets('the error banner shows a reported error until dismissed', (
    tester,
  ) async {
    await pumpApp(tester, await buildTestDependencies(tester));
    readCubit<AppErrorCubit>(
      tester,
    ).report(StateError('disk full'), context: 'Could not save the preset');
    await tester.pump();
    expect(
      find.text('Could not save the preset: Bad state: disk full'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(AppErrorBanner.dismissKey));
    await tester.pump();
    expect(find.textContaining('disk full'), findsNothing);
  });

  testWidgets('the built-in presets are loaded at startup', (tester) async {
    await pumpApp(tester, await buildTestDependencies(tester));
    expect(readCubit<PresetsCubit>(tester).state.builtIns, hasLength(4));
  });
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/app`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Declare the asset.** In `pubspec.yaml`, change the `flutter:` section to:
```yaml
flutter:
  uses-material-design: true
  assets:
    - assets/presets/builtin.json
```
Then run `flutter pub get`.

- [ ] **Step 4: Implement**

`lib/core/platform/file_access.dart`:
```dart
import 'dart:convert';

import 'package:file_selector/file_selector.dart';

/// Opening and saving text files: preset import and export (spec §6).
abstract interface class FileAccess {
  /// Asks for a file and returns its text, or null when the user cancels.
  Future<String?> openText({
    required String label,
    required List<String> extensions,
  });

  /// Saves [text]. Desktop asks where to save; web downloads the file.
  /// Returns false when the user cancels.
  Future<bool> saveText({required String suggestedName, required String text});
}

class PlatformFileAccess implements FileAccess {
  const PlatformFileAccess();

  @override
  Future<String?> openText({
    required String label,
    required List<String> extensions,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: label,
          extensions: extensions,
          mimeTypes: const ['application/json'],
          uniformTypeIdentifiers: const ['public.json'],
        ),
      ],
    );
    return file?.readAsString();
  }

  @override
  Future<bool> saveText({
    required String suggestedName,
    required String text,
  }) async {
    // On web this returns a placeholder location, and saveTo downloads the
    // file under its name.
    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location == null) {
      return false;
    }
    await XFile.fromData(
      utf8.encode(text),
      mimeType: 'application/json',
      name: suggestedName,
    ).saveTo(location.path);
    return true;
  }
}
```

`lib/app/app_error_cubit.dart`:
```dart
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The app-wide, dismissible error (spec §11). The state is the message, or
/// null when there is nothing to show.
class AppErrorCubit extends Cubit<String?> {
  AppErrorCubit() : super(null);

  /// Shows [error], redacted, after what the app was doing ([context]).
  void report(Object error, {String? context}) {
    final text = redact('$error');
    emit(context == null ? text : '$context: $text');
  }

  void dismiss() => emit(null);
}
```

`lib/app/app_error_banner.dart`:
```dart
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AppErrorBanner extends StatelessWidget {
  const AppErrorBanner({super.key});

  static const dismissKey = Key('app-error-dismiss');

  @override
  Widget build(BuildContext context) {
    final message = context.watch<AppErrorCubit>().state;
    if (message == null) {
      return const SizedBox.shrink();
    }
    return MaterialBanner(
      leading: const Icon(Icons.error_outline),
      content: Text(message),
      actions: [
        TextButton(
          key: dismissKey,
          onPressed: () => context.read<AppErrorCubit>().dismiss(),
          child: const Text('Dismiss'),
        ),
      ],
    );
  }
}
```

Replace `lib/app/dependencies.dart` with:
```dart
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:fcm_studio/core/platform/file_access.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/features/composer/data/message_sender.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/presets/data/presets_repository.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Every long-lived service, created once at startup.
class AppDependencies {
  factory AppDependencies({
    required http.Client httpClient,
    required AppDatabase database,
    required SecretStore secrets,
    Clock clock = const SystemClock(),
    FileAccess files = const PlatformFileAccess(),
    Future<String> Function()? loadBuiltInPresets,
  }) {
    final projectsRepository = ProjectsRepository(
      database: database,
      secrets: secrets,
    );
    final authRegistry = ProjectAuthRegistry(
      repository: projectsRepository,
      httpClient: httpClient,
      clock: clock,
    );
    final historyRepository = HistoryRepository(database: database);
    final targetsRepository = TargetsRepository(database: database);
    return AppDependencies._(
      httpClient: httpClient,
      database: database,
      clock: clock,
      files: files,
      projectsRepository: projectsRepository,
      authRegistry: authRegistry,
      firebaseProjectsApi: FirebaseProjectsApi(httpClient: httpClient),
      presetsRepository: PresetsRepository(
        database: database,
        loadBuiltInJson:
            loadBuiltInPresets ??
            () => rootBundle.loadString(PresetsRepository.builtInAsset),
      ),
      historyRepository: historyRepository,
      targetsRepository: targetsRepository,
      messageSender: MessageSender(
        fcmClient: FcmClient(httpClient: httpClient),
        auth: authRegistry,
        history: historyRepository,
        targets: targetsRepository,
        clock: clock,
      ),
    );
  }

  AppDependencies._({
    required this.httpClient,
    required this.database,
    required this.clock,
    required this.files,
    required this.projectsRepository,
    required this.authRegistry,
    required this.firebaseProjectsApi,
    required this.presetsRepository,
    required this.historyRepository,
    required this.targetsRepository,
    required this.messageSender,
  });

  static Future<AppDependencies> create() async => AppDependencies(
    httpClient: http.Client(),
    database: await AppDatabase.open(),
    // On web, keys stay in memory unless the user ticks "Remember on this browser".
    secrets: LayeredSecretStore(
      persistent: FlutterSecureSecretStore(),
      alwaysPersist: !kIsWeb,
    ),
  );

  final http.Client httpClient;
  final AppDatabase database;
  final Clock clock;
  final FileAccess files;
  final ProjectsRepository projectsRepository;
  final ProjectAuthRegistry authRegistry;
  final FirebaseProjectsApi firebaseProjectsApi;
  final PresetsRepository presetsRepository;
  final HistoryRepository historyRepository;
  final TargetsRepository targetsRepository;
  final MessageSender messageSender;
}
```

Replace `lib/app/app.dart` with:
```dart
import 'package:fcm_studio/app/app_error_banner.dart';
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/dependencies.dart';
import 'package:fcm_studio/app/theme.dart';
import 'package:fcm_studio/core/platform/file_access.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/view/composer_screen.dart';
import 'package:fcm_studio/features/history/cubit/history_cubit.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FcmStudioApp extends StatelessWidget {
  const FcmStudioApp({required this.dependencies, this.errors, super.key});

  final AppDependencies dependencies;

  /// The error banner's cubit. `main()` passes one that also receives
  /// uncaught errors; otherwise the app makes its own.
  final AppErrorCubit? errors;

  @override
  Widget build(BuildContext context) {
    final errors = this.errors;
    return RepositoryProvider<FileAccess>.value(
      value: dependencies.files,
      child: MultiBlocProvider(
        providers: [
          if (errors != null)
            BlocProvider.value(value: errors)
          else
            BlocProvider(create: (_) => AppErrorCubit()),
          BlocProvider(
            create: (_) => ProjectsCubit(
              repository: dependencies.projectsRepository,
              authRegistry: dependencies.authRegistry,
              firebaseApi: dependencies.firebaseProjectsApi,
            )..load(),
          ),
          BlocProvider(
            lazy: false,
            create: (_) => PresetsCubit(
              repository: dependencies.presetsRepository,
              clock: dependencies.clock,
            )..load(),
          ),
          BlocProvider(
            lazy: false,
            create: (_) => TargetsCubit(
              repository: dependencies.targetsRepository,
              clock: dependencies.clock,
            )..load(),
          ),
          BlocProvider(
            lazy: false,
            create: (_) => HistoryCubit(
              repository: dependencies.historyRepository,
              sender: dependencies.messageSender,
            )..load(),
          ),
          BlocProvider(
            create: (_) => ComposerCubit(sender: dependencies.messageSender),
          ),
        ],
        child: MaterialApp(
          title: 'FCM Studio',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          // The error banner stays above every screen and dialog.
          builder: (context, child) => Column(
            children: [
              const AppErrorBanner(),
              Expanded(child: child ?? const SizedBox.shrink()),
            ],
          ),
          home: const ComposerScreen(),
        ),
      ),
    );
  }
}
```

Replace `lib/main.dart` with:
```dart
import 'package:fcm_studio/app/app.dart';
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/dependencies.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final errors = AppErrorCubit();
  // Errors that nothing else caught show as a dismissible banner (spec §11).
  binding.platformDispatcher.onError = (error, stack) {
    errors.report(error);
    return true;
  };
  final dependencies = await AppDependencies.create();
  runApp(FcmStudioApp(dependencies: dependencies, errors: errors));
}
```

- [ ] **Step 5: Update the test helpers**

`test/helpers/fake_file_access.dart`:
```dart
import 'package:fcm_studio/core/platform/file_access.dart';

class FakeFileAccess implements FileAccess {
  /// Returned by the next [openText]; null acts like the user cancelling.
  String? nextOpen;

  /// Every file saved, in order.
  final List<({String name, String text})> saved = [];

  @override
  Future<String?> openText({
    required String label,
    required List<String> extensions,
  }) async => nextOpen;

  @override
  Future<bool> saveText({
    required String suggestedName,
    required String text,
  }) async {
    saved.add((name: suggestedName, text: text));
    return true;
  }
}
```

Replace `test/helpers/app_harness.dart` with:
```dart
import 'package:fcm_studio/app/app.dart';
import 'package:fcm_studio/app/dependencies.dart';
import 'package:fcm_studio/core/platform/file_access.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/view/project_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fake_file_access.dart';
import 'fake_google.dart';
import 'fcm_fixtures.dart';
import 'presets_fixture.dart';
import 'service_account_fixture.dart';

/// Real async work (sembast, RSA signing, MockClient) runs inside `tester.runAsync`.
Future<AppDependencies> buildTestDependencies(
  WidgetTester tester, {
  http.Client? client,
  FileAccess? files,
}) async {
  final database = await tester.runAsync(AppDatabase.inMemory);
  return AppDependencies(
    httpClient: client ?? fakeGoogle(),
    database: database!,
    secrets: MemorySecretStore(),
    files: files ?? FakeFileAccess(),
    loadBuiltInPresets: loadBuiltInPresetsFromFile,
  );
}

Future<void> pumpApp(WidgetTester tester, AppDependencies dependencies) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(FcmStudioApp(dependencies: dependencies));
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Reads a cubit from the widget tree, through the always-present
/// ProjectSwitcher (also while another screen is in front).
T readCubit<T extends Cubit<Object?>>(WidgetTester tester) =>
    BlocProvider.of<T>(
      tester.element(find.byType(ProjectSwitcher, skipOffstage: false)),
    );

/// Adds the test project through the real cubit.
Future<ProjectsCubit> addTestProject(WidgetTester tester) async {
  final projects = readCubit<ProjectsCubit>(tester);
  await tester.runAsync(
    () =>
        projects.addFromServiceAccount(serviceAccountJson(), persistKey: true),
  );
  await tester.pump();
  return projects;
}

/// Pumps the app with the test project already added, and returns both cubits.
Future<(ProjectsCubit, ComposerCubit)> pumpAppWithProject(
  WidgetTester tester, {
  int fcmStatus = 200,
  String fcmBody = successBody,
  void Function(http.Request request)? onFcmRequest,
  FileAccess? files,
}) async {
  final dependencies = await buildTestDependencies(
    tester,
    client: fakeGoogle(
      fcmStatus: fcmStatus,
      fcmBody: fcmBody,
      onFcmRequest: onFcmRequest,
    ),
    files: files,
  );
  await pumpApp(tester, dependencies);
  final projects = await addTestProject(tester);
  return (projects, readCubit<ComposerCubit>(tester));
}

/// Lets real async work finish, then settles animations.
Future<void> settleAsync(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 50)),
  );
  await tester.pumpAndSettle();
}
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `flutter test`
Expected: everything passes. Then `flutter analyze` (No issues found!) and `flutter build web` (succeeds; `file_selector` and `cross_file` compile for web).

- [ ] **Step 7: Commit**

```bash
dart format lib test
git add pubspec.yaml lib/main.dart lib/app lib/core/platform/file_access.dart test/helpers test/app
git commit -m "feat: wire presets, targets and history into the app, with an error banner"
```

---

### Task 12: The Form tab and the Form/JSON tabs

The centre column becomes two tabs, Form and JSON, kept alive in an `IndexedStack`. The Form edits the template through `ComposerCubit`; the JSON editor follows those edits and answers "Show in JSON" requests (spec §5.3, §5.4, §8.2).

**Files:**
- Create: `lib/features/composer/view/form_fields.dart`, `lib/features/composer/view/data_entries_editor.dart`, `lib/features/composer/view/form_tab.dart`, `lib/features/composer/view/message_editor_tabs.dart`
- Modify: `lib/features/composer/view/json_template_editor.dart`, `lib/features/composer/view/composer_screen.dart`, `test/helpers/keyboard.dart`, `test/features/composer/composer_keyboard_test.dart`, `test/features/composer/composer_keyboard_macos_test.dart`, `test/features/composer/composer_screen_test.dart`
- Test: `test/features/composer/form_tab_test.dart`

**Interfaces:**
- Consumes: `ComposerCubit.setField`, `setDataOnly`, `setDataEntries`, `showField`, `ComposerState.jsonFocus` (Task 8); `TemplateEdits` (Task 2).
- Produces:
  - `SyncedTextField({required String label, required String value, required ValueChanged<String> onChanged, String? hint, int maxLines = 1, TextInputType? keyboardType, String? Function(String)? validator, Key? key})`.
  - `ChoiceField({required label, required value, required List<String> options, required ValueChanged<String> onChanged})` (an empty value means "Not set").
  - `FormSection({required String title, required List<Widget> children, Widget? trailing})`.
  - `String formText(Object? value)` (in `form_fields.dart`), `FormTab` (with `static const readOnlyMessage`), `DataEntriesEditor` (in `data_entries_editor.dart`, with `static const addKey`).
  - `MessageEditorTabs` with `static const formTabKey` and `jsonTabKey`. The Form tab is shown first.
  - Form field keys are `ValueKey('form-<path joined by .>')`, e.g. `ValueKey('form-notification.title')`. Data rows use `ValueKey('data-key-<i>')`, `data-value-<i>`, `data-up-<i>`, `data-down-<i>`, `data-remove-<i>`.

- [ ] **Step 1: Write the failing tests** `test/features/composer/form_tab_test.dart`

```dart
import 'package:fcm_studio/features/composer/domain/template_edits.dart';
import 'package:fcm_studio/features/composer/view/data_entries_editor.dart';
import 'package:fcm_studio/features/composer/view/form_tab.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:re_editor/re_editor.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/keyboard.dart';

void main() {
  Finder field(String path) => find.byKey(ValueKey('form-$path'));

  testWidgets('typing in the form updates the template and the JSON editor', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    await tester.enterText(field('notification.title'), 'Order shipped');
    await tester.pump();
    expect(
      TemplateEdits.read(composer.state.template!, ['notification', 'title']),
      'Order shipped',
    );
    expect(editorController(tester).text, contains('"title": "Order shipped"'));
  });

  testWidgets('fields the form does not cover are kept', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.updateTemplateText(
      '{"notification": {"title": "a"}, "fcm_options": {"analytics_label": "x"}}',
    );
    await tester.pump();
    await tester.enterText(field('notification.title'), 'b');
    await tester.pump();
    expect(composer.state.template!['fcm_options'], {'analytics_label': 'x'});
  });

  testWidgets('an edit in the JSON shows up in the form', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.updateTemplateText('{"notification": {"title": "From JSON"}}');
    await tester.pump();
    expect(
      find.descendant(
        of: field('notification.title'),
        matching: find.text('From JSON'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('switching to data only hides the notification fields', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    await tester.tap(find.text('Data only'));
    await tester.pump();
    expect(TemplateEdits.isDataOnly(composer.state.template!), isTrue);
    expect(
      TemplateEdits.read(composer.state.template!, ['android', 'priority']),
      'high',
    );
    expect(field('notification.title'), findsNothing);
  });

  testWidgets('invalid JSON makes the form read-only', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.updateTemplateText('{');
    await tester.pump();
    expect(find.text(FormTab.readOnlyMessage), findsOneWidget);
    expect(field('notification.title'), findsNothing);
  });

  testWidgets('a data key that already exists is refused and both entries are kept', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.updateTemplateText('{"data": {"a": "1", "b": "2"}}');
    await tester.pump();
    await tester.enterText(find.byKey(const ValueKey('data-key-1')), 'a');
    await tester.pump();
    expect(find.text('Duplicate key'), findsOneWidget);
    expect(composer.state.template!['data'], {'a': '1', 'b': '2'});
  });

  testWidgets('data rows can be added, moved and removed', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    List<String> keys() => TemplateEdits.dataEntries(
      composer.state.template!,
    ).map((e) => e.key).toList();
    composer.updateTemplateText('{"data": {"a": "1"}}');
    await tester.pump();

    await tester.tap(find.byKey(DataEntriesEditor.addKey));
    await tester.pump();
    expect(keys(), ['a', 'key']);

    await tester.tap(find.byKey(const ValueKey('data-up-1')));
    await tester.pump();
    expect(keys(), ['key', 'a']);

    await tester.tap(find.byKey(const ValueKey('data-remove-0')));
    await tester.pump();
    expect(composer.state.template!['data'], {'a': '1'});
  });

  testWidgets('Show in JSON switches to the JSON tab and selects the line', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.updateTemplateText('{\n  "data": {\n    "a": "1"\n  }\n}');
    await tester.pump();
    expect(find.byType(CodeEditor), findsNothing, reason: 'Form tab first');

    composer.showField('message.data[0].value');
    await tester.pump();
    await tester.pump();

    expect(find.byType(CodeEditor), findsOneWidget);
    expect(editorController(tester).selection.baseIndex, 2);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/composer/form_tab_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement the shared form widgets** `lib/features/composer/view/form_fields.dart`

```dart
import 'dart:convert';

import 'package:flutter/material.dart';

/// How a template value shows in a form field.
String formText(Object? value) => switch (value) {
  null => '',
  final String text => text,
  _ => jsonEncode(value),
};

/// A text field for a value the cubit owns. It follows changes made
/// elsewhere (the JSON tab, a loaded preset) without fighting the typing.
class SyncedTextField extends StatefulWidget {
  const SyncedTextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.hint,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    super.key,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  final String? hint;
  final int maxLines;
  final TextInputType? keyboardType;

  /// Returns an error to show under the field, or null.
  final String? Function(String text)? validator;

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  String? _error;

  @override
  void didUpdateWidget(SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only a change from outside replaces the text. The user's own edits come
    // back here unchanged, and a refused edit (e.g. a duplicate key) leaves
    // the value as it was, so the typed text stays with its error.
    if (widget.value != oldWidget.value && widget.value != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
      _error = null;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: _controller,
        minLines: 1,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        decoration: InputDecoration(
          labelText: widget.label,
          hintText: widget.hint,
          errorText: _error,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (text) {
          final error = widget.validator?.call(text);
          if (error != _error) {
            setState(() => _error = error);
          }
          widget.onChanged(text);
        },
      ),
    );
  }
}

/// A dropdown with a "Not set" choice (the empty value).
class ChoiceField extends StatelessWidget {
  const ChoiceField({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    super.key,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    // A value the list doesn't know (e.g. "{{priority}}") is still shown.
    final all = [
      ...options,
      if (value.isNotEmpty && !options.contains(value)) value,
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            isDense: true,
            isExpanded: true,
            value: value,
            items: [
              const DropdownMenuItem(value: '', child: Text('Not set')),
              for (final option in all)
                DropdownMenuItem(value: option, child: Text(option)),
            ],
            onChanged: (selected) => onChanged(selected ?? ''),
          ),
        ),
      ),
    );
  }
}

/// A titled group of form fields.
class FormSection extends StatelessWidget {
  const FormSection({
    required this.title,
    required this.children,
    this.trailing,
    super.key,
  });

  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              if (trailing case final widget?) widget,
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: Implement the Form tab**

`lib/features/composer/view/data_entries_editor.dart`:
```dart
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/view/form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The `data` key/value table: rows can be added, moved and removed.
class DataEntriesEditor extends StatelessWidget {
  const DataEntriesEditor({required this.entries, super.key});

  static const addKey = Key('data-add');

  final List<MapEntry<String, Object?>> entries;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<ComposerCubit>();
    void replace(List<MapEntry<String, Object?>> updated) =>
        cubit.setDataEntries(updated);
    List<MapEntry<String, Object?>> changed(
      int index,
      MapEntry<String, Object?> entry,
    ) => [...entries]..[index] = entry;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, entry) in entries.indexed)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SyncedTextField(
                  key: ValueKey('data-key-$index'),
                  label: 'Key',
                  value: entry.key,
                  validator: (key) => _keyProblem(key, index),
                  onChanged: (key) {
                    // A refused key is not applied, so no entry is lost.
                    if (_keyProblem(key, index) == null) {
                      replace(changed(index, MapEntry(key.trim(), entry.value)));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: SyncedTextField(
                  key: ValueKey('data-value-$index'),
                  label: 'Value',
                  value: formText(entry.value),
                  onChanged: (value) =>
                      replace(changed(index, MapEntry(entry.key, value))),
                ),
              ),
              IconButton(
                key: ValueKey('data-up-$index'),
                tooltip: 'Move up',
                icon: const Icon(Icons.arrow_upward),
                onPressed: index == 0 ? null : () => replace(_moved(index, -1)),
              ),
              IconButton(
                key: ValueKey('data-down-$index'),
                tooltip: 'Move down',
                icon: const Icon(Icons.arrow_downward),
                onPressed: index == entries.length - 1
                    ? null
                    : () => replace(_moved(index, 1)),
              ),
              IconButton(
                key: ValueKey('data-remove-$index'),
                tooltip: 'Remove',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => replace([...entries]..removeAt(index)),
              ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: addKey,
            onPressed: () => replace([...entries, MapEntry(_freeKey(), '')]),
            icon: const Icon(Icons.add),
            label: const Text('Add data field'),
          ),
        ),
      ],
    );
  }

  String? _keyProblem(String key, int index) {
    final trimmed = key.trim();
    if (trimmed.isEmpty) {
      return 'Enter a key';
    }
    for (final (i, entry) in entries.indexed) {
      if (i != index && entry.key == trimmed) {
        return 'Duplicate key';
      }
    }
    return null;
  }

  String _freeKey() {
    final keys = {for (final entry in entries) entry.key};
    if (!keys.contains('key')) {
      return 'key';
    }
    var n = 2;
    while (keys.contains('key_$n')) {
      n++;
    }
    return 'key_$n';
  }

  List<MapEntry<String, Object?>> _moved(int index, int delta) {
    final result = [...entries];
    final entry = result.removeAt(index);
    result.insert(index + delta, entry);
    return result;
  }
}
```

`lib/features/composer/view/form_tab.dart`:
```dart
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/template_edits.dart';
import 'package:fcm_studio/features/composer/view/data_entries_editor.dart';
import 'package:fcm_studio/features/composer/view/form_fields.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A structured editor for common fields (spec §5.3). Fields it doesn't
/// cover are kept unchanged in the template.
class FormTab extends StatelessWidget {
  const FormTab({super.key});

  static const readOnlyMessage =
      'The JSON has an error, so the form is read-only. Fix it in the JSON tab.';

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ComposerCubit, ComposerState>(
      buildWhen: (previous, current) => previous.template != current.template,
      builder: (context, state) {
        final template = state.template;
        if (template == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text(readOnlyMessage),
          );
        }
        final cubit = context.read<ComposerCubit>();
        final dataOnly = TemplateEdits.isDataOnly(template);

        Widget field(
          List<String> path,
          String label, {
          int maxLines = 1,
          String? hint,
          Object? Function(String text)? parse,
        }) => SyncedTextField(
          key: ValueKey('form-${path.join('.')}'),
          label: label,
          hint: hint,
          maxLines: maxLines,
          value: formText(TemplateEdits.read(template, path)),
          onChanged: (text) =>
              cubit.setField(path, parse == null ? text : parse(text)),
        );

        Widget choice(List<String> path, String label, List<String> options) =>
            ChoiceField(
              key: ValueKey('form-${path.join('.')}'),
              label: label,
              options: options,
              value: formText(TemplateEdits.read(template, path)),
              onChanged: (value) => cubit.setField(path, value),
            );

        Widget flag(List<String> path, String label, String subtitle) =>
            SwitchListTile(
              key: ValueKey('form-${path.join('.')}'),
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              subtitle: Text(subtitle),
              value: TemplateEdits.read(template, path) == 1,
              onChanged: (on) => cubit.setField(path, on ? 1 : null),
            );

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            FormSection(
              title: 'Message type',
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(
                      value: false,
                      label: Text('Notification + data'),
                    ),
                    ButtonSegment(value: true, label: Text('Data only')),
                  ],
                  selected: {dataOnly},
                  onSelectionChanged: (selection) =>
                      cubit.setDataOnly(selection.first),
                ),
              ],
            ),
            if (!dataOnly)
              FormSection(
                title: 'Notification',
                children: [
                  field(['notification', 'title'], 'Title'),
                  field(['notification', 'body'], 'Body', maxLines: 4),
                  field(
                    ['notification', 'image'],
                    'Image URL',
                    hint: 'https://…',
                  ),
                ],
              ),
            FormSection(
              title: 'Data',
              children: [
                DataEntriesEditor(entries: TemplateEdits.dataEntries(template)),
              ],
            ),
            FormSection(
              title: 'Android',
              children: [
                choice(['android', 'priority'], 'Priority', const [
                  'normal',
                  'high',
                ]),
                field(['android', 'ttl'], 'TTL', hint: 'e.g. 3600s'),
                field(['android', 'collapse_key'], 'Collapse key'),
                field(['android', 'notification', 'channel_id'], 'Channel ID'),
                field(
                  ['android', 'notification', 'sound'],
                  'Sound',
                  hint: 'default',
                ),
                field(
                  ['android', 'notification', 'click_action'],
                  'Click action',
                ),
              ],
            ),
            FormSection(
              title: 'APNs (iOS)',
              children: [
                choice(['apns', 'headers', 'apns-priority'], 'apns-priority', const [
                  '5',
                  '10',
                ]),
                field(['apns', 'payload', 'aps', 'sound'], 'Sound', hint: 'default'),
                field(
                  ['apns', 'payload', 'aps', 'badge'],
                  'Badge',
                  // A number stays a number; "{{badge}}" stays a placeholder.
                  parse: (text) => int.tryParse(text.trim()) ?? text,
                ),
                flag(
                  ['apns', 'payload', 'aps', 'content-available'],
                  'content-available',
                  'Wake the app in the background',
                ),
                flag(
                  ['apns', 'payload', 'aps', 'mutable-content'],
                  'mutable-content',
                  'Let a notification service extension change it',
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 5: Implement the tabs and make the JSON editor follow outside edits**

`lib/features/composer/view/message_editor_tabs.dart`:
```dart
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/view/form_tab.dart';
import 'package:fcm_studio/features/composer/view/json_template_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The Form and JSON tabs. Both stay alive, so switching keeps the editor's
/// cursor and undo history.
class MessageEditorTabs extends StatefulWidget {
  const MessageEditorTabs({super.key});

  static const formTabKey = Key('form-tab');
  static const jsonTabKey = Key('json-tab');

  @override
  State<MessageEditorTabs> createState() => _MessageEditorTabsState();
}

class _MessageEditorTabsState extends State<MessageEditorTabs>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(_onTabChanged);

  void _onTabChanged() => setState(() {});

  @override
  void dispose() {
    _tabs
      ..removeListener(_onTabChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ComposerCubit, ComposerState>(
      // "Show in JSON" brings the JSON tab to the front.
      listenWhen: (previous, current) =>
          current.jsonFocus != null && previous.jsonFocus != current.jsonFocus,
      listener: (context, state) => _tabs.index = 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TabBar(
            controller: _tabs,
            tabs: const [
              Tab(key: MessageEditorTabs.formTabKey, text: 'Form'),
              Tab(key: MessageEditorTabs.jsonTabKey, text: 'JSON'),
            ],
          ),
          Expanded(
            child: IndexedStack(
              index: _tabs.index,
              children: const [FormTab(), JsonTemplateEditor()],
            ),
          ),
        ],
      ),
    );
  }
}
```

Replace `lib/features/composer/view/json_template_editor.dart` with:
```dart
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

/// The JSON editor for the message template.
///
/// Every edit reaches the cubit immediately, so Send (or Cmd/Ctrl+Enter) right
/// after typing always sends what is on screen. Edits made elsewhere (the
/// Form tab, a loaded preset) replace the editor's text.
class JsonTemplateEditor extends StatefulWidget {
  const JsonTemplateEditor({super.key});

  @override
  State<JsonTemplateEditor> createState() => _JsonTemplateEditorState();
}

class _JsonTemplateEditorState extends State<JsonTemplateEditor> {
  late final CodeLineEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(
      context.read<ComposerCubit>().state.templateText,
    );
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    context.read<ComposerCubit>().updateTemplateText(_controller.text);
  }

  /// Selects [line] (1-based) once the tab switch has put the editor on screen.
  void _showLine(int line) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _focusNode.requestFocus();
      _controller.selectLine(line - 1);
    });
  }

  @override
  void dispose() {
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return MultiBlocListener(
      listeners: [
        BlocListener<ComposerCubit, ComposerState>(
          listenWhen: (previous, current) =>
              previous.templateText != current.templateText,
          listener: (context, state) {
            if (state.templateText != _controller.text) {
              _controller.text = state.templateText;
            }
          },
        ),
        BlocListener<ComposerCubit, ComposerState>(
          listenWhen: (previous, current) =>
              current.jsonFocus != null &&
              previous.jsonFocus != current.jsonFocus,
          listener: (context, state) => _showLine(state.jsonFocus!.line),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(
              'Message JSON (the FCM "message" object, without the target)',
              style: theme.textTheme.titleSmall,
            ),
          ),
          Expanded(
            child: CodeEditor(
              controller: _controller,
              focusNode: _focusNode,
              shortcutsActivatorsBuilder: const _ComposerKeyFreeShortcuts(),
              style: CodeEditorStyle(
                fontSize: 13,
                codeTheme: CodeHighlightTheme(
                  languages: {'json': CodeHighlightThemeMode(mode: langJson)},
                  theme: dark ? atomOneDarkTheme : atomOneLightTheme,
                ),
              ),
            ),
          ),
          BlocSelector<ComposerCubit, ComposerState, String?>(
            selector: (state) => state.jsonError,
            builder: (context, error) => error == null
                ? const SizedBox.shrink()
                : Container(
                    width: double.infinity,
                    color: theme.colorScheme.errorContainer,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Text(
                      error,
                      style: TextStyle(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// re_editor's default shortcuts, minus the keys the composer screen uses:
/// Cmd/Ctrl+Enter ("new line" in re_editor) sends.
class _ComposerKeyFreeShortcuts extends DefaultCodeShortcutsActivatorsBuilder {
  const _ComposerKeyFreeShortcuts();

  static bool _isSendKey(ShortcutActivator activator) =>
      activator is SingleActivator &&
      (activator.meta || activator.control) &&
      (activator.trigger == LogicalKeyboardKey.enter ||
          activator.trigger == LogicalKeyboardKey.numpadEnter);

  @override
  List<ShortcutActivator>? build(CodeShortcutType type) {
    final activators = super.build(type);
    if (type != CodeShortcutType.newLine || activators == null) {
      return activators;
    }
    return activators.where((activator) => !_isSendKey(activator)).toList();
  }
}
```

In `lib/features/composer/view/composer_screen.dart`, replace the import of `json_template_editor.dart` with `import 'package:fcm_studio/features/composer/view/message_editor_tabs.dart';`, replace `Expanded(child: JsonTemplateEditor()),` in the wide layout with `Expanded(child: MessageEditorTabs()),`, and in the narrow layout use these tabs and children:
```dart
                    TabBar(
                      tabs: [
                        Tab(text: 'Setup'),
                        Tab(text: 'Message'),
                        Tab(text: 'Preview & result'),
                      ],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _SetupPane(),
                          MessageEditorTabs(),
                          _OutputPane(),
                        ],
                      ),
                    ),
```

- [ ] **Step 6: Update the existing tests for the Form tab coming first**

In `test/helpers/keyboard.dart`, find the editor even while the JSON tab is hidden:
```dart
CodeLineEditingController editorController(WidgetTester tester) => tester
    .widget<CodeEditor>(find.byType(CodeEditor, skipOffstage: false))
    .controller!;

/// Brings the JSON tab to the front.
Future<void> showJsonTab(WidgetTester tester) async {
  await tester.tap(find.byKey(MessageEditorTabs.jsonTabKey));
  await tester.pump();
}
```
(add `import 'package:fcm_studio/features/composer/view/message_editor_tabs.dart';` to that file).

In `test/features/composer/composer_keyboard_test.dart` and `test/features/composer/composer_keyboard_macos_test.dart`, add `await showJsonTab(tester);` on the line before `await tester.tap(find.byType(CodeEditor));`.

In `test/features/composer/composer_screen_test.dart`, in "invalid JSON shows the error and disables Send", add `await showJsonTab(tester);` after `await tester.pump();` and import `'../../helpers/keyboard.dart'`.

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `flutter test test/features/composer`
Expected: PASS, including the 8 new Form tests and the updated keyboard and screen tests. Then `flutter test` and `flutter analyze` (No issues found!).

- [ ] **Step 8: Commit**

```bash
dart format lib test
git add lib/features/composer/view test/helpers/keyboard.dart test/features/composer
git commit -m "feat: add the Form tab, kept in sync with the JSON editor"
```

---

### Task 13: Variables, preset picking and saving, Cmd/Ctrl+S

**Files:**
- Create: `lib/features/composer/view/variables_section.dart`, `lib/features/presets/view/variables_dialog.dart`, `lib/features/presets/view/preset_details_dialog.dart`, `lib/features/presets/view/preset_actions.dart`, `lib/features/presets/view/preset_picker.dart`
- Modify: `lib/features/composer/view/form_tab.dart`, `lib/features/composer/view/json_template_editor.dart`, `lib/features/composer/view/composer_screen.dart`
- Test: `test/features/composer/variables_test.dart`, `test/features/presets/preset_picker_test.dart`, `test/features/composer/composer_keyboard_test.dart`

**Interfaces:**
- Consumes: `ComposerCubit.loadPreset`, `presetSaved`, `setVariables`, `setVariableValue`, `addMissingVariables`, `ComposerState.isDirty`, `preset`, `variables`, `values`, `render.undefinedPlaceholders` (Task 8); `PresetsCubit` (Task 9); `AppErrorCubit` (Task 11); `VariableDef`/`VariableType` (Task 1); `SyncedTextField`, `ChoiceField`, `FormSection` (Task 12).
- Produces:
  - `VariablesSection` with `static const editKey` and `addMissingKey`; variable inputs keyed `ValueKey('variable-<key>')`.
  - `Future<List<VariableDef>?> showVariablesDialog(BuildContext, List<VariableDef>)` and `VariablesDialog`. Row fields are keyed `ValueKey('variable-key-<i>')`, `variable-label-<i>`, `variable-type-<i>`, `variable-default-<i>`, `variable-options-<i>`; buttons `Key('variable-add')`, `Key('variables-save')`.
  - `typedef PresetDetails = ({String name, String description});`, `Future<PresetDetails?> showPresetDetailsDialog(BuildContext, {required String title, required bool Function(String) isNameTaken, String name = '', String description = ''})`, and `PresetDetailsDialog` with `nameKey`, `descriptionKey`, `saveKey`.
  - In `preset_actions.dart`: `Future<bool> openPreset(BuildContext, Preset)`, `Future<bool> confirmDiscardChanges(BuildContext)`, `Future<void> savePreset(BuildContext)`, `Future<void> savePresetAs(BuildContext)`, `Future<void> updatePreset(BuildContext)`.
  - `PresetPicker` with `dropdownKey`, `saveAsKey`, `updateKey`. A loaded preset with unsaved changes shows as `• <name>`.

- [ ] **Step 1: Write the failing tests**

`test/features/composer/variables_test.dart`:
```dart
import 'package:fcm_studio/features/composer/view/variables_section.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:fcm_studio/features/presets/view/variables_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  testWidgets('the quick fix defines placeholders that have no variable', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.updateTemplateText(
      '{"notification": {"title": "Order {{order_id}}"}}',
    );
    await tester.pump();
    expect(
      find.textContaining('{{order_id}} without a definition'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(VariablesSection.addMissingKey));
    await tester.pump();
    expect(composer.state.variables.single.key, 'order_id');

    await tester.enterText(
      find.byKey(const ValueKey('variable-order_id')),
      '42',
    );
    await tester.pump();
    expect(find.textContaining('"title": "Order 42"'), findsOneWidget);
  });

  testWidgets('each variable type gets its own input', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.setVariables(const [
      VariableDef(key: 'on', type: VariableType.boolean),
      VariableDef(
        key: 'size',
        type: VariableType.enumeration,
        options: ['s', 'l'],
      ),
      VariableDef(key: 'note', type: VariableType.multiline),
    ]);
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('variable-on')),
        matching: find.byType(Switch),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('variable-size')),
        matching: find.byType(DropdownButton<String>),
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('variable-on')));
    await tester.pump();
    expect(composer.state.values['on'], 'true');
  });

  testWidgets('the variables dialog adds a number variable', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    await tester.tap(find.byKey(VariablesSection.editKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('variable-add')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('variable-key-0')),
      'badge',
    );
    await tester.tap(find.byKey(const ValueKey('variable-type-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Number').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('variables-save')));
    await tester.pumpAndSettle();

    expect(
      composer.state.variables.single,
      const VariableDef(key: 'badge', type: VariableType.number),
    );
  });

  testWidgets('the variables dialog refuses a duplicate key', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    await tester.tap(find.byKey(VariablesSection.editKey));
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const Key('variable-add')));
      await tester.pump();
      await tester.enterText(find.byKey(ValueKey('variable-key-$i')), 'a');
    }
    await tester.tap(find.byKey(const Key('variables-save')));
    await tester.pump();

    expect(find.text('The key "a" is used twice.'), findsOneWidget);
    expect(find.byType(VariablesDialog), findsOneWidget);
    expect(composer.state.variables, isEmpty);
  });
}
```

`test/features/presets/preset_picker_test.dart`:
```dart
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/view/preset_details_dialog.dart';
import 'package:fcm_studio/features/presets/view/preset_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  Future<void> pickPreset(WidgetTester tester, String label) async {
    await tester.tap(find.byKey(PresetPicker.dropdownKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  testWidgets('picking a built-in preset loads its template and variables', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    await pickPreset(tester, 'Simple notification (built-in)');
    expect(composer.state.preset?.id, 'builtin.simple');
    expect(find.byKey(const ValueKey('variable-title')), findsOneWidget);
    expect(find.text('Hello from FCM Studio'), findsWidgets);
  });

  testWidgets('an edit shows the dot; Save as stores a preset and clears it', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final presets = readCubit<PresetsCubit>(tester);
    composer
      ..loadPreset(presets.state.byId('builtin.simple')!)
      ..setField(['notification', 'body'], 'Changed');
    await tester.pump();
    expect(find.text('• Simple notification (built-in)'), findsOneWidget);

    await tester.tap(find.byKey(PresetPicker.saveAsKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(PresetDetailsDialog.nameKey),
      'My order message',
    );
    await tester.tap(find.byKey(PresetDetailsDialog.saveKey));
    await settleAsync(tester);

    expect(presets.state.userPresets.single.name, 'My order message');
    expect(composer.state.preset?.name, 'My order message');
    expect(composer.state.isDirty, isFalse);
    expect(find.text('My order message'), findsOneWidget);
  });

  testWidgets('Save as refuses a name that is already used', (tester) async {
    await pumpAppWithProject(tester);
    await tester.tap(find.byKey(PresetPicker.saveAsKey));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(PresetDetailsDialog.nameKey),
      'simple notification',
    );
    await tester.tap(find.byKey(PresetDetailsDialog.saveKey));
    await tester.pump();
    expect(
      find.text('A preset named "simple notification" already exists.'),
      findsOneWidget,
    );
  });

  testWidgets('Update preset is off for built-ins and overwrites a user preset', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final presets = readCubit<PresetsCubit>(tester);
    OutlinedButton update() =>
        tester.widget<OutlinedButton>(find.byKey(PresetPicker.updateKey));

    composer
      ..loadPreset(presets.state.byId('builtin.simple')!)
      ..setField(['notification', 'body'], 'Changed');
    await tester.pump();
    expect(update().onPressed, isNull);

    final mine = (await tester.runAsync(
      () => presets.saveAs(
        name: 'Mine',
        template: const {
          'notification': {'title': 'A'},
        },
        variables: const [],
      ),
    ))!;
    composer
      ..loadPreset(mine)
      ..setField(['notification', 'title'], 'B');
    await tester.pump();
    expect(update().onPressed, isNotNull);

    await tester.tap(find.byKey(PresetPicker.updateKey));
    await settleAsync(tester);
    expect(presets.state.userPresets.single.template, {
      'notification': {'title': 'B'},
    });
    expect(composer.state.isDirty, isFalse);
  });

  testWidgets('switching presets with unsaved changes asks first', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final presets = readCubit<PresetsCubit>(tester);
    composer
      ..loadPreset(presets.state.byId('builtin.simple')!)
      ..setField(['notification', 'body'], 'Changed');
    await tester.pump();

    await pickPreset(tester, 'Data only (silent / background) (built-in)');
    expect(find.text('Discard unsaved changes?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(composer.state.preset?.id, 'builtin.simple');

    await pickPreset(tester, 'Data only (silent / background) (built-in)');
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(composer.state.preset?.id, 'builtin.data_only');
  });
}
```

Add to `test/features/composer/composer_keyboard_test.dart` (imports: `package:fcm_studio/features/presets/cubit/presets_cubit.dart`):
```dart
  testWidgets(
    'Ctrl+S updates the loaded user preset, even from inside the JSON editor',
    (tester) async {
      final (_, composer) = await pumpAppWithProject(tester);
      final presets = readCubit<PresetsCubit>(tester);
      final mine = (await tester.runAsync(
        () => presets.saveAs(
          name: 'Mine',
          template: const {
            'notification': {'title': 'A'},
          },
          variables: const [],
        ),
      ))!;
      composer
        ..loadPreset(mine)
        ..setField(['notification', 'title'], 'B');
      await tester.pump();
      await showJsonTab(tester);
      await tester.tap(find.byType(CodeEditor));
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await settleAsync(tester);

      expect(presets.state.userPresets.single.template, {
        'notification': {'title': 'B'},
      });
      expect(composer.state.isDirty, isFalse);
    },
    variant: _windows,
  );
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/composer/variables_test.dart test/features/presets/preset_picker_test.dart test/features/composer/composer_keyboard_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement the variables UI**

`lib/features/presets/view/variables_dialog.dart`:
```dart
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:flutter/material.dart';

Future<List<VariableDef>?> showVariablesDialog(
  BuildContext context,
  List<VariableDef> variables,
) => showDialog<List<VariableDef>>(
  context: context,
  builder: (_) => VariablesDialog(initial: variables),
);

/// Adds, edits and removes variable definitions (spec §6).
class VariablesDialog extends StatefulWidget {
  const VariablesDialog({required this.initial, super.key});

  final List<VariableDef> initial;

  @override
  State<VariablesDialog> createState() => _VariablesDialogState();
}

/// One editable row.
class _Draft {
  _Draft([VariableDef? variable])
    : key = TextEditingController(text: variable?.key ?? ''),
      label = TextEditingController(text: variable?.label ?? ''),
      defaultValue = TextEditingController(text: variable?.defaultValue ?? ''),
      options = TextEditingController(text: variable?.options.join(', ') ?? ''),
      type = variable?.type ?? VariableType.text,
      required = variable?.required ?? false;

  final TextEditingController key;
  final TextEditingController label;
  final TextEditingController defaultValue;
  final TextEditingController options;
  VariableType type;
  bool required;

  VariableDef toVariable() {
    final keyText = key.text.trim();
    final labelText = label.text.trim();
    return VariableDef(
      key: keyText,
      label: labelText.isEmpty ? keyText : labelText,
      type: type,
      options: type == VariableType.enumeration
          ? [
              for (final option in options.text.split(','))
                if (option.trim().isNotEmpty) option.trim(),
            ]
          : const [],
      required: required,
      defaultValue: defaultValue.text,
    );
  }

  void dispose() {
    key.dispose();
    label.dispose();
    defaultValue.dispose();
    options.dispose();
  }
}

class _VariablesDialogState extends State<VariablesDialog> {
  late final List<_Draft> _drafts = [
    for (final variable in widget.initial) _Draft(variable),
  ];
  String? _error;

  @override
  void dispose() {
    for (final draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  void _remove(int index) {
    final draft = _drafts[index];
    setState(() => _drafts.removeAt(index));
    // Its text fields are still mounted until the next frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => draft.dispose());
  }

  void _save() {
    final variables = [for (final draft in _drafts) draft.toVariable()];
    final keys = <String>{};
    for (final variable in variables) {
      final problem =
          variable.problem ??
          (keys.add(variable.key)
              ? null
              : 'The key "${variable.key}" is used twice.');
      if (problem != null) {
        setState(() => _error = problem);
        return;
      }
    }
    Navigator.of(context).pop(variables);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    return AlertDialog(
      title: const Text('Variables'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use a variable in the message as {{key}}.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final (index, draft) in _drafts.indexed)
                _DraftRow(
                  index: index,
                  draft: draft,
                  onChanged: () => setState(() {}),
                  onRemove: () => _remove(index),
                ),
              TextButton.icon(
                key: const Key('variable-add'),
                onPressed: () => setState(() => _drafts.add(_Draft())),
                icon: const Icon(Icons.add),
                label: const Text('Add variable'),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    error,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('variables-save'),
          onPressed: _save,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.index,
    required this.draft,
    required this.onChanged,
    required this.onRemove,
  });

  final int index;
  final _Draft draft;
  final VoidCallback onChanged;
  final VoidCallback onRemove;

  static String _typeLabel(VariableType type) => switch (type) {
    VariableType.text => 'Text',
    VariableType.multiline => 'Multi-line text',
    VariableType.number => 'Number',
    VariableType.boolean => 'On/off',
    VariableType.enumeration => 'Choice list',
  };

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: 140,
              child: TextField(
                key: ValueKey('variable-key-$index'),
                controller: draft.key,
                decoration: const InputDecoration(
                  labelText: 'Key',
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                key: ValueKey('variable-label-$index'),
                controller: draft.label,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  isDense: true,
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: DropdownButton<VariableType>(
                key: ValueKey('variable-type-$index'),
                isExpanded: true,
                value: draft.type,
                items: [
                  for (final type in VariableType.values)
                    DropdownMenuItem(value: type, child: Text(_typeLabel(type))),
                ],
                onChanged: (type) {
                  if (type != null) {
                    draft.type = type;
                    onChanged();
                  }
                },
              ),
            ),
            SizedBox(
              width: 160,
              child: TextField(
                key: ValueKey('variable-default-$index'),
                controller: draft.defaultValue,
                decoration: const InputDecoration(
                  labelText: 'Default',
                  isDense: true,
                ),
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: draft.required,
                  onChanged: (value) {
                    draft.required = value ?? false;
                    onChanged();
                  },
                ),
                const Text('Required'),
              ],
            ),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
              onPressed: onRemove,
            ),
            if (draft.type == VariableType.enumeration)
              SizedBox(
                width: 600,
                child: TextField(
                  key: ValueKey('variable-options-$index'),
                  controller: draft.options,
                  decoration: const InputDecoration(
                    labelText: 'Options, separated by commas',
                    isDense: true,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
```

`lib/features/composer/view/variables_section.dart`:
```dart
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/view/form_fields.dart';
import 'package:fcm_studio/features/presets/domain/variable_def.dart';
import 'package:fcm_studio/features/presets/view/variables_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The Form tab's Variables section: one input per variable, and a quick fix
/// for placeholders that have no definition (spec §5.3, §6).
class VariablesSection extends StatelessWidget {
  const VariablesSection({super.key});

  static const editKey = Key('variables-edit');
  static const addMissingKey = Key('variables-add-missing');

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ComposerCubit, ComposerState>(
      buildWhen: (previous, current) =>
          previous.variables != current.variables ||
          previous.values != current.values ||
          previous.render.undefinedPlaceholders !=
              current.render.undefinedPlaceholders,
      builder: (context, state) {
        final cubit = context.read<ComposerCubit>();
        final undefined = state.render.undefinedPlaceholders;
        return FormSection(
          title: 'Variables',
          trailing: TextButton.icon(
            key: editKey,
            onPressed: () => _edit(context),
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Edit variables…'),
          ),
          children: [
            if (undefined.isNotEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.lightbulb_outline),
                  title: Text(
                    'The message uses '
                    '${undefined.map((key) => '{{$key}}').join(', ')} '
                    'without a definition.',
                  ),
                  trailing: TextButton(
                    key: addMissingKey,
                    onPressed: cubit.addMissingVariables,
                    child: const Text('Add as variables'),
                  ),
                ),
              ),
            if (state.variables.isEmpty && undefined.isEmpty)
              Text(
                'No variables. Use {{name}} in the message to add one.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            for (final variable in state.variables)
              VariableInput(
                variable: variable,
                value: state.values[variable.key] ?? variable.defaultValue,
                onChanged: (value) =>
                    cubit.setVariableValue(variable.key, value),
              ),
          ],
        );
      },
    );
  }

  Future<void> _edit(BuildContext context) async {
    final cubit = context.read<ComposerCubit>();
    final updated = await showVariablesDialog(context, cubit.state.variables);
    if (updated != null) {
      cubit.setVariables(updated);
    }
  }
}

/// The input for one variable, by its type.
class VariableInput extends StatelessWidget {
  const VariableInput({
    required this.variable,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final VariableDef variable;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = variable.required ? '${variable.label} *' : variable.label;
    final fieldKey = ValueKey('variable-${variable.key}');
    switch (variable.type) {
      case VariableType.text:
        return SyncedTextField(
          key: fieldKey,
          label: label,
          value: value,
          onChanged: onChanged,
        );
      case VariableType.multiline:
        return SyncedTextField(
          key: fieldKey,
          label: label,
          value: value,
          onChanged: onChanged,
          maxLines: 4,
        );
      case VariableType.number:
        return SyncedTextField(
          key: fieldKey,
          label: label,
          value: value,
          onChanged: onChanged,
          keyboardType: TextInputType.number,
        );
      case VariableType.boolean:
        return SwitchListTile(
          key: fieldKey,
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          value: value == 'true',
          onChanged: (on) => onChanged('$on'),
        );
      case VariableType.enumeration:
        return ChoiceField(
          key: fieldKey,
          label: label,
          value: value,
          options: variable.options,
          onChanged: onChanged,
        );
    }
  }
}
```

In `lib/features/composer/view/form_tab.dart`, import `package:fcm_studio/features/composer/view/variables_section.dart` and make `const VariablesSection(),` the first child of the `ListView`.

- [ ] **Step 4: Implement preset picking and saving**

`lib/features/presets/view/preset_details_dialog.dart`:
```dart
import 'package:flutter/material.dart';

typedef PresetDetails = ({String name, String description});

Future<PresetDetails?> showPresetDetailsDialog(
  BuildContext context, {
  required String title,
  required bool Function(String name) isNameTaken,
  String name = '',
  String description = '',
}) => showDialog<PresetDetails>(
  context: context,
  builder: (_) => PresetDetailsDialog(
    title: title,
    isNameTaken: isNameTaken,
    name: name,
    description: description,
  ),
);

/// Asks for a preset's name and description. Names must be unique.
class PresetDetailsDialog extends StatefulWidget {
  const PresetDetailsDialog({
    required this.title,
    required this.isNameTaken,
    this.name = '',
    this.description = '',
    super.key,
  });

  static const nameKey = Key('preset-name');
  static const descriptionKey = Key('preset-description');
  static const saveKey = Key('preset-details-save');

  final String title;
  final bool Function(String name) isNameTaken;
  final String name;
  final String description;

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
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    super.dispose();
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
    Navigator.of(
      context,
    ).pop((name: name, description: _description.text.trim()));
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

`lib/features/presets/view/preset_actions.dart`:
```dart
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/view/preset_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Loads [preset] into the composer, asking first when the loaded preset has
/// unsaved changes. Returns false when the user keeps editing.
Future<bool> openPreset(BuildContext context, Preset preset) async {
  final composer = context.read<ComposerCubit>();
  if (composer.state.isDirty && !await confirmDiscardChanges(context)) {
    return false;
  }
  composer.loadPreset(preset);
  return true;
}

Future<bool> confirmDiscardChanges(BuildContext context) async {
  final name = context.read<ComposerCubit>().state.preset?.name;
  final discard = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discard unsaved changes?'),
      content: Text(
        'Your changes to ${name == null ? 'this message' : '"$name"'} are not saved.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep editing'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Discard'),
        ),
      ],
    ),
  );
  return discard ?? false;
}

/// Cmd/Ctrl+S: updates the loaded user preset, or asks for a name.
Future<void> savePreset(BuildContext context) {
  final preset = context.read<ComposerCubit>().state.preset;
  return preset != null && !preset.builtIn
      ? updatePreset(context)
      : savePresetAs(context);
}

/// "Save as preset": a new preset from the composer's template and variables.
Future<void> savePresetAs(BuildContext context) async {
  final composer = context.read<ComposerCubit>();
  final presets = context.read<PresetsCubit>();
  final errors = context.read<AppErrorCubit>();
  final template = composer.state.template;
  if (template == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fix the JSON before saving it as a preset.')),
    );
    return;
  }
  final details = await showPresetDetailsDialog(
    context,
    title: 'Save as preset',
    isNameTaken: presets.state.nameTaken,
  );
  if (details == null) {
    return;
  }
  try {
    final saved = await presets.saveAs(
      name: details.name,
      description: details.description,
      template: template,
      variables: composer.state.variables,
    );
    composer.presetSaved(saved);
  } catch (e) {
    errors.report(e, context: 'Could not save the preset');
  }
}

/// "Update preset": overwrites the loaded user preset.
Future<void> updatePreset(BuildContext context) async {
  final composer = context.read<ComposerCubit>();
  final presets = context.read<PresetsCubit>();
  final errors = context.read<AppErrorCubit>();
  final preset = composer.state.preset;
  final template = composer.state.template;
  if (preset == null || preset.builtIn || template == null) {
    return;
  }
  try {
    final updated = await presets.update(
      preset,
      template: template,
      variables: composer.state.variables,
    );
    composer.presetSaved(updated);
  } catch (e) {
    errors.report(e, context: 'Could not update the preset');
  }
}
```

`lib/features/presets/view/preset_picker.dart`:
```dart
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/view/preset_actions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The composer's preset picker, with Save as and Update (spec §5.5, §6).
class PresetPicker extends StatelessWidget {
  const PresetPicker({super.key});

  static const dropdownKey = Key('preset-dropdown');
  static const saveAsKey = Key('preset-save-as');
  static const updateKey = Key('preset-update');

  static String _label(Preset preset) =>
      preset.builtIn ? '${preset.name} (built-in)' : preset.name;

  @override
  Widget build(BuildContext context) {
    final presets = context.watch<PresetsCubit>().state;
    return BlocBuilder<ComposerCubit, ComposerState>(
      buildWhen: (previous, current) =>
          previous.preset != current.preset ||
          previous.isDirty != current.isDirty,
      builder: (context, composer) {
        final current = composer.preset;
        final selectedId = current != null && presets.byId(current.id) != null
            ? current.id
            : null;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Preset', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            DropdownButton<String>(
              key: dropdownKey,
              isExpanded: true,
              hint: const Text('No preset'),
              value: selectedId,
              items: [
                for (final preset in presets.all)
                  DropdownMenuItem(
                    value: preset.id,
                    child: Text(
                      _label(preset),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              // The dot marks unsaved changes (spec §6).
              selectedItemBuilder: (context) => [
                for (final preset in presets.all)
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(
                      preset.id == selectedId && composer.isDirty
                          ? '• ${_label(preset)}'
                          : _label(preset),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: (id) {
                final preset = id == null ? null : presets.byId(id);
                if (preset != null) {
                  openPreset(context, preset);
                }
              },
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: saveAsKey,
                  onPressed: () => savePresetAs(context),
                  child: const Text('Save as preset…'),
                ),
                OutlinedButton(
                  key: updateKey,
                  onPressed:
                      current != null && !current.builtIn && composer.isDirty
                      ? () => updatePreset(context)
                      : null,
                  child: const Text('Update preset'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 5: Add the picker and Cmd/Ctrl+S to the composer**

In `lib/features/composer/view/composer_screen.dart`:
- import `package:fcm_studio/features/presets/view/preset_actions.dart` and `package:fcm_studio/features/presets/view/preset_picker.dart`;
- add these two entries to the `bindings` map of `CallbackShortcuts`:
```dart
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            savePreset(context),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            savePreset(context),
```
- make `_SetupPane` build:
```dart
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ProjectSwitcher(),
        SizedBox(height: 24),
        TargetPicker(),
        SizedBox(height: 24),
        PresetPicker(),
      ],
    );
```

In `lib/features/composer/view/json_template_editor.dart`, re_editor binds Cmd/Ctrl+S to its own "save" intent. Free it for the screen by making `_ComposerKeyFreeShortcuts.build` start with:
```dart
    // Cmd/Ctrl+S saves the preset (composer screen shortcut).
    if (type == CodeShortcutType.save) {
      return null;
    }
```
and update its doc comment to mention Cmd/Ctrl+S.

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `flutter test test/features/composer test/features/presets`
Expected: PASS. Then `flutter test` and `flutter analyze` (No issues found!).

- [ ] **Step 7: Commit**

```bash
dart format lib test
git add lib/features/composer/view lib/features/presets/view test/features/composer test/features/presets
git commit -m "feat: fill in variables, pick and save presets, Cmd/Ctrl+S to save"
```

---

### Task 14: Target autocomplete and the save-target star

**Files:**
- Create: `lib/app/widgets/prompt_dialog.dart`
- Modify: `lib/features/composer/view/target_picker.dart`
- Test: `test/features/composer/target_picker_test.dart`

**Interfaces:**
- Consumes: `TargetsCubit`, `SavedTarget.orderFor`, `defaultLabel`, `displayValue` (Tasks 5, 10); `ComposerCubit.setTarget`, `ComposerState.target` (Task 8); `ProjectsCubit` (existing); `AppErrorCubit` (Task 11).
- Produces:
  - `Future<String?> promptForText(BuildContext, {required String title, required String label, String initial = '', String confirmLabel = 'Save'})` and `PromptDialog` with `fieldKey` and `confirmKey`.
  - `TargetPicker` with `static const fieldKey = Key('target-field')` and `starKey = Key('save-target')`. Suggestions are `ListTile`s keyed `ValueKey('target-suggestion-<id>')`.

- [ ] **Step 1: Write the failing tests** `test/features/composer/target_picker_test.dart`

```dart
import 'package:fcm_studio/app/widgets/prompt_dialog.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/composer/view/target_picker.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';

void main() {
  const token = 'fAbC12345678909xYz';

  Finder starIcon(IconData icon) => find.descendant(
    of: find.byKey(TargetPicker.starKey),
    matching: find.byIcon(icon),
  );

  testWidgets('the star saves the current target with a label', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final targets = readCubit<TargetsCubit>(tester);
    composer.setTargetValue(token);
    await tester.pump();
    expect(starIcon(Icons.star_border), findsOneWidget);

    await tester.tap(find.byKey(TargetPicker.starKey));
    await tester.pumpAndSettle();
    expect(find.text('Token fAbC12…9xYz'), findsOneWidget);
    await tester.enterText(find.byKey(PromptDialog.fieldKey), 'Redmi debug');
    await tester.tap(find.byKey(PromptDialog.confirmKey));
    await settleAsync(tester);

    expect(targets.state.targets.single.label, 'Redmi debug');
    expect(targets.state.targets.single.projectId, 'demo-project');
    expect(starIcon(Icons.star), findsOneWidget);
  });

  testWidgets('tapping a filled star removes the saved target', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final targets = readCubit<TargetsCubit>(tester);
    await tester.runAsync(
      () => targets.save(const TokenTarget(token), label: 'Redmi'),
    );
    composer.setTargetValue(token);
    await tester.pump();
    expect(starIcon(Icons.star), findsOneWidget);

    await tester.tap(find.byKey(TargetPicker.starKey));
    await settleAsync(tester);
    expect(targets.state.targets, isEmpty);
    expect(starIcon(Icons.star_border), findsOneWidget);
  });

  testWidgets('suggestions put the current project first and fill the target', (
    tester,
  ) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final targets = readCubit<TargetsCubit>(tester);
    await tester.runAsync(() async {
      await targets.save(
        const TokenTarget(token),
        label: 'Phone A',
        projectId: 'demo-project',
      );
      await targets.save(
        const TopicTarget('other-news'),
        label: 'Phone B',
        projectId: 'other-project',
      );
    });
    await tester.pump();

    await tester.enterText(find.byKey(TargetPicker.fieldKey), 'phone');
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Phone A')).dy,
      lessThan(tester.getTopLeft(find.text('Phone B')).dy),
    );

    await tester.tap(find.text('Phone B'));
    await tester.pumpAndSettle();
    expect(composer.state.targetKind, TargetKind.topic);
    expect(composer.state.targetValue, 'other-news');
    expect(
      find.descendant(
        of: find.byKey(TargetPicker.fieldKey),
        matching: find.text('other-news'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('a target set from elsewhere shows in the field', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.setTarget(TargetKind.topic, 'news');
    await tester.pump();
    expect(
      find.descendant(
        of: find.byKey(TargetPicker.fieldKey),
        matching: find.text('news'),
      ),
      findsOneWidget,
    );
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/composer/target_picker_test.dart`
Expected: FAIL, compilation errors (`prompt_dialog.dart`, `TargetPicker.starKey` don't exist).

- [ ] **Step 3: Implement**

`lib/app/widgets/prompt_dialog.dart`:
```dart
import 'package:flutter/material.dart';

/// Asks for one line of text. Returns null when cancelled.
Future<String?> promptForText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String confirmLabel = 'Save',
}) => showDialog<String>(
  context: context,
  builder: (_) => PromptDialog(
    title: title,
    label: label,
    initial: initial,
    confirmLabel: confirmLabel,
  ),
);

class PromptDialog extends StatefulWidget {
  const PromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.confirmLabel,
    super.key,
  });

  static const fieldKey = Key('prompt-field');
  static const confirmKey = Key('prompt-confirm');

  final String title;
  final String label;
  final String initial;
  final String confirmLabel;

  @override
  State<PromptDialog> createState() => _PromptDialogState();
}

class _PromptDialogState extends State<PromptDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  )..selection = TextSelection(baseOffset: 0, extentOffset: widget.initial.length);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 380,
        child: TextField(
          key: PromptDialog.fieldKey,
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(labelText: widget.label),
          onSubmitted: (text) => Navigator.of(context).pop(text),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: PromptDialog.confirmKey,
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
```

Replace `lib/features/composer/view/target_picker.dart` with:
```dart
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/widgets/prompt_dialog.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Token / Topic / Condition, an autocomplete from saved targets, and the
/// star that saves the current target (spec §5.5, §7.1).
class TargetPicker extends StatefulWidget {
  const TargetPicker({super.key});

  static const fieldKey = Key('target-field');
  static const starKey = Key('save-target');

  @override
  State<TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends State<TargetPicker> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: context.read<ComposerCubit>().state.targetValue,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Iterable<SavedTarget> _suggestions(String text) {
    final query = text.trim().toLowerCase();
    final projectId = context.read<ProjectsCubit>().state.selectedId;
    final targets = context.read<TargetsCubit>().state.targets;
    return SavedTarget.orderFor(targets, projectId)
        .where(
          (t) =>
              query.isEmpty ||
              t.label.toLowerCase().contains(query) ||
              t.value.toLowerCase().contains(query),
        )
        .take(8);
  }

  Future<void> _toggleSaved(Target target, SavedTarget? saved) async {
    final targets = context.read<TargetsCubit>();
    final errors = context.read<AppErrorCubit>();
    final projectId = context.read<ProjectsCubit>().state.selectedId;
    final label = saved == null
        ? await promptForText(
            context,
            title: 'Save target',
            label: 'Label',
            initial: SavedTarget.defaultLabel(target),
          )
        : null;
    if (saved == null && label == null) {
      return;
    }
    try {
      if (saved != null) {
        await targets.remove(saved);
      } else {
        await targets.save(target, label: label!, projectId: projectId);
      }
    } catch (e) {
      errors.report(e, context: 'Could not update saved targets');
    }
  }

  @override
  Widget build(BuildContext context) {
    final kind = context.select((ComposerCubit c) => c.state.targetKind);
    final target = context.select((ComposerCubit c) => c.state.target);
    final saved = context.select(
      (TargetsCubit c) => c.state.matching(target),
    );
    final cubit = context.read<ComposerCubit>();
    return BlocListener<ComposerCubit, ComposerState>(
      // History and the Targets screen set the target from outside the field.
      listenWhen: (previous, current) =>
          previous.targetValue != current.targetValue,
      listener: (context, state) {
        if (state.targetValue != _controller.text) {
          _controller.text = state.targetValue;
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Target',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                key: TargetPicker.starKey,
                tooltip: saved == null
                    ? 'Save this target'
                    : 'Remove from saved targets',
                icon: Icon(saved == null ? Icons.star_border : Icons.star),
                onPressed: target.validate().isNotEmpty
                    ? null
                    : () => _toggleSaved(target, saved),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SegmentedButton<TargetKind>(
            segments: const [
              ButtonSegment(value: TargetKind.token, label: Text('Token')),
              ButtonSegment(value: TargetKind.topic, label: Text('Topic')),
              ButtonSegment(
                value: TargetKind.condition,
                label: Text('Condition'),
              ),
            ],
            selected: {kind},
            onSelectionChanged: (selection) =>
                cubit.setTargetKind(selection.first),
          ),
          const SizedBox(height: 8),
          RawAutocomplete<SavedTarget>(
            textEditingController: _controller,
            focusNode: _focusNode,
            displayStringForOption: (option) => option.value,
            optionsBuilder: (value) => _suggestions(value.text),
            onSelected: (option) => cubit.setTarget(option.kind, option.value),
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) =>
                TextField(
                  key: TargetPicker.fieldKey,
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: kind == TargetKind.token ? 4 : 2,
                  decoration: InputDecoration(
                    border: const OutlineInputBorder(),
                    labelText: switch (kind) {
                      TargetKind.token => 'Device token',
                      TargetKind.topic => 'Topic name',
                      TargetKind.condition => 'Condition',
                    },
                    hintText: switch (kind) {
                      TargetKind.token => 'Paste the FCM registration token',
                      TargetKind.topic => 'e.g. news (without /topics/)',
                      TargetKind.condition =>
                        "e.g. 'news' in topics && 'sports' in topics",
                    },
                  ),
                  onChanged: cubit.setTargetValue,
                ),
            optionsViewBuilder: (context, onSelected, options) =>
                _Suggestions(options: options.toList(), onSelected: onSelected),
          ),
        ],
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.options, required this.onSelected});

  final List<SavedTarget> options;
  final AutocompleteOnSelected<SavedTarget> onSelected;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 4,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 280, maxWidth: 360),
          child: ListView(
            padding: EdgeInsets.zero,
            shrinkWrap: true,
            children: [
              for (final option in options)
                ListTile(
                  key: ValueKey('target-suggestion-${option.id}'),
                  dense: true,
                  title: Text(option.label),
                  subtitle: Text(
                    [
                      option.kind.name,
                      option.displayValue,
                      if (option.projectId case final projectId?) projectId,
                    ].join(' · '),
                  ),
                  onTap: () => onSelected(option),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/features/composer`
Expected: PASS. Then `flutter test` and `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/app/widgets/prompt_dialog.dart lib/features/composer/view/target_picker.dart test/features/composer/target_picker_test.dart
git commit -m "feat: suggest saved targets and save the current one with the star"
```

---

### Task 15: Dry run, the production safeguard, Retry, cURL and "Show in JSON"

**Files:**
- Create: `lib/features/composer/view/send_confirmation_dialog.dart`, `lib/features/composer/view/prod_banner.dart`, `test/helpers/clipboard.dart`
- Modify: `lib/features/composer/view/send_panel.dart`, `lib/features/composer/view/preview_panel.dart`, `lib/features/composer/view/composer_screen.dart`
- Test: `test/features/composer/send_panel_test.dart`, `test/features/composer/composer_keyboard_test.dart`

**Interfaces:**
- Consumes: `SendConfirmation` (Task 3); `ComposerCubit.setValidateOnly`, `curl`, `showField`, `ComposerState.target`, `validateOnly`, `lastSentDryRun`, `lastHistoryError` (Task 8); `AuthException`, `FieldViolation` (existing).
- Produces:
  - `Future<void> sendSelected(BuildContext)`: every send path (Send, Cmd/Ctrl+Enter, Retry) uses it, so a production project always asks.
  - `Future<bool> confirmSend(BuildContext, SendConfirmation)` and `SendConfirmationDialog` with `typedKey` and `confirmKey`.
  - `ProdBanner` (keyed `Key('prod-banner')`).
  - `SendPanel.dryRunKey`; `ResultView({required result, explanation, bool dryRun, String? historyError, VoidCallback? onRetry, ValueChanged<String>? onShowField})` with `retryKey`; violation buttons keyed `ValueKey('show-field-<field>')`.
  - `PreviewPanel.curlMenuKey`.
  - Test helper `String? Function() mockClipboard(WidgetTester)`.

- [ ] **Step 1: Add the clipboard helper** `test/helpers/clipboard.dart`

```dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the app copies. Returns a function that reads the last copy.
String? Function() mockClipboard(WidgetTester tester) {
  String? copied;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return () => copied;
}
```

- [ ] **Step 2: Write the failing tests** `test/features/composer/send_panel_test.dart`

```dart
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/composer/view/preview_panel.dart';
import 'package:fcm_studio/features/composer/view/send_confirmation_dialog.dart';
import 'package:fcm_studio/features/composer/view/send_panel.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/app_harness.dart';
import '../../helpers/clipboard.dart';
import '../../helpers/fcm_fixtures.dart';
import '../../helpers/keyboard.dart';
import '../../helpers/service_account_fixture.dart';

void main() {
  const token = 'abc:APA91bxyz';
  const unavailableBody =
      '{"error":{"code":503,"message":"Try later.","status":"UNAVAILABLE"}}';

  Future<(ProjectsCubit, ComposerCubit)> pumpProd(
    WidgetTester tester, {
    required List<http.Request> requests,
    int fcmStatus = 200,
    String fcmBody = successBody,
  }) async {
    final (projects, composer) = await pumpAppWithProject(
      tester,
      fcmStatus: fcmStatus,
      fcmBody: fcmBody,
      onFcmRequest: requests.add,
    );
    await tester.runAsync(
      () => projects.setEnvironment(testProjectId, ProjectEnvironment.prod),
    );
    await tester.pump();
    return (projects, composer);
  }

  ButtonStyleButton confirmButton(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(
        find.byKey(SendConfirmationDialog.confirmKey),
      );

  testWidgets('the production banner shows for prod projects only', (
    tester,
  ) async {
    final (projects, _) = await pumpAppWithProject(tester);
    expect(find.byKey(const Key('prod-banner')), findsNothing);
    await tester.runAsync(
      () => projects.setEnvironment(testProjectId, ProjectEnvironment.prod),
    );
    await tester.pump();
    expect(find.byKey(const Key('prod-banner')), findsOneWidget);
  });

  testWidgets('a prod topic send needs the project ID typed before it goes out', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final (_, composer) = await pumpProd(tester, requests: requests);
    composer
      ..setTargetKind(TargetKind.topic)
      ..setTargetValue('all_zone_store');
    await tester.pump();

    await tester.tap(find.byKey(SendPanel.sendButtonKey));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('every device subscribed to `all_zone_store`'),
      findsOneWidget,
    );
    expect(confirmButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(SendConfirmationDialog.typedKey),
      'demo-projec',
    );
    await tester.pump();
    expect(confirmButton(tester).onPressed, isNull);

    await tester.enterText(
      find.byKey(SendConfirmationDialog.typedKey),
      'demo-project',
    );
    await tester.pump();
    await tester.tap(find.byKey(SendConfirmationDialog.confirmKey));
    await settleAsync(tester);
    expect(requests, hasLength(1));
  });

  testWidgets('a prod token send asks, and Cancel sends nothing', (tester) async {
    final requests = <http.Request>[];
    final (_, composer) = await pumpProd(tester, requests: requests);
    composer.setTargetValue(token);
    await tester.pump();

    await tester.tap(find.byKey(SendPanel.sendButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('Send to production?'), findsOneWidget);
    expect(find.byKey(SendConfirmationDialog.typedKey), findsNothing);
    expect(confirmButton(tester).onPressed, isNotNull);

    await tester.tap(find.text('Cancel'));
    await settleAsync(tester);
    expect(requests, isEmpty);
  });

  testWidgets('a prod dry run goes out without asking', (tester) async {
    final requests = <http.Request>[];
    final (_, composer) = await pumpProd(tester, requests: requests);
    composer
      ..setTargetKind(TargetKind.topic)
      ..setTargetValue('news');
    await tester.tap(find.byKey(SendPanel.dryRunKey));
    await tester.pump();

    await tester.tap(find.byKey(SendPanel.sendButtonKey));
    await settleAsync(tester);
    expect(find.text('Send to production?'), findsNothing);
    expect(requests, hasLength(1));
    expect(find.text('Valid (dry run, not delivered)'), findsOneWidget);
  });

  testWidgets('a dry run adds validate_only to the request', (tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    composer.setTargetValue(token);
    await tester.tap(find.byKey(SendPanel.dryRunKey));
    await tester.pump();
    expect(find.textContaining('"validate_only": true'), findsOneWidget);
  });

  testWidgets('Retry sends again after a failure', (tester) async {
    final requests = <http.Request>[];
    final (projects, composer) = await pumpAppWithProject(
      tester,
      fcmStatus: 503,
      fcmBody: unavailableBody,
      onFcmRequest: requests.add,
    );
    composer.setTargetValue(token);
    await tester.runAsync(() => composer.send(projects.state.selected!));
    await tester.pump();
    expect(find.text('Temporary FCM problem'), findsOneWidget);

    await tester.tap(find.byKey(ResultView.retryKey));
    await settleAsync(tester);
    expect(requests, hasLength(2));
  });

  testWidgets('Retry on a prod project asks again', (tester) async {
    final requests = <http.Request>[];
    final (_, composer) = await pumpProd(
      tester,
      requests: requests,
      fcmStatus: 503,
      fcmBody: unavailableBody,
    );
    composer.setTargetValue(token);
    await tester.pump();
    await tester.tap(find.byKey(SendPanel.sendButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SendConfirmationDialog.confirmKey));
    await settleAsync(tester);
    expect(requests, hasLength(1));

    await tester.tap(find.byKey(ResultView.retryKey));
    await tester.pumpAndSettle();
    expect(find.text('Send to production?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settleAsync(tester);
    expect(requests, hasLength(1));
  });

  testWidgets('Show in JSON for a field FCM rejected', (tester) async {
    final (projects, composer) = await pumpAppWithProject(
      tester,
      fcmStatus: 400,
      fcmBody: invalidArgumentBody,
    );
    composer
      ..updateTemplateText(
        '{\n  "notification": {"title": "a"},\n  "data": {\n    "count": 42\n  }\n}',
      )
      ..setTargetValue(token);
    await tester.runAsync(() => composer.send(projects.state.selected!));
    await tester.pump();

    final button = find.byKey(const ValueKey('show-field-message.data[0].value'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();
    await tester.pump();
    expect(editorController(tester).selection.baseIndex, 3);
  });

  testWidgets(r'Copy as cURL with $FCM_ACCESS_TOKEN', (tester) async {
    final copied = mockClipboard(tester);
    final (_, composer) = await pumpAppWithProject(tester);
    composer.setTargetValue(token);
    await tester.pump();

    await tester.tap(find.byKey(PreviewPanel.curlMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text(r'Copy as cURL with $FCM_ACCESS_TOKEN'));
    await settleAsync(tester);
    expect(copied(), contains(r'Bearer $FCM_ACCESS_TOKEN'));
    expect(copied(), contains('projects/demo-project/messages:send'));
  });

  testWidgets('Copy as cURL with the access token warns about it', (
    tester,
  ) async {
    final copied = mockClipboard(tester);
    final (_, composer) = await pumpAppWithProject(tester);
    composer.setTargetValue(token);
    await tester.pump();

    await tester.tap(find.byKey(PreviewPanel.curlMenuKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy as cURL with access token'));
    await settleAsync(tester);
    expect(copied(), contains('Bearer ya29.test-token'));
    expect(find.textContaining('valid for up to 1 hour'), findsOneWidget);
  });
}
```

Add to `test/features/composer/composer_keyboard_test.dart` (imports: `package:fcm_studio/features/projects/domain/project.dart`, `'../../helpers/service_account_fixture.dart'`):
```dart
  testWidgets('Ctrl+Enter on a prod project asks before sending', (
    tester,
  ) async {
    final requests = <http.Request>[];
    final (projects, composer) = await pumpAppWithProject(
      tester,
      onFcmRequest: requests.add,
    );
    await tester.runAsync(
      () => projects.setEnvironment(testProjectId, ProjectEnvironment.prod),
    );
    composer.setTargetValue(token);
    await tester.pump();

    await pressWithEnter(tester, LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('Send to production?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(requests, isEmpty);
  }, variant: _windows);
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/composer/send_panel_test.dart test/features/composer/composer_keyboard_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 4: Implement the confirmation dialog and the banner**

`lib/features/composer/view/send_confirmation_dialog.dart`:
```dart
import 'package:fcm_studio/features/composer/domain/send_confirmation.dart';
import 'package:flutter/material.dart';

/// Asks before a production send (spec §4.3). True means send.
Future<bool> confirmSend(
  BuildContext context,
  SendConfirmation confirmation,
) async =>
    await showDialog<bool>(
      context: context,
      builder: (_) => SendConfirmationDialog(confirmation: confirmation),
    ) ??
    false;

class SendConfirmationDialog extends StatefulWidget {
  const SendConfirmationDialog({required this.confirmation, super.key});

  static const typedKey = Key('confirm-project-id');
  static const confirmKey = Key('confirm-send');

  final SendConfirmation confirmation;

  @override
  State<SendConfirmationDialog> createState() => _SendConfirmationDialogState();
}

class _SendConfirmationDialogState extends State<SendConfirmationDialog> {
  final TextEditingController _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final confirmation = widget.confirmation;
    final scheme = Theme.of(context).colorScheme;
    final ready =
        !confirmation.requiresTypedProjectId ||
        _typed.text.trim() == confirmation.projectId;
    return AlertDialog(
      icon: Icon(Icons.warning_amber, color: scheme.error),
      title: const Text('Send to production?'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Project: ${confirmation.projectId} (PROD)'),
            const SizedBox(height: 8),
            Text('Audience: ${confirmation.audience}'),
            if (confirmation.requiresTypedProjectId) ...[
              const SizedBox(height: 16),
              TextField(
                key: SendConfirmationDialog.typedKey,
                controller: _typed,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Type ${confirmation.projectId} to confirm',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: SendConfirmationDialog.confirmKey,
          style: FilledButton.styleFrom(
            backgroundColor: scheme.error,
            foregroundColor: scheme.onError,
          ),
          onPressed: ready ? () => Navigator.of(context).pop(true) : null,
          child: const Text('Send'),
        ),
      ],
    );
  }
}
```

`lib/features/composer/view/prod_banner.dart`:
```dart
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The red banner above the composer for production projects (spec §4.3).
class ProdBanner extends StatelessWidget {
  const ProdBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final project = context.select((ProjectsCubit c) => c.state.selected);
    if (project == null || project.environment != ProjectEnvironment.prod) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('prod-banner'),
      width: double.infinity,
      color: scheme.error,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        'PRODUCTION · ${project.id} · every send asks for confirmation',
        style: TextStyle(color: scheme.onError, fontWeight: FontWeight.w600),
      ),
    );
  }
}
```

- [ ] **Step 5: Update the send panel.** Replace `lib/features/composer/view/send_panel.dart` with:

```dart
import 'package:fcm_studio/core/fcm/fcm_error_explainer.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/send_confirmation.dart';
import 'package:fcm_studio/features/composer/view/send_confirmation_dialog.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sends the composer's message to the selected project. Send,
/// Cmd/Ctrl+Enter and Retry all come here, so a production project always
/// asks first (spec §4.3).
Future<void> sendSelected(BuildContext context) async {
  final project = context.read<ProjectsCubit>().state.selected;
  final composer = context.read<ComposerCubit>();
  if (project == null || !composer.state.canSend) {
    return;
  }
  final confirmation = SendConfirmation.forSend(
    project: project,
    target: composer.state.target,
    validateOnly: composer.state.validateOnly,
  );
  if (confirmation != null && !await confirmSend(context, confirmation)) {
    return;
  }
  await composer.send(project);
}

class SendPanel extends StatelessWidget {
  const SendPanel({super.key});

  static const sendButtonKey = Key('send-button');
  static const dryRunKey = Key('dry-run');

  @override
  Widget build(BuildContext context) {
    final hasProject = context.select(
      (ProjectsCubit cubit) => cubit.state.selected != null,
    );
    return BlocBuilder<ComposerCubit, ComposerState>(
      builder: (context, state) {
        final cubit = context.read<ComposerCubit>();
        final sending = state.sendStatus == SendStatus.sending;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                key: dryRunKey,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: state.validateOnly,
                onChanged: (value) => cubit.setValidateOnly(value ?? false),
                title: const Text('Dry run (validate only)'),
                subtitle: const Text(
                  'FCM checks the message but delivers nothing.',
                ),
              ),
              const SizedBox(height: 8),
              Tooltip(
                message: hasProject ? 'Cmd/Ctrl + Enter' : 'Add a project first',
                child: FilledButton.icon(
                  key: sendButtonKey,
                  onPressed: hasProject && state.canSend
                      ? () => sendSelected(context)
                      : null,
                  icon: sending
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(
                    sending
                        ? 'Sending…'
                        : state.validateOnly
                        ? 'Send (dry run)'
                        : 'Send',
                  ),
                ),
              ),
              if (state.lastResult case final result?) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: SingleChildScrollView(
                    child: ResultView(
                      result: result,
                      explanation: state.lastExplanation,
                      dryRun: state.lastSentDryRun,
                      historyError: state.lastHistoryError,
                      onRetry: hasProject && state.canSend
                          ? () => sendSelected(context)
                          : null,
                      onShowField: cubit.showField,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class ResultView extends StatelessWidget {
  const ResultView({
    required this.result,
    this.explanation,
    this.dryRun = false,
    this.historyError,
    this.onRetry,
    this.onShowField,
    super.key,
  });

  static const retryKey = Key('retry-button');

  final FcmSendResult result;
  final ErrorExplanation? explanation;

  /// The result of a dry run: FCM validated the message and delivered nothing.
  final bool dryRun;

  /// Shown when the send could not be saved to history.
  final String? historyError;

  /// Sends again. Null while sending again isn't possible.
  final VoidCallback? onRetry;

  /// Shows a rejected field (e.g. `message.data[0].value`) in the JSON tab.
  final ValueChanged<String>? onShowField;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final milliseconds = result.duration.inMilliseconds;
    final historyNote = historyError;
    switch (result) {
      case FcmSendSuccess(:final messageName):
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(dryRun ? 'Valid (dry run, not delivered)' : 'Sent'),
              subtitle: SelectableText('$messageName · $milliseconds ms'),
            ),
            if (historyNote != null)
              Text(historyNote, style: theme.textTheme.bodySmall),
          ],
        );
      case FcmSendFailure(:final error):
        final e = explanation;
        final showField = onShowField;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    e?.title ?? 'Send failed',
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            if (e != null) ...[
              const SizedBox(height: 8),
              SelectableText(e.explanation),
              const SizedBox(height: 8),
              Text(
                e.action,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
            if (showField != null)
              for (final violation in error.fieldViolations)
                TextButton.icon(
                  key: ValueKey('show-field-${violation.field}'),
                  onPressed: () => showField(violation.field),
                  icon: const Icon(Icons.my_location, size: 16),
                  label: Text('Show ${violation.field} in JSON'),
                ),
            Wrap(
              spacing: 8,
              children: [
                if (e?.link case final link?)
                  TextButton.icon(
                    onPressed: () => launchUrl(link),
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('Open in console'),
                  ),
                TextButton.icon(
                  key: retryKey,
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('Retry'),
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'Raw response${result.httpStatus == null ? '' : ' (HTTP ${result.httpStatus})'}',
              ),
              children: [
                SelectableText(
                  result.responseBody ?? error.message ?? 'No response body.',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
            if (historyNote != null)
              Text(historyNote, style: theme.textTheme.bodySmall),
          ],
        );
    }
  }
}
```

- [ ] **Step 6: Add Copy as cURL to the preview.** In `lib/features/composer/view/preview_panel.dart`:
- add the imports `package:fcm_studio/core/auth/access_token_provider.dart` and `package:fcm_studio/features/projects/cubit/projects_cubit.dart`;
- add `static const curlMenuKey = Key('copy-curl');` to `PreviewPanel`;
- insert this widget in the header `Row`, after the existing "Copy request body" `IconButton`:
```dart
                PopupMenuButton<bool>(
                  key: curlMenuKey,
                  tooltip: 'Copy as cURL',
                  enabled: requestText != null,
                  icon: const Icon(Icons.terminal, size: 18),
                  onSelected: (withToken) =>
                      _copyCurl(context, includeAccessToken: withToken),
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: true,
                      child: ListTile(
                        title: Text('Copy as cURL with access token'),
                        subtitle: Text(
                          "Valid for up to 1 hour. Don't paste it into chats.",
                        ),
                      ),
                    ),
                    PopupMenuItem(
                      value: false,
                      child: ListTile(
                        title: Text(r'Copy as cURL with $FCM_ACCESS_TOKEN'),
                      ),
                    ),
                  ],
                ),
```
- add this method to `PreviewPanel`:
```dart
  static Future<void> _copyCurl(
    BuildContext context, {
    required bool includeAccessToken,
  }) async {
    final project = context.read<ProjectsCubit>().state.selected;
    final composer = context.read<ComposerCubit>();
    final messenger = ScaffoldMessenger.of(context);
    if (project == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Add a project first.')),
      );
      return;
    }
    try {
      final command = await composer.curl(
        project,
        includeAccessToken: includeAccessToken,
      );
      if (command == null) {
        return;
      }
      await Clipboard.setData(ClipboardData(text: command));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            includeAccessToken
                ? "Copied. The access token in it is valid for up to 1 hour; don't paste it into chats."
                : r'Copied. Set $FCM_ACCESS_TOKEN before running it.',
          ),
        ),
      );
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
```

- [ ] **Step 7: Put the banner above the composer.** Replace `lib/features/composer/view/composer_screen.dart` with its final M2 form:

```dart
import 'package:fcm_studio/features/composer/view/message_editor_tabs.dart';
import 'package:fcm_studio/features/composer/view/preview_panel.dart';
import 'package:fcm_studio/features/composer/view/prod_banner.dart';
import 'package:fcm_studio/features/composer/view/send_panel.dart';
import 'package:fcm_studio/features/composer/view/target_picker.dart';
import 'package:fcm_studio/features/presets/view/preset_actions.dart';
import 'package:fcm_studio/features/presets/view/preset_picker.dart';
import 'package:fcm_studio/features/projects/view/project_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ComposerScreen extends StatelessWidget {
  const ComposerScreen({super.key});

  static const wideLayoutMinWidth = 1000.0;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(
          LogicalKeyboardKey.enter,
          meta: true,
          includeRepeats: false,
        ): () =>
            sendSelected(context),
        const SingleActivator(
          LogicalKeyboardKey.enter,
          control: true,
          includeRepeats: false,
        ): () =>
            sendSelected(context),
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            savePreset(context),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            savePreset(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(title: const Text('FCM Studio')),
          body: Column(
            children: [
              const ProdBanner(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth >= wideLayoutMinWidth) {
                      return const Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 320, child: _SetupPane()),
                          VerticalDivider(width: 1),
                          Expanded(child: MessageEditorTabs()),
                          VerticalDivider(width: 1),
                          SizedBox(width: 420, child: _OutputPane()),
                        ],
                      );
                    }
                    return const DefaultTabController(
                      length: 3,
                      child: Column(
                        children: [
                          TabBar(
                            tabs: [
                              Tab(text: 'Setup'),
                              Tab(text: 'Message'),
                              Tab(text: 'Preview & result'),
                            ],
                          ),
                          Expanded(
                            child: TabBarView(
                              children: [
                                _SetupPane(),
                                MessageEditorTabs(),
                                _OutputPane(),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SetupPane extends StatelessWidget {
  const _SetupPane();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [
        ProjectSwitcher(),
        SizedBox(height: 24),
        TargetPicker(),
        SizedBox(height: 24),
        PresetPicker(),
      ],
    );
  }
}

class _OutputPane extends StatelessWidget {
  const _OutputPane();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: PreviewPanel()),
        Divider(height: 1),
        SendPanel(),
      ],
    );
  }
}
```

- [ ] **Step 8: Run the tests and confirm they pass**

Run: `flutter test test/features/composer`
Expected: PASS (10 new send-panel tests, the new keyboard test, and every existing composer test). Then `flutter test` and `flutter analyze` (No issues found!).

- [ ] **Step 9: Commit**

```bash
dart format lib test
git add lib/features/composer/view test/helpers/clipboard.dart test/features/composer
git commit -m "feat: add dry run, prod confirmation on every send path, retry and copy as cURL"
```

---

### Task 16: Navigation shell and the Presets screen

**Files:**
- Create: `lib/app/navigation_cubit.dart`, `lib/app/shell.dart`, `lib/features/presets/view/presets_screen.dart`
- Modify: `lib/app/app.dart`
- Test: `test/features/presets/presets_screen_test.dart`

**Interfaces:**
- Consumes: `PresetsCubit`, `PresetCodec`, `ImportPreview`, `ImportConflictChoice`, `PresetFormatException` (Tasks 4, 9); `FileAccess` (Task 11); `openPreset`, `showPresetDetailsDialog` (Task 13); `ComposerCubit.detachPreset` (Task 8); `AppErrorCubit` (Task 11); test helpers `FakeFileAccess`, `settleAsync`, `readCubit`.
- Produces:
  - `enum AppSection { composer, presets }` (Task 17 adds `targets` and `history`) and `class NavigationCubit extends Cubit<AppSection>` with `show(AppSection)`.
  - `AppShell`: a `NavigationRail` whose labels are keyed `Key('nav-composer')`, `Key('nav-presets')`, and an `IndexedStack` of the screens.
  - `enum PresetAction { open, duplicate, edit, export, delete }`, `PresetsScreen` with `importKey`, `exportKey`; tiles keyed `ValueKey('preset-<id>')`, menus `ValueKey('preset-menu-<id>')`; `ImportConflictDialog`.

- [ ] **Step 1: Write the failing tests** `test/features/presets/presets_screen_test.dart`

```dart
import 'dart:convert';

import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/view/presets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_file_access.dart';

void main() {
  Future<(ComposerCubit, PresetsCubit, FakeFileAccess)> openPresets(
    WidgetTester tester,
  ) async {
    final files = FakeFileAccess();
    final (_, composer) = await pumpAppWithProject(tester, files: files);
    await tester.tap(find.byKey(const Key('nav-presets')));
    await tester.pumpAndSettle();
    return (composer, readCubit<PresetsCubit>(tester), files);
  }

  Future<Preset> saveMine(
    WidgetTester tester,
    PresetsCubit presets,
    String name,
  ) async {
    final saved = (await tester.runAsync(
      () => presets.saveAs(
        name: name,
        template: const {
          'notification': {'title': 'A'},
        },
        variables: const [],
      ),
    ))!;
    await tester.pump();
    return saved;
  }

  testWidgets("lists the built-in presets and the user's own", (tester) async {
    final (_, presets, _) = await openPresets(tester);
    await saveMine(tester, presets, 'Mine');
    expect(find.text('Simple notification'), findsOneWidget);
    expect(find.text('Data only (silent / background)'), findsOneWidget);
    expect(find.text('Mine'), findsOneWidget);
  });

  testWidgets('Open in composer loads the preset and shows the composer', (
    tester,
  ) async {
    final (composer, _, _) = await openPresets(tester);
    await tester.tap(find.text('Notification + data'));
    await tester.pumpAndSettle();
    expect(composer.state.preset?.id, 'builtin.notification_data');
    expect(readCubit<NavigationCubit>(tester).state, AppSection.composer);
  });

  testWidgets('Duplicate makes an editable copy', (tester) async {
    final (_, presets, _) = await openPresets(tester);
    await tester.tap(find.byKey(const ValueKey('preset-menu-builtin.simple')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await settleAsync(tester);
    expect(presets.state.userPresets.single.name, 'Simple notification (copy)');
    expect(find.text('Simple notification (copy)'), findsOneWidget);
  });

  testWidgets('Export all saves a presets file without the built-in ones', (
    tester,
  ) async {
    final (_, presets, files) = await openPresets(tester);
    await saveMine(tester, presets, 'My alerts');
    await tester.tap(find.byKey(PresetsScreen.exportKey));
    await settleAsync(tester);
    expect(files.saved.single.name, 'my-alerts.fcmpresets.json');
    expect(
      PresetCodec.decode(files.saved.single.text).map((p) => p.name),
      ['My alerts'],
    );
  });

  testWidgets('Import asks about name conflicts and can keep both', (
    tester,
  ) async {
    final (_, presets, files) = await openPresets(tester);
    final mine = await saveMine(tester, presets, 'Mine');
    files.nextOpen = PresetCodec.encode([mine], exportedAt: DateTime.utc(2026));

    await tester.tap(find.byKey(PresetsScreen.importKey));
    await tester.pumpAndSettle();
    expect(find.text('Some presets already exist'), findsOneWidget);
    await tester.tap(find.text('Keep both'));
    await settleAsync(tester);

    expect(presets.state.userPresets.map((p) => p.name), ['Mine', 'Mine (2)']);
    expect(find.text('Imported 1 preset.'), findsOneWidget);
  });

  testWidgets('a newer presets file is explained and nothing is imported', (
    tester,
  ) async {
    final (_, presets, files) = await openPresets(tester);
    files.nextOpen = jsonEncode({
      'format': PresetCodec.format,
      'version': 2,
      'presets': <Object?>[],
    });
    await tester.tap(find.byKey(PresetsScreen.importKey));
    await tester.pumpAndSettle();
    expect(find.text("Can't import this file"), findsOneWidget);
    expect(find.textContaining('newer FCM Studio'), findsOneWidget);
    expect(presets.state.userPresets, isEmpty);
  });

  testWidgets('deleting the preset loaded in the composer detaches it', (
    tester,
  ) async {
    final (composer, presets, _) = await openPresets(tester);
    final mine = await saveMine(tester, presets, 'Mine');
    composer.loadPreset(mine);

    await tester.tap(find.byKey(ValueKey('preset-menu-${mine.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await settleAsync(tester);

    expect(presets.state.userPresets, isEmpty);
    expect(composer.state.preset, isNull);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/presets/presets_screen_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement the navigation**

`lib/app/navigation_cubit.dart`:
```dart
import 'package:flutter_bloc/flutter_bloc.dart';

/// The screens in the navigation rail, in rail order.
enum AppSection { composer, presets }

class NavigationCubit extends Cubit<AppSection> {
  NavigationCubit() : super(AppSection.composer);

  void show(AppSection section) => emit(section);
}
```

`lib/app/shell.dart`:
```dart
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/features/composer/view/composer_screen.dart';
import 'package:fcm_studio/features/presets/view/presets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The navigation rail and the screens behind it (spec §3.3). Screens stay
/// alive in an IndexedStack, so switching keeps their state.
class AppShell extends StatelessWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context) {
    final section = context.watch<NavigationCubit>().state;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: section.index,
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (index) =>
                context.read<NavigationCubit>().show(AppSection.values[index]),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.send_outlined),
                selectedIcon: Icon(Icons.send),
                label: Text('Composer', key: Key('nav-composer')),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.bookmarks_outlined),
                selectedIcon: Icon(Icons.bookmarks),
                label: Text('Presets', key: Key('nav-presets')),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: IndexedStack(
              index: section.index,
              children: const [ComposerScreen(), PresetsScreen()],
            ),
          ),
        ],
      ),
    );
  }
}
```

In `lib/app/app.dart`: import `navigation_cubit.dart` and `shell.dart`, add `BlocProvider(create: (_) => NavigationCubit()),` to the providers, and change `home: const ComposerScreen(),` to `home: const AppShell(),` (remove the now-unused `composer_screen.dart` import).

- [ ] **Step 4: Implement the Presets screen** `lib/features/presets/view/presets_screen.dart`

```dart
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/core/platform/file_access.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/domain/preset.dart';
import 'package:fcm_studio/features/presets/domain/preset_codec.dart';
import 'package:fcm_studio/features/presets/view/preset_actions.dart';
import 'package:fcm_studio/features/presets/view/preset_details_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

enum PresetAction { open, duplicate, edit, export, delete }

/// Built-in and user presets, with export and import (spec §6).
class PresetsScreen extends StatefulWidget {
  const PresetsScreen({super.key});

  static const importKey = Key('presets-import');
  static const exportKey = Key('presets-export');

  @override
  State<PresetsScreen> createState() => _PresetsScreenState();
}

class _PresetsScreenState extends State<PresetsScreen> {
  /// User presets ticked for export.
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final state = context.watch<PresetsCubit>().state;
    final selected = [
      for (final p in state.userPresets)
        if (_selected.contains(p.id)) p,
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Presets'),
        actions: [
          TextButton.icon(
            key: PresetsScreen.importKey,
            onPressed: () => _run('import presets', _import),
            icon: const Icon(Icons.file_open_outlined),
            label: const Text('Import…'),
          ),
          TextButton.icon(
            key: PresetsScreen.exportKey,
            onPressed: state.userPresets.isEmpty
                ? null
                : () => _run(
                    'export presets',
                    () => _export(selected.isEmpty ? state.userPresets : selected),
                  ),
            icon: const Icon(Icons.save_alt),
            label: Text(
              selected.isEmpty ? 'Export all' : 'Export ${selected.length}',
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          const _Header('Built-in'),
          for (final preset in state.builtIns)
            _PresetTile(preset: preset, onAction: _onAction),
          const _Header('My presets'),
          if (state.userPresets.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                'No presets yet. Save one from the composer, or import a file.',
              ),
            ),
          for (final preset in state.userPresets)
            _PresetTile(
              preset: preset,
              selected: _selected.contains(preset.id),
              onSelected: (on) => setState(() {
                if (on) {
                  _selected.add(preset.id);
                } else {
                  _selected.remove(preset.id);
                }
              }),
              onAction: _onAction,
            ),
        ],
      ),
    );
  }

  /// Runs [action]; an unexpected failure goes to the error banner.
  Future<void> _run(String what, Future<void> Function() action) async {
    final errors = context.read<AppErrorCubit>();
    try {
      await action();
    } catch (e) {
      errors.report(e, context: 'Could not $what');
    }
  }

  Future<void> _onAction(Preset preset, PresetAction action) =>
      _run('${action.name} the preset', () async {
        final presets = context.read<PresetsCubit>();
        final composer = context.read<ComposerCubit>();
        final navigation = context.read<NavigationCubit>();
        final messenger = ScaffoldMessenger.of(context);
        switch (action) {
          case PresetAction.open:
            if (await openPreset(context, preset)) {
              navigation.show(AppSection.composer);
            }
          case PresetAction.duplicate:
            final copy = await presets.duplicate(preset);
            messenger.showSnackBar(
              SnackBar(content: Text('Created "${copy.name}".')),
            );
          case PresetAction.edit:
            final details = await showPresetDetailsDialog(
              context,
              title: 'Rename preset',
              name: preset.name,
              description: preset.description,
              isNameTaken: (name) =>
                  presets.state.nameTaken(name, exceptId: preset.id),
            );
            if (details != null) {
              await presets.rename(
                preset,
                name: details.name,
                description: details.description,
              );
            }
          case PresetAction.export:
            await _export([preset]);
          case PresetAction.delete:
            if (await _confirmDelete(preset)) {
              await presets.delete(preset);
              composer.detachPreset(preset.id);
            }
        }
      });

  Future<bool> _confirmDelete(Preset preset) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete "${preset.name}"?'),
        content: const Text('This cannot be undone. Export it first to keep a copy.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _export(List<Preset> presets) async {
    final cubit = context.read<PresetsCubit>();
    final files = context.read<FileAccess>();
    final messenger = ScaffoldMessenger.of(context);
    final name = presets.length == 1
        ? '${_fileName(presets.single.name)}${PresetCodec.fileExtension}'
        : 'fcm-studio-presets${PresetCodec.fileExtension}';
    final saved = await files.saveText(
      suggestedName: name,
      text: cubit.exportText(presets),
    );
    if (saved) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Exported ${presets.length} preset${presets.length == 1 ? '' : 's'}.',
          ),
        ),
      );
    }
  }

  Future<void> _import() async {
    final cubit = context.read<PresetsCubit>();
    final files = context.read<FileAccess>();
    final messenger = ScaffoldMessenger.of(context);
    final text = await files.openText(
      label: 'FCM Studio presets',
      extensions: const ['json'],
    );
    if (text == null || !mounted) {
      return;
    }
    final ImportPreview preview;
    try {
      preview = cubit.previewImport(text);
    } on PresetFormatException catch (e) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Can't import this file"),
          content: Text(e.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    var choice = ImportConflictChoice.keepBoth;
    if (preview.conflicts.isNotEmpty) {
      final picked = await showDialog<ImportConflictChoice>(
        context: context,
        builder: (_) => ImportConflictDialog(conflicts: preview.conflicts),
      );
      if (picked == null) {
        return;
      }
      choice = picked;
    }
    final count = await cubit.applyImport(preview, choice);
    messenger.showSnackBar(
      SnackBar(
        content: Text('Imported $count preset${count == 1 ? '' : 's'}.'),
      ),
    );
  }

  static String _fileName(String name) {
    final safe = name
        .toLowerCase()
        .replaceAll(RegExp('[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return safe.isEmpty ? 'preset' : safe;
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    );
  }
}

class _PresetTile extends StatelessWidget {
  const _PresetTile({
    required this.preset,
    required this.onAction,
    this.selected = false,
    this.onSelected,
  });

  final Preset preset;
  final bool selected;
  final ValueChanged<bool>? onSelected;
  final Future<void> Function(Preset preset, PresetAction action) onAction;

  @override
  Widget build(BuildContext context) {
    final count = preset.variables.length;
    final details = [
      if (preset.description.isNotEmpty) preset.description,
      '$count variable${count == 1 ? '' : 's'}',
    ].join(' · ');
    return ListTile(
      key: ValueKey('preset-${preset.id}'),
      leading: preset.builtIn
          ? const Icon(Icons.lock_outline)
          : Checkbox(
              value: selected,
              onChanged: (value) => onSelected?.call(value ?? false),
            ),
      title: Text(preset.name),
      subtitle: Text(details),
      onTap: () => onAction(preset, PresetAction.open),
      trailing: PopupMenuButton<PresetAction>(
        key: ValueKey('preset-menu-${preset.id}'),
        tooltip: 'Preset actions',
        onSelected: (action) => onAction(preset, action),
        itemBuilder: (context) => [
          const PopupMenuItem(
            value: PresetAction.open,
            child: Text('Open in composer'),
          ),
          const PopupMenuItem(
            value: PresetAction.duplicate,
            child: Text('Duplicate'),
          ),
          if (!preset.builtIn) ...const [
            PopupMenuItem(value: PresetAction.edit, child: Text('Rename…')),
            PopupMenuItem(value: PresetAction.export, child: Text('Export…')),
            PopupMenuItem(value: PresetAction.delete, child: Text('Delete…')),
          ],
        ],
      ),
    );
  }
}

/// Asks what to do with imported presets whose names already exist.
class ImportConflictDialog extends StatelessWidget {
  const ImportConflictDialog({required this.conflicts, super.key});

  final List<String> conflicts;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Some presets already exist'),
      content: Text(
        'These names are already used: ${conflicts.join(', ')}.\n\n'
        'Your choice applies to all of them. Built-in presets are never '
        'replaced; a clash with one is kept as a copy.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(ImportConflictChoice.skip),
          child: const Text('Skip'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(ImportConflictChoice.replace),
          child: const Text('Replace'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(ImportConflictChoice.keepBoth),
          child: const Text('Keep both'),
        ),
      ],
    );
  }
}
```

If the analyzer flags `use_build_context_synchronously` inside `_onAction`, read everything from `context` (including `ScaffoldMessenger`) before the `switch`, as the code already does, and add `if (!mounted) return;` before the `showPresetDetailsDialog` and `_confirmDelete` calls.

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/features/presets`
Expected: PASS (7 new screen tests and the earlier presets tests). Then `flutter test` and `flutter analyze` (No issues found!).

- [ ] **Step 6: Commit**

```bash
dart format lib test
git add lib/app lib/features/presets/view/presets_screen.dart test/features/presets/presets_screen_test.dart
git commit -m "feat: add the navigation rail and the Presets screen with import and export"
```

---

### Task 17: Saved targets and History screens

**Files:**
- Create: `lib/core/utils/time_format.dart`, `lib/features/targets/view/targets_screen.dart`, `lib/features/history/view/history_screen.dart`
- Modify: `lib/app/navigation_cubit.dart`, `lib/app/shell.dart`
- Test: `test/core/utils/time_format_test.dart`, `test/features/targets/targets_screen_test.dart`, `test/features/history/history_screen_test.dart`

**Interfaces:**
- Consumes: `TargetsCubit`, `SavedTarget` (Tasks 5, 10); `HistoryCubit`, `HistoryEntry`, `HistoryFilter`, `OutcomeFilter`, `ModeFilter` (Tasks 6, 10); `SendConfirmation`, `confirmSend` (Tasks 3, 15); `confirmDiscardChanges`, `showPresetDetailsDialog` (Task 13); `promptForText` (Task 14); `NavigationCubit` (Task 16); `ComposerCubit.setTarget`, `openMessage` (Task 8); `shortenMiddle` (Task 3); test helpers `historyEntry`, `mockClipboard`, `buildTestDependencies`, `addTestProject`.
- Produces:
  - `String formatLocalTime(DateTime)`, e.g. `2026-10-03 14:05:09` in local time.
  - `enum AppSection { composer, presets, targets, history }`; rail labels keyed `Key('nav-targets')`, `Key('nav-history')`.
  - `TargetsScreen`: tiles keyed `ValueKey('target-<id>')`, menus `ValueKey('target-menu-<id>')`.
  - `HistoryScreen` with `clearKey`, `searchKey`; `HistoryTile` (expansion tile keyed `ValueKey('history-<id>')`) with buttons keyed `ValueKey('history-resend-<id>')`, `history-open-<id>`, `history-save-<id>`, `history-curl-<id>`.

- [ ] **Step 1: Write the failing tests**

`test/core/utils/time_format_test.dart`:
```dart
import 'package:fcm_studio/core/utils/time_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats local time with zero padding', () {
    expect(formatLocalTime(DateTime(2026, 3, 4, 5, 6, 7)), '2026-03-04 05:06:07');
  });
}
```

`test/features/targets/targets_screen_test.dart`:
```dart
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/app/widgets/prompt_dialog.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/clipboard.dart';

void main() {
  const token = 'fAbC12345678909xYz';

  Future<(ComposerCubit, TargetsCubit)> openTargets(WidgetTester tester) async {
    final (_, composer) = await pumpAppWithProject(tester);
    final targets = readCubit<TargetsCubit>(tester);
    await tester.runAsync(
      () => targets.save(
        const TokenTarget(token),
        label: 'Redmi',
        projectId: 'demo-project',
      ),
    );
    await tester.tap(find.byKey(const Key('nav-targets')));
    await tester.pumpAndSettle();
    return (composer, targets);
  }

  testWidgets('shows tokens shortened and copies the full value on tap', (
    tester,
  ) async {
    final copied = mockClipboard(tester);
    await openTargets(tester);
    expect(
      find.textContaining('token · fAbC12…9xYz · demo-project'),
      findsOneWidget,
    );
    await tester.tap(find.text('Redmi'));
    await tester.pumpAndSettle();
    expect(copied(), token);
  });

  testWidgets('Use in composer sets the target and shows the composer', (
    tester,
  ) async {
    final (composer, targets) = await openTargets(tester);
    final id = targets.state.targets.single.id;
    await tester.tap(find.byKey(ValueKey('target-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use in composer'));
    await tester.pumpAndSettle();
    expect(composer.state.targetKind, TargetKind.token);
    expect(composer.state.targetValue, token);
    expect(readCubit<NavigationCubit>(tester).state, AppSection.composer);
  });

  testWidgets('rename and delete', (tester) async {
    final (_, targets) = await openTargets(tester);
    final id = targets.state.targets.single.id;

    await tester.tap(find.byKey(ValueKey('target-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(PromptDialog.fieldKey), 'Pixel');
    await tester.tap(find.byKey(PromptDialog.confirmKey));
    await settleAsync(tester);
    expect(targets.state.targets.single.label, 'Pixel');

    await tester.tap(find.byKey(ValueKey('target-menu-$id')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await settleAsync(tester);
    expect(targets.state.targets, isEmpty);
  });
}
```

`test/features/history/history_screen_test.dart`:
```dart
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/history/cubit/history_cubit.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/history/view/history_screen.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/view/preset_details_dialog.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/app_harness.dart';
import '../../helpers/fake_google.dart';
import '../../helpers/history_fixture.dart';
import '../../helpers/service_account_fixture.dart';

void main() {
  Future<(ComposerCubit, List<http.Request>)> openHistory(
    WidgetTester tester, {
    List<HistoryEntry> entries = const [],
    ProjectEnvironment environment = ProjectEnvironment.dev,
  }) async {
    final requests = <http.Request>[];
    final dependencies = await buildTestDependencies(
      tester,
      client: fakeGoogle(onFcmRequest: requests.add),
    );
    await tester.runAsync(() async {
      for (final entry in entries) {
        await dependencies.historyRepository.add(entry);
      }
    });
    await pumpApp(tester, dependencies);
    final projects = await addTestProject(tester);
    await tester.runAsync(
      () => projects.setEnvironment(testProjectId, environment),
    );
    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pumpAndSettle();
    return (readCubit<ComposerCubit>(tester), requests);
  }

  Future<void> expand(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey('history-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('a send from the composer shows up in History', (tester) async {
    final (projects, composer) = await pumpAppWithProject(tester);
    composer.setTargetValue('abc:APA91bxyz');
    await tester.runAsync(() => composer.send(projects.state.selected!));
    await tester.runAsync(readCubit<HistoryCubit>(tester).load);
    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pumpAndSettle();
    expect(find.textContaining('demo-project · Sent'), findsOneWidget);
  });

  testWidgets('filters by outcome and searches', (tester) async {
    await openHistory(
      tester,
      entries: [
        historyEntry('ok', presetName: 'Promo', sentAt: DateTime.utc(2026, 10, 3, 9)),
        historyEntry('bad', ok: false, sentAt: DateTime.utc(2026, 10, 3, 10)),
      ],
    );
    expect(find.byType(HistoryTile), findsNWidgets(2));

    await tester.tap(find.text('Failed'));
    await tester.pump();
    expect(find.byType(HistoryTile), findsOneWidget);
    expect(find.textContaining('UNREGISTERED'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.enterText(find.byKey(HistoryScreen.searchKey), 'promo');
    await tester.pump();
    expect(find.byType(HistoryTile), findsOneWidget);
    expect(find.textContaining('Promo'), findsOneWidget);
  });

  testWidgets('Resend sends the stored request again', (tester) async {
    final (_, requests) = await openHistory(
      tester,
      entries: [historyEntry('e1')],
    );
    await expand(tester, 'e1');
    await tester.tap(find.byKey(const ValueKey('history-resend-e1')));
    await settleAsync(tester);
    expect(requests, hasLength(1));
    expect(
      find.text('Resent: projects/demo-project/messages/0:1'),
      findsOneWidget,
    );
  });

  testWidgets('Resend asks first for a production project', (tester) async {
    final (_, requests) = await openHistory(
      tester,
      entries: [historyEntry('e1')],
      environment: ProjectEnvironment.prod,
    );
    await expand(tester, 'e1');
    await tester.tap(find.byKey(const ValueKey('history-resend-e1')));
    await tester.pumpAndSettle();
    expect(find.text('Send to production?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settleAsync(tester);
    expect(requests, isEmpty);
  });

  testWidgets('Resend is off when the project was removed', (tester) async {
    await openHistory(
      tester,
      entries: [historyEntry('gone', projectId: 'gone-project')],
    );
    await expand(tester, 'gone');
    final resend = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('history-resend-gone')),
    );
    expect(resend.onPressed, isNull);
    expect(find.byTooltip('The project gone-project was removed.'), findsOneWidget);
  });

  testWidgets('Open in composer loads the message and its target', (
    tester,
  ) async {
    final (composer, _) = await openHistory(
      tester,
      entries: [historyEntry('e1')],
    );
    await expand(tester, 'e1');
    await tester.tap(find.byKey(const ValueKey('history-open-e1')));
    await tester.pumpAndSettle();
    expect(composer.state.template, {
      'notification': {'title': 'Order shipped'},
    });
    expect(composer.state.targetValue, 'abc:APA91bxyz');
    expect(readCubit<NavigationCubit>(tester).state, AppSection.composer);
  });

  testWidgets('Save as preset stores the message without variables', (
    tester,
  ) async {
    await openHistory(tester, entries: [historyEntry('e1')]);
    await expand(tester, 'e1');
    await tester.tap(find.byKey(const ValueKey('history-save-e1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(PresetDetailsDialog.nameKey),
      'From history',
    );
    await tester.tap(find.byKey(PresetDetailsDialog.saveKey));
    await settleAsync(tester);
    final saved = readCubit<PresetsCubit>(tester).state.userPresets.single;
    expect(saved.name, 'From history');
    expect(saved.variables, isEmpty);
    expect(saved.template, {
      'notification': {'title': 'Order shipped'},
    });
  });

  testWidgets('Clear history asks, then empties the list', (tester) async {
    await openHistory(tester, entries: [historyEntry('e1')]);
    await tester.tap(find.byKey(HistoryScreen.clearKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-clear-confirm')));
    await settleAsync(tester);
    expect(find.text('Nothing sent yet.'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/core/utils/time_format_test.dart test/features/targets/targets_screen_test.dart test/features/history/history_screen_test.dart`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement**

`lib/core/utils/time_format.dart`:
```dart
/// `2026-10-03 14:05:09`, in local time.
String formatLocalTime(DateTime time) {
  final t = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} '
      '${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}
```

In `lib/app/navigation_cubit.dart`, change the enum to:
```dart
enum AppSection { composer, presets, targets, history }
```

In `lib/app/shell.dart`, import `package:fcm_studio/features/history/view/history_screen.dart` and `package:fcm_studio/features/targets/view/targets_screen.dart`, add these destinations after Presets:
```dart
              NavigationRailDestination(
                icon: Icon(Icons.star_outline),
                selectedIcon: Icon(Icons.star),
                label: Text('Targets', key: Key('nav-targets')),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.history),
                label: Text('History', key: Key('nav-history')),
              ),
```
and make the `IndexedStack` children `const [ComposerScreen(), PresetsScreen(), TargetsScreen(), HistoryScreen()]`.

`lib/features/targets/view/targets_screen.dart`:
```dart
import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/app/widgets/prompt_dialog.dart';
import 'package:fcm_studio/core/utils/time_format.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/cubit/targets_cubit.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Saved tokens, topics and conditions (spec §7.1).
class TargetsScreen extends StatelessWidget {
  const TargetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final targets = context.watch<TargetsCubit>().state.targets;
    return Scaffold(
      appBar: AppBar(title: const Text('Saved targets')),
      body: targets.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No saved targets yet. Use the star next to the target '
                  'field in the composer.',
                ),
              ),
            )
          : ListView(
              children: [
                for (final target in targets) _TargetTile(target: target),
              ],
            ),
    );
  }
}

enum _TargetAction { use, rename, delete }

class _TargetTile extends StatelessWidget {
  const _TargetTile({required this.target});

  final SavedTarget target;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: ValueKey('target-${target.id}'),
      leading: Icon(switch (target.kind) {
        TargetKind.token => Icons.smartphone,
        TargetKind.topic => Icons.tag,
        TargetKind.condition => Icons.rule,
      }),
      title: Text(target.label),
      subtitle: Text(
        [
          target.kind.name,
          target.displayValue,
          if (target.projectId case final projectId?) projectId,
          'last used ${formatLocalTime(target.lastUsedAt)}',
        ].join(' · '),
      ),
      // Lists show tokens shortened; a tap copies the full value.
      onTap: () => _copy(context),
      trailing: PopupMenuButton<_TargetAction>(
        key: ValueKey('target-menu-${target.id}'),
        tooltip: 'Target actions',
        onSelected: (action) => _onAction(context, action),
        itemBuilder: (context) => const [
          PopupMenuItem(value: _TargetAction.use, child: Text('Use in composer')),
          PopupMenuItem(value: _TargetAction.rename, child: Text('Rename…')),
          PopupMenuItem(value: _TargetAction.delete, child: Text('Delete')),
        ],
      ),
    );
  }

  Future<void> _copy(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: target.value));
    messenger.showSnackBar(
      const SnackBar(content: Text('Copied the full value.')),
    );
  }

  Future<void> _onAction(BuildContext context, _TargetAction action) async {
    final targets = context.read<TargetsCubit>();
    final composer = context.read<ComposerCubit>();
    final navigation = context.read<NavigationCubit>();
    final errors = context.read<AppErrorCubit>();
    try {
      switch (action) {
        case _TargetAction.use:
          composer.setTarget(target.kind, target.value);
          navigation.show(AppSection.composer);
        case _TargetAction.rename:
          final label = await promptForText(
            context,
            title: 'Rename target',
            label: 'Label',
            initial: target.label,
          );
          if (label != null && label.trim().isNotEmpty) {
            await targets.rename(target, label);
          }
        case _TargetAction.delete:
          await targets.remove(target);
      }
    } catch (e) {
      errors.report(e, context: 'Could not update the saved target');
    }
  }
}
```

`lib/features/history/view/history_screen.dart`:
```dart
import 'dart:convert';

import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/core/utils/shorten.dart';
import 'package:fcm_studio/core/utils/time_format.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/send_confirmation.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/composer/view/send_confirmation_dialog.dart';
import 'package:fcm_studio/features/history/cubit/history_cubit.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/history/domain/history_filter.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/view/preset_actions.dart';
import 'package:fcm_studio/features/presets/view/preset_details_dialog.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Every send attempt, with filters and actions (spec §7.2).
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  static const clearKey = Key('history-clear');
  static const searchKey = Key('history-search');

  @override
  Widget build(BuildContext context) {
    final state = context.watch<HistoryCubit>().state;
    final visible = state.visible;
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          TextButton.icon(
            key: clearKey,
            onPressed: state.entries.isEmpty ? null : () => _clear(context),
            icon: const Icon(Icons.delete_sweep_outlined),
            label: const Text('Clear history'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Filters(state: state),
          const Divider(height: 1),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: Text(
                      state.entries.isEmpty
                          ? 'Nothing sent yet.'
                          : 'No entries match the filters.',
                    ),
                  )
                : ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) =>
                        HistoryTile(entry: visible[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _clear(BuildContext context) async {
    final history = context.read<HistoryCubit>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
          'Every history entry is deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const Key('history-clear-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await history.clear();
    }
  }
}

class _Filters extends StatefulWidget {
  const _Filters({required this.state});

  final HistoryState state;

  @override
  State<_Filters> createState() => _FiltersState();
}

class _FiltersState extends State<_Filters> {
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<HistoryCubit>();
    final filter = widget.state.filter;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String?>(
            value: filter.projectId,
            items: [
              const DropdownMenuItem<String?>(child: Text('All projects')),
              for (final id in widget.state.projectIds)
                DropdownMenuItem<String?>(value: id, child: Text(id)),
            ],
            onChanged: (id) =>
                cubit.setFilter(filter.copyWith(projectId: () => id)),
          ),
          SegmentedButton<OutcomeFilter>(
            segments: const [
              ButtonSegment(value: OutcomeFilter.all, label: Text('All')),
              ButtonSegment(
                value: OutcomeFilter.success,
                label: Text('Succeeded'),
              ),
              ButtonSegment(value: OutcomeFilter.failure, label: Text('Failed')),
            ],
            selected: {filter.outcome},
            onSelectionChanged: (selection) =>
                cubit.setFilter(filter.copyWith(outcome: selection.first)),
          ),
          SegmentedButton<ModeFilter>(
            segments: const [
              ButtonSegment(value: ModeFilter.all, label: Text('Real + dry run')),
              ButtonSegment(value: ModeFilter.real, label: Text('Real')),
              ButtonSegment(value: ModeFilter.dryRun, label: Text('Dry run')),
            ],
            selected: {filter.mode},
            onSelectionChanged: (selection) =>
                cubit.setFilter(filter.copyWith(mode: selection.first)),
          ),
          SizedBox(
            width: 260,
            child: TextField(
              key: HistoryScreen.searchKey,
              controller: _search,
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Icons.search),
                hintText: 'Search target, preset, body',
                border: OutlineInputBorder(),
              ),
              onChanged: (query) => cubit.setFilter(
                cubit.state.filter.copyWith(query: query),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One history entry, expandable to its request, response and actions.
class HistoryTile extends StatelessWidget {
  const HistoryTile({required this.entry, super.key});

  final HistoryEntry entry;

  static const _monospace = TextStyle(fontFamily: 'monospace', fontSize: 12);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = context.select(
      (ProjectsCubit c) =>
          c.state.projects.where((p) => p.id == entry.projectId).firstOrNull,
    );
    final target = entry.target;
    final targetText =
        target.label ??
        (target.kind == TargetKind.token
            ? shortenMiddle(target.value)
            : target.value);
    final outcome = switch (entry.outcome) {
      HistorySuccess() => entry.validateOnly ? 'Valid (dry run)' : 'Sent',
      HistoryFailure(:final code, :final explanation) => '$code · $explanation',
    };
    final id = entry.id;
    return ExpansionTile(
      key: ValueKey('history-$id'),
      leading: Icon(
        entry.succeeded ? Icons.check_circle : Icons.error,
        color: entry.succeeded ? Colors.green : theme.colorScheme.error,
      ),
      title: Text(targetText),
      subtitle: Text(
        [
          formatLocalTime(entry.sentAt),
          entry.projectId,
          if (entry.presetName case final name?) name,
          outcome,
        ].join(' · '),
      ),
      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Tooltip(
              message: project == null
                  ? 'The project ${entry.projectId} was removed.'
                  : 'Send again with a current access token',
              child: FilledButton.tonalIcon(
                key: ValueKey('history-resend-$id'),
                onPressed: project == null
                    ? null
                    : () => _resend(context, project),
                icon: const Icon(Icons.replay),
                label: const Text('Resend'),
              ),
            ),
            OutlinedButton(
              key: ValueKey('history-open-$id'),
              onPressed: () => _open(context),
              child: const Text('Open in composer'),
            ),
            OutlinedButton(
              key: ValueKey('history-save-$id'),
              onPressed: () => _saveAsPreset(context),
              child: const Text('Save as preset…'),
            ),
            PopupMenuButton<bool>(
              key: ValueKey('history-curl-$id'),
              enabled: project != null,
              tooltip: 'Copy as cURL',
              onSelected: (withToken) {
                if (project != null) {
                  _copyCurl(context, project, includeAccessToken: withToken);
                }
              },
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: true,
                  child: Text('Copy as cURL with access token'),
                ),
                PopupMenuItem(
                  value: false,
                  child: Text(r'Copy as cURL with $FCM_ACCESS_TOKEN'),
                ),
              ],
              child: const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Copy as cURL'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text('Request', style: theme.textTheme.titleSmall),
        SelectableText(
          const JsonEncoder.withIndent('  ').convert(entry.request),
          style: _monospace,
        ),
        if (entry.responseBody case final body?) ...[
          const SizedBox(height: 8),
          Text(
            'Response${entry.httpStatus == null ? '' : ' (HTTP ${entry.httpStatus})'}'
            ' · ${entry.duration.inMilliseconds} ms',
            style: theme.textTheme.titleSmall,
          ),
          SelectableText(body, style: _monospace),
        ],
      ],
    );
  }

  /// Resend asks first for a production project, like every send (spec §4.3).
  Future<void> _resend(BuildContext context, Project project) async {
    final history = context.read<HistoryCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final confirmation = SendConfirmation.forSend(
      project: project,
      target: entry.target.toTarget(),
      validateOnly: entry.validateOnly,
    );
    if (confirmation != null && !await confirmSend(context, confirmation)) {
      return;
    }
    final outcome = await history.resend(entry, project);
    messenger.showSnackBar(
      SnackBar(
        content: Text(switch (outcome.result) {
          FcmSendSuccess(:final messageName) => 'Resent: $messageName',
          FcmSendFailure() =>
            'Resend failed: ${outcome.explanation?.title ?? 'see History'}',
        }),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    final composer = context.read<ComposerCubit>();
    final navigation = context.read<NavigationCubit>();
    if (composer.state.isDirty && !await confirmDiscardChanges(context)) {
      return;
    }
    composer.openMessage(
      template: entry.template,
      target: entry.target.toTarget(),
    );
    navigation.show(AppSection.composer);
  }

  Future<void> _saveAsPreset(BuildContext context) async {
    final presets = context.read<PresetsCubit>();
    final errors = context.read<AppErrorCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final details = await showPresetDetailsDialog(
      context,
      title: 'Save as preset',
      isNameTaken: presets.state.nameTaken,
    );
    if (details == null) {
      return;
    }
    try {
      await presets.saveAs(
        name: details.name,
        description: details.description,
        template: entry.template,
        variables: const [],
      );
      messenger.showSnackBar(
        SnackBar(content: Text('Saved "${details.name}".')),
      );
    } catch (e) {
      errors.report(e, context: 'Could not save the preset');
    }
  }

  Future<void> _copyCurl(
    BuildContext context,
    Project project, {
    required bool includeAccessToken,
  }) async {
    final history = context.read<HistoryCubit>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final command = await history.curl(
        entry,
        project,
        includeAccessToken: includeAccessToken,
      );
      await Clipboard.setData(ClipboardData(text: command));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            includeAccessToken
                ? "Copied. The access token in it is valid for up to 1 hour; don't paste it into chats."
                : r'Copied. Set $FCM_ACCESS_TOKEN before running it.',
          ),
        ),
      );
    } on AuthException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/core/utils/time_format_test.dart test/features/targets test/features/history`
Expected: PASS. Then `flutter test` and `flutter analyze` (No issues found!).

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/core/utils/time_format.dart lib/app lib/features/targets/view lib/features/history/view test/core/utils/time_format_test.dart test/features/targets/targets_screen_test.dart test/features/history/history_screen_test.dart
git commit -m "feat: add the saved targets and history screens"
```

---

### Task 18: Builds, the M2 success test, and the spec

This task checks the whole milestone. Steps 3 and 4 need the user (a real key, a phone and a token).

**Files:**
- Modify: `docs/superpowers/specs/2026-10-03-fcm-studio-design.md` (§4.3, §6, §13)

- [ ] **Step 1: Run the full checks**

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```
Expected: no formatting changes, `No issues found!`, all tests pass.

- [ ] **Step 2: Build every target that can be built here**

```bash
flutter build macos --debug
flutter build web
```
Expected: both succeed. (Windows is built on a Windows machine in M5.)

- [ ] **Step 3: The M2 success test (the user, on macOS).** Run `flutter run -d macos`. With the project already added and a device token at hand (from the app's logs or backend):
  1. Start a timer. Pick the project, pick **Simple notification**, paste the token into the target field, press **Send**.
  2. Stop the timer when the notification appears on the phone. **Done when: under 30 seconds.**
  3. Tick **Dry run** and send: the result says "Valid (dry run, not delivered)" and nothing arrives.
  4. Send **Data only (silent / background)**: no notification appears, and the app receives the data (check its log).
  5. Star the token, label it, then clear the field and pick it again from the suggestions.
  6. Edit the message, **Save as preset…**, quit and relaunch: the preset, the saved target and the history are still there.
  7. Set the project to **prod**: the red banner appears, a token send asks once, and a topic send needs the project ID typed.
  8. History → **Resend** the first entry, then **Copy as cURL** (`$FCM_ACCESS_TOKEN` version) and check the command looks right.
  9. Presets → **Export all**, then **Import…** the same file and choose **Keep both**.

- [ ] **Step 4: Web check (the user).** Run `flutter run -d chrome --web-port 5050`: add the project (with "Remember on this browser"), pick a preset, send to a topic, then **Export all** (the browser downloads the file) and **Import…** it back.

- [ ] **Step 5: Record the results in the spec**
  - §4.3, add a last bullet: `Dry runs (validate only) skip the confirmation, because they deliver nothing.`
  - §6, under Export, add: `Built-in presets are not exported; every install has them.` Under Import, add: `One choice applies to every name clash in the file.`
  - §13, add under the M0/M1 status:
    ```
    **M2 status (<date>):**
    - *Done:* <number> automated tests passing and a clean `flutter analyze`; the macOS debug and web builds succeed.
    - *Manual:* <which of Step 3 items 1–9 and Step 4 passed, with the success-test time>.
    - *Still pending from M1:* <anything from the M0/M1 pending list that is still open>.
    ```

- [ ] **Step 6: Commit**

```bash
git add docs/superpowers/specs/2026-10-03-fcm-studio-design.md
git commit -m "docs: record M2 status and the decisions made for it"
```
