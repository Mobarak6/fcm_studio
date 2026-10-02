import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fcm_fixtures.dart';
import 'service_account_fixture.dart';

/// What the fake Firebase Management API lists by default.
const listedTestProject = <String, Object?>{
  'projectId': testProjectId,
  'projectNumber': testProjectNumber,
  'displayName': 'Demo Project',
};

/// Answers the three Google hosts the app talks to.
http.Client fakeGoogle({
  int tokenStatus = 200,
  int firebaseStatus = 200,
  int fcmStatus = 200,
  String fcmBody = successBody,
  void Function(http.Request request)? onFcmRequest,
  List<Map<String, Object?>> firebaseProjects = const [listedTestProject],
}) {
  return MockClient((request) async {
    switch (request.url.host) {
      case 'oauth2.googleapis.com':
        return tokenStatus == 200
            ? http.Response(
                jsonEncode({
                  'access_token': 'ya29.test-token',
                  'expires_in': 3599,
                  'token_type': 'Bearer',
                }),
                200,
              )
            : http.Response(
                jsonEncode({
                  'error': 'invalid_grant',
                  'error_description': 'Invalid JWT Signature.',
                }),
                tokenStatus,
              );
      case 'firebase.googleapis.com':
        if (request.url.path == '/v1beta1/projects') {
          return http.Response(jsonEncode({'results': firebaseProjects}), 200);
        }
        return firebaseStatus == 200
            ? http.Response(
                jsonEncode({
                  'projectId': testProjectId,
                  'projectNumber': testProjectNumber,
                  'displayName': 'Demo Project',
                }),
                200,
              )
            : http.Response(
                '{"error":{"code":$firebaseStatus}}',
                firebaseStatus,
              );
      case 'fcm.googleapis.com':
        onFcmRequest?.call(request);
        return http.Response(fcmBody, fcmStatus);
      default:
        return http.Response('unexpected host ${request.url.host}', 500);
    }
  });
}
