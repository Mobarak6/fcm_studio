import 'dart:convert';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_error_explainer.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:fcm_studio/features/composer/cubit/composer_state.dart';
import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/composer/cubit/composer_state.dart';

class ComposerCubit extends Cubit<ComposerState> {
  ComposerCubit({
    required FcmClient fcmClient,
    required this._auth,
    this._renderer = const MessageRenderer(),
    this._explainer = const FcmErrorExplainer(),
  }) : _fcm = fcmClient,
       super(_rendered(_parsed(defaultTemplate), _renderer));

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

  final FcmClient _fcm;
  final AccessTokenResolver _auth;
  final MessageRenderer _renderer;
  final FcmErrorExplainer _explainer;

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
        _renderer,
      ),
    );
  }

  void setTargetKind(TargetKind kind) {
    if (kind == state.targetKind) {
      return;
    }
    emit(_rendered(state.copyWith(targetKind: kind), _renderer));
  }

  void setTargetValue(String value) {
    emit(_rendered(state.copyWith(targetValue: value), _renderer));
  }

  /// Sends the rendered request. Does nothing while a send is in progress.
  Future<void> send(Project project) async {
    if (!state.canSend) {
      return;
    }
    final request = state.render.request!;
    emit(
      state.copyWith(
        sendStatus: SendStatus.sending,
        lastResult: null,
        lastExplanation: null,
      ),
    );

    FcmSendResult result;
    try {
      final auth = await _auth.providerFor(project);
      result = await _fcm.send(
        projectId: project.id,
        body: request,
        auth: auth,
      );
    } on AuthException catch (e) {
      result = FcmSendFailure(
        error: FcmError(transport: FcmTransportError.auth, message: e.message),
        duration: Duration.zero,
      );
    } catch (e) {
      // Anything else (e.g. a denied Keychain prompt) must still end the send,
      // otherwise Send stays disabled until the app restarts.
      result = FcmSendFailure(
        error: FcmError(
          transport: FcmTransportError.unexpected,
          message: redact('$e'),
        ),
        duration: Duration.zero,
      );
    }
    if (isClosed) {
      return;
    }
    emit(
      state.copyWith(
        sendStatus: SendStatus.done,
        lastResult: result,
        lastExplanation: switch (result) {
          FcmSendFailure(:final error) => _explainer.explain(
            error,
            projectId: project.id,
          ),
          FcmSendSuccess() => null,
        },
      ),
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

  static ComposerState _rendered(
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
        target: Target.of(state.targetKind, state.targetValue),
      ),
    );
  }
}
