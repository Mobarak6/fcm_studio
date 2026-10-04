import 'dart:typed_data';

/// The browser couldn't claim the phone's adb interface, usually because adb
/// or Android Studio holds it (design §7).
class UsbClaimException implements Exception {
  const UsbClaimException(this.message);

  final String message;

  @override
  String toString() => 'UsbClaimException: $message';
}

/// A USB transfer failed: the phone was unplugged or reset.
class UsbDisconnectedException implements Exception {
  const UsbDisconnectedException([
    this.message = 'The phone was disconnected.',
  ]);

  final String message;

  @override
  String toString() => 'UsbDisconnectedException: $message';
}

/// Bytes to and from a phone's adb interface (design §4.2).
abstract interface class UsbTransport {
  /// One bulk IN transfer of up to [length] bytes.
  Future<Uint8List> read(int length);

  /// One bulk OUT transfer.
  Future<void> write(Uint8List bytes);

  Future<void> close();
}
