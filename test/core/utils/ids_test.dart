import 'package:fcm_studio/core/utils/ids.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('newUuid returns distinct version 4 UUIDs', () {
    final pattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    );
    final ids = {for (var i = 0; i < 100; i++) newUuid()};
    expect(ids, hasLength(100));
    expect(ids.every(pattern.hasMatch), isTrue);
  });
}
