import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:http/http.dart' as http;

class FirebaseProjectInfo extends Equatable {
  const FirebaseProjectInfo({
    required this.projectId,
    required this.displayName,
    this.projectNumber,
  });

  final String projectId;
  final String displayName;
  final String? projectNumber;

  @override
  List<Object?> get props => [projectId, displayName, projectNumber];
}

class FirebaseApiException implements Exception {
  const FirebaseApiException(this.message);

  final String message;

  @override
  String toString() => 'FirebaseApiException: $message';
}

/// Reads project details from the Firebase Management API.
class FirebaseProjectsApi {
  FirebaseProjectsApi({required http.Client httpClient}) : _http = httpClient;

  final http.Client _http;

  static Uri projectUri(String projectId) => Uri.parse(
    'https://firebase.googleapis.com/v1beta1/projects/${Uri.encodeComponent(projectId)}',
  );

  /// Returns null when the credential may not read project details (403)
  /// or the project is not a Firebase project (404).
  Future<FirebaseProjectInfo?> getProject(
    String projectId,
    AccessTokenProvider auth,
  ) async {
    final token = await auth.getToken();
    final response = await _http
        .get(
          projectUri(projectId),
          headers: {
            'Authorization': 'Bearer ${token.value}',
            ...auth.extraHeaders(projectId),
          },
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 403 || response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw FirebaseApiException(
        'Firebase Management API returned HTTP ${response.statusCode}.',
      );
    }
    final json = jsonDecode(response.body) as Map<String, Object?>;
    final displayName = json['displayName'];
    final projectNumber = json['projectNumber'];
    return FirebaseProjectInfo(
      projectId: projectId,
      displayName: displayName is String && displayName.isNotEmpty
          ? displayName
          : projectId,
      projectNumber: projectNumber is String ? projectNumber : null,
    );
  }
}
