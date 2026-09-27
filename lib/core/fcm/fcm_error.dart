import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/utils/redact.dart';

/// Why a send failed before FCM returned an HTTP answer.
enum FcmTransportError { none, network, timeout, auth, unexpected }

class FieldViolation extends Equatable {
  const FieldViolation(this.field, this.description);

  final String field;
  final String description;

  @override
  List<Object?> get props => [field, description];
}

class FcmError extends Equatable {
  const FcmError({
    this.httpStatus,
    this.status,
    this.message,
    this.fcmErrorCode,
    this.reason,
    this.fieldViolations = const [],
    this.transport = FcmTransportError.none,
    this.fromGoogle = true,
  });

  /// Parses a Google API error body. Never throws, even for non-JSON bodies.
  factory FcmError.fromResponse(int httpStatus, String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    final error = decoded is Map<String, Object?> ? decoded['error'] : null;
    if (error is! Map<String, Object?>) {
      final text = body.trim();
      return FcmError(
        httpStatus: httpStatus,
        message: text.isEmpty ? null : redact(truncate(text)),
        fromGoogle: false,
      );
    }

    String? fcmErrorCode;
    String? reason;
    final violations = <FieldViolation>[];
    final details = error['details'];
    if (details is List<Object?>) {
      for (final detail in details.whereType<Map<String, Object?>>()) {
        final type = detail['@type'];
        if (type is! String) {
          continue;
        }
        if (type.endsWith('google.firebase.fcm.v1.FcmError')) {
          fcmErrorCode = _string(detail['errorCode']);
        } else if (type.endsWith('google.rpc.ErrorInfo')) {
          reason = _string(detail['reason']);
        } else if (type.endsWith('google.rpc.BadRequest')) {
          final list = detail['fieldViolations'];
          if (list is List<Object?>) {
            for (final v in list.whereType<Map<String, Object?>>()) {
              violations.add(
                FieldViolation(
                  _string(v['field']) ?? '',
                  _string(v['description']) ?? '',
                ),
              );
            }
          }
        }
      }
    }

    final message = _string(error['message']);
    return FcmError(
      httpStatus: httpStatus,
      status: _string(error['status']),
      message: message == null ? null : redact(message),
      fcmErrorCode: fcmErrorCode,
      reason: reason,
      fieldViolations: violations,
    );
  }

  final int? httpStatus;

  /// Google RPC status, e.g. `NOT_FOUND`, `INVALID_ARGUMENT`.
  final String? status;
  final String? message;

  /// `details[].errorCode` of type `google.firebase.fcm.v1.FcmError`, e.g. `UNREGISTERED`.
  final String? fcmErrorCode;

  /// `details[].reason` of type `google.rpc.ErrorInfo`, e.g. `SERVICE_DISABLED`.
  final String? reason;
  final List<FieldViolation> fieldViolations;
  final FcmTransportError transport;

  /// False when the body was not a Google API error, e.g. an HTML page from a
  /// proxy, firewall or captive portal.
  final bool fromGoogle;

  static String? _string(Object? value) => value is String ? value : null;

  /// Shortens [text] to 500 characters for display.
  static String truncate(String text) =>
      text.length <= 500 ? text : '${text.substring(0, 500)}…';

  @override
  List<Object?> get props => [
    httpStatus,
    status,
    message,
    fcmErrorCode,
    reason,
    fieldViolations,
    transport,
    fromGoogle,
  ];
}
