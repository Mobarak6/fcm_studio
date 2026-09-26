import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

/// Finds the access token provider for a project's credential.
abstract interface class AccessTokenResolver {
  /// Throws [AuthException] when the credential is not available.
  Future<AccessTokenProvider> providerFor(Project project);
}
