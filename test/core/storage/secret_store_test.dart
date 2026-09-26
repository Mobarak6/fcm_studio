import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LayeredSecretStore', () {
    late MemorySecretStore persistent;

    setUp(() => persistent = MemorySecretStore());

    test('desktop: always persists, even when persist is false', () async {
      final store = LayeredSecretStore(
        persistent: persistent,
        alwaysPersist: true,
      );
      await store.write('k', 'v', persist: false);
      expect(await persistent.read('k'), 'v');
    });

    test('web without "remember": keeps the secret in memory only', () async {
      final store = LayeredSecretStore(
        persistent: persistent,
        alwaysPersist: false,
      );
      await store.write('k', 'v', persist: false);
      expect(await store.read('k'), 'v');
      expect(await persistent.read('k'), isNull);
    });

    test('a memory-only write removes an older persisted copy', () async {
      final store = LayeredSecretStore(
        persistent: persistent,
        alwaysPersist: false,
      );
      await store.write('k', 'old');
      await store.write('k', 'new', persist: false);
      expect(await persistent.read('k'), isNull);
      expect(await store.read('k'), 'new');
    });

    test('after a restart, reads fall back to persistent storage', () async {
      await LayeredSecretStore(
        persistent: persistent,
        alwaysPersist: false,
      ).write('k', 'v');
      final restarted = LayeredSecretStore(
        persistent: persistent,
        alwaysPersist: false,
      );
      expect(await restarted.read('k'), 'v');
    });

    test('delete removes the secret from both layers', () async {
      final store = LayeredSecretStore(
        persistent: persistent,
        alwaysPersist: true,
      );
      await store.write('k', 'v');
      await store.delete('k');
      expect(await store.read('k'), isNull);
      expect(await persistent.read('k'), isNull);
    });
  });
}
