/// A phone command that failed. The message names the command (spec §11).
class AdbException implements Exception {
  const AdbException(this.message);

  final String message;

  @override
  String toString() => 'AdbException: $message';
}
