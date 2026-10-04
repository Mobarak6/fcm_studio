import 'dart:convert';

import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/devices/data/webusb/adb_key.dart';

/// Keeps the browser's adb key in [SecretStore] (design §4.5, §8). It is
/// made once; later visits reuse it, so phones don't ask again.
class AdbKeyStore {
  AdbKeyStore({required this._secrets, required this._generateJwk});

  static const secretKey = 'adb:browser-key';

  final SecretStore _secrets;

  /// Makes a new key as a JWK (WebCrypto in the browser).
  final Future<Map<String, Object?>> Function() _generateJwk;
  Future<AdbKey>? _loading;

  /// The key, made and stored on first use. Loads at the same time share
  /// one; a failed one is tried again next time.
  Future<AdbKey> load() async {
    final loading = _loading ??= _load();
    try {
      return await loading;
    } on Object {
      if (identical(_loading, loading)) {
        _loading = null;
      }
      rethrow;
    }
  }

  Future<AdbKey> _load() async {
    final saved = await _secrets.read(secretKey);
    if (saved != null) {
      try {
        final Object? jwk = jsonDecode(saved);
        if (jwk is Map<String, Object?>) {
          return AdbKey.fromJwk(jwk);
        }
      } on FormatException {
        // A damaged key is replaced; phones then ask once more.
      }
    }
    final jwk = await _generateJwk();
    final key = AdbKey.fromJwk(jwk);
    await _secrets.write(secretKey, jsonEncode(jwk), persist: true);
    return key;
  }
}
