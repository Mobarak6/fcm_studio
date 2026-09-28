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
