/// What the Devices screen asks the browser to do with phones (WebUSB
/// design §4.8). Desktop has no such thing: adb finds phones itself.
abstract interface class PhoneAccess {
  /// Shows the browser's chooser. Must follow a button press.
  Future<void> connectPhone();

  /// Connects again to a phone that is offline or waiting for approval.
  Future<void> retry(String serial);

  /// Revokes this site's access to the phone and removes it.
  Future<void> forget(String serial);
}
