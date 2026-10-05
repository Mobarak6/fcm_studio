import 'package:flutter_test/flutter_test.dart';

/// Waits in real time until [condition] holds, and fails after [timeout].
Future<void> eventually(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > timeout) {
      fail('Timed out waiting for a condition.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}
