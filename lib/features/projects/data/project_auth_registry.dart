import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_account_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/google_user_info.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/auth/service_account_token_provider.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/projects/domain/google_session.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:http/http.dart' as http;

/// Keeps one token provider per credential, so tokens are cached across sends.
class ProjectAuthRegistry implements AccessTokenResolver {
  ProjectAuthRegistry({
    required this._repository,
    required http.Client httpClient,
    this._clock = const SystemClock(),
    this._googleFlow,
    GoogleUserInfo? googleUserInfo,
  }) : _http = httpClient,
       _userInfo = googleUserInfo ?? GoogleUserInfoApi(httpClient: httpClient);

  static const _notSetUp =
      'Google sign-in is not set up in this copy of FCM Studio. '
      'See docs/oauth-setup.md.';

  final ProjectsRepository _repository;
  final http.Client _http;
  final Clock _clock;
  final GoogleAuthFlow? _googleFlow;
  final GoogleUserInfo _userInfo;
  final Map<String, AccessTokenProvider> _providers = {};

  /// False when `config/oauth.json` has no client for this platform.
  bool get canSignInWithGoogle => _googleFlow != null;

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

  /// Signs in to Google, checks the granted permissions and finds the account
  /// (plan Decisions 2–3). Nothing is stored or registered yet. Throws
  /// [GoogleSignInCancelled] or [AuthException].
  Future<GoogleSession> signInWithGoogle({
    String? loginHint,
    Future<void>? cancel,
  }) async {
    final flow = _googleFlow;
    if (flow == null) {
      throw const AuthException(_notSetUp);
    }
    final credentials = await flow.signIn(loginHint: loginHint, cancel: cancel);
    if (credentials.missingScopes.isNotEmpty) {
      throw const AuthException(missingScopesMessage);
    }
    final email = await _userInfo.emailOf(credentials.accessToken);
    return GoogleSession(
      email: email,
      credentials: credentials,
      provider: GoogleAccountTokenProvider(
        email: email,
        flow: flow,
        userInfo: _userInfo,
        refreshToken: credentials.refreshToken,
        initialToken: credentials.accessToken,
        clock: _clock,
      ),
    );
  }

  /// From now on, [session]'s provider serves its account.
  void registerGoogle(GoogleSession session) =>
      _providers[session.account.secretKey] = session.provider;

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
      case GoogleAccountRef(:final email):
        final flow = _googleFlow;
        if (flow == null) {
          throw AuthException(
            '$_notSetUp Projects that use $email cannot send until then.',
          );
        }
        final refreshToken = flow.canRefresh
            ? await _repository.readGoogleRefreshToken(credential)
            : null;
        if (flow.canRefresh && refreshToken == null) {
          throw AuthException(
            GoogleAccountTokenProvider.notStoredMessage(email),
          );
        }
        final provider = GoogleAccountTokenProvider(
          email: email,
          flow: flow,
          userInfo: _userInfo,
          refreshToken: refreshToken,
          clock: _clock,
        );
        _providers[credential.secretKey] = provider;
        return provider;
    }
  }
}
