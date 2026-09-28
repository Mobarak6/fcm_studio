import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/curl_builder.dart';
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_error_explainer.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/core/utils/ids.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';

/// The result of [MessageSender.send].
class SendOutcome extends Equatable {
  const SendOutcome({
    required this.result,
    this.explanation,
    this.historyError,
  });

  final FcmSendResult result;

  /// A plain-language explanation of a failure; null on success.
  final ErrorExplanation? explanation;

  /// Set when the send happened but could not be saved to history.
  final String? historyError;

  @override
  List<Object?> get props => [result, explanation, historyError];
}

/// Sends a rendered request for a project and records the attempt in history
/// (spec §7.2). The composer and History → Resend both use it.
class MessageSender {
  MessageSender({
    required FcmClient fcmClient,
    required this._auth,
    required this._history,
    required this._targets,
    this._clock = const SystemClock(),
    this._newId = newUuid,
    this._explainer = const FcmErrorExplainer(),
  }) : _fcm = fcmClient;

  final FcmClient _fcm;
  final AccessTokenResolver _auth;
  final HistoryRepository _history;
  final TargetsRepository _targets;
  final Clock _clock;
  final IdGenerator _newId;
  final FcmErrorExplainer _explainer;

  /// Sends [request] and records it. Never throws: every failure becomes an
  /// [FcmSendFailure] with an explanation.
  Future<SendOutcome> send({
    required Project project,
    required Map<String, Object?> request,
    required Target target,
    String? presetName,
  }) async {
    final sentAt = _clock.now();
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
      // e.g. a denied Keychain prompt: the send must still end.
      result = FcmSendFailure(
        error: FcmError(
          transport: FcmTransportError.unexpected,
          message: redact('$e'),
        ),
        duration: Duration.zero,
      );
    }
    final explanation = switch (result) {
      FcmSendFailure(:final error) => _explainer.explain(
        error,
        projectId: project.id,
      ),
      FcmSendSuccess() => null,
    };

    String? historyError;
    try {
      final saved = await _targets.findMatching(target);
      final responseBody = result.responseBody;
      await _history.add(
        HistoryEntry(
          id: _newId(),
          sentAt: sentAt,
          projectId: project.id,
          environment: project.environment,
          target: HistoryTarget(
            kind: target.kind,
            value: target.normalized,
            label: saved?.label,
          ),
          presetName: presetName,
          request: request,
          validateOnly: request['validate_only'] == true,
          httpStatus: result.httpStatus,
          outcome: switch (result) {
            FcmSendSuccess(:final messageName) => HistorySuccess(messageName),
            FcmSendFailure(:final error) => HistoryFailure(
              code: _code(error),
              explanation: explanation?.title ?? 'Send failed',
            ),
          },
          responseBody: responseBody == null ? null : redact(responseBody),
          duration: result.duration,
        ),
      );
      if (saved != null) {
        await _targets.markUsed(target, sentAt);
      }
    } catch (e) {
      historyError = 'Could not save this send to history: ${redact('$e')}';
    }
    return SendOutcome(
      result: result,
      explanation: explanation,
      historyError: historyError,
    );
  }

  /// A bash curl command for [request] (spec §8.3). With
  /// [includeAccessToken] it fetches a current token, which needs the key.
  Future<String> curl({
    required Project project,
    required Map<String, Object?> request,
    required bool includeAccessToken,
  }) async {
    AccessTokenProvider? auth;
    try {
      auth = await _auth.providerFor(project);
    } on AuthException {
      if (includeAccessToken) {
        rethrow;
      }
    }
    final token = includeAccessToken ? (await auth!.getToken()).value : null;
    return CurlBuilder.build(
      projectId: project.id,
      body: request,
      accessToken: token,
      extraHeaders: auth?.extraHeaders(project.id) ?? const {},
    );
  }

  static String _code(FcmError error) =>
      error.fcmErrorCode ??
      error.status ??
      switch (error.transport) {
        FcmTransportError.none =>
          error.httpStatus == null ? 'ERROR' : 'HTTP ${error.httpStatus}',
        final transport => transport.name.toUpperCase(),
      };
}
