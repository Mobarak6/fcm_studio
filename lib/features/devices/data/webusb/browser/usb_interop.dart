// WebUSB isn't in package:web (it only covers standards-track APIs), so the
// few calls FCM Studio needs are declared here. Web only (design §4.1).
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

/// `navigator.usb`, or null in browsers without WebUSB.
Usb? get navigatorUsb {
  final usb = (web.window.navigator as JSObject).getProperty<JSAny?>(
    'usb'.toJS,
  );
  return usb.isUndefinedOrNull ? null : usb as Usb;
}

extension type Usb._(JSObject _) implements web.EventTarget {
  external JSPromise<JSArray<UsbDevice>> getDevices();
  external JSPromise<UsbDevice> requestDevice(UsbDeviceRequestOptions options);
}

extension type UsbDeviceRequestOptions._(JSObject _) implements JSObject {
  external factory UsbDeviceRequestOptions({
    required JSArray<UsbDeviceFilter> filters,
  });
}

extension type UsbDeviceFilter._(JSObject _) implements JSObject {
  external factory UsbDeviceFilter({
    int classCode,
    int subclassCode,
    int protocolCode,
  });
}

extension type UsbDevice._(JSObject _) implements JSObject {
  external String? get serialNumber;
  external String? get productName;
  external int get vendorId;
  external int get productId;
  external bool get opened;
  external UsbConfiguration? get configuration;
  external JSArray<UsbConfiguration> get configurations;
  external JSPromise<JSAny?> open();
  external JSPromise<JSAny?> close();
  external JSPromise<JSAny?> forget();
  external JSPromise<JSAny?> selectConfiguration(int configurationValue);
  external JSPromise<JSAny?> claimInterface(int interfaceNumber);
  external JSPromise<JSAny?> releaseInterface(int interfaceNumber);
  external JSPromise<UsbInTransferResult> transferIn(
    int endpointNumber,
    int length,
  );
  external JSPromise<UsbOutTransferResult> transferOut(
    int endpointNumber,
    JSUint8Array data,
  );
}

extension type UsbConfiguration._(JSObject _) implements JSObject {
  external int get configurationValue;
  external JSArray<UsbInterface> get interfaces;
}

extension type UsbInterface._(JSObject _) implements JSObject {
  external int get interfaceNumber;
  external JSArray<UsbAlternateInterface> get alternates;
}

extension type UsbAlternateInterface._(JSObject _) implements JSObject {
  external int get interfaceClass;
  external int get interfaceSubclass;
  external int get interfaceProtocol;
  external JSArray<UsbEndpoint> get endpoints;
}

extension type UsbEndpoint._(JSObject _) implements JSObject {
  external int get endpointNumber;

  /// `in` or `out`.
  external String get direction;

  /// `bulk`, `interrupt` or `isochronous`.
  external String get type;
  external int get packetSize;
}

extension type UsbInTransferResult._(JSObject _) implements JSObject {
  external JSDataView? get data;

  /// `ok`, `stall` or `babble`.
  external String get status;
}

extension type UsbOutTransferResult._(JSObject _) implements JSObject {
  external int get bytesWritten;
  external String get status;
}

extension type UsbConnectionEvent._(JSObject _) implements web.Event {
  external UsbDevice get device;
}
