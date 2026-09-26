import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fcm_fixtures.dart';

void main() {
  test('reads the FCM error code', () {
    final error = FcmError.fromResponse(404, unregisteredBody);
    expect(error.httpStatus, 404);
    expect(error.status, 'NOT_FOUND');
    expect(error.fcmErrorCode, 'UNREGISTERED');
    expect(error.message, 'Requested entity was not found.');
  });

  test('reads field violations', () {
    final error = FcmError.fromResponse(400, invalidArgumentBody);
    expect(error.status, 'INVALID_ARGUMENT');
    expect(error.fieldViolations.single.field, 'message.data[0].value');
  });

  test('reads the ErrorInfo reason', () {
    expect(
      FcmError.fromResponse(403, serviceDisabledBody).reason,
      'SERVICE_DISABLED',
    );
  });

  test('keeps a non-JSON body as the message', () {
    final error = FcmError.fromResponse(502, '<html>Bad Gateway</html>');
    expect(error.message, '<html>Bad Gateway</html>');
    expect(error.status, isNull);
    expect(error.fcmErrorCode, isNull);
  });

  test('an empty body has no message', () {
    expect(FcmError.fromResponse(500, '').message, isNull);
  });

  test('truncates very long non-JSON bodies', () {
    expect(FcmError.fromResponse(502, 'x' * 2000).message, hasLength(501));
  });
}
