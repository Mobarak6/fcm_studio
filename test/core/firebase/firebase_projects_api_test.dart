import 'dart:convert';

import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_token_provider.dart';

void main() {
  test('reads the display name and project number', () async {
    late http.Request captured;
    final api = FirebaseProjectsApi(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'projectId': 'demo-project',
            'projectNumber': '123456789012',
            'displayName': 'Demo Project',
          }),
          200,
        );
      }),
    );

    final info = await api.getProject(
      'demo-project',
      FakeTokenProvider(headers: {'x-goog-user-project': 'demo-project'}),
    );

    expect(
      info,
      const FirebaseProjectInfo(
        projectId: 'demo-project',
        displayName: 'Demo Project',
        projectNumber: '123456789012',
      ),
    );
    expect(
      captured.url.toString(),
      'https://firebase.googleapis.com/v1beta1/projects/demo-project',
    );
    expect(captured.headers['Authorization'], 'Bearer token-1');
    expect(captured.headers['x-goog-user-project'], 'demo-project');
  });

  for (final status in [403, 404]) {
    test('returns null on HTTP $status', () async {
      final api = FirebaseProjectsApi(
        httpClient: MockClient(
          (_) async => http.Response('{"error":{}}', status),
        ),
      );
      expect(await api.getProject('demo-project', FakeTokenProvider()), isNull);
    });
  }

  test('throws on other failures', () async {
    final api = FirebaseProjectsApi(
      httpClient: MockClient((_) async => http.Response('oops', 500)),
    );
    await expectLater(
      api.getProject('demo-project', FakeTokenProvider()),
      throwsA(isA<FirebaseApiException>()),
    );
  });
}
