import 'dart:js_interop';
import 'dart:typed_data';

import 'package:fcm_studio/features/devices/data/webusb/browser/usb_interop.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';

/// The adb interface: class 0xFF, subclass 0x42, protocol 0x01.
const adbClass = 0xFF;
const adbSubclass = 0x42;
const adbProtocol = 0x01;

/// Where a device's adb interface and its bulk endpoints are.
class AdbInterface {
  const AdbInterface({
    required this.configurationValue,
    required this.interfaceNumber,
    required this.inEndpoint,
    required this.outEndpoint,
    required this.packetSize,
  });

  final int configurationValue;
  final int interfaceNumber;
  final int inEndpoint;
  final int outEndpoint;
  final int packetSize;
}

/// The device's adb interface, or null when it has none.
AdbInterface? findAdbInterface(UsbDevice device) {
  for (final configuration in device.configurations.toDart) {
    for (final interface in configuration.interfaces.toDart) {
      for (final alternate in interface.alternates.toDart) {
        if (alternate.interfaceClass != adbClass ||
            alternate.interfaceSubclass != adbSubclass ||
            alternate.interfaceProtocol != adbProtocol) {
          continue;
        }
        UsbEndpoint? inEndpoint;
        UsbEndpoint? outEndpoint;
        for (final endpoint in alternate.endpoints.toDart) {
          if (endpoint.type != 'bulk') {
            continue;
          }
          if (endpoint.direction == 'in') {
            inEndpoint = endpoint;
          } else {
            outEndpoint = endpoint;
          }
        }
        if (inEndpoint != null && outEndpoint != null) {
          return AdbInterface(
            configurationValue: configuration.configurationValue,
            interfaceNumber: interface.interfaceNumber,
            inEndpoint: inEndpoint.endpointNumber,
            outEndpoint: outEndpoint.endpointNumber,
            packetSize: outEndpoint.packetSize,
          );
        }
      }
    }
  }
  return null;
}

/// A claimed adb interface (design §4.2).
class WebUsbTransport implements UsbTransport {
  WebUsbTransport._(this._device, this._interface);

  /// Opens [device] and claims its adb interface. Throws
  /// [UsbClaimException] when that fails, usually because adb or Android
  /// Studio holds the phone.
  static Future<WebUsbTransport> open(UsbDevice device) async {
    final interface = findAdbInterface(device);
    if (interface == null) {
      throw const UsbClaimException('This device has no adb interface.');
    }
    try {
      if (!device.opened) {
        await device.open().toDart;
      }
      if (device.configuration?.configurationValue !=
          interface.configurationValue) {
        await device.selectConfiguration(interface.configurationValue).toDart;
      }
      await device.claimInterface(interface.interfaceNumber).toDart;
    } on Object catch (error) {
      throw UsbClaimException('$error');
    }
    return WebUsbTransport._(device, interface);
  }

  final UsbDevice _device;
  final AdbInterface _interface;

  @override
  Future<Uint8List> read(int length) async {
    final UsbInTransferResult result;
    try {
      result = await _device.transferIn(_interface.inEndpoint, length).toDart;
    } on Object catch (error) {
      throw UsbDisconnectedException('$error');
    }
    final data = result.data;
    if (result.status != 'ok' || data == null) {
      throw UsbDisconnectedException('USB read failed: ${result.status}.');
    }
    final bytes = data.toDart;
    return Uint8List.fromList(
      bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
    );
  }

  @override
  Future<void> write(Uint8List bytes) async {
    try {
      await _transfer(bytes);
      // Some phones wait for a zero-length packet after a transfer that
      // fills its last USB packet exactly (design §12).
      if (bytes.isNotEmpty && bytes.length % _interface.packetSize == 0) {
        await _transfer(Uint8List(0));
      }
    } on UsbDisconnectedException {
      rethrow;
    } on Object catch (error) {
      throw UsbDisconnectedException('$error');
    }
  }

  Future<void> _transfer(Uint8List bytes) async {
    final result = await _device
        .transferOut(_interface.outEndpoint, bytes.toJS)
        .toDart;
    if (result.status != 'ok') {
      throw UsbDisconnectedException('USB write failed: ${result.status}.');
    }
  }

  @override
  Future<void> close() async {
    try {
      await _device.releaseInterface(_interface.interfaceNumber).toDart;
      await _device.close().toDart;
    } on Object {
      // Unplugged phones can't be released; the browser cleans up.
    }
  }
}
