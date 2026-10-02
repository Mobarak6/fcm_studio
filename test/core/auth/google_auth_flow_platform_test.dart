import 'package:fcm_studio/core/auth/google_auth_flow_io.dart';
import 'package:fcm_studio/core/auth/google_auth_flow_platform.dart'
    as platform;
import 'package:fcm_studio/core/auth/oauth_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final client = MockClient((_) async => http.Response('unused', 500));

  test('off the web the platform switch picks the desktop sign-in', () {
    expect(
      platform.createGoogleAuthFlow(
        const OAuthConfig(
          desktopClientId: 'd',
          desktopClientSecret: 's',
          webClientId: 'w',
        ),
        client,
      ),
      isA<DesktopGoogleAuthFlow>(),
    );
    expect(
      platform.createGoogleAuthFlow(
        const OAuthConfig(webClientId: 'w'),
        client,
      ),
      isNull,
    );
  });
}
