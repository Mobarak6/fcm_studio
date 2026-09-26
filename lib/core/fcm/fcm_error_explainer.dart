import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';

class ErrorExplanation extends Equatable {
  const ErrorExplanation({
    required this.title,
    required this.explanation,
    required this.action,
    this.link,
  });

  final String title;
  final String explanation;
  final String action;
  final Uri? link;

  @override
  List<Object?> get props => [title, explanation, action, link];
}

/// Turns an [FcmError] into plain words: what happened, why, and what to do.
class FcmErrorExplainer {
  const FcmErrorExplainer();

  ErrorExplanation explain(FcmError error, {required String projectId}) {
    switch (error.transport) {
      case FcmTransportError.network:
        return ErrorExplanation(
          title: 'Network error',
          explanation:
              'Could not reach FCM${error.message == null ? '.' : ': ${error.message}'}',
          action: 'Check your internet connection, then retry.',
        );
      case FcmTransportError.timeout:
        return ErrorExplanation(
          title: 'FCM did not respond',
          explanation: error.message ?? 'No response within 20 seconds.',
          action:
              'Retry. If it keeps happening, check your connection or proxy.',
        );
      case FcmTransportError.auth:
        return ErrorExplanation(
          title: 'Could not get an access token',
          explanation: error.message ?? 'Google did not issue an access token.',
          action: 'Add the project again with its service account key file.',
        );
      case FcmTransportError.none:
        break;
    }

    switch (error.fcmErrorCode ?? error.status) {
      case 'UNREGISTERED':
        return const ErrorExplanation(
          title: 'Token is no longer valid',
          explanation:
              'The app was uninstalled, its data was cleared, '
              'or it received a new token since this one was copied.',
          action: 'Get the current token from the device and send again.',
        );
      case 'INVALID_ARGUMENT':
        return ErrorExplanation(
          title: 'FCM rejected the message',
          explanation: error.fieldViolations.isEmpty
              ? error.message ?? 'The request is not a valid FCM message.'
              : error.fieldViolations
                    .map((v) => '• ${v.field}: ${v.description}')
                    .join('\n'),
          action: 'Fix the fields listed above in the JSON, then send again.',
        );
      case 'SENDER_ID_MISMATCH':
        return ErrorExplanation(
          title: 'Token belongs to another Firebase project',
          explanation:
              'This token was issued for a different sender than project $projectId.',
          action:
              'Select the project the app is built with, '
              'or get a token from an app that uses $projectId.',
        );
      case 'QUOTA_EXCEEDED':
        return const ErrorExplanation(
          title: 'Sending too fast',
          explanation:
              "FCM's rate limit for this project or device was reached.",
          action: 'Wait a minute, then retry.',
        );
      case 'UNAVAILABLE' || 'INTERNAL':
        return _temporary(error);
      case 'THIRD_PARTY_AUTH_ERROR':
        return ErrorExplanation(
          title: 'APNs or web push credentials problem',
          explanation:
              'Firebase could not authenticate with Apple (APNs) or the web push '
              'service to deliver this message.',
          action:
              'Upload a valid APNs authentication key in Project settings → Cloud Messaging.',
          link: Uri.parse(
            'https://console.firebase.google.com/project/$projectId/settings/cloudmessaging',
          ),
        );
    }

    if (error.reason == 'SERVICE_DISABLED') {
      return ErrorExplanation(
        title: 'The FCM API is not enabled',
        explanation:
            error.message ??
            'Firebase Cloud Messaging API is disabled for this project.',
        action:
            'Enable "Firebase Cloud Messaging API" for $projectId, wait a few minutes, then retry.',
        link: Uri.parse(
          'https://console.developers.google.com/apis/api/fcm.googleapis.com/overview?project=$projectId',
        ),
      );
    }

    final status = error.httpStatus;
    if (status == 401) {
      return const ErrorExplanation(
        title: 'Access token rejected',
        explanation:
            'Google rejected the access token even after getting a fresh one. '
            'The key may have been deleted or the service account disabled.',
        action:
            'Create a new key for the service account and add the project again.',
      );
    }
    if (status == 403) {
      return ErrorExplanation(
        title: 'Permission denied',
        explanation:
            'This service account is not allowed to send messages for $projectId.',
        action:
            'In Google Cloud IAM, give the service account the '
            '"Firebase Cloud Messaging API Admin" role.',
        link: Uri.parse(
          'https://console.cloud.google.com/iam-admin/iam?project=$projectId',
        ),
      );
    }
    if (status == 404) {
      return ErrorExplanation(
        title: 'Not found',
        explanation: error.message ?? 'FCM could not find this project.',
        action: 'Check that the key file belongs to $projectId.',
      );
    }
    if (status != null && status >= 500) {
      return _temporary(error);
    }
    return ErrorExplanation(
      title: 'FCM returned an error${status == null ? '' : ' (HTTP $status)'}',
      explanation: error.message ?? 'No details were returned.',
      action: 'See the raw response below.',
    );
  }

  static ErrorExplanation _temporary(FcmError error) => ErrorExplanation(
    title: 'Temporary FCM problem',
    explanation: error.message ?? 'FCM returned a server error.',
    action: 'Retry in a few seconds.',
  );
}
