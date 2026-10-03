import 'dart:convert';
import 'dart:io';

import 'package:fcm_studio/features/devices/data/webusb/adb_key.dart';

/// A throwaway key made with `adb keygen` (test/fixtures/adb). No phone
/// trusts it.
Map<String, Object?> testAdbKeyJwk() =>
    jsonDecode(
          File('test/fixtures/adb/test_adbkey.jwk.json').readAsStringSync(),
        )
        as Map<String, Object?>;

AdbKey testAdbKey() => AdbKey.fromJwk(testAdbKeyJwk());
