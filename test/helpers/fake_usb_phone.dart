import 'dart:async';

import 'package:fcm_studio/features/devices/data/webusb/usb_phone.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';

import 'fake_adbd.dart';

class FakeUsbPhone implements UsbPhone {
  FakeUsbPhone({
    this.serialNumber = 'DETWFUOZZHZ5SWFQ',
    this.productName = 'Redmi 14C',
    this.vendorId = 0x2717,
    this.productId = 0xFF48,
    FakeAdbd? adbd,
  }) : adbd = adbd ?? FakeAdbd();

  @override
  final String serialNumber;
  @override
  final String productName;
  @override
  final int vendorId;
  @override
  final int productId;

  /// The adbd behind open().
  FakeAdbd adbd;

  /// Thrown by open() when set, e.g. a [UsbClaimException].
  Object? openError;
  int opens = 0;
  bool forgotten = false;

  @override
  Future<UsbTransport> open() async {
    opens++;
    final error = openError;
    if (error != null) {
      throw error;
    }
    adbd.start();
    return adbd.transport;
  }

  @override
  Future<void> forget() async => forgotten = true;
}

class FakeUsbPhoneSource implements UsbPhoneSource {
  final List<UsbPhone> permittedPhones = [];

  /// What the chooser returns; null means the user closed it.
  UsbPhone? chosen;
  final StreamController<UsbPhone> connectedController =
      StreamController<UsbPhone>.broadcast();
  final StreamController<UsbPhone> disconnectedController =
      StreamController<UsbPhone>.broadcast();

  @override
  Future<List<UsbPhone>> permitted() async => [...permittedPhones];

  @override
  Future<UsbPhone?> request() async => chosen;

  @override
  Stream<UsbPhone> get connected => connectedController.stream;

  @override
  Stream<UsbPhone> get disconnected => disconnectedController.stream;
}
