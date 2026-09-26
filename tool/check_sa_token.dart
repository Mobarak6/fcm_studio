import 'dart:io';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/auth/service_account_token_provider.dart';
import 'package:http/http.dart' as http;

/// Usage: dart run tool/check_sa_token.dart <service-account.json>
/// Prints whether Google issues a token for the key. Never prints the token itself.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln(
      'Usage: dart run tool/check_sa_token.dart <service-account.json>',
    );
    exitCode = 64;
    return;
  }
  final client = http.Client();
  try {
    final key = ServiceAccountKey.parse(await File(args.single).readAsString());
    final token = await ServiceAccountTokenProvider(
      key: key,
      httpClient: client,
    ).getToken();
    final seconds = token.expiresAt
        .difference(DateTime.now().toUtc())
        .inSeconds;
    stdout.writeln(
      'OK: Google issued an access token for ${key.clientEmail} '
      '(project ${key.projectId}), valid for ${seconds}s.',
    );
  } on ServiceAccountKeyException catch (e) {
    stderr.writeln('Invalid key file: ${e.message}');
    exitCode = 1;
  } on AuthException catch (e) {
    stderr.writeln('Token request failed: ${e.message}');
    exitCode = 1;
  } finally {
    client.close();
  }
}
