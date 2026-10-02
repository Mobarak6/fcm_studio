import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/utils/redact.dart';
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

  static final Uri listUri = Uri.parse(
    'https://firebase.googleapis.com/v1beta1/projects',
  );
  static const _maxPages = 50;

  /// Every Firebase project the account can see, following pages (spec §4.2),
  /// sorted by name. No `x-goog-user-project` header is sent, because no
  /// project is chosen yet (plan Decision 8). Throws [FirebaseApiException].
  Future<List<FirebaseProjectInfo>> listProjects(
    AccessTokenProvider auth,
  ) async {
    final token = await auth.getToken();
    final projects = <FirebaseProjectInfo>[];
    String? pageToken;
    for (var page = 0; page < _maxPages; page++) {
      final response = await _getListPage(token, pageToken);
      final json = _decodeObject(response.body);
      final results = json?['results'];
      if (results is List<Object?>) {
        for (final item in results.whereType<Map<String, Object?>>()) {
          final info = _listedProject(item);
          if (info != null) {
            projects.add(info);
          }
        }
      }
      final next = json?['nextPageToken'];
      if (next is! String || next.isEmpty) {
        break;
      }
      pageToken = next;
    }
    projects.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return projects;
  }

  Future<http.Response> _getListPage(
    AccessToken token,
    String? pageToken,
  ) async {
    final http.Response response;
    try {
      response = await _http
          .get(
            listUri.replace(
              queryParameters: {'pageSize': '100', 'pageToken': ?pageToken},
            ),
            headers: {'Authorization': 'Bearer ${token.value}'},
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const FirebaseApiException(
        'The Firebase Management API did not answer within 20 seconds.',
      );
    } on Exception catch (e) {
      throw FirebaseApiException(
        'Network error while listing your Firebase projects: ${redact('$e')}',
      );
    }
    if (response.statusCode != 200) {
      throw FirebaseApiException(_describeListError(response));
    }
    return response;
  }

  static FirebaseProjectInfo? _listedProject(Map<String, Object?> item) {
    final id = item['projectId'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    final name = item['displayName'];
    final number = item['projectNumber'];
    return FirebaseProjectInfo(
      projectId: id,
      displayName: name is String && name.isNotEmpty ? name : id,
      projectNumber: number is String ? number : null,
    );
  }

  static Map<String, Object?>? _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String _describeListError(http.Response response) {
    final error = FcmError.fromResponse(response.statusCode, response.body);
    final detail = error.message == null ? '' : ': ${error.message}';
    if (error.reason == 'SERVICE_DISABLED') {
      return 'The Firebase Management API is not enabled in the Google Cloud '
          "project that owns FCM Studio's OAuth client. Enable it there (see "
          'docs/oauth-setup.md), wait a few minutes, then try again.';
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      return 'Google refused to list your Firebase projects '
          '(HTTP ${response.statusCode}$detail).';
    }
    return 'Listing your Firebase projects failed '
        '(HTTP ${response.statusCode}$detail).';
  }
}
