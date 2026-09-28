import 'package:fcm_studio/core/platform/file_access.dart';

class FakeFileAccess implements FileAccess {
  /// Returned by the next [openText]; null acts like the user cancelling.
  String? nextOpen;

  /// Every file saved, in order.
  final List<({String name, String text})> saved = [];

  @override
  Future<String?> openText({
    required String label,
    required List<String> extensions,
  }) async => nextOpen;

  @override
  Future<bool> saveText({
    required String suggestedName,
    required String text,
  }) async {
    saved.add((name: suggestedName, text: text));
    return true;
  }
}
