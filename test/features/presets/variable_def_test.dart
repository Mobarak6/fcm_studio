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
      {'key': 'n', 'type': 'number', 'defaultValue': 'NaN'},
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
