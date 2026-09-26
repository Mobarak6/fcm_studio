import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Stores secrets such as service account keys.
abstract interface class SecretStore {
  Future<String?> read(String key);

  /// When [persist] is false the secret may be kept in memory only (web without "remember").
  Future<void> write(String key, String value, {bool persist = true});

  Future<void> delete(String key);
}

class MemorySecretStore implements SecretStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value, {bool persist = true}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// A session (memory) layer in front of persistent storage.
///
/// With [alwaysPersist] (desktop) every write is persisted. Without it (web),
/// a write is persisted only when `persist` is true.
class LayeredSecretStore implements SecretStore {
  LayeredSecretStore({required this._persistent, required this.alwaysPersist});

  final SecretStore _persistent;
  final bool alwaysPersist;
  final MemorySecretStore _session = MemorySecretStore();

  @override
  Future<String?> read(String key) async =>
      await _session.read(key) ?? await _persistent.read(key);

  @override
  Future<void> write(String key, String value, {bool persist = true}) async {
    await _session.write(key, value);
    if (persist || alwaysPersist) {
      await _persistent.write(key, value);
    } else {
      await _persistent.delete(key);
    }
  }

  @override
  Future<void> delete(String key) async {
    await _session.delete(key);
    await _persistent.delete(key);
  }
}

/// Keychain (macOS), DPAPI-encrypted file (Windows) or browser storage (web).
class FlutterSecureSecretStore implements SecretStore {
  FlutterSecureSecretStore([FlutterSecureStorage? storage])
    : _storage =
          storage ??
          const FlutterSecureStorage(
            // The data-protection keychain needs a signing team, which unsigned
            // internal builds don't have. See spec §10.
            mOptions: MacOsOptions(usesDataProtectionKeychain: false),
          );

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value, {bool persist = true}) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}
