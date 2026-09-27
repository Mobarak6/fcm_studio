import 'dart:io';

import 'package:fcm_studio/core/fcm/curl_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const body = {
    'message': {'topic': 'news'},
  };

  test('builds a bash command that reads the token from a variable', () {
    final command = CurlBuilder.build(projectId: 'demo-project', body: body);
    expect(
      command,
      "curl -X POST 'https://fcm.googleapis.com/v1/projects/demo-project/messages:send' \\\n"
      '  -H "Authorization: Bearer \$FCM_ACCESS_TOKEN" \\\n'
      "  -H 'Content-Type: application/json; charset=utf-8' \\\n"
      """  -d '{"message":{"topic":"news"}}'""",
    );
  });

  test('can include the access token and extra headers', () {
    final command = CurlBuilder.build(
      projectId: 'demo-project',
      body: body,
      accessToken: 'ya29.abc',
      extraHeaders: {'x-goog-user-project': 'demo-project'},
    );
    expect(command, contains("-H 'Authorization: Bearer ya29.abc'"));
    expect(command, contains("-H 'x-goog-user-project: demo-project'"));
  });

  test('escapes single quotes in the body', () {
    final command = CurlBuilder.build(
      projectId: 'demo-project',
      body: {
        'message': {
          'notification': {'title': "it's"},
        },
      },
    );
    expect(
      command,
      contains(r"""-d '{"message":{"notification":{"title":"it'\''s"}}}'"""),
    );
  });

  test('quoting survives bash', () async {
    const tricky = 'it\'s a "test" with \$HOME and \\n';
    final result = await Process.run('bash', [
      '-c',
      'printf %s ${CurlBuilder.quote(tricky)}',
    ]);
    expect(result.stdout, tricky);
  }, skip: Platform.isWindows ? 'needs bash' : false);
}
