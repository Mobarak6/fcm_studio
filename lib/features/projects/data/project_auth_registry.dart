import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/auth/service_account_token_provider.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:http/http.dart' as http;

/// Keeps one token provider per credential, so tokens are cached across sends.
class ProjectAuthRegistry implements AccessTokenResolver {
  ProjectAuthRegistry({
    required this._repository,
    required http.Client httpClient,
    this._clock = const SystemClock(),
  }) : _http = httpClient;

  final ProjectsRepository _repository;
  final http.Client _http;
  final Clock _clock;
  final Map<String, AccessTokenProvider> _providers = {};

  /// Creates (or replaces) the provider for [key]'s service account.
  AccessTokenProvider registerKey(ServiceAccountKey key) {
    final provider = ServiceAccountTokenProvider(
      key: key,
      httpClient: _http,
      clock: _clock,
    );
    _providers[ServiceAccountRef(key.clientEmail).secretKey] = provider;
    return provider;
  }

  void forget(CredentialRef credential) =>
      _providers.remove(credential.secretKey);

  @override
  Future<AccessTokenProvider> providerFor(Project project) async {
    final credential = project.credential;
    final cached = _providers[credential.secretKey];
    if (cached != null) {
      return cached;
    }
    switch (credential) {
      case ServiceAccountRef():
        final key = await _repository.readServiceAccountKey(credential);
        if (key == null) {
          throw AuthException(
            'The service account key for ${project.id} is not available in this session. '
            'Add the project again with the same key file.',
          );
        }
        return registerKey(key);
    }
  }
}
