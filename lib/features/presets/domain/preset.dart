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
    this.group = '',
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
    final targetField = _targetField(template);
    if (targetField != null) {
      throw FormatException(
        '"$name" sets "$targetField" in its template; '
        'the target is never part of a preset.',
      );
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
    final group = json['group'];
    return Preset(
      id: id,
      name: name.trim(),
      description: description is String ? description : '',
      group: group is String ? group.trim() : '',
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

  /// The group the preset is listed under, stored trimmed. '' is No group.
  final String group;
  final List<VariableDef> variables;

  /// The FCM `message` object without the target.
  final Map<String, Object?> template;

  /// Shipped with the app; read-only, but can be duplicated.
  final bool builtIn;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Why [template] can't be stored in a preset, or null when it can.
  /// A preset never holds the target (`token`, `topic` or `condition`).
  static String? templateProblem(Map<String, Object?> template) {
    final field = _targetField(template);
    return field == null
        ? null
        : 'The template sets "$field"; remove it — the target is set in the '
              'Target field.';
  }

  /// The first target field that [template] sets, if any.
  static String? _targetField(Map<String, Object?> template) {
    for (final field in Target.messageFields) {
      if (template.containsKey(field)) {
        return field;
      }
    }
    return null;
  }

  static DateTime _date(Object? value) =>
      (value is String ? DateTime.tryParse(value) : null)?.toUtc() ??
      DateTime.utc(1970);

  Preset copyWith({
    String? id,
    String? name,
    String? description,
    String? group,
    List<VariableDef>? variables,
    Map<String, Object?>? template,
    bool? builtIn,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => Preset(
    id: id ?? this.id,
    name: name ?? this.name,
    description: description ?? this.description,
    group: group ?? this.group,
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
    'group': group,
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
    group,
    variables,
    template,
    builtIn,
    createdAt,
    updatedAt,
  ];
}
