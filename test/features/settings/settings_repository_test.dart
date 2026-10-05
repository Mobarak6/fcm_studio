import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/settings/data/settings_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() async => database = await AppDatabase.inMemory());
  tearDown(() => database.close());

  test('stores, reads and clears the adb path', () async {
    final settings = SettingsRepository(database: database);
    expect(await settings.readAdbPath(), isNull);
    await settings.writeAdbPath('  /custom/adb  ');
    expect(await settings.readAdbPath(), '/custom/adb');
    await settings.writeAdbPath(' ');
    expect(await settings.readAdbPath(), isNull);
    await settings.writeAdbPath('/custom/adb');
    await settings.writeAdbPath(null);
    expect(await settings.readAdbPath(), isNull);
  });

  test('remembers whether the bridge connects by itself', () async {
    final settings = SettingsRepository(database: database);
    expect(await settings.readBridgeAutoConnect(), isFalse);
    await settings.writeBridgeAutoConnect(true);
    expect(await settings.readBridgeAutoConnect(), isTrue);
    await settings.writeBridgeAutoConnect(false);
    expect(await settings.readBridgeAutoConnect(), isFalse);
  });
}
