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
        state.copyWith(
          templateText: text,
          template: template,
          jsonError: error,
        ),
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

  /// The loaded preset changed elsewhere: renamed, or replaced by an import.
  /// Ignored unless [preset] is the loaded one. Unsaved edits are kept (the
  /// dot stays); otherwise the composer shows the new version, keeping the
  /// values of variables that still exist.
  void presetUpdated(Preset preset) {
    if (state.preset?.id != preset.id) {
      return;
    }
    if (state.hasContentOf(preset) || state.isDirty) {
      emit(state.copyWith(preset: preset));
      return;
    }
    emit(
      _rendered(
        state.copyWith(
          templateText: _encoder.convert(preset.template),
          template: TemplateEdits.copy(preset.template),
          jsonError: null,
          variables: preset.variables,
          values: {
            for (final v in preset.variables)
              v.key: state.values[v.key] ?? v.defaultValue,
          },
          preset: preset,
        ),
      ),
    );
  }

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
