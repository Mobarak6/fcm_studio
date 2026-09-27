import 'package:fcm_studio/core/utils/shorten.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('shortens long values in the middle and leaves short ones alone', () {
    expect(shortenMiddle('fAbC12345678909xYz'), 'fAbC12…9xYz');
    expect(shortenMiddle('news'), 'news');
  });
}
