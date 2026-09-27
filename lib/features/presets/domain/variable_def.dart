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

  static final RegExp _decimal = RegExp(
    r'^[+-]?(\d+(\.\d*)?|\.\d+)([eE][+-]?\d+)?$',
  );

  /// Parses a finite decimal number (`-3`, `1.5`, `2e3`). Returns null for
  /// anything else, including NaN, Infinity and hex, which JSON can't carry.
  static num? parseNumber(String text) {
    if (!_decimal.hasMatch(text)) {
      return null;
    }
    final number = num.tryParse(text);
    return number != null && number.isFinite ? number : null;
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
        parseNumber(defaultValue) == null) {
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
