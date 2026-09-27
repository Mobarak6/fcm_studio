class ReservedKeyProblem {
  const ReservedKeyProblem(this.message, {required this.blocking});

  final String message;

  /// True when FCM rejects the key; false when it only might cause trouble.
  final bool blocking;
}

abstract final class FcmRules {
  static final RegExp topicPattern = RegExp(r'^[a-zA-Z0-9\-_.~%]+$');
  static const maxPayloadBytes = 4096;

  static ReservedKeyProblem? reservedDataKeyProblem(String key) {
    if (key == 'from' || key == 'message_type') {
      return ReservedKeyProblem(
        '"$key" is reserved by FCM. Rename this key.',
        blocking: true,
      );
    }
    for (final prefix in const ['google.', 'gcm.notification.']) {
      if (key.startsWith(prefix)) {
        return ReservedKeyProblem(
          'Keys starting with "$prefix" are reserved by FCM. Rename this key.',
          blocking: true,
        );
      }
    }
    if (key == 'notification' ||
        key.startsWith('google') ||
        key.startsWith('gcm')) {
      return ReservedKeyProblem(
        '"$key" may be treated as reserved by older FCM SDKs. Consider renaming it.',
        blocking: false,
      );
    }
    return null;
  }
}
