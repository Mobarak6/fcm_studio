import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/fcm/fcm_error_explainer.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';

enum SendStatus { idle, sending, done }

class ComposerState extends Equatable {
  const ComposerState({
    required this.templateText,
    this.template,
    this.jsonError,
    this.targetKind = TargetKind.token,
    this.targetValue = '',
    this.render = const RenderResult(),
    this.sendStatus = SendStatus.idle,
    this.lastResult,
    this.lastExplanation,
  });

  /// Exactly what is in the JSON editor.
  final String templateText;

  /// [templateText] parsed. Null while the JSON is invalid.
  final Map<String, Object?>? template;
  final String? jsonError;
  final TargetKind targetKind;
  final String targetValue;
  final RenderResult render;
  final SendStatus sendStatus;
  final FcmSendResult? lastResult;
  final ErrorExplanation? lastExplanation;

  bool get canSend =>
      template != null && render.canSend && sendStatus != SendStatus.sending;

  static const Object _unset = Object();

  ComposerState copyWith({
    String? templateText,
    Object? template = _unset,
    Object? jsonError = _unset,
    TargetKind? targetKind,
    String? targetValue,
    RenderResult? render,
    SendStatus? sendStatus,
    Object? lastResult = _unset,
    Object? lastExplanation = _unset,
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
      render: render ?? this.render,
      sendStatus: sendStatus ?? this.sendStatus,
      lastResult: identical(lastResult, _unset)
          ? this.lastResult
          : lastResult as FcmSendResult?,
      lastExplanation: identical(lastExplanation, _unset)
          ? this.lastExplanation
          : lastExplanation as ErrorExplanation?,
    );
  }

  @override
  List<Object?> get props => [
    templateText,
    template,
    jsonError,
    targetKind,
    targetValue,
    render,
    sendStatus,
    lastResult,
    lastExplanation,
  ];
}
