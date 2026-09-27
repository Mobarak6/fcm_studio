import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:http/http.dart' as http;

/// Sends messages with the FCM HTTP v1 API.
///
/// Never retries automatically, so a notification is never delivered twice.
/// The only exception is a 401, where the token is refreshed and the request is
/// resent once.
class FcmClient {
  FcmClient({
    required http.Client httpClient,
    this.timeout = const Duration(seconds: 20),
  }) : _http = httpClient;

  final http.Client _http;
  final Duration timeout;

  static Uri sendUri(String projectId) => Uri.parse(
    'https://fcm.googleapis.com/v1/projects/${Uri.encodeComponent(projectId)}/messages:send',
  );

  Future<FcmSendResult> send({
    required String projectId,
    required Map<String, Object?> body,
    required AccessTokenProvider auth,
  }) async {
    final stopwatch = Stopwatch()..start();
    final encoded = jsonEncode(body);
    try {
      var response = await _post(
        projectId,
        encoded,
        await auth.getToken(),
        auth,
      );
      if (response.statusCode == 401) {
        response = await _post(
          projectId,
          encoded,
          await auth.getToken(forceRefresh: true),
          auth,
        );
      }
      stopwatch.stop();
      final messageName = response.statusCode == 200
          ? _messageName(response.body)
          : '';
      if (messageName.isNotEmpty) {
        return FcmSendSuccess(
          messageName: messageName,
          duration: stopwatch.elapsed,
          httpStatus: 200,
          responseBody: response.body,
        );
      }
      return FcmSendFailure(
        // A 200 without a message name did not come from FCM (e.g. a captive portal).
        error: response.statusCode == 200
            ? FcmError(
                httpStatus: 200,
                message: redact(FcmError.truncate(response.body.trim())),
                fromGoogle: false,
              )
            : FcmError.fromResponse(response.statusCode, response.body),
        duration: stopwatch.elapsed,
        httpStatus: response.statusCode,
        responseBody: response.body,
      );
    } on AuthException catch (e) {
      return FcmSendFailure(
        error: FcmError(transport: FcmTransportError.auth, message: e.message),
        duration: stopwatch.elapsed,
      );
    } on TimeoutException {
      return FcmSendFailure(
        error: FcmError(
          transport: FcmTransportError.timeout,
          message: 'No response within ${timeout.inSeconds} seconds.',
        ),
        duration: stopwatch.elapsed,
      );
    } on http.ClientException catch (e) {
      return FcmSendFailure(
        error: FcmError(
          transport: FcmTransportError.network,
          message: redact(e.message),
        ),
        duration: stopwatch.elapsed,
      );
    } on Exception catch (e) {
      // Anything else from the network stack, e.g. a TLS HandshakeException
      // when a proxy intercepts HTTPS.
      return FcmSendFailure(
        error: FcmError(
          transport: FcmTransportError.network,
          message: redact('$e'),
        ),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<http.Response> _post(
    String projectId,
    String encodedBody,
    AccessToken token,
    AccessTokenProvider auth,
  ) {
    return _http
        .post(
          sendUri(projectId),
          headers: {
            'Authorization': 'Bearer ${token.value}',
            'Content-Type': 'application/json; charset=utf-8',
            ...auth.extraHeaders(projectId),
          },
          body: encodedBody,
        )
        .timeout(timeout);
  }

  static String _messageName(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        final name = decoded['name'];
        if (name is String) {
          return name;
        }
      }
    } on FormatException {
      // A 200 without a JSON body still means the message was accepted.
    }
    return '';
  }
}
