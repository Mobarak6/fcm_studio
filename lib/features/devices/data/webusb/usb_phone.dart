import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';

/// A USB device with an adb interface that this site may use (design §4.8).
abstract interface class UsbPhone {
  /// May be empty.
  String get serialNumber;
  String get productName;
  int get vendorId;
  int get productId;

  /// Opens the device and claims its adb interface. Throws
  /// [UsbClaimException] when another program holds it.
  Future<UsbTransport> open();

  /// Revokes this site's access to the phone.
  Future<void> forget();
}

/// The browser's phones: the ones this site may use, and the chooser.
abstract interface class UsbPhoneSource {
  Future<List<UsbPhone>> permitted();

  /// Shows the browser's chooser (needs a button press). Null when closed.
  Future<UsbPhone?> request();

  /// A permitted phone was plugged in. The same phone is the same object.
  Stream<UsbPhone> get connected;

  Stream<UsbPhone> get disconnected;
}
