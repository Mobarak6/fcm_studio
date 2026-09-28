import 'dart:convert';

import 'package:file_selector/file_selector.dart';

/// Opening and saving text files: preset import and export (spec §6).
abstract interface class FileAccess {
  /// Asks for a file and returns its text, or null when the user cancels.
  Future<String?> openText({
    required String label,
    required List<String> extensions,
  });

  /// Saves [text]. Desktop asks where to save; web downloads the file.
  /// Returns false when the user cancels.
  Future<bool> saveText({required String suggestedName, required String text});
}

class PlatformFileAccess implements FileAccess {
  const PlatformFileAccess();

  @override
  Future<String?> openText({
    required String label,
    required List<String> extensions,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: label,
          extensions: extensions,
          mimeTypes: const ['application/json'],
          uniformTypeIdentifiers: const ['public.json'],
        ),
      ],
    );
    return file?.readAsString();
  }

  @override
  Future<bool> saveText({
    required String suggestedName,
    required String text,
  }) async {
    // On web this returns a placeholder location, and saveTo downloads the
    // file under its name.
    final location = await getSaveLocation(suggestedName: suggestedName);
    if (location == null) {
      return false;
    }
    await XFile.fromData(
      utf8.encode(text),
      mimeType: 'application/json',
      name: suggestedName,
    ).saveTo(location.path);
    return true;
  }
}
