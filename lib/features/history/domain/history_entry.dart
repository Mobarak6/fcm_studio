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
