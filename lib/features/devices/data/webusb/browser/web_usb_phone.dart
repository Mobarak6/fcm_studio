import 'dart:async';
import 'dart:js_interop';

import 'package:fcm_studio/features/devices/data/webusb/browser/usb_interop.dart';
import 'package:fcm_studio/features/devices/data/webusb/browser/web_usb_transport.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_phone.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';
import 'package:web/web.dart' as web;

/// One browser USB device with an adb interface.
class WebUsbPhone implements UsbPhone {
  WebUsbPhone(this.device);

  final UsbDevice device;

  @override
  String get serialNumber => device.serialNumber ?? '';

  @override
  String get productName => device.productName ?? '';

  @override
  int get vendorId => device.vendorId;

  @override
  int get productId => device.productId;

  @override
  Future<UsbTransport> open() => WebUsbTransport.open(device);

  @override
  Future<void> forget() async {
    try {
      await device.forget().toDart;
    } on Object {
      // Browsers before Chrome 101 can't forget; the phone stays allowed.
    }
  }
}

/// `navigator.usb`, limited to phones with an adb interface.
class WebUsbPhoneSource implements UsbPhoneSource {
  WebUsbPhoneSource(this._usb);

  final Usb _usb;

  /// One wrapper per device, so the same phone is the same object.
  final List<WebUsbPhone> _phones = [];

  WebUsbPhone _wrap(UsbDevice device) {
    for (final phone in _phones) {
      if (phone.device == device) {
        return phone;
      }
    }
    final phone = WebUsbPhone(device);
    _phones.add(phone);
    return phone;
  }

  @override
  Future<List<UsbPhone>> permitted() async => [
    for (final device in (await _usb.getDevices().toDart).toDart)
      if (findAdbInterface(device) != null) _wrap(device),
  ];

  @override
  Future<UsbPhone?> request() async {
    try {
      final device = await _usb
          .requestDevice(
            UsbDeviceRequestOptions(
              filters: [
                UsbDeviceFilter(
                  classCode: adbClass,
                  subclassCode: adbSubclass,
                  protocolCode: adbProtocol,
                ),
              ].toJS,
            ),
          )
          .toDart;
      return _wrap(device);
    } on Object {
      // The user closed the chooser (NotFoundError).
      return null;
    }
  }

  @override
  Stream<UsbPhone> get connected => _events(
    'connect',
  ).where((device) => findAdbInterface(device) != null).map(_wrap);

  @override
  Stream<UsbPhone> get disconnected => _events('disconnect').map(_wrap);

  Stream<UsbDevice> _events(String type) => web.EventStreamProvider<web.Event>(
    type,
  ).forTarget(_usb).map((event) => (event as UsbConnectionEvent).device);
}
