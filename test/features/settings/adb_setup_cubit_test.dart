import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/devices/data/adb_locator.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_cubit.dart';
import 'package:fcm_studio/features/settings/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_process_runner.dart';

const adbVersion = 'Android Debug Bridge version 1.0.41\n';

void main() {
  late AppDatabase database;
  late FakeProcessRunner runner;
  late SettingsRepository settings;

  setUp(() async {
    database = await AppDatabase.inMemory();
    runner = FakeProcessRunner();
    settings = SettingsRepository(database: database);
  });

  tearDown(() => database.close());

  AdbSetupCubit build() => AdbSetupCubit(
    locator: AdbLocator(
      runner: runner,
      environment: const {'HOME': '/Users/me'},
      isWindows: false,
    ),
    settings: settings,
  );

  test('finds adb at startup', () async {
    runner.on('/opt/homebrew/bin/adb version', ok(adbVersion));
    final cubit = build();
    await cubit.locate();
    expect(cubit.state.status, AdbStatus.found);
    expect(cubit.state.adbPath, '/opt/homebrew/bin/adb');
    expect(cubit.state.userPathFailed, isFalse);
  });

  test('says where it looked when adb is not found', () async {
    final cubit = build();
    await cubit.locate();
    expect(cubit.state.status, AdbStatus.notFound);
    expect(cubit.state.adbPath, isNull);
    expect(cubit.state.tried, contains('/opt/homebrew/bin/adb'));
  });

  test('a path set by the user is stored and used first', () async {
    runner
      ..on('/opt/homebrew/bin/adb version', ok(adbVersion))
      ..on('/custom/adb version', ok(adbVersion));
    final cubit = build();
    await cubit.setUserPath('/custom/adb');
    expect(cubit.state.adbPath, '/custom/adb');
    expect(cubit.state.location?.source, AdbSource.settings);
    expect(await settings.readAdbPath(), '/custom/adb');

    await cubit.setUserPath(null);
    expect(cubit.state.adbPath, '/opt/homebrew/bin/adb');
    expect(cubit.state.userPath, isNull);
  });

  test('a user path that does not run adb is flagged', () async {
    runner.on('/opt/homebrew/bin/adb version', ok(adbVersion));
    final cubit = build();
    await cubit.setUserPath('/wrong/adb');
    expect(cubit.state.adbPath, '/opt/homebrew/bin/adb');
    expect(cubit.state.userPathFailed, isTrue);
  });
}
