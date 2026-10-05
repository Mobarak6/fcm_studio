import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/core/platform/platform_capabilities.dart';
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/devices/cubit/bridge_cubit.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_protocol.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:fcm_studio/features/devices/data/phone_access.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/view/device_actions.dart';
import 'package:fcm_studio/features/devices/view/token_read_view.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Plugged-in phones, their apps, and reading an app's token (spec §9; on
/// the web through WebUSB or the bridge: WebUSB design §4.9, bridge design
/// §4.6).
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  static const openSettingsKey = Key('devices-open-settings');
  static const connectPhoneKey = Key('devices-connect-phone');
  static const bridgeMenuKey = Key('devices-bridge-menu');
  static const bridgeConnectKey = Key('devices-bridge-connect');
  static const bridgeDisconnectKey = Key('devices-bridge-disconnect');
  static const bridgeRetryKey = Key('devices-bridge-retry');
  static const bridgeCopyKey = Key('devices-bridge-copy');
  static const bridgeDownloadKey = Key('devices-bridge-download');

  static Key deviceMenuKey(String serial) => ValueKey('device-menu-$serial');
  static Key deviceLinkKey(String serial) => ValueKey('device-link-$serial');

  static const noWebUsbMessage =
      'Connecting a phone over USB needs Chrome or Edge. Use the bridge '
      'instead.';
  static const notSecureMessage =
      'Connecting a phone over USB needs FCM Studio opened over https. Use '
      'the bridge instead.';
  static const keyNotice =
      'This browser keeps a USB debugging key for this site. Forget removes '
      'its access to a phone.';
  static const emptyWebText =
      'Start the bridge (if you have adb), or turn on USB debugging, plug the '
      'phone in, and click Connect a phone (USB).';
  static const emptyBridgeText =
      'Start the bridge to read phones through adb on this computer.';

  static const bridgeOffText = 'Bridge: off';
  static const bridgeConnectingText = 'Bridge: connecting…';
  static String bridgeConnectedText(String adbPath) =>
      'Bridge: connected · adb: $adbPath';
  static const bridgeNotRunningText =
      "The bridge isn't running. In the folder where you saved it, run "
      '`${BridgeProtocol.startCommand}`. '
      "If it's running, its window says why it refused this page.";
  static String bridgeWrongVersionText(int bridgeProtocol) =>
      "This fcm_bridge.dart doesn't match this page (bridge protocol "
      '$bridgeProtocol, page ${BridgeProtocol.version}). Download it again '
      'and restart it.';
  static const bridgeBlockedText =
      'The browser is blocking this site from reaching apps on this '
      'computer. Allow it in the site settings (the icon left of the '
      'address), then try again.';

  /// Changes when a different phone becomes ready to read.
  static String? _readyPhone(DevicesState state) {
    final device = state.selected;
    return device != null && device.isReady
        ? '${state.adbPath}|${device.serial}'
        : null;
  }

  static FoundToken? _singleToken(TokenRead read) =>
      read is TokenReadFound && read.tokens.length == 1
      ? read.tokens.single
      : null;

  /// The browser only shows its chooser after a button press.
  static Future<void> _connectPhone(BuildContext context) async {
    final errors = context.read<AppErrorCubit>();
    try {
      await context.read<PhoneAccess>().connectPhone();
    } on Object catch (error) {
      errors.report(error, context: 'Could not connect the phone');
    }
  }

  @override
  Widget build(BuildContext context) {
    final access = context.read<PlatformFeatures>().deviceAccess;
    final onWeb = access != DeviceAccess.adb;
    final webUsb = access == DeviceAccess.webUsb;
    return MultiBlocListener(
      listeners: [
        BlocListener<DevicesBloc, DevicesState>(
          listenWhen: (previous, current) =>
              _readyPhone(previous) != _readyPhone(current),
          listener: (context, state) {
            final device = state.selected;
            final adbPath = state.adbPath;
            final reader = context.read<TokenReaderCubit>();
            if (device != null &&
                device.isReady &&
                adbPath != null &&
                (reader.state.serial != device.serial ||
                    reader.adbPath != adbPath)) {
              reader.openDevice(adbPath, device.serial);
            }
          },
        ),
        BlocListener<TokenReaderCubit, TokenReaderState>(
          // A single token is used straight away.
          listenWhen: (previous, current) =>
              previous.read != current.read &&
              _singleToken(current.read) != null,
          listener: (context, state) {
            final found = state.read as TokenReadFound;
            useDeviceToken(
              context,
              package: found.package,
              found: found.tokens.single,
              method: found.method,
            );
          },
        ),
      ],
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Devices'),
          actions: [
            if (onWeb) ...[
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilledButton.icon(
                  key: connectPhoneKey,
                  onPressed: webUsb ? () => _connectPhone(context) : null,
                  icon: const Icon(Icons.usb),
                  label: const Text('Connect a phone (USB)'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: _BridgeMenu(),
              ),
            ],
          ],
        ),
        body: BlocBuilder<DevicesBloc, DevicesState>(
          builder: (context, state) {
            if (state.status == TrackerStatus.noAdb && !onWeb) {
              return const _NoAdb();
            }
            final lists = Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 320,
                  child: _DeviceList(
                    state: state,
                    onWeb: onWeb,
                    webUsb: webUsb,
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _DevicePanel(state: state)),
              ],
            );
            if (!onWeb) {
              return lists;
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _BridgeBar(
                  usbProblem: switch (access) {
                    DeviceAccess.noWebUsb => noWebUsbMessage,
                    DeviceAccess.notSecure => notSecureMessage,
                    _ => null,
                  },
                ),
                const Divider(height: 1),
                Expanded(child: lists),
              ],
            );
          },
        ),
      ),
    );
  }
}

enum _BridgeAction { connect, disconnect, download, copy }

/// What the bridge buttons and menu do.
Future<void> _runBridgeAction(
  BuildContext context,
  _BridgeAction action,
) async {
  final bridge = context.read<BridgeCubit>();
  final errors = context.read<AppErrorCubit>();
  final messenger = ScaffoldMessenger.of(context);
  try {
    switch (action) {
      case _BridgeAction.connect:
        bridge.connect();
      case _BridgeAction.disconnect:
        await bridge.disconnect();
      case _BridgeAction.download:
        bridge.download();
      case _BridgeAction.copy:
        await Clipboard.setData(
          const ClipboardData(text: BridgeProtocol.startCommand),
        );
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Copied: ${BridgeProtocol.startCommand}'),
          ),
        );
    }
  } on Object catch (error) {
    errors.report(error, context: 'The bridge action failed');
  }
}

/// The app bar's Bridge menu (bridge design §4.6).
class _BridgeMenu extends StatelessWidget {
  const _BridgeMenu();

  @override
  Widget build(BuildContext context) {
    final off = context.watch<BridgeCubit>().state is BridgeOff;
    return PopupMenuButton<_BridgeAction>(
      key: DevicesScreen.bridgeMenuKey,
      tooltip: 'Bridge options',
      onSelected: (action) => _runBridgeAction(context, action),
      itemBuilder: (context) => [
        if (off)
          const PopupMenuItem(
            value: _BridgeAction.connect,
            child: Text('Connect through bridge'),
          )
        else
          const PopupMenuItem(
            value: _BridgeAction.disconnect,
            child: Text('Disconnect'),
          ),
        const PopupMenuItem(
          value: _BridgeAction.download,
          child: Text('Download fcm_bridge.dart'),
        ),
        const PopupMenuItem(
          value: _BridgeAction.copy,
          child: Text('Copy the start command'),
        ),
      ],
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cable),
            SizedBox(width: 4),
            Text('Bridge'),
            Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }
}

/// The bridge's status line with what to do next (bridge design §6), and
/// why USB is unavailable in this browser.
class _BridgeBar extends StatelessWidget {
  const _BridgeBar({required this.usbProblem});

  final String? usbProblem;

  @override
  Widget build(BuildContext context) {
    final status = context.watch<BridgeCubit>().state;
    Widget button(Key key, String label, _BridgeAction action) => TextButton(
      key: key,
      onPressed: () => _runBridgeAction(context, action),
      child: Text(label),
    );
    final retry = button(
      DevicesScreen.bridgeRetryKey,
      'Try again',
      _BridgeAction.connect,
    );
    final download = button(
      DevicesScreen.bridgeDownloadKey,
      'Download fcm_bridge.dart',
      _BridgeAction.download,
    );
    final (IconData icon, String text, List<Widget> actions) = switch (status) {
      BridgeOff() => (
        Icons.cable,
        DevicesScreen.bridgeOffText,
        <Widget>[
          button(
            DevicesScreen.bridgeConnectKey,
            'Connect through bridge',
            _BridgeAction.connect,
          ),
        ],
      ),
      BridgeConnecting() => (
        Icons.sync,
        DevicesScreen.bridgeConnectingText,
        <Widget>[],
      ),
      BridgeConnected(:final adbPath) => (
        Icons.check_circle_outline,
        DevicesScreen.bridgeConnectedText(adbPath),
        <Widget>[
          button(
            DevicesScreen.bridgeDisconnectKey,
            'Disconnect',
            _BridgeAction.disconnect,
          ),
        ],
      ),
      BridgeNotRunning() => (
        Icons.cable,
        DevicesScreen.bridgeNotRunningText,
        <Widget>[
          button(DevicesScreen.bridgeCopyKey, 'Copy', _BridgeAction.copy),
          download,
          retry,
        ],
      ),
      BridgeWrongVersion(:final bridgeProtocol) => (
        Icons.error_outline,
        DevicesScreen.bridgeWrongVersionText(bridgeProtocol),
        <Widget>[download],
      ),
      BridgeNoAdb(:final problem) => (
        Icons.error_outline,
        problem,
        <Widget>[retry],
      ),
      BridgeBlocked() => (
        Icons.block,
        DevicesScreen.bridgeBlockedText,
        <Widget>[retry],
      ),
    };
    final problem = usbProblem;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(text)),
              ...actions,
            ],
          ),
          if (problem != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.usb_off, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(problem)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// "USB" or "Bridge": how a web phone is reached.
class _LinkLabel extends StatelessWidget {
  const _LinkLabel({required this.serial, required this.link});

  final String serial;
  final PhoneLink link;

  @override
  Widget build(BuildContext context) => Text(
    switch (link) {
      PhoneLink.usb => 'USB',
      PhoneLink.bridge => 'Bridge',
    },
    key: DevicesScreen.deviceLinkKey(serial),
    style: Theme.of(context).textTheme.labelSmall,
  );
}

class _NoAdb extends StatelessWidget {
  const _NoAdb();

  @override
  Widget build(BuildContext context) {
    final status = context.watch<AdbSetupCubit>().state.status;
    if (status == AdbStatus.unknown || status == AdbStatus.locating) {
      return const Center(child: Text('Looking for adb…'));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.usb_off, size: 48),
            const SizedBox(height: 12),
            const Text("adb was not found, so phones can't be read."),
            const SizedBox(height: 8),
            const Text(
              'Install Android SDK Platform-Tools, or set the path to adb in Settings.',
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: DevicesScreen.openSettingsKey,
              onPressed: () =>
                  context.read<NavigationCubit>().show(AppSection.settings),
              child: const Text('Open Settings'),
            ),
          ],
        ),
      ),
    );
  }
}

enum _PhoneAction { retry, forget }

class _DeviceList extends StatelessWidget {
  const _DeviceList({
    required this.state,
    required this.onWeb,
    required this.webUsb,
  });

  final DevicesState state;
  final bool onWeb;
  final bool webUsb;

  /// A WebUSB phone's note (e.g. "in use by another program") wins.
  static String _stateText(AdbDevice device) =>
      device.note ??
      switch (device.state) {
        DeviceState.device => 'Ready',
        DeviceState.unauthorized =>
          'Accept the USB debugging prompt on the phone',
        DeviceState.offline =>
          'Offline. Unplug the phone and plug it in again.',
        DeviceState.other => device.rawState,
      };

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (state.status == TrackerStatus.starting)
          ListTile(
            title: Text(onWeb ? 'Looking for phones…' : 'Starting adb…'),
          ),
        if (state.status == TrackerStatus.restarting)
          ListTile(
            key: const Key('devices-restarting'),
            leading: Icon(Icons.sync_problem, color: error),
            title: Text(
              'adb stopped. Trying again in '
              '${state.retryIn?.inSeconds ?? 0} s…',
            ),
            subtitle: switch (state.lastError) {
              final message? => Text(message),
              null => null,
            },
          ),
        if (state.status == TrackerStatus.running && state.devices.isEmpty)
          ListTile(
            leading: const Icon(Icons.phone_android),
            title: Text(onWeb ? 'No phones yet' : 'No phone connected'),
            subtitle: Text(
              webUsb
                  ? DevicesScreen.emptyWebText
                  : onWeb
                  ? DevicesScreen.emptyBridgeText
                  : 'Connect an Android phone with USB debugging turned on.',
            ),
          ),
        for (final device in state.devices)
          ListTile(
            key: ValueKey('device-${device.serial}'),
            selected: device.serial == state.selectedSerial,
            enabled: device.isReady,
            leading: Icon(
              device.isReady ? Icons.phone_android : Icons.phonelink_erase,
            ),
            title: Text(state.nameOf(device)),
            subtitle: Text(_stateText(device)),
            trailing: switch (device.link) {
              PhoneLink.bridge => _LinkLabel(
                serial: device.serial,
                link: PhoneLink.bridge,
              ),
              PhoneLink.usb => Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _LinkLabel(serial: device.serial, link: PhoneLink.usb),
                  _PhoneMenu(device: device),
                ],
              ),
              null => null,
            },
            onTap: device.isReady
                ? () => context.read<DevicesBloc>().add(
                    DeviceSelected(device.serial),
                  )
                : null,
          ),
        if (webUsb)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              DevicesScreen.keyNotice,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// Retry (when not ready) and Forget, for a WebUSB phone.
class _PhoneMenu extends StatelessWidget {
  const _PhoneMenu({required this.device});

  final AdbDevice device;

  Future<void> _run(BuildContext context, _PhoneAction action) async {
    final phones = context.read<PhoneAccess>();
    final errors = context.read<AppErrorCubit>();
    try {
      switch (action) {
        case _PhoneAction.retry:
          await phones.retry(device.serial);
        case _PhoneAction.forget:
          await phones.forget(device.serial);
      }
    } on Object catch (error) {
      errors.report(error, context: 'Could not ${action.name} the phone');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_PhoneAction>(
      key: DevicesScreen.deviceMenuKey(device.serial),
      tooltip: 'Phone options',
      onSelected: (action) => _run(context, action),
      itemBuilder: (context) => [
        if (!device.isReady)
          const PopupMenuItem(value: _PhoneAction.retry, child: Text('Retry')),
        const PopupMenuItem(value: _PhoneAction.forget, child: Text('Forget')),
      ],
    );
  }
}

class _DevicePanel extends StatelessWidget {
  const _DevicePanel({required this.state});

  final DevicesState state;

  @override
  Widget build(BuildContext context) {
    if (state.selectedSerial == null) {
      return const Center(child: Text('Select a phone on the left.'));
    }
    final device = state.selected;
    if (device == null || !device.isReady) {
      return const Center(
        child: Text('The phone is disconnected. Plug it in again.'),
      );
    }
    final details = state.details[device.serial];
    return BlocBuilder<TokenReaderCubit, TokenReaderState>(
      builder: (context, reader) {
        final cubit = context.read<TokenReaderCubit>();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(
                state.nameOf(device),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                [
                  if (details != null && details.brand.isNotEmpty)
                    details.brand,
                  if (details != null && details.androidVersion.isNotEmpty)
                    'Android ${details.androidVersion}',
                  device.serial,
                ].join(' · '),
              ),
              trailing: IconButton(
                tooltip: 'Refresh the app list',
                icon: const Icon(Icons.refresh),
                onPressed: cubit.refreshPackages,
              ),
            ),
            TokenReadView(read: reader.read),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              // Keyed by phone: switching phones resets the query in the
              // cubit, so the box must start empty too.
              child: KeyedSubtree(
                key: ValueKey(device.serial),
                child: TextField(
                  key: const Key('devices-search'),
                  decoration: const InputDecoration(
                    isDense: true,
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Search apps',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: cubit.search,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(child: _PackageList(reader: reader)),
          ],
        );
      },
    );
  }
}

class _PackageList extends StatelessWidget {
  const _PackageList({required this.reader});

  final TokenReaderState reader;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TokenReaderCubit>();
    switch (reader.packagesStatus) {
      case PackagesStatus.idle || PackagesStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case PackagesStatus.failed:
        return Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            reader.packagesError ?? 'Could not list the apps.',
          ),
        );
      case PackagesStatus.ready:
        final packages = reader.packages;
        if (packages.isEmpty) {
          return const Center(child: Text('No apps found.'));
        }
        return ListView(
          children: [
            for (final package in packages)
              ListTile(
                key: ValueKey('package-$package'),
                dense: true,
                enabled: !reader.isBusy,
                title: Text(package),
                trailing: reader.recent.contains(package)
                    ? const Text('recent')
                    : null,
                onTap: () => cubit.readToken(
                  package,
                  projectNumber: context
                      .read<ProjectsCubit>()
                      .state
                      .selected
                      ?.projectNumber,
                ),
              ),
          ],
        );
    }
  }
}
