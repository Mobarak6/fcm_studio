import 'package:fcm_studio/core/auth/access_token_provider.dart';

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
