import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/composer/domain/fcm_rules.dart';
import 'package:fcm_studio/features/composer/domain/render_issue.dart';

enum TargetKind { token, topic, condition }

sealed class Target extends Equatable {
  const Target();

  factory Target.of(TargetKind kind, String value) => switch (kind) {
    TargetKind.token => TokenTarget(value),
    TargetKind.topic => TopicTarget(value),
    TargetKind.condition => ConditionTarget(value),
  };

  /// The FCM `message` fields that hold the target. Not allowed in templates.
  static const messageFields = {'token', 'topic', 'condition'};

  TargetKind get kind;

  /// The value as it goes to FCM: what [toMessageField] puts in the message.
  String get normalized;

  Map<String, String> toMessageField();

  List<RenderIssue> validate();
}

final class TokenTarget extends Target {
  const TokenTarget(this.raw);

  final String raw;

  static final _whitespace = RegExp(r'\s+');
  static final _surroundingQuotes = RegExp(r'''^["']+|["']+$''');

  /// The token with whitespace, line breaks and surrounding quotes removed.
  String get token =>
      raw.replaceAll(_whitespace, '').replaceAll(_surroundingQuotes, '');

  @override
  TargetKind get kind => TargetKind.token;

  @override
  String get normalized => token;

  @override
  Map<String, String> toMessageField() => {'token': token};

  @override
  List<RenderIssue> validate() => token.isEmpty
      ? const [RenderIssue('target', 'Enter a device token.')]
      : const [];

  @override
  List<Object?> get props => [token];
}

final class TopicTarget extends Target {
  const TopicTarget(this.raw);

  final String raw;

  /// The topic name without a leading `/topics/`.
  String get name {
    final trimmed = raw.trim();
    return trimmed.startsWith('/topics/')
        ? trimmed.substring('/topics/'.length)
        : trimmed;
  }

  @override
  TargetKind get kind => TargetKind.topic;

  @override
  String get normalized => name;

  @override
  Map<String, String> toMessageField() => {'topic': name};

  @override
  List<RenderIssue> validate() {
    if (name.isEmpty) {
      return const [RenderIssue('target', 'Enter a topic name.')];
    }
    if (!FcmRules.topicPattern.hasMatch(name)) {
      return const [
        RenderIssue(
          'target',
          'Topic names may only contain letters, digits and - _ . ~ %.',
        ),
      ];
    }
    return const [];
  }

  @override
  List<Object?> get props => [name];
}

final class ConditionTarget extends Target {
  const ConditionTarget(this.raw);

  final String raw;

  String get expression => raw.trim();

  @override
  TargetKind get kind => TargetKind.condition;

  @override
  String get normalized => expression;

  @override
  Map<String, String> toMessageField() => {'condition': expression};

  @override
  List<RenderIssue> validate() => expression.isEmpty
      ? const [
          RenderIssue('target', "Enter a condition, e.g. 'news' in topics."),
        ]
      : const [];

  @override
  List<Object?> get props => [expression];
}
