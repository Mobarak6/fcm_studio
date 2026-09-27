import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

class FakeTokenProvider implements AccessTokenProvider {
  FakeTokenProvider({this.headers = const {}, this.error});

  final Map<String, String> headers;
  final AuthException? error;
  final List<bool> forceRefreshCalls = [];
  int _issued = 0;

  @override
  Future<AccessToken> getToken({bool forceRefresh = false}) async {
    forceRefreshCalls.add(forceRefresh);
    final failure = error;
    if (failure != null) throw failure;
    _issued++;
    return AccessToken('token-$_issued', DateTime.utc(2100));
  }

  @override
  Map<String, String> extraHeaders(String projectId) => headers;
}

class FakeResolver implements AccessTokenResolver {
  FakeResolver({this.error});

  final AuthException? error;

  @override
  Future<AccessTokenProvider> providerFor(Project project) async {
    final failure = error;
    if (failure != null) throw failure;
    return FakeTokenProvider();
  }
}
