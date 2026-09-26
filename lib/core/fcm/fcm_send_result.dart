import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';

sealed class FcmSendResult extends Equatable {
  const FcmSendResult({
    required this.duration,
    this.httpStatus,
    this.responseBody,
  });

  final Duration duration;
  final int? httpStatus;
  final String? responseBody;
}

final class FcmSendSuccess extends FcmSendResult {
  const FcmSendSuccess({
    required this.messageName,
    required super.duration,
    super.httpStatus,
    super.responseBody,
  });

  /// e.g. `projects/demo-project/messages/0:1700000000000000%abc`.
  final String messageName;

  @override
  List<Object?> get props => [messageName, duration, httpStatus, responseBody];
}

final class FcmSendFailure extends FcmSendResult {
  const FcmSendFailure({
    required this.error,
    required super.duration,
    super.httpStatus,
    super.responseBody,
  });

  final FcmError error;

  @override
  List<Object?> get props => [error, duration, httpStatus, responseBody];
}
