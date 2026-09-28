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
