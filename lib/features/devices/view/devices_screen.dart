import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/devices/cubit/token_reader_cubit.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/view/device_actions.dart';
import 'package:fcm_studio/features/devices/view/token_read_view.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Plugged-in phones, their apps, and reading an app's token (spec §9).
class DevicesScreen extends StatelessWidget {
  const DevicesScreen({super.key});

  static const openSettingsKey = Key('devices-open-settings');

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

  @override
  Widget build(BuildContext context) {
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
        appBar: AppBar(title: const Text('Devices')),
        body: BlocBuilder<DevicesBloc, DevicesState>(
          builder: (context, state) {
            if (state.status == TrackerStatus.noAdb) {
              return const _NoAdb();
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(width: 320, child: _DeviceList(state: state)),
                const VerticalDivider(width: 1),
                Expanded(child: _DevicePanel(state: state)),
              ],
            );
          },
        ),
      ),
    );
  }
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

class _DeviceList extends StatelessWidget {
  const _DeviceList({required this.state});

  final DevicesState state;

  static String _stateText(AdbDevice device) => switch (device.state) {
    DeviceState.device => 'Ready',
    DeviceState.unauthorized => 'Accept the USB debugging prompt on the phone',
    DeviceState.offline => 'Offline. Unplug the phone and plug it in again.',
    DeviceState.other => device.rawState,
  };

  @override
  Widget build(BuildContext context) {
    final error = Theme.of(context).colorScheme.error;
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        if (state.status == TrackerStatus.starting)
          const ListTile(title: Text('Starting adb…')),
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
          const ListTile(
            leading: Icon(Icons.phone_android),
            title: Text('No phone connected'),
            subtitle: Text(
              'Connect an Android phone with USB debugging turned on.',
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
            onTap: device.isReady
                ? () => context.read<DevicesBloc>().add(
                    DeviceSelected(device.serial),
                  )
                : null,
          ),
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
