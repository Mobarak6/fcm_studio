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

  group('listProjects', () {
    Map<String, Object?> listed(String id, String name, String number) => {
      'projectId': id,
      'displayName': name,
      'projectNumber': number,
    };

    test(
      'follows every page, sorts by name, and sends no quota project',
      () async {
        final requests = <http.Request>[];
        final api = FirebaseProjectsApi(
          httpClient: MockClient((request) async {
            requests.add(request);
            final second = request.url.queryParameters['pageToken'] == 'p2';
            return http.Response(
              jsonEncode(
                second
                    ? {
                        'results': [listed('alpha-app', 'Alpha', '111')],
                      }
                    : {
                        'results': [listed('zulu-app', 'Zulu', '999')],
                        'nextPageToken': 'p2',
                      },
              ),
              200,
            );
          }),
        );

        final projects = await api.listProjects(
          FakeTokenProvider(
            headers: {'x-goog-user-project': 'must-not-be-sent'},
          ),
        );

        expect(projects.map((p) => p.projectId), ['alpha-app', 'zulu-app']);
        expect(
          projects.first,
          const FirebaseProjectInfo(
            projectId: 'alpha-app',
            displayName: 'Alpha',
            projectNumber: '111',
          ),
        );
        expect(requests, hasLength(2));
        expect(requests.first.url.path, '/v1beta1/projects');
        expect(requests.first.url.queryParameters['pageSize'], '100');
        expect(requests.first.headers['Authorization'], 'Bearer token-1');
        expect(
          requests.first.headers.containsKey('x-goog-user-project'),
          isFalse,
        );
      },
    );

    test('an account without Firebase projects gets an empty list', () async {
      final api = FirebaseProjectsApi(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(await api.listProjects(FakeTokenProvider()), isEmpty);
    });

    test(
      'a project without a name shows its ID; items without an ID are skipped',
      () async {
        final api = FirebaseProjectsApi(
          httpClient: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'results': [
                  {'projectId': 'bare-app'},
                  {'displayName': 'No ID'},
                ],
              }),
              200,
            ),
          ),
        );
        expect(await api.listProjects(FakeTokenProvider()), [
          const FirebaseProjectInfo(
            projectId: 'bare-app',
            displayName: 'bare-app',
          ),
        ]);
      },
    );

    test('a disabled Firebase Management API says where to enable it', () async {
      final api = FirebaseProjectsApi(
        httpClient: MockClient(
          (_) async => http.Response(
            '{"error":{"code":403,"message":"Firebase Management API has not been used '
            'in project 42 before or it is disabled.","status":"PERMISSION_DENIED",'
            '"details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo",'
            '"reason":"SERVICE_DISABLED"}]}}',
            403,
          ),
        ),
      );
      await expectLater(
        api.listProjects(FakeTokenProvider()),
        throwsA(
          isA<FirebaseApiException>().having(
            (e) => e.message,
            'message',
            allOf(contains('OAuth client'), contains('docs/oauth-setup.md')),
          ),
        ),
      );
    });

    test('other errors name the HTTP status', () async {
      final api = FirebaseProjectsApi(
        httpClient: MockClient((_) async => http.Response('oops', 500)),
      );
      await expectLater(
        api.listProjects(FakeTokenProvider()),
        throwsA(
          isA<FirebaseApiException>().having(
            (e) => e.message,
            'message',
            contains('HTTP 500'),
          ),
        ),
      );
    });

    test('a page token that never ends stops after 50 pages', () async {
      var calls = 0;
      final api = FirebaseProjectsApi(
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{"results":[],"nextPageToken":"again"}', 200);
        }),
      );
      expect(await api.listProjects(FakeTokenProvider()), isEmpty);
      expect(calls, 50);
    });
  });
}
