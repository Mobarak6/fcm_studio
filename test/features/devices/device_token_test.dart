import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/device_fixtures.dart';

void main() {
  DeviceToken token(TokenReadMethod method) => DeviceToken(
    token: fakeDeviceToken,
    senderId: '123456789012',
    method: method,
    readAt: DateTime.utc(2026, 10, 4),
    serial: redmiSerial,
    package: 'com.syldel.delivery',
    deviceName: 'Redmi 14C',
  );

  test('the label names the phone, the app and the build type (spec §7.1)', () {
    expect(
      token(TokenReadMethod.runAs).label,
      'Redmi 14C · com.syldel.delivery (debug)',
    );
    expect(
      token(TokenReadMethod.logcat).label,
      'Redmi 14C · com.syldel.delivery (release)',
    );
  });
}
