import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:equatable/equatable.dart';

class ServiceAccountKeyException implements Exception {
  const ServiceAccountKeyException(this.message);

  final String message;

  @override
  String toString() => 'ServiceAccountKeyException: $message';
}

/// A parsed and validated Google service account key file.
class ServiceAccountKey extends Equatable {
  const ServiceAccountKey._({
    required this.projectId,
    required this.clientEmail,
    required this.privateKeyId,
    required this.privateKeyPem,
    required this.rawJson,
  });

  factory ServiceAccountKey.parse(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw const ServiceAccountKeyException(
        'This file is not valid JSON. Choose the .json key file downloaded from Firebase.',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const ServiceAccountKeyException(
        'This file is not a service account key (expected a JSON object).',
      );
    }
    final json = decoded;

    if (json.containsKey('project_info') && json.containsKey('client')) {
      throw const ServiceAccountKeyException(
        'This is google-services.json, the Android app config. You need a service account key: '
        'Firebase console → Project settings → Service accounts → Generate new private key.',
      );
    }
    if (json.containsKey('installed') || json.containsKey('web')) {
      throw const ServiceAccountKeyException(
        'This is an OAuth client file, not a service account key. '
        'Generate one in Firebase console → Project settings → Service accounts.',
      );
    }
    final type = json['type'];
    if (type != 'service_account') {
      throw ServiceAccountKeyException(
        'This key has type "${type ?? 'missing'}". A key with type "service_account" is required.',
      );
    }

    String requireField(String name) {
      final value = json[name];
      if (value is! String || value.trim().isEmpty) {
        throw ServiceAccountKeyException('The key file is missing "$name".');
      }
      return value;
    }

    final privateKeyPem = requireField('private_key');
    if (!privateKeyPem.contains('-----BEGIN PRIVATE KEY-----')) {
      throw const ServiceAccountKeyException(
        '"private_key" is not a PKCS#8 PEM key (expected "-----BEGIN PRIVATE KEY-----").',
      );
    }
    try {
      RSAPrivateKey(privateKeyPem);
    } catch (_) {
      throw const ServiceAccountKeyException(
        '"private_key" could not be read as an RSA key. Download a new key file.',
      );
    }

    final keyId = json['private_key_id'];
    return ServiceAccountKey._(
      projectId: requireField('project_id'),
      clientEmail: requireField('client_email'),
      privateKeyId: keyId is String ? keyId : '',
      privateKeyPem: privateKeyPem,
      rawJson: jsonText,
    );
  }

  final String projectId;
  final String clientEmail;
  final String privateKeyId;
  final String privateKeyPem;

  /// The original file contents, stored in SecretStore as-is.
  final String rawJson;

  @override
  List<Object?> get props => [
    projectId,
    clientEmail,
    privateKeyId,
    privateKeyPem,
  ];

  @override
  String toString() => 'ServiceAccountKey($clientEmail, project: $projectId)';
}
