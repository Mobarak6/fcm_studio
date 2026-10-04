import 'package:fcm_studio/features/devices/data/phone_access.dart';

/// Records what the Devices screen asked the browser to do.
class FakePhoneAccess implements PhoneAccess {
  int connects = 0;
  final List<String> retried = [];
  final List<String> forgotten = [];

  /// Thrown by connectPhone when set.
  Object? connectError;

  @override
  Future<void> connectPhone() async {
    connects++;
    final error = connectError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<void> retry(String serial) async => retried.add(serial);

  @override
  Future<void> forget(String serial) async => forgotten.add(serial);
}
