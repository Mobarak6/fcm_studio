import 'package:fcm_studio/core/utils/time_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('formats local time with zero padding', () {
    expect(
      formatLocalTime(DateTime(2026, 3, 4, 5, 6, 7)),
      '2026-03-04 05:06:07',
    );
  });
}
