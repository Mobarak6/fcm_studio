import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sembast/sembast.dart';

void main() {
  test('in-memory databases are independent of each other', () async {
    final a = await AppDatabase.inMemory();
    final b = await AppDatabase.inMemory();
    final store = StoreRef<String, String>('t');

    await store.record('k').put(a.db, 'v');

    expect(await store.record('k').get(a.db), 'v');
    expect(await store.record('k').get(b.db), isNull);
    await a.close();
    await b.close();
  });
}
