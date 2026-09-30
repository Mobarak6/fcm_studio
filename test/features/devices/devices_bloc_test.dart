import 'package:fcm_studio/features/devices/bloc/devices_bloc.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/device_fixtures.dart';
import '../../helpers/fake_adb_service.dart';

const redmi = AdbDevice(
  serial: redmiSerial,
  state: DeviceState.device,
  rawState: 'device',
  model: '2409BRN2CA',
);
const unauthorized = AdbDevice(
  serial: 'R58M123ABC',
  state: DeviceState.unauthorized,
  rawState: 'unauthorized',
);
const emulator = AdbDevice(
  serial: 'emulator-5554',
  state: DeviceState.device,
  rawState: 'device',
);

void main() {
  late FakeAdbService adb;
  final delays = <Duration>[];

  setUp(() {
    adb = FakeAdbService();
    delays.clear();
  });

  DevicesBloc build() {
    final bloc = DevicesBloc(
      serviceFor: (_) => adb,
      backoff: (attempt) {
        delays.add(DevicesBloc.defaultBackoff(attempt));
        return Duration.zero;
      },
    );
    addTearDown(bloc.close);
    return bloc;
  }

  Future<void> flush() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  test('backoff is 1, 2, 4, 8, 16, then 30 seconds', () {
    expect(
      [for (var i = 1; i <= 7; i++) DevicesBloc.defaultBackoff(i).inSeconds],
      [1, 2, 4, 8, 16, 30, 30],
    );
  });

  test(
    'tracks phones once adb is found, selects the only ready one and loads its details',
    () async {
      adb.details[redmiSerial] = const DeviceDetails(
        name: 'Redmi 14C',
        brand: 'Redmi',
        androidVersion: '16',
      );
      final bloc = build()..add(const DevicesAdbChanged('/sdk/adb'));
      await flush();
      expect(bloc.state.status, TrackerStatus.starting);
      expect(bloc.state.adbPath, '/sdk/adb');

      adb.tracker.add([redmi]);
      await flush();
      expect(bloc.state.status, TrackerStatus.running);
      expect(bloc.state.selected, redmi);
      expect(bloc.state.nameOf(redmi), 'Redmi 14C');
    },
  );

  test('an unauthorized phone is listed but not selected or queried', () async {
    final bloc = build()..add(const DevicesAdbChanged('/sdk/adb'));
    await flush();
    adb.tracker.add([unauthorized]);
    await flush();
    expect(bloc.state.devices, [unauthorized]);
    expect(bloc.state.selectedSerial, isNull);
    expect(adb.calls, ['track-devices']);
    expect(bloc.state.nameOf(unauthorized), 'R58M123ABC');
  });

  test('with two ready phones the user chooses', () async {
    final bloc = build()..add(const DevicesAdbChanged('/sdk/adb'));
    await flush();
    adb.tracker.add([redmi, emulator]);
    await flush();
    expect(bloc.state.selectedSerial, isNull);
    bloc.add(const DeviceSelected('emulator-5554'));
    await flush();
    expect(bloc.state.selected, emulator);
    expect(adb.calls, contains('details emulator-5554'));
  });

  test('restarts the tracker with backoff after adb exits', () async {
    final bloc = build()..add(const DevicesAdbChanged('/sdk/adb'));
    await flush();
    await adb.tracker.close();
    await flush();
    expect(adb.trackers, hasLength(2));
    await adb.tracker.close();
    await flush();
    expect(adb.trackers, hasLength(3));
    expect(delays, [const Duration(seconds: 1), const Duration(seconds: 2)]);

    adb.tracker.add([redmi]);
    await flush();
    await adb.tracker.close();
    await flush();
    expect(
      delays.last,
      const Duration(seconds: 1),
      reason: 'a tracker that worked resets the backoff',
    );
    expect(bloc.state.status, isNot(TrackerStatus.noAdb));
  });

  test('keeps the selection while the phone is unplugged', () async {
    final bloc = build()..add(const DevicesAdbChanged('/sdk/adb'));
    await flush();
    adb.tracker.add([redmi]);
    await flush();
    adb.tracker.add([]);
    await flush();
    expect(bloc.state.selectedSerial, redmiSerial);
    expect(bloc.state.selected, isNull);
    adb.tracker.add([redmi]);
    await flush();
    expect(bloc.state.selected, redmi);
  });

  test('losing adb stops tracking', () async {
    final bloc = build()..add(const DevicesAdbChanged('/sdk/adb'));
    await flush();
    bloc.add(const DevicesAdbChanged(null));
    await flush();
    expect(bloc.state.status, TrackerStatus.noAdb);
    expect(adb.trackers.single.hasListener, isFalse);
  });
}
