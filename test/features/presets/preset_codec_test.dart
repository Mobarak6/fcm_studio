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
        jsonEncode({
          'project_info': <String, Object?>{},
          'client': <Object?>[],
        }),
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
    // The generic four come first; the 6amMart ones have their own test.
    expect(presets.take(4).map((p) => p.name), [
      'Simple notification',
      'Notification with image',
      'Notification + data',
      'Data only (silent / background)',
    ]);
    expect(presets, hasLength(27));
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

    test('replace never gives two imported presets the same id', () {
      final result = PresetCodec.resolve(
        existing: [named('A', id: 'mine')],
        incoming: [named('A'), named('A')],
        choice: ImportConflictChoice.replace,
        newId: newId,
        now: created,
      );
      expect(result.map((p) => p.id), ['mine', 'new-1']);
      expect(result.map((p) => p.name), ['A', 'A (2)']);
    });

    test('a clash inside the file is kept as a copy on replace', () {
      final result = PresetCodec.resolve(
        existing: const [],
        incoming: [named('B'), named('B')],
        choice: ImportConflictChoice.replace,
        newId: newId,
        now: created,
      );
      expect(result.map((p) => p.name), ['B', 'B (2)']);
      expect(result.map((p) => p.id).toSet(), hasLength(2));
    });
  });

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
}
