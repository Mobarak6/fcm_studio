import 'package:equatable/equatable.dart';

class AccessToken extends Equatable {
  const AccessToken(this.value, this.expiresAt);

  final String value;
  final DateTime expiresAt;

  bool isValidAt(DateTime now, {Duration margin = Duration.zero}) =>
      now.add(margin).isBefore(expiresAt);

  @override
  List<Object?> get props => [value, expiresAt];

  @override
  String toString() => 'AccessToken(expiresAt: $expiresAt)';
}

/// Supplies OAuth access tokens for Google API calls.
abstract interface class AccessTokenProvider {
  Future<AccessToken> getToken({bool forceRefresh = false});

  /// Extra headers to send with every API call for [projectId].
  Map<String, String> extraHeaders(String projectId);
}

class AuthException implements Exception {
  const AuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AuthException($statusCode): $message';
}
