import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/features/devices/data/process_runner.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_message.dart';
import 'package:fcm_studio/features/devices/data/webusb/shell_v2.dart';

import 'fake_usb_transport.dart';

/// Plays adbd on a phone: answers the handshake and runs scripted shell
/// commands over the shell v2 protocol.
class FakeAdbd {
  FakeAdbd({
    this.banner = 'device::ro.product.model=2409BRN2CA;features=shell_v2,cmd',
    this.requiresAuth = true,
    this.trustsKey = true,
    this.approves = true,
  });

  final FakeUsbTransport transport = FakeUsbTransport();
  final String banner;
  final bool requiresAuth;

  /// Accepts the signature (the phone already trusts this browser).
  bool trustsKey;

  /// The user taps Allow when the public key arrives.
  bool approves;

  /// Commands that finish: what they print and their exit code.
  final Map<String, ProcessOutput> commands = {};

  /// Commands that keep running; the test writes their stdout.
  final Map<String, StreamController<String>> running = {};

  /// Every command the host opened, in order.
  final List<String> opened = [];

  /// Long-running commands whose stream the host closed.
  final List<String> closedByHost = [];

  /// Set once the host sent its public key.
  bool sawPublicKey = false;

  final Map<int, String> _commandByRemoteId = {};
  int _nextId = 100;
  bool _serving = false;

  void start() {
    if (_serving) {
      return;
    }
    _serving = true;
    unawaited(_serve());
  }

  Future<void> _serve() async {
    while (true) {
      final AdbMessage message;
      try {
        message = await transport.nextHostMessage();
      } on Object {
        return;
      }
      switch (message.command) {
        case AdbCommand.cnxn:
          if (requiresAuth) {
            _sendToken();
          } else {
            _sendBanner();
          }
        case AdbCommand.auth when message.arg0 == 2:
          if (trustsKey) {
            _sendBanner();
          } else {
            _sendToken();
          }
        case AdbCommand.auth when message.arg0 == 3:
          sawPublicKey = true;
          if (approves) {
            _sendBanner();
          }
        case AdbCommand.open:
          _open(message);
        case AdbCommand.clse:
          final command = _commandByRemoteId.remove(message.arg1);
          if (command != null) {
            closedByHost.add(command);
          }
      }
    }
  }

  void _sendToken() => transport.phoneSends(
    AdbMessage(AdbCommand.auth, 1, 0, List<int>.generate(20, (i) => i)),
  );

  void _sendBanner() => transport.phoneSends(
    AdbMessage.text(AdbCommand.cnxn, 0x01000001, 256 * 1024, banner),
  );

  void _open(AdbMessage message) {
    final hostId = message.arg0;
    final service = message.text;
    const prefix = 'shell,v2,raw:';
    final command = service.startsWith(prefix)
        ? service.substring(prefix.length)
        : service;
    opened.add(command);
    final output = commands[command];
    final stdout = running[command];
    if (output == null && stdout == null) {
      transport.phoneSends(AdbMessage(AdbCommand.clse, 0, hostId));
      return;
    }
    final id = _nextId++;
    transport.phoneSends(AdbMessage(AdbCommand.okay, id, hostId));
    if (output != null) {
      transport
        ..phoneSends(
          AdbMessage(AdbCommand.wrte, id, hostId, [
            if (output.stdout.isNotEmpty)
              ...ShellV2.packet(ShellV2.stdout, utf8.encode(output.stdout)),
            if (output.stderr.isNotEmpty)
              ...ShellV2.packet(ShellV2.stderr, utf8.encode(output.stderr)),
            ...ShellV2.packet(ShellV2.exit, [output.exitCode]),
          ]),
        )
        ..phoneSends(AdbMessage(AdbCommand.clse, id, hostId));
    } else {
      _commandByRemoteId[id] = command;
      stdout!.stream.listen(
        (text) => transport.phoneSends(
          AdbMessage(
            AdbCommand.wrte,
            id,
            hostId,
            ShellV2.packet(ShellV2.stdout, utf8.encode(text)),
          ),
        ),
      );
    }
  }
}
