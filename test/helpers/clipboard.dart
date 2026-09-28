import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what the app copies. Returns a function that reads the last copy.
String? Function() mockClipboard(WidgetTester tester) {
  String? copied;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'Clipboard.setData') {
      copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
    }
    return null;
  });
  addTearDown(
    () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
  );
  return () => copied;
}
