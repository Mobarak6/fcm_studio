import 'dart:convert';
import 'dart:io';

const testProjectId = 'demo-project';
const testProjectNumber = '123456789012';
const testClientEmail = 'fcm-sender@demo-project.iam.gserviceaccount.com';

String testPrivateKeyPem() =>
    File('test/fixtures/keys/test_private_key.pem').readAsStringSync();

String testPublicKeyPem() =>
    File('test/fixtures/keys/test_public_key.pem').readAsStringSync();

Map<String, Object?> serviceAccountMap({
  String projectId = testProjectId,
  String clientEmail = testClientEmail,
}) => {
  'type': 'service_account',
  'project_id': projectId,
  'private_key_id': 'test-key-id-1',
  'private_key': testPrivateKeyPem(),
  'client_email': clientEmail,
  'client_id': '100000000000000000001',
  'auth_uri': 'https://accounts.google.com/o/oauth2/auth',
  'token_uri': 'https://oauth2.googleapis.com/token',
};

String serviceAccountJson({
  String projectId = testProjectId,
  String clientEmail = testClientEmail,
}) => jsonEncode(
  serviceAccountMap(projectId: projectId, clientEmail: clientEmail),
);
