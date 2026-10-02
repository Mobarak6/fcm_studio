import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

/// A finished Google sign-in: whose it is, what Google gave back, and the
/// token provider that already holds the new access token.
class GoogleSession {
  const GoogleSession({
    required this.email,
    required this.credentials,
    required this.provider,
  });

  final String email;
  final GoogleCredentials credentials;
  final AccessTokenProvider provider;

  GoogleAccountRef get account => GoogleAccountRef(email);

  @override
  String toString() => 'GoogleSession($email)';
}
