import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/features/devices/data/recent_packages_repository.dart';
import 'package:fcm_studio/features/devices/domain/package_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase database;

  setUp(() async => database = await AppDatabase.inMemory());
  tearDown(() => database.close());

  test('remembers the last 5 packages per phone, newest first', () async {
    final recent = RecentPackagesRepository(database: database);
    for (final package in ['a', 'b', 'c', 'd', 'e', 'f', 'b']) {
      await recent.remember('phone-1', package);
    }
    expect(await recent.recent('phone-1'), ['b', 'f', 'e', 'd', 'c']);
    expect(await recent.recent('phone-2'), isEmpty);
  });

  test(
    'orders recent packages first, the rest sorted, filtered by the search',
    () {
      const installed = [
        'com.zeta',
        'com.alpha',
        'com.syldel.delivery',
        'com.beta',
      ];
      expect(
        orderPackages(installed, ['com.syldel.delivery', 'com.gone'], ''),
        ['com.syldel.delivery', 'com.alpha', 'com.beta', 'com.zeta'],
      );
      expect(orderPackages(installed, ['com.syldel.delivery'], 'ALP'), [
        'com.alpha',
      ]);
    },
  );
}
