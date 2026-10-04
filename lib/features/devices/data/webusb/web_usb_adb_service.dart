import 'dart:async';

import 'package:fcm_studio/features/devices/data/adb_commands.dart';
import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/data/phone_access.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_connection.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_key.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_phone.dart';
import 'package:fcm_studio/features/devices/data/webusb/usb_transport.dart';
import 'package:fcm_studio/features/devices/data/webusb/web_usb_device_shell.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';

/// The browser's phones as an [AdbService] (design §4.8): one adb connection
/// per phone, and the same phone commands as desktop.
class WebUsbAdbService implements AdbService, PhoneAccess {
  WebUsbAdbService({
    required this._source,
    required this._loadKey,
    required this._keyName,
    this._isWindows = false,
  });

  /// On the web there is no adb path; this stands in for it, so
  /// `DevicesBloc` and `TokenReaderCubit` work unchanged.
  static const source = 'webusb';

  static const connectingNote = 'Connecting…';
  static const inUseNote =
      'This phone is in use by another program. Close Android Studio or run '
      '`adb kill-server`, then click Retry.';
  static const windowsDriverNote =
      ' If it still fails, install the Google USB Driver for this phone.';
  static const tooOldNote =
      'This phone runs Android 6 or older. Use the desktop app for it.';
  static const notReadyMessage =
      'The phone is not connected. Plug it in and click Retry.';

  final UsbPhoneSource _source;
  final Future<AdbKey> Function() _loadKey;
  final String _keyName;
  final bool _isWindows;
  final List<_Phone> _phones = [];
  final StreamController<List<AdbDevice>> _changes =
      StreamController<List<AdbDevice>>.broadcast();
  late final AdbCommands _commands = AdbCommands(
    shell: WebUsbDeviceShell(connectionFor: _connectionFor, nameOf: _nameOf),
  );
  Future<void>? _started;
  int _fallbackSerials = 0;

  /// The current phones at once, then every change. Never ends.
  @override
  Stream<List<AdbDevice>> trackDevices() {
    late final StreamController<List<AdbDevice>> controller;
    StreamSubscription<List<AdbDevice>>? changes;
    controller = StreamController<List<AdbDevice>>(
      onListen: () {
        changes = _changes.stream.listen(controller.add);
        controller.add(_devices());
        unawaited(_start());
      },
      onCancel: () => changes?.cancel(),
    );
    return controller.stream;
  }

  @override
  Future<DeviceDetails> deviceDetails(String serial) =>
      _commands.deviceDetails(serial);

  @override
  Future<List<String>> listPackages(String serial) =>
      _commands.listPackages(serial);

  @override
  Future<RunAsResult> readTokenWithRunAs(String serial, String package) =>
      _commands.readTokenWithRunAs(serial, package);

  @override
  Future<void> launchApp(String serial, String package) =>
      _commands.launchApp(serial, package);

  @override
  Stream<LogcatProgress> readTokenFromLogcat(String serial, String package) =>
      _commands.readTokenFromLogcat(serial, package);

  @override
  Future<void> connectPhone() async {
    await _start();
    final usb = await _source.request();
    if (usb == null) {
      return;
    }
    final known = _phoneFor(usb);
    if (known == null) {
      _add(usb);
    } else if (known.state != DeviceState.device) {
      unawaited(_connect(known));
    }
  }

  @override
  Future<void> retry(String serial) async {
    final phone = _find(serial);
    if (phone != null) {
      unawaited(_connect(phone));
    }
  }

  @override
  Future<void> forget(String serial) async {
    final phone = _find(serial);
    if (phone == null) {
      return;
    }
    _remove(phone.usb);
    await phone.usb.forget();
  }

  Future<void> _start() => _started ??= _listen();

  Future<void> _listen() async {
    _source.connected.listen(_add);
    _source.disconnected.listen(_remove);
    for (final usb in await _source.permitted()) {
      _add(usb);
    }
  }

  _Phone? _phoneFor(UsbPhone usb) {
    for (final phone in _phones) {
      if (identical(phone.usb, usb)) {
        return phone;
      }
    }
    return null;
  }

  _Phone? _find(String serial) {
    for (final phone in _phones) {
      if (phone.serial == serial) {
        return phone;
      }
    }
    return null;
  }

  void _add(UsbPhone usb) {
    if (_phoneFor(usb) != null) {
      return;
    }
    final phone = _Phone(usb, _serialFor(usb));
    _phones.add(phone);
    unawaited(_connect(phone));
  }

  /// The USB serial number, or `usb:<vendor>:<product>#<n>` when it is empty
  /// or another phone already has it (design §4.8).
  String _serialFor(UsbPhone usb) {
    final serial = usb.serialNumber;
    if (serial.isNotEmpty && _find(serial) == null) {
      return serial;
    }
    _fallbackSerials++;
    String hex(int id) => id.toRadixString(16).padLeft(4, '0');
    return 'usb:${hex(usb.vendorId)}:${hex(usb.productId)}#$_fallbackSerials';
  }

  void _remove(UsbPhone usb) {
    final phone = _phoneFor(usb);
    if (phone == null) {
      return;
    }
    _phones.remove(phone);
    phone.attempt++;
    final connection = phone.connection;
    phone.connection = null;
    if (connection != null) {
      unawaited(connection.close());
    }
    _emit();
  }

  /// Claims the phone and runs the handshake. A newer attempt, or the phone
  /// going away, makes an older one stop quietly.
  Future<void> _connect(_Phone phone) async {
    final attempt = ++phone.attempt;
    bool current() => phone.attempt == attempt && _phones.contains(phone);
    final old = phone.connection;
    phone.connection = null;
    _set(
      phone,
      DeviceState.other,
      rawState: 'connecting',
      note: connectingNote,
    );
    if (old != null) {
      await old.close();
    }
    try {
      final transport = await phone.usb.open();
      if (!current()) {
        await transport.close();
        return;
      }
      final connection = AdbConnection(
        transport: transport,
        loadKey: _loadKey,
        keyName: _keyName,
      );
      phone.connection = connection;
      unawaited(
        connection.lost.then((error) {
          if (current()) {
            _set(
              phone,
              DeviceState.offline,
              note: connectionFailureMessage(error),
            );
          }
        }),
      );
      final banner = await connection.connect(
        onWaitingForApproval: () {
          if (current()) {
            _set(phone, DeviceState.unauthorized);
          }
        },
      );
      if (!current()) {
        return;
      }
      if (!banner.hasShellV2) {
        phone.connection = null;
        await connection.close();
        _set(phone, DeviceState.offline, note: tooOldNote);
        return;
      }
      phone.model = banner.model;
      _set(phone, DeviceState.device);
    } on UsbClaimException {
      if (current()) {
        _set(
          phone,
          DeviceState.offline,
          note: _isWindows ? '$inUseNote$windowsDriverNote' : inUseNote,
        );
      }
    } on Object catch (error) {
      if (current()) {
        _set(phone, DeviceState.offline, note: connectionFailureMessage(error));
      }
    }
  }

  void _set(_Phone phone, DeviceState state, {String? rawState, String? note}) {
    phone
      ..state = state
      ..rawState = rawState ?? state.name
      ..note = note;
    _emit();
  }

  void _emit() => _changes.add(_devices());

  List<AdbDevice> _devices() => [
    for (final phone in _phones)
      AdbDevice(
        serial: phone.serial,
        state: phone.state,
        rawState: phone.rawState,
        model: phone.model ?? _nonEmpty(phone.usb.productName),
        note: phone.note,
      ),
  ];

  AdbConnection _connectionFor(String serial) {
    final phone = _find(serial);
    final connection = phone?.connection;
    if (phone == null ||
        phone.state != DeviceState.device ||
        connection == null) {
      throw const AdbException(notReadyMessage);
    }
    return connection;
  }

  String _nameOf(String serial) {
    final phone = _find(serial);
    if (phone == null) {
      return serial;
    }
    return _nonEmpty(phone.usb.productName) ?? phone.model ?? serial;
  }

  static String? _nonEmpty(String text) => text.isEmpty ? null : text;
}

class _Phone {
  _Phone(this.usb, this.serial);

  final UsbPhone usb;
  final String serial;
  DeviceState state = DeviceState.other;
  String rawState = 'connecting';
  String? note = WebUsbAdbService.connectingNote;
  String? model;
  AdbConnection? connection;

  /// Bumped by every connect and by removal; older attempts stop.
  int attempt = 0;
}
