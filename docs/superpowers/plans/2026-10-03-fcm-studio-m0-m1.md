# FCM Studio M0 + M1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the FCM Studio Flutter app and get it to the M1 milestone: add a Firebase project from a service account key, write a message as JSON, send it to a device token, topic or condition, and see a clear result. Along the way, finish the remaining M0 checks.

**Architecture:** One Flutter app for macOS, Windows and web, with no backend. Pure-Dart services (`core/auth`, `core/fcm`, `core/firebase`, `core/storage`) are created once in `AppDependencies` and passed to two Cubits: `ProjectsCubit` and `ComposerCubit`. The composer keeps the JSON template as its single source of truth. A pure `MessageRenderer` turns the template and target into the exact request body.

**Tech Stack:** Flutter 3.44 / Dart 3.12, `flutter_bloc`, `equatable`, `http`, `dart_jsonwebtoken`, `sembast` + `sembast_web`, `flutter_secure_storage`, `file_selector`, `re_editor` + `re_highlight`, `url_launcher`, `path_provider`.

**Spec:** `docs/superpowers/specs/2026-10-03-fcm-studio-design.md`. Read sections 1–5, 8, 10 and 11 before starting.

## Global Constraints

- Project root: `/Users/mobarak/Documents/learn/fcm_studio`. Package name `fcm_studio`. Platforms: **macOS, Windows, web only**.
- Use package imports (`package:fcm_studio/...`) everywhere in `lib/`, `test/` and `tool/`. Never use relative imports.
- State: `flutter_bloc` Cubits. States extend `Equatable`. Models are hand-written (`fromJson`/`toJson`/`copyWith`) with **no code generation**.
- Lints: `flutter_lints` plus `strict-casts`, `strict-inference` and `strict-raw-types`. `flutter analyze` must report **No issues found** at the end of every task.
- Secrets (service account JSON) live **only** in `SecretStore`. They never go into sembast, logs or UI text. Network error text passes through `redact()`.
- Token endpoint: always `https://oauth2.googleapis.com/token`; the `token_uri` in the key file is ignored. Scopes: `https://www.googleapis.com/auth/firebase.messaging` and `https://www.googleapis.com/auth/firebase.readonly`. Tokens are refreshed when less than 5 minutes remain.
- FCM send: `POST https://fcm.googleapis.com/v1/projects/{projectId}/messages:send` with a 20 s timeout. **No automatic retries**, except a single token refresh and resend after a `401`.
- `validate_only` is added to the request body only for dry runs. Dry runs have no UI in M1.
- macOS: App Sandbox **off**. Secure storage uses `MacOsOptions(usesDataProtectionKeychain: false)`.
- Web: service account keys are kept in memory only, unless the user ticks "Remember on this browser".
- **Do not stage or commit.** The user's standing preference is to make changes and stop; they stage and commit themselves. Each task ends with a checkpoint instead of a commit.

## Review Focus

These inputs are the most likely to cause trouble for someone using the app. Each one has a test in the task named.

1. **Double-clicking Send.** Exactly one request must go out while a send is in progress. *Task 13: "ignores Send while a send is in progress".*
2. **Choosing the wrong JSON file** (`google-services.json`, an OAuth client file, an `authorized_user` key). The user needs a specific message saying what the file is and where to get the right one. *Task 4.*
3. **Web reload without "Remember".** The project still exists but its key is gone. Send must explain "add the project again with the same key file" and must not crash. *Task 10 (registry) and Task 13 (composer).*
4. **A token pasted with spaces, line breaks or quotes, or a topic typed as `/topics/news`.** These must be normalised, not rejected. *Task 12.*
5. **An error response that isn't JSON** (an HTML 502 from a proxy or captive portal). It must show a readable explanation and the raw text, and must not crash. *Task 6 (`FcmError`) and Task 7 (explainer).*

## Not in this plan (M2 and later)

These parts of the spec are deliberately left out of M0/M1. Don't build them here:
- Variables and built-in placeholders (§5.2 step 1).
- The Form tab and the data-only switch (§5.3).
- Presets (§6), saved targets and history (§7).
- The dry-run checkbox and copy as cURL (§8.3).
- The production safeguard (§4.3).
- Highlighting `INVALID_ARGUMENT` fields in the editor.
- An app-wide error banner for unexpected exceptions (§11, last bullet). In M1, failures surface through `AddProjectFailure` and `FcmSendFailure`.
- adb (M3) and Google sign-in (M4).

---

### Task 1: Scaffold the project

**Files:**
- Create (via `flutter create`): the project skeleton in `/Users/mobarak/Documents/learn/fcm_studio`
- Modify: `pubspec.yaml` (dependencies), `analysis_options.yaml`, `.gitignore`, `macos/Runner/DebugProfile.entitlements`, `macos/Runner/Release.entitlements`
- Create: `lib/main.dart`, `lib/app/app.dart`, `lib/app/theme.dart`
- Test: `test/app/app_test.dart`

**Interfaces:**
- Produces: `FcmStudioApp` (temporary no-argument version, replaced in Task 14) and `AppTheme.light` / `AppTheme.dark`.

- [ ] **Step 1: Create the Flutter project inside the existing folder.** The folder already contains `docs/`, which must be kept.

```bash
cd /Users/mobarak/Documents/learn/fcm_studio
flutter create . --project-name fcm_studio --org dev.fcmstudio --platforms macos,windows,web --empty
```
Expected: `All done!`. If `test/widget_test.dart` was generated, delete it.

- [ ] **Step 2: Initialise git.** This only creates the repository, so reviewers can see diffs. Don't stage or commit anything.

```bash
git init
```

- [ ] **Step 3: Add dependencies**

```bash
flutter pub add flutter_bloc equatable http dart_jsonwebtoken sembast sembast_web path_provider path flutter_secure_storage file_selector re_editor re_highlight url_launcher
```
Expected: `Changed N dependencies!`. Check that `flutter_lints` is already listed under `dev_dependencies`. If it isn't, run `flutter pub add --dev flutter_lints`.

- [ ] **Step 4: Replace `analysis_options.yaml`**

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true

linter:
  rules:
    - always_declare_return_types
    - avoid_dynamic_calls
    - prefer_final_locals
    - prefer_single_quotes
    - unawaited_futures
```

- [ ] **Step 5: Add these lines to the end of `.gitignore`**

```gitignore

# FCM Studio: never commit real credentials
secrets/
config/oauth.json
```

- [ ] **Step 6: Turn off the macOS App Sandbox** (needed to run `adb` in M3; see spec §10). Replace `macos/Runner/DebugProfile.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
	<key>com.apple.security.cs.allow-jit</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
</dict>
</plist>
```

Replace `macos/Runner/Release.entitlements` with:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<false/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
</dict>
</plist>
```

- [ ] **Step 7: Write the failing smoke test** `test/app/app_test.dart`

```dart
import 'package:fcm_studio/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the app title', (tester) async {
    await tester.pumpWidget(const FcmStudioApp());
    expect(find.text('FCM Studio'), findsOneWidget);
  });
}
```

- [ ] **Step 8: Run it to see it fail**

Run: `flutter test test/app/app_test.dart`
Expected: FAIL, compilation error (`app.dart` doesn't exist).

- [ ] **Step 9: Write the theme, the temporary app and `main.dart`**

`lib/app/theme.dart`:
```dart
import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFFF57C00);

  static final ThemeData light = ThemeData(
    colorSchemeSeed: _seed,
    brightness: Brightness.light,
    useMaterial3: true,
  );

  static final ThemeData dark = ThemeData(
    colorSchemeSeed: _seed,
    brightness: Brightness.dark,
    useMaterial3: true,
  );
}
```

`lib/app/app.dart` (temporary; Task 14 replaces it):
```dart
import 'package:fcm_studio/app/theme.dart';
import 'package:flutter/material.dart';

class FcmStudioApp extends StatelessWidget {
  const FcmStudioApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FCM Studio',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      home: const Scaffold(body: Center(child: Text('FCM Studio'))),
    );
  }
}
```

`lib/main.dart`:
```dart
import 'package:fcm_studio/app/app.dart';
import 'package:flutter/widgets.dart';

void main() {
  runApp(const FcmStudioApp());
}
```

- [ ] **Step 10: Run the test and confirm it passes**

Run: `flutter test test/app/app_test.dart`
Expected: PASS.

- [ ] **Step 11: Check that the macOS and web builds work**

```bash
flutter analyze
flutter build macos --debug
flutter build web
```
Expected: `No issues found!`, then `✓ Built build/macos/Build/Products/Debug/fcm_studio.app`, then `✓ Built build/web`.

- [ ] **Step 12: Checkpoint.** Run `dart format lib test` and `git status --short`. List the changed files in your report. Do not stage or commit.

---

### Task 2: M0 check: capture the Android token file (user-assisted)

This task writes no app code. It records the real format of the Firebase token file and the real `run-as` messages, which M3's parser is built on. Claude Code's auto mode refuses to read FCM tokens, so **the user runs the capture commands**. The output is sanitised before it touches the repo.

If no debug build that uses `firebase_messaging` is available today, add a line to spec §13 saying "token-file capture deferred to the start of M3", then move on. Nothing in M1 depends on this task.

**Files:**
- Create: `test/fixtures/adb/appid_prefs_debug.xml`, `test/fixtures/adb/run_as_not_debuggable.txt`, `test/fixtures/adb/run_as_no_such_file.txt`, `test/fixtures/adb/run_as_unknown_package.txt`
- Modify: `docs/superpowers/specs/2026-10-03-fcm-studio-design.md` §9.3

- [ ] **Step 1: The user installs a debug build** of any app that uses `firebase_messaging` on the Redmi (serial `DETWFUOZZHZ5SWFQ`), for example by running `flutter run -d DETWFUOZZHZ5SWFQ` in a team app. They open the app once so it gets a token, and tell you its package name (below: `<debug.package>`).

- [ ] **Step 2: The user captures the token file with tokens and long keys replaced.** Ask them to run this from the project root:

```bash
mkdir -p test/fixtures/adb
adb -s DETWFUOZZHZ5SWFQ exec-out run-as <debug.package> cat shared_prefs/com.google.android.gms.appid.xml \
  | sed -E -e 's/[A-Za-z0-9_-]{11,}:APA91b[A-Za-z0-9_-]+/fakeInstanceId0000000:APA91bFAKE_TOKEN_FOR_TESTS_ONLY_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/g' \
           -e 's/>[A-Za-z0-9+\/=_-]{40,}</>REDACTED_LONG_VALUE</g' \
  > test/fixtures/adb/appid_prefs_debug.xml
```

- [ ] **Step 3: The user captures the three `run-as` error messages**

```bash
adb -s DETWFUOZZHZ5SWFQ exec-out run-as com.syldel.delivery ls > test/fixtures/adb/run_as_not_debuggable.txt 2>&1
adb -s DETWFUOZZHZ5SWFQ exec-out run-as <debug.package> cat shared_prefs/does_not_exist.xml > test/fixtures/adb/run_as_no_such_file.txt 2>&1
adb -s DETWFUOZZHZ5SWFQ exec-out run-as com.does.not.exist ls > test/fixtures/adb/run_as_unknown_package.txt 2>&1
```

- [ ] **Step 4: Check that the fixture is clean.** It must contain no real token (only `fakeInstanceId…`), and must contain at least one `|T|<digits>|` key.

```bash
grep -c "APA91b" test/fixtures/adb/appid_prefs_debug.xml
grep -E -o "APA91b[A-Za-z0-9_-]{0,12}" test/fixtures/adb/appid_prefs_debug.xml | sort -u
grep -E -o '\|T\|[0-9]+\|[^"]*' test/fixtures/adb/appid_prefs_debug.xml
cat test/fixtures/adb/run_as_*.txt
```
Expected: the only `APA91b…` value is `APA91bFAKE_TOKEN_FOR_` and at least one `|T|…` key is listed. If anything that looks like a real token remains, delete the file and ask the user to run Step 2 again.

- [ ] **Step 5: Record the results in the spec, §9.3.**
  - Replace the italic sentence *"The exact file format must be confirmed…"* with: `Confirmed on <date> with <debug.package> (firebase-messaging via firebase_messaging <version from the app's pubspec.lock>). Fixture: test/fixtures/adb/appid_prefs_debug.xml.` Describe the key and value format you actually saw: escaped JSON or a raw token, which scope suffix, and any extra keys.
  - Replace the "Output" column entries for `package not debuggable`, `No such file or directory` and `Package '<p>' is unknown` with the exact text from the three `.txt` fixtures.

- [ ] **Step 6: Checkpoint.** Run `git status --short` and report. Do not stage or commit.

---

### Task 3: Clock and redaction helpers

**Files:**
- Create: `lib/core/utils/clock.dart`, `lib/core/utils/redact.dart`, `test/helpers/fixed_clock.dart`
- Test: `test/core/utils/redact_test.dart`

**Interfaces:**
- Produces: `abstract interface class Clock { DateTime now(); }`, `class SystemClock implements Clock` (UTC), `String redact(String input)`, and the test helper `FixedClock(DateTime)` with `.advance(Duration)`.

- [ ] **Step 1: Write the failing test** `test/core/utils/redact_test.dart`

```dart
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('redact', () {
    test('removes PEM private keys, including JSON-escaped ones', () {
      const raw =
          '{"private_key": "-----BEGIN PRIVATE KEY-----\\nMIIEsecret\\n-----END PRIVATE KEY-----\\n"}';
      final out = redact(raw);
      expect(out, isNot(contains('MIIEsecret')));
      expect(out, contains('[REDACTED'));
    });

    test('removes bearer tokens', () {
      expect(
        redact('Authorization: Bearer ya29.a0AfB_secret'),
        'Authorization: Bearer [REDACTED]',
      );
    });

    test('removes access and refresh tokens in JSON', () {
      expect(
        redact('{"access_token":"abc","refresh_token":"def"}'),
        '{"access_token":"[REDACTED]","refresh_token":"[REDACTED]"}',
      );
    });

    test('removes bare ya29 access tokens', () {
      expect(redact('got ya29.c.b0Aaek-xyz end'), 'got ya29.[REDACTED] end');
    });

    test('leaves ordinary text alone', () {
      expect(
        redact('Requested entity was not found.'),
        'Requested entity was not found.',
      );
    });
  });
}
```

- [ ] **Step 2: Run it to see it fail**

Run: `flutter test test/core/utils/redact_test.dart`
Expected: FAIL, compilation error (`redact.dart` doesn't exist).

- [ ] **Step 3: Implement**

`lib/core/utils/redact.dart`:
```dart
final _pemPrivateKey = RegExp(
  r'-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----',
);
final _secretJsonField = RegExp(
  r'("(?:private_key|refresh_token|access_token|assertion)"\s*:\s*")[^"]*(")',
);
final _bearer = RegExp(r'(Bearer\s+)[A-Za-z0-9._~+/=-]+');
final _googleAccessToken = RegExp(r'ya29\.[A-Za-z0-9._-]+');

/// Removes private keys and OAuth tokens from [input] so it can be shown or logged.
String redact(String input) {
  return input
      .replaceAll(_pemPrivateKey, '[REDACTED PRIVATE KEY]')
      .replaceAllMapped(_secretJsonField, (m) => '${m[1]}[REDACTED]${m[2]}')
      .replaceAllMapped(_bearer, (m) => '${m[1]}[REDACTED]')
      .replaceAll(_googleAccessToken, 'ya29.[REDACTED]');
}
```

`lib/core/utils/clock.dart`:
```dart
/// Source of the current time. Injected so tests can control it.
abstract interface class Clock {
  DateTime now();
}

class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now().toUtc();
}
```

`test/helpers/fixed_clock.dart`:
```dart
import 'package:fcm_studio/core/utils/clock.dart';

class FixedClock implements Clock {
  FixedClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration duration) => current = current.add(duration);
}
```

- [ ] **Step 4: Run the test and confirm it passes**

Run: `flutter test test/core/utils/redact_test.dart`
Expected: PASS (5 tests).

- [ ] **Step 5: Checkpoint.** Run `dart format lib test`, `flutter analyze` (expect No issues found) and `git status --short`, and report. Do not stage or commit.

---

### Task 4: Service account key parsing

**Files:**
- Create: `lib/core/auth/service_account_key.dart`, `test/helpers/service_account_fixture.dart`, `test/fixtures/keys/test_private_key.pem`, `test/fixtures/keys/test_public_key.pem`
- Test: `test/core/auth/service_account_key_test.dart`

**Interfaces:**
- Produces:
  - `class ServiceAccountKeyException implements Exception { final String message; }`
  - `class ServiceAccountKey` with `factory ServiceAccountKey.parse(String jsonText)`, and the fields `projectId`, `clientEmail`, `privateKeyId`, `privateKeyPem`, `rawJson` (all `String`). Equality covers everything except `rawJson`. `toString()` never includes the key.
  - Test helpers: `testProjectId = 'demo-project'`, `testProjectNumber = '123456789012'`, `testClientEmail = 'fcm-sender@demo-project.iam.gserviceaccount.com'`, `testPrivateKeyPem()`, `testPublicKeyPem()`, `serviceAccountMap({projectId, clientEmail})`, `serviceAccountJson({projectId, clientEmail})`.

- [ ] **Step 1: Generate a throwaway RSA key pair for tests.** It's for tests only, never used with Google, and safe to commit.

```bash
mkdir -p test/fixtures/keys
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out test/fixtures/keys/test_private_key.pem
openssl pkey -in test/fixtures/keys/test_private_key.pem -pubout -out test/fixtures/keys/test_public_key.pem
head -1 test/fixtures/keys/test_private_key.pem
```
Expected: `-----BEGIN PRIVATE KEY-----` (PKCS#8, the same format Google uses).

- [ ] **Step 2: Write the fixture helper** `test/helpers/service_account_fixture.dart`

```dart
import 'dart:convert';
import 'dart:io';

const testProjectId = 'demo-project';
const testProjectNumber = '123456789012';
const testClientEmail = 'fcm-sender@demo-project.iam.gserviceaccount.com';

String testPrivateKeyPem() =>
    File('test/fixtures/keys/test_private_key.pem').readAsStringSync();

String testPublicKeyPem() =>
    File('test/fixtures/keys/test_public_key.pem').readAsStringSync();

Map<String, Object?> serviceAccountMap({
  String projectId = testProjectId,
  String clientEmail = testClientEmail,
}) =>
    {
      'type': 'service_account',
      'project_id': projectId,
      'private_key_id': 'test-key-id-1',
      'private_key': testPrivateKeyPem(),
      'client_email': clientEmail,
      'client_id': '100000000000000000001',
      'auth_uri': 'https://accounts.google.com/o/oauth2/auth',
      'token_uri': 'https://oauth2.googleapis.com/token',
    };

String serviceAccountJson({
  String projectId = testProjectId,
  String clientEmail = testClientEmail,
}) =>
    jsonEncode(serviceAccountMap(projectId: projectId, clientEmail: clientEmail));
```

- [ ] **Step 3: Write the failing tests** `test/core/auth/service_account_key_test.dart`

```dart
import 'dart:convert';

import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/service_account_fixture.dart';

Matcher throwsKeyError(String text) => throwsA(
      isA<ServiceAccountKeyException>()
          .having((e) => e.message, 'message', contains(text)),
    );

void main() {
  test('parses a valid service account key', () {
    final key = ServiceAccountKey.parse(serviceAccountJson());
    expect(key.projectId, testProjectId);
    expect(key.clientEmail, testClientEmail);
    expect(key.privateKeyId, 'test-key-id-1');
    expect(key.privateKeyPem, startsWith('-----BEGIN PRIVATE KEY-----'));
  });

  test('rejects text that is not JSON', () {
    expect(() => ServiceAccountKey.parse('not json'), throwsKeyError('not valid JSON'));
  });

  test('recognises google-services.json', () {
    final file = jsonEncode({
      'project_info': {'project_id': 'x'},
      'client': <Object?>[],
    });
    expect(() => ServiceAccountKey.parse(file), throwsKeyError('google-services.json'));
  });

  test('recognises an OAuth client file', () {
    final file = jsonEncode({
      'installed': {'client_id': 'x'},
    });
    expect(() => ServiceAccountKey.parse(file), throwsKeyError('OAuth client'));
  });

  test('rejects other credential types', () {
    final file = jsonEncode({...serviceAccountMap(), 'type': 'authorized_user'});
    expect(() => ServiceAccountKey.parse(file), throwsKeyError('authorized_user'));
  });

  test('names a missing field', () {
    final map = serviceAccountMap()..remove('client_email');
    expect(() => ServiceAccountKey.parse(jsonEncode(map)), throwsKeyError('"client_email"'));
  });

  test('rejects a private key that is not PKCS#8 PEM', () {
    final file = jsonEncode({...serviceAccountMap(), 'private_key': 'not a key'});
    expect(() => ServiceAccountKey.parse(file), throwsKeyError('PKCS#8'));
  });

  test('rejects a PEM block that is not a usable RSA key', () {
    final file = jsonEncode({
      ...serviceAccountMap(),
      'private_key': '-----BEGIN PRIVATE KEY-----\nAAAA\n-----END PRIVATE KEY-----\n',
    });
    expect(() => ServiceAccountKey.parse(file), throwsKeyError('could not be read'));
  });

  test('toString never contains the private key', () {
    final key = ServiceAccountKey.parse(serviceAccountJson());
    expect(key.toString(), isNot(contains('PRIVATE KEY')));
    expect(key.toString(), contains(testClientEmail));
  });
}
```

- [ ] **Step 4: Run them to see them fail**

Run: `flutter test test/core/auth/service_account_key_test.dart`
Expected: FAIL, compilation error.

- [ ] **Step 5: Implement** `lib/core/auth/service_account_key.dart`

```dart
import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:equatable/equatable.dart';

class ServiceAccountKeyException implements Exception {
  const ServiceAccountKeyException(this.message);

  final String message;

  @override
  String toString() => 'ServiceAccountKeyException: $message';
}

/// A parsed and validated Google service account key file.
class ServiceAccountKey extends Equatable {
  const ServiceAccountKey._({
    required this.projectId,
    required this.clientEmail,
    required this.privateKeyId,
    required this.privateKeyPem,
    required this.rawJson,
  });

  factory ServiceAccountKey.parse(String jsonText) {
    final Object? decoded;
    try {
      decoded = jsonDecode(jsonText);
    } on FormatException {
      throw const ServiceAccountKeyException(
        'This file is not valid JSON. Choose the .json key file downloaded from Firebase.',
      );
    }
    if (decoded is! Map<String, Object?>) {
      throw const ServiceAccountKeyException(
        'This file is not a service account key (expected a JSON object).',
      );
    }
    final json = decoded;

    if (json.containsKey('project_info') && json.containsKey('client')) {
      throw const ServiceAccountKeyException(
        'This is google-services.json, the Android app config. You need a service account key: '
        'Firebase console → Project settings → Service accounts → Generate new private key.',
      );
    }
    if (json.containsKey('installed') || json.containsKey('web')) {
      throw const ServiceAccountKeyException(
        'This is an OAuth client file, not a service account key. '
        'Generate one in Firebase console → Project settings → Service accounts.',
      );
    }
    final type = json['type'];
    if (type != 'service_account') {
      throw ServiceAccountKeyException(
        'This key has type "${type ?? 'missing'}". A key with type "service_account" is required.',
      );
    }

    String requireField(String name) {
      final value = json[name];
      if (value is! String || value.trim().isEmpty) {
        throw ServiceAccountKeyException('The key file is missing "$name".');
      }
      return value;
    }

    final privateKeyPem = requireField('private_key');
    if (!privateKeyPem.contains('-----BEGIN PRIVATE KEY-----')) {
      throw const ServiceAccountKeyException(
        '"private_key" is not a PKCS#8 PEM key (expected "-----BEGIN PRIVATE KEY-----").',
      );
    }
    try {
      RSAPrivateKey(privateKeyPem);
    } catch (_) {
      throw const ServiceAccountKeyException(
        '"private_key" could not be read as an RSA key. Download a new key file.',
      );
    }

    final keyId = json['private_key_id'];
    return ServiceAccountKey._(
      projectId: requireField('project_id'),
      clientEmail: requireField('client_email'),
      privateKeyId: keyId is String ? keyId : '',
      privateKeyPem: privateKeyPem,
      rawJson: jsonText,
    );
  }

  final String projectId;
  final String clientEmail;
  final String privateKeyId;
  final String privateKeyPem;

  /// The original file contents, stored in SecretStore as-is.
  final String rawJson;

  @override
  List<Object?> get props => [projectId, clientEmail, privateKeyId, privateKeyPem];

  @override
  String toString() => 'ServiceAccountKey($clientEmail, project: $projectId)';
}
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `flutter test test/core/auth/service_account_key_test.dart`
Expected: PASS (9 tests). If the "not a usable RSA key" test fails because `RSAPrivateKey('…AAAA…')` doesn't throw, check how `dart_jsonwebtoken` parses keys. If it parses lazily, add `JWT(<String, Object?>{}).sign(RSAPrivateKey(privateKeyPem), algorithm: JWTAlgorithm.RS256)` inside the same `try`, which forces a real parse.

- [ ] **Step 7: Checkpoint.** Run `dart format lib test`, `flutter analyze` (expect No issues found) and `git status --short`, and report. Do not stage or commit.

---

### Task 5: Access tokens from a service account (+ M0 real-key check)

**Files:**
- Create: `lib/core/auth/access_token_provider.dart`, `lib/core/auth/service_account_token_provider.dart`, `tool/check_sa_token.dart`
- Test: `test/core/auth/service_account_token_provider_test.dart`

**Interfaces:**
- Consumes: `ServiceAccountKey` (Task 4), `Clock`/`SystemClock` and `redact` (Task 3).
- Produces:
  - `class AccessToken extends Equatable { AccessToken(String value, DateTime expiresAt); bool isValidAt(DateTime now, {Duration margin}); }`
  - `abstract interface class AccessTokenProvider { Future<AccessToken> getToken({bool forceRefresh = false}); Map<String, String> extraHeaders(String projectId); }`
  - `class AuthException implements Exception { AuthException(String message, {int? statusCode}); }`
  - `class ServiceAccountTokenProvider implements AccessTokenProvider` with constructor `({required ServiceAccountKey key, required http.Client httpClient, Clock clock = const SystemClock()})`, the statics `tokenEndpoint`, `scopes`, `refreshMargin`, and `String buildAssertion()`.

- [ ] **Step 1: Write the failing tests** `test/core/auth/service_account_token_provider_test.dart`

```dart
import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/auth/service_account_token_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fixed_clock.dart';
import '../../helpers/service_account_fixture.dart';

http.Response tokenResponse({String token = 'ya29.test-token', int expiresIn = 3599}) =>
    http.Response(
      jsonEncode({'access_token': token, 'expires_in': expiresIn, 'token_type': 'Bearer'}),
      200,
    );

void main() {
  late FixedClock clock;
  late ServiceAccountKey key;

  setUp(() {
    clock = FixedClock(DateTime.utc(2026, 1, 1, 12));
    key = ServiceAccountKey.parse(serviceAccountJson());
  });

  ServiceAccountTokenProvider provider(MockClientHandler handler) =>
      ServiceAccountTokenProvider(key: key, httpClient: MockClient(handler), clock: clock);

  test('builds an RS256 assertion with the claims Google expects', () {
    final assertion = provider((_) async => tokenResponse()).buildAssertion();
    final jwt = JWT.verify(assertion, RSAPublicKey(testPublicKeyPem()), checkExpiresIn: false);
    final payload = jwt.payload as Map<String, dynamic>;
    final issuedAt = clock.now().millisecondsSinceEpoch ~/ 1000;

    expect(payload['iss'], testClientEmail);
    expect(payload['sub'], testClientEmail);
    expect(payload['aud'], 'https://oauth2.googleapis.com/token');
    expect(
      payload['scope'],
      'https://www.googleapis.com/auth/firebase.messaging '
      'https://www.googleapis.com/auth/firebase.readonly',
    );
    expect(payload['iat'], issuedAt);
    expect(payload['exp'], issuedAt + 3600);
    expect(jwt.header?['alg'], 'RS256');
    expect(jwt.header?['kid'], 'test-key-id-1');
  });

  test('exchanges the assertion for an access token', () async {
    late http.Request captured;
    final token = await provider((request) async {
      captured = request;
      return tokenResponse();
    }).getToken();

    expect(token.value, 'ya29.test-token');
    expect(token.expiresAt, clock.now().add(const Duration(seconds: 3599)));
    expect(captured.url.toString(), 'https://oauth2.googleapis.com/token');
    expect(captured.bodyFields['grant_type'], 'urn:ietf:params:oauth:grant-type:jwt-bearer');
    expect(captured.bodyFields['assertion'], isNotEmpty);
  });

  test('reuses the token until 5 minutes before it expires', () async {
    var calls = 0;
    final p = provider((_) async {
      calls++;
      return tokenResponse(token: 'ya29.token-$calls');
    });

    expect((await p.getToken()).value, 'ya29.token-1');
    clock.advance(const Duration(minutes: 50));
    expect((await p.getToken()).value, 'ya29.token-1');
    clock.advance(const Duration(minutes: 5));
    expect((await p.getToken()).value, 'ya29.token-2');
    expect(calls, 2);
  });

  test('forceRefresh always fetches a new token', () async {
    var calls = 0;
    final p = provider((_) async {
      calls++;
      return tokenResponse();
    });
    await p.getToken();
    await p.getToken(forceRefresh: true);
    expect(calls, 2);
  });

  test('concurrent callers share one request', () async {
    var calls = 0;
    final p = provider((_) async {
      calls++;
      return tokenResponse();
    });
    await Future.wait([p.getToken(), p.getToken(), p.getToken()]);
    expect(calls, 1);
  });

  test('explains a key that Google rejects', () async {
    final p = provider(
      (_) async => http.Response(
        jsonEncode({'error': 'invalid_grant', 'error_description': 'Invalid JWT Signature.'}),
        400,
      ),
    );
    await expectLater(
      p.getToken(),
      throwsA(
        isA<AuthException>()
            .having((e) => e.message, 'message', contains('rejected this key'))
            .having((e) => e.statusCode, 'statusCode', 400),
      ),
    );
  });

  test('turns network failures into AuthException', () async {
    final p = provider((_) async => throw http.ClientException('Failed host lookup'));
    await expectLater(
      p.getToken(),
      throwsA(isA<AuthException>().having((e) => e.message, 'message', contains('Network error'))),
    );
  });

  test('a failed request does not block later attempts', () async {
    var calls = 0;
    final p = provider((_) async {
      calls++;
      return calls == 1 ? http.Response('oops', 500) : tokenResponse();
    });
    await expectLater(p.getToken(), throwsA(isA<AuthException>()));
    expect((await p.getToken()).value, 'ya29.test-token');
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/core/auth/service_account_token_provider_test.dart`
Expected: FAIL, compilation error.

- [ ] **Step 3: Implement**

`lib/core/auth/access_token_provider.dart`:
```dart
import 'package:equatable/equatable.dart';

class AccessToken extends Equatable {
  const AccessToken(this.value, this.expiresAt);

  final String value;
  final DateTime expiresAt;

  bool isValidAt(DateTime now, {Duration margin = Duration.zero}) =>
      now.add(margin).isBefore(expiresAt);

  @override
  List<Object?> get props => [value, expiresAt];

  @override
  String toString() => 'AccessToken(expiresAt: $expiresAt)';
}

/// Supplies OAuth access tokens for Google API calls.
abstract interface class AccessTokenProvider {
  Future<AccessToken> getToken({bool forceRefresh = false});

  /// Extra headers to send with every API call for [projectId].
  Map<String, String> extraHeaders(String projectId);
}

class AuthException implements Exception {
  const AuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AuthException($statusCode): $message';
}
```

`lib/core/auth/service_account_token_provider.dart`:
```dart
import 'dart:async';
import 'dart:convert';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:http/http.dart' as http;

/// Gets access tokens by signing a JWT with a service account key (works on every platform).
class ServiceAccountTokenProvider implements AccessTokenProvider {
  ServiceAccountTokenProvider({
    required this.key,
    required http.Client httpClient,
    Clock clock = const SystemClock(),
  })  : _http = httpClient,
        _clock = clock,
        _signingKey = RSAPrivateKey(key.privateKeyPem);

  static final Uri tokenEndpoint = Uri.parse('https://oauth2.googleapis.com/token');
  static const scopes = [
    'https://www.googleapis.com/auth/firebase.messaging',
    'https://www.googleapis.com/auth/firebase.readonly',
  ];
  static const refreshMargin = Duration(minutes: 5);
  static const _requestTimeout = Duration(seconds: 20);

  final ServiceAccountKey key;
  final http.Client _http;
  final Clock _clock;
  final RSAPrivateKey _signingKey;
  AccessToken? _cached;
  Future<AccessToken>? _inFlight;

  @override
  Future<AccessToken> getToken({bool forceRefresh = false}) {
    final cached = _cached;
    if (!forceRefresh &&
        cached != null &&
        cached.isValidAt(_clock.now(), margin: refreshMargin)) {
      return Future.value(cached);
    }
    return _inFlight ??= _fetch().whenComplete(() => _inFlight = null);
  }

  @override
  Map<String, String> extraHeaders(String projectId) => const {};

  /// The signed JWT sent to Google's token endpoint. Visible for tests.
  String buildAssertion() {
    final issuedAt = _clock.now().millisecondsSinceEpoch ~/ 1000;
    final jwt = JWT(
      {
        'iss': key.clientEmail,
        'sub': key.clientEmail,
        'aud': tokenEndpoint.toString(),
        'scope': scopes.join(' '),
        'iat': issuedAt,
        'exp': issuedAt + 3600,
      },
      header: {'kid': key.privateKeyId},
    );
    return jwt.sign(_signingKey, algorithm: JWTAlgorithm.RS256, noIssueAt: true);
  }

  Future<AccessToken> _fetch() async {
    final http.Response response;
    try {
      response = await _http.post(
        tokenEndpoint,
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': buildAssertion(),
        },
      ).timeout(_requestTimeout);
    } on TimeoutException {
      throw const AuthException('Google did not answer the token request within 20 seconds.');
    } on http.ClientException catch (e) {
      throw AuthException('Network error while getting an access token: ${redact(e.message)}');
    }

    final body = _decode(response.body);
    if (response.statusCode != 200) {
      throw AuthException(
        _describeError(response.statusCode, body),
        statusCode: response.statusCode,
      );
    }
    final token = body?['access_token'];
    final expiresIn = body?['expires_in'];
    if (token is! String || expiresIn is! num) {
      throw const AuthException('Google returned an unexpected token response.');
    }
    final accessToken = AccessToken(
      token,
      _clock.now().add(Duration(seconds: expiresIn.toInt())),
    );
    _cached = accessToken;
    return accessToken;
  }

  static Map<String, Object?>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String _describeError(int status, Map<String, Object?>? body) {
    final error = body?['error'];
    final description = body?['error_description'];
    final detail = [
      if (error is String) error,
      if (description is String) description,
    ].join(': ');
    if (error == 'invalid_grant') {
      return 'Google rejected this key ($detail). '
          'The key may have been deleted or the service account disabled.';
    }
    return 'Token request failed (HTTP $status${detail.isEmpty ? '' : ', $detail'}).';
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/core/auth/service_account_token_provider_test.dart`
Expected: PASS (8 tests). If `JWT(...)` has no `header:` parameter or `JWT.verify` has no `checkExpiresIn:` in the installed `dart_jsonwebtoken`, check the package's example. Keep the claims and `kid` header the same and only change how they're passed.

- [ ] **Step 5: Write the real-key check tool** `tool/check_sa_token.dart` (M0 check: `dart_jsonwebtoken` with a real Google PKCS#8 key)

```dart
import 'dart:io';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/auth/service_account_token_provider.dart';
import 'package:http/http.dart' as http;

/// Usage: dart run tool/check_sa_token.dart <service-account.json>
/// Prints whether Google issues a token for the key. Never prints the token itself.
Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/check_sa_token.dart <service-account.json>');
    exitCode = 64;
    return;
  }
  final client = http.Client();
  try {
    final key = ServiceAccountKey.parse(await File(args.single).readAsString());
    final token = await ServiceAccountTokenProvider(key: key, httpClient: client).getToken();
    final seconds = token.expiresAt.difference(DateTime.now().toUtc()).inSeconds;
    stdout.writeln(
      'OK: Google issued an access token for ${key.clientEmail} '
      '(project ${key.projectId}), valid for ${seconds}s.',
    );
  } on ServiceAccountKeyException catch (e) {
    stderr.writeln('Invalid key file: ${e.message}');
    exitCode = 1;
  } on AuthException catch (e) {
    stderr.writeln('Token request failed: ${e.message}');
    exitCode = 1;
  } finally {
    client.close();
  }
}
```

- [ ] **Step 6: Run the M0 real-key check.** Ask the user for the path to a real service account key, ideally a separate one with only the "Firebase Cloud Messaging API Admin" role, stored outside the repo or under the git-ignored `secrets/`. Then run:

```bash
dart run tool/check_sa_token.dart <path-to-key.json>
```
Expected: `OK: Google issued an access token for …, valid for 3599s.` (or a value just below). If the user has no key yet, record "real-key check pending" in spec §13 and continue; Task 15 repeats it inside the app.

- [ ] **Step 7: Checkpoint.** Run `dart format lib test tool`, `flutter analyze` (expect No issues found) and `git status --short`, and report. Do not stage or commit.

---

### Task 6: FCM errors, send results and `FcmClient`

**Files:**
- Create: `lib/core/fcm/fcm_error.dart`, `lib/core/fcm/fcm_send_result.dart`, `lib/core/fcm/fcm_client.dart`, `test/helpers/fake_token_provider.dart`, `test/helpers/fcm_fixtures.dart`
- Test: `test/core/fcm/fcm_error_test.dart`, `test/core/fcm/fcm_client_test.dart`

**Interfaces:**
- Consumes: `AccessToken`, `AccessTokenProvider`, `AuthException` (Task 5); `redact` (Task 3).
- Produces:
  - `enum FcmTransportError { none, network, timeout, auth }`
  - `class FieldViolation(String field, String description)`
  - `class FcmError({int? httpStatus, String? status, String? message, String? fcmErrorCode, String? reason, List<FieldViolation> fieldViolations, FcmTransportError transport})` with `factory FcmError.fromResponse(int httpStatus, String body)`
  - `sealed class FcmSendResult { Duration duration; int? httpStatus; String? responseBody; }`, with `FcmSendSuccess(messageName)` and `FcmSendFailure(error)`
  - `class FcmClient({required http.Client httpClient, Duration timeout = 20 s})`, with `static Uri sendUri(String projectId)` and `Future<FcmSendResult> send({required String projectId, required Map<String, Object?> body, required AccessTokenProvider auth})`
  - Test helpers: `FakeTokenProvider({Map<String, String> headers, AuthException? error})`, which issues `token-1`, `token-2`, … and records `forceRefreshCalls`; plus the constants `successBody`, `unregisteredBody`, `invalidArgumentBody`, `serviceDisabledBody`.

- [ ] **Step 1: Write the test helpers**

`test/helpers/fake_token_provider.dart`:
```dart
import 'package:fcm_studio/core/auth/access_token_provider.dart';

class FakeTokenProvider implements AccessTokenProvider {
  FakeTokenProvider({this.headers = const {}, this.error});

  final Map<String, String> headers;
  final AuthException? error;
  final List<bool> forceRefreshCalls = [];
  int _issued = 0;

  @override
  Future<AccessToken> getToken({bool forceRefresh = false}) async {
    forceRefreshCalls.add(forceRefresh);
    final failure = error;
    if (failure != null) throw failure;
    _issued++;
    return AccessToken('token-$_issued', DateTime.utc(2100));
  }

  @override
  Map<String, String> extraHeaders(String projectId) => headers;
}
```

`test/helpers/fcm_fixtures.dart`:
```dart
const successBody = '{"name":"projects/demo-project/messages/0:1"}';

const unregisteredBody =
    '{"error":{"code":404,"message":"Requested entity was not found.","status":"NOT_FOUND",'
    '"details":[{"@type":"type.googleapis.com/google.firebase.fcm.v1.FcmError","errorCode":"UNREGISTERED"}]}}';

const invalidArgumentBody =
    '{"error":{"code":400,"message":"Invalid value at \'message.data[0].value\' (TYPE_STRING), 42",'
    '"status":"INVALID_ARGUMENT","details":[{"@type":"type.googleapis.com/google.rpc.BadRequest",'
    '"fieldViolations":[{"field":"message.data[0].value",'
    '"description":"Invalid value at \'message.data[0].value\' (TYPE_STRING), 42"}]}]}}';

const serviceDisabledBody =
    '{"error":{"code":403,"message":"Firebase Cloud Messaging API has not been used in project '
    '123456789012 before or it is disabled.","status":"PERMISSION_DENIED","details":[{"@type":'
    '"type.googleapis.com/google.rpc.ErrorInfo","reason":"SERVICE_DISABLED","domain":"googleapis.com"}]}}';
```

- [ ] **Step 2: Write the failing error-parsing tests** `test/core/fcm/fcm_error_test.dart`

```dart
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fcm_fixtures.dart';

void main() {
  test('reads the FCM error code', () {
    final error = FcmError.fromResponse(404, unregisteredBody);
    expect(error.httpStatus, 404);
    expect(error.status, 'NOT_FOUND');
    expect(error.fcmErrorCode, 'UNREGISTERED');
    expect(error.message, 'Requested entity was not found.');
  });

  test('reads field violations', () {
    final error = FcmError.fromResponse(400, invalidArgumentBody);
    expect(error.status, 'INVALID_ARGUMENT');
    expect(error.fieldViolations.single.field, 'message.data[0].value');
  });

  test('reads the ErrorInfo reason', () {
    expect(FcmError.fromResponse(403, serviceDisabledBody).reason, 'SERVICE_DISABLED');
  });

  test('keeps a non-JSON body as the message', () {
    final error = FcmError.fromResponse(502, '<html>Bad Gateway</html>');
    expect(error.message, '<html>Bad Gateway</html>');
    expect(error.status, isNull);
    expect(error.fcmErrorCode, isNull);
  });

  test('an empty body has no message', () {
    expect(FcmError.fromResponse(500, '').message, isNull);
  });

  test('truncates very long non-JSON bodies', () {
    expect(FcmError.fromResponse(502, 'x' * 2000).message, hasLength(501));
  });
}
```

- [ ] **Step 3: Write the failing client tests** `test/core/fcm/fcm_client_test.dart`

```dart
import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_token_provider.dart';
import '../../helpers/fcm_fixtures.dart';

void main() {
  const projectId = 'demo-project';
  final body = <String, Object?>{
    'message': {
      'token': 'abc',
      'notification': {'title': 'Hi'},
    },
  };

  test('posts the body with a bearer token and reads the message name', () async {
    late http.Request captured;
    final client = FcmClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(successBody, 200);
      }),
    );

    final result = await client.send(projectId: projectId, body: body, auth: FakeTokenProvider());

    expect(
      result,
      isA<FcmSendSuccess>()
          .having((r) => r.messageName, 'messageName', 'projects/demo-project/messages/0:1'),
    );
    expect(captured.method, 'POST');
    expect(captured.url.toString(), 'https://fcm.googleapis.com/v1/projects/demo-project/messages:send');
    expect(captured.headers['Authorization'], 'Bearer token-1');
    expect(captured.headers['Content-Type'], startsWith('application/json'));
    expect(jsonDecode(captured.body), body);
  });

  test('adds the provider extra headers', () async {
    late http.Request captured;
    final client = FcmClient(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(successBody, 200);
      }),
    );
    await client.send(
      projectId: projectId,
      body: body,
      auth: FakeTokenProvider(headers: {'x-goog-user-project': projectId}),
    );
    expect(captured.headers['x-goog-user-project'], projectId);
  });

  test('after a 401 it refreshes the token once and resends', () async {
    final authHeaders = <String?>[];
    final auth = FakeTokenProvider();
    final client = FcmClient(
      httpClient: MockClient((request) async {
        authHeaders.add(request.headers['Authorization']);
        return authHeaders.length == 1
            ? http.Response('{"error":{"code":401,"status":"UNAUTHENTICATED"}}', 401)
            : http.Response(successBody, 200);
      }),
    );

    final result = await client.send(projectId: projectId, body: body, auth: auth);

    expect(result, isA<FcmSendSuccess>());
    expect(authHeaders, ['Bearer token-1', 'Bearer token-2']);
    expect(auth.forceRefreshCalls, [false, true]);
  });

  test('stops after the second 401', () async {
    var requests = 0;
    final client = FcmClient(
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{"error":{"code":401,"status":"UNAUTHENTICATED"}}', 401);
      }),
    );
    final result = await client.send(projectId: projectId, body: body, auth: FakeTokenProvider());
    expect(requests, 2);
    expect(result, isA<FcmSendFailure>().having((r) => r.httpStatus, 'httpStatus', 401));
  });

  test('does not retry server errors', () async {
    var requests = 0;
    final client = FcmClient(
      httpClient: MockClient((_) async {
        requests++;
        return http.Response('{"error":{"code":503,"status":"UNAVAILABLE"}}', 503);
      }),
    );
    final result = await client.send(projectId: projectId, body: body, auth: FakeTokenProvider());
    expect(requests, 1);
    expect(
      result,
      isA<FcmSendFailure>().having((r) => r.error.status, 'status', 'UNAVAILABLE'),
    );
  });

  test('parses FCM error responses', () async {
    final client = FcmClient(
      httpClient: MockClient((_) async => http.Response(unregisteredBody, 404)),
    );
    final result = await client.send(projectId: projectId, body: body, auth: FakeTokenProvider());
    expect(
      result,
      isA<FcmSendFailure>()
          .having((r) => r.error.fcmErrorCode, 'fcmErrorCode', 'UNREGISTERED')
          .having((r) => r.responseBody, 'responseBody', unregisteredBody),
    );
  });

  test('reports a timeout', () async {
    final client = FcmClient(
      httpClient: MockClient((_) => Completer<http.Response>().future),
      timeout: const Duration(milliseconds: 10),
    );
    final result = await client.send(projectId: projectId, body: body, auth: FakeTokenProvider());
    expect(
      result,
      isA<FcmSendFailure>().having((r) => r.error.transport, 'transport', FcmTransportError.timeout),
    );
  });

  test('reports a network error', () async {
    final client = FcmClient(
      httpClient: MockClient((_) async => throw http.ClientException('Failed host lookup')),
    );
    final result = await client.send(projectId: projectId, body: body, auth: FakeTokenProvider());
    expect(
      result,
      isA<FcmSendFailure>().having((r) => r.error.transport, 'transport', FcmTransportError.network),
    );
  });

  test('reports a failure to get a token', () async {
    final client = FcmClient(httpClient: MockClient((_) async => http.Response(successBody, 200)));
    final result = await client.send(
      projectId: projectId,
      body: body,
      auth: FakeTokenProvider(error: const AuthException('Google rejected this key')),
    );
    expect(
      result,
      isA<FcmSendFailure>()
          .having((r) => r.error.transport, 'transport', FcmTransportError.auth)
          .having((r) => r.error.message, 'message', 'Google rejected this key'),
    );
  });
}
```

- [ ] **Step 4: Run them to see them fail**

Run: `flutter test test/core/fcm/`
Expected: FAIL, compilation errors.

- [ ] **Step 5: Implement**

`lib/core/fcm/fcm_error.dart`:
```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/utils/redact.dart';

/// Why a send failed before FCM returned an HTTP answer.
enum FcmTransportError { none, network, timeout, auth }

class FieldViolation extends Equatable {
  const FieldViolation(this.field, this.description);

  final String field;
  final String description;

  @override
  List<Object?> get props => [field, description];
}

class FcmError extends Equatable {
  const FcmError({
    this.httpStatus,
    this.status,
    this.message,
    this.fcmErrorCode,
    this.reason,
    this.fieldViolations = const [],
    this.transport = FcmTransportError.none,
  });

  /// Parses a Google API error body. Never throws, even for non-JSON bodies.
  factory FcmError.fromResponse(int httpStatus, String body) {
    Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      decoded = null;
    }
    final error = decoded is Map<String, Object?> ? decoded['error'] : null;
    if (error is! Map<String, Object?>) {
      final text = body.trim();
      return FcmError(
        httpStatus: httpStatus,
        message: text.isEmpty ? null : redact(_truncate(text)),
      );
    }

    String? fcmErrorCode;
    String? reason;
    final violations = <FieldViolation>[];
    final details = error['details'];
    if (details is List<Object?>) {
      for (final detail in details.whereType<Map<String, Object?>>()) {
        final type = detail['@type'];
        if (type is! String) {
          continue;
        }
        if (type.endsWith('google.firebase.fcm.v1.FcmError')) {
          fcmErrorCode = _string(detail['errorCode']);
        } else if (type.endsWith('google.rpc.ErrorInfo')) {
          reason = _string(detail['reason']);
        } else if (type.endsWith('google.rpc.BadRequest')) {
          final list = detail['fieldViolations'];
          if (list is List<Object?>) {
            for (final v in list.whereType<Map<String, Object?>>()) {
              violations.add(
                FieldViolation(_string(v['field']) ?? '', _string(v['description']) ?? ''),
              );
            }
          }
        }
      }
    }

    final message = _string(error['message']);
    return FcmError(
      httpStatus: httpStatus,
      status: _string(error['status']),
      message: message == null ? null : redact(message),
      fcmErrorCode: fcmErrorCode,
      reason: reason,
      fieldViolations: violations,
    );
  }

  final int? httpStatus;

  /// Google RPC status, e.g. `NOT_FOUND`, `INVALID_ARGUMENT`.
  final String? status;
  final String? message;

  /// `details[].errorCode` of type `google.firebase.fcm.v1.FcmError`, e.g. `UNREGISTERED`.
  final String? fcmErrorCode;

  /// `details[].reason` of type `google.rpc.ErrorInfo`, e.g. `SERVICE_DISABLED`.
  final String? reason;
  final List<FieldViolation> fieldViolations;
  final FcmTransportError transport;

  static String? _string(Object? value) => value is String ? value : null;

  static String _truncate(String text) =>
      text.length <= 500 ? text : '${text.substring(0, 500)}…';

  @override
  List<Object?> get props =>
      [httpStatus, status, message, fcmErrorCode, reason, fieldViolations, transport];
}
```

`lib/core/fcm/fcm_send_result.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';

sealed class FcmSendResult extends Equatable {
  const FcmSendResult({required this.duration, this.httpStatus, this.responseBody});

  final Duration duration;
  final int? httpStatus;
  final String? responseBody;
}

final class FcmSendSuccess extends FcmSendResult {
  const FcmSendSuccess({
    required this.messageName,
    required super.duration,
    super.httpStatus,
    super.responseBody,
  });

  /// e.g. `projects/demo-project/messages/0:1700000000000000%abc`.
  final String messageName;

  @override
  List<Object?> get props => [messageName, duration, httpStatus, responseBody];
}

final class FcmSendFailure extends FcmSendResult {
  const FcmSendFailure({
    required this.error,
    required super.duration,
    super.httpStatus,
    super.responseBody,
  });

  final FcmError error;

  @override
  List<Object?> get props => [error, duration, httpStatus, responseBody];
}
```

`lib/core/fcm/fcm_client.dart`:
```dart
import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:http/http.dart' as http;

/// Sends messages with the FCM HTTP v1 API.
///
/// Never retries automatically, so a notification is never delivered twice.
/// The only exception is a 401, where the token is refreshed and the request is
/// resent once.
class FcmClient {
  FcmClient({required http.Client httpClient, this.timeout = const Duration(seconds: 20)})
      : _http = httpClient;

  final http.Client _http;
  final Duration timeout;

  static Uri sendUri(String projectId) => Uri.parse(
        'https://fcm.googleapis.com/v1/projects/${Uri.encodeComponent(projectId)}/messages:send',
      );

  Future<FcmSendResult> send({
    required String projectId,
    required Map<String, Object?> body,
    required AccessTokenProvider auth,
  }) async {
    final stopwatch = Stopwatch()..start();
    final encoded = jsonEncode(body);
    try {
      var response = await _post(projectId, encoded, await auth.getToken(), auth);
      if (response.statusCode == 401) {
        response = await _post(projectId, encoded, await auth.getToken(forceRefresh: true), auth);
      }
      stopwatch.stop();
      if (response.statusCode == 200) {
        return FcmSendSuccess(
          messageName: _messageName(response.body),
          duration: stopwatch.elapsed,
          httpStatus: 200,
          responseBody: response.body,
        );
      }
      return FcmSendFailure(
        error: FcmError.fromResponse(response.statusCode, response.body),
        duration: stopwatch.elapsed,
        httpStatus: response.statusCode,
        responseBody: response.body,
      );
    } on AuthException catch (e) {
      return FcmSendFailure(
        error: FcmError(transport: FcmTransportError.auth, message: e.message),
        duration: stopwatch.elapsed,
      );
    } on TimeoutException {
      return FcmSendFailure(
        error: FcmError(
          transport: FcmTransportError.timeout,
          message: 'No response within ${timeout.inSeconds} seconds.',
        ),
        duration: stopwatch.elapsed,
      );
    } on http.ClientException catch (e) {
      return FcmSendFailure(
        error: FcmError(transport: FcmTransportError.network, message: redact(e.message)),
        duration: stopwatch.elapsed,
      );
    }
  }

  Future<http.Response> _post(
    String projectId,
    String encodedBody,
    AccessToken token,
    AccessTokenProvider auth,
  ) {
    return _http
        .post(
          sendUri(projectId),
          headers: {
            'Authorization': 'Bearer ${token.value}',
            'Content-Type': 'application/json; charset=utf-8',
            ...auth.extraHeaders(projectId),
          },
          body: encodedBody,
        )
        .timeout(timeout);
  }

  static String _messageName(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, Object?>) {
        final name = decoded['name'];
        if (name is String) {
          return name;
        }
      }
    } on FormatException {
      // A 200 without a JSON body still means the message was accepted.
    }
    return '';
  }
}
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `flutter test test/core/fcm/`
Expected: PASS (6 + 9 tests).

- [ ] **Step 7: Checkpoint.** Run `dart format lib test`, `flutter analyze` (expect No issues found) and `git status --short`, and report. Do not stage or commit.

---

### Task 7: `FcmErrorExplainer`

**Files:**
- Create: `lib/core/fcm/fcm_error_explainer.dart`
- Test: `test/core/fcm/fcm_error_explainer_test.dart`

**Interfaces:**
- Consumes: `FcmError`, `FcmTransportError` (Task 6).
- Produces: `class ErrorExplanation({required String title, required String explanation, required String action, Uri? link})` and `class FcmErrorExplainer { const FcmErrorExplainer(); ErrorExplanation explain(FcmError error, {required String projectId}); }`.

- [ ] **Step 1: Write the failing tests** `test/core/fcm/fcm_error_explainer_test.dart`

```dart
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_error_explainer.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fcm_fixtures.dart';

void main() {
  const explainer = FcmErrorExplainer();
  ErrorExplanation explain(FcmError error) => explainer.explain(error, projectId: 'demo-project');

  test('UNREGISTERED: the token is stale', () {
    expect(explain(FcmError.fromResponse(404, unregisteredBody)).title, 'Token is no longer valid');
  });

  test('INVALID_ARGUMENT lists each field violation', () {
    final e = explain(FcmError.fromResponse(400, invalidArgumentBody));
    expect(e.title, 'FCM rejected the message');
    expect(e.explanation, contains('message.data[0].value'));
  });

  test('SENDER_ID_MISMATCH: token from another project', () {
    const error = FcmError(httpStatus: 403, status: 'PERMISSION_DENIED', fcmErrorCode: 'SENDER_ID_MISMATCH');
    expect(explain(error).title, 'Token belongs to another Firebase project');
  });

  test('QUOTA_EXCEEDED: sending too fast', () {
    const error = FcmError(httpStatus: 429, status: 'RESOURCE_EXHAUSTED', fcmErrorCode: 'QUOTA_EXCEEDED');
    expect(explain(error).title, 'Sending too fast');
  });

  test('UNAVAILABLE and INTERNAL: temporary problem', () {
    expect(explain(const FcmError(httpStatus: 503, status: 'UNAVAILABLE')).title, 'Temporary FCM problem');
    expect(explain(const FcmError(httpStatus: 500, status: 'INTERNAL')).title, 'Temporary FCM problem');
  });

  test('a non-JSON 502 is a temporary problem that shows the raw text', () {
    final e = explain(FcmError.fromResponse(502, '<html>Bad Gateway</html>'));
    expect(e.title, 'Temporary FCM problem');
    expect(e.explanation, contains('Bad Gateway'));
  });

  test('THIRD_PARTY_AUTH_ERROR links to Cloud Messaging settings', () {
    const error = FcmError(httpStatus: 401, status: 'UNAUTHENTICATED', fcmErrorCode: 'THIRD_PARTY_AUTH_ERROR');
    final e = explain(error);
    expect(e.title, 'APNs or web push credentials problem');
    expect(
      e.link,
      Uri.parse('https://console.firebase.google.com/project/demo-project/settings/cloudmessaging'),
    );
  });

  test('SERVICE_DISABLED links to the API page', () {
    final e = explain(FcmError.fromResponse(403, serviceDisabledBody));
    expect(e.title, 'The FCM API is not enabled');
    expect(e.link.toString(), contains('fcm.googleapis.com/overview?project=demo-project'));
  });

  test('a 401 without an FCM code: token rejected after refresh', () {
    expect(explain(const FcmError(httpStatus: 401, status: 'UNAUTHENTICATED')).title, 'Access token rejected');
  });

  test('other 403s: permission denied, names the role', () {
    final e = explain(const FcmError(httpStatus: 403, status: 'PERMISSION_DENIED'));
    expect(e.title, 'Permission denied');
    expect(e.action, contains('Firebase Cloud Messaging API Admin'));
  });

  test('a 404 without an FCM code: not found', () {
    final e = explain(const FcmError(httpStatus: 404, status: 'NOT_FOUND', message: 'Requested entity was not found.'));
    expect(e.title, 'Not found');
  });

  test('transport errors', () {
    expect(explain(const FcmError(transport: FcmTransportError.network, message: 'x')).title, 'Network error');
    expect(explain(const FcmError(transport: FcmTransportError.timeout)).title, 'FCM did not respond');
    final auth = explain(const FcmError(transport: FcmTransportError.auth, message: 'Key missing.'));
    expect(auth.title, 'Could not get an access token');
    expect(auth.explanation, 'Key missing.');
  });

  test('unknown errors fall back to the raw message', () {
    final e = explain(const FcmError(httpStatus: 418, message: 'teapot'));
    expect(e.title, 'FCM returned an error (HTTP 418)');
    expect(e.explanation, 'teapot');
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/core/fcm/fcm_error_explainer_test.dart`
Expected: FAIL, compilation error.

- [ ] **Step 3: Implement** `lib/core/fcm/fcm_error_explainer.dart`

```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';

class ErrorExplanation extends Equatable {
  const ErrorExplanation({
    required this.title,
    required this.explanation,
    required this.action,
    this.link,
  });

  final String title;
  final String explanation;
  final String action;
  final Uri? link;

  @override
  List<Object?> get props => [title, explanation, action, link];
}

/// Turns an [FcmError] into plain words: what happened, why, and what to do.
class FcmErrorExplainer {
  const FcmErrorExplainer();

  ErrorExplanation explain(FcmError error, {required String projectId}) {
    switch (error.transport) {
      case FcmTransportError.network:
        return ErrorExplanation(
          title: 'Network error',
          explanation: 'Could not reach FCM${error.message == null ? '.' : ': ${error.message}'}',
          action: 'Check your internet connection, then retry.',
        );
      case FcmTransportError.timeout:
        return ErrorExplanation(
          title: 'FCM did not respond',
          explanation: error.message ?? 'No response within 20 seconds.',
          action: 'Retry. If it keeps happening, check your connection or proxy.',
        );
      case FcmTransportError.auth:
        return ErrorExplanation(
          title: 'Could not get an access token',
          explanation: error.message ?? 'Google did not issue an access token.',
          action: 'Add the project again with its service account key file.',
        );
      case FcmTransportError.none:
        break;
    }

    switch (error.fcmErrorCode ?? error.status) {
      case 'UNREGISTERED':
        return const ErrorExplanation(
          title: 'Token is no longer valid',
          explanation: 'The app was uninstalled, its data was cleared, '
              'or it received a new token since this one was copied.',
          action: 'Get the current token from the device and send again.',
        );
      case 'INVALID_ARGUMENT':
        return ErrorExplanation(
          title: 'FCM rejected the message',
          explanation: error.fieldViolations.isEmpty
              ? error.message ?? 'The request is not a valid FCM message.'
              : error.fieldViolations.map((v) => '• ${v.field}: ${v.description}').join('\n'),
          action: 'Fix the fields listed above in the JSON, then send again.',
        );
      case 'SENDER_ID_MISMATCH':
        return ErrorExplanation(
          title: 'Token belongs to another Firebase project',
          explanation: 'This token was issued for a different sender than project $projectId.',
          action: 'Select the project the app is built with, '
              'or get a token from an app that uses $projectId.',
        );
      case 'QUOTA_EXCEEDED':
        return const ErrorExplanation(
          title: 'Sending too fast',
          explanation: "FCM's rate limit for this project or device was reached.",
          action: 'Wait a minute, then retry.',
        );
      case 'UNAVAILABLE' || 'INTERNAL':
        return _temporary(error);
      case 'THIRD_PARTY_AUTH_ERROR':
        return ErrorExplanation(
          title: 'APNs or web push credentials problem',
          explanation: 'Firebase could not authenticate with Apple (APNs) or the web push '
              'service to deliver this message.',
          action: 'Upload a valid APNs authentication key in Project settings → Cloud Messaging.',
          link: Uri.parse(
            'https://console.firebase.google.com/project/$projectId/settings/cloudmessaging',
          ),
        );
    }

    if (error.reason == 'SERVICE_DISABLED') {
      return ErrorExplanation(
        title: 'The FCM API is not enabled',
        explanation: error.message ?? 'Firebase Cloud Messaging API is disabled for this project.',
        action: 'Enable "Firebase Cloud Messaging API" for $projectId, wait a few minutes, then retry.',
        link: Uri.parse(
          'https://console.developers.google.com/apis/api/fcm.googleapis.com/overview?project=$projectId',
        ),
      );
    }

    final status = error.httpStatus;
    if (status == 401) {
      return const ErrorExplanation(
        title: 'Access token rejected',
        explanation: 'Google rejected the access token even after getting a fresh one. '
            'The key may have been deleted or the service account disabled.',
        action: 'Create a new key for the service account and add the project again.',
      );
    }
    if (status == 403) {
      return ErrorExplanation(
        title: 'Permission denied',
        explanation: 'This service account is not allowed to send messages for $projectId.',
        action: 'In Google Cloud IAM, give the service account the '
            '"Firebase Cloud Messaging API Admin" role.',
        link: Uri.parse('https://console.cloud.google.com/iam-admin/iam?project=$projectId'),
      );
    }
    if (status == 404) {
      return ErrorExplanation(
        title: 'Not found',
        explanation: error.message ?? 'FCM could not find this project.',
        action: 'Check that the key file belongs to $projectId.',
      );
    }
    if (status != null && status >= 500) {
      return _temporary(error);
    }
    return ErrorExplanation(
      title: 'FCM returned an error${status == null ? '' : ' (HTTP $status)'}',
      explanation: error.message ?? 'No details were returned.',
      action: 'See the raw response below.',
    );
  }

  static ErrorExplanation _temporary(FcmError error) => ErrorExplanation(
        title: 'Temporary FCM problem',
        explanation: error.message ?? 'FCM returned a server error.',
        action: 'Retry in a few seconds.',
      );
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/core/fcm/fcm_error_explainer_test.dart`
Expected: PASS (13 tests).

- [ ] **Step 5: Checkpoint.** Run `dart format lib test`, `flutter analyze` (expect No issues found) and `git status --short`, and report. Do not stage or commit.

---

### Task 8: Storage: local database and secret store

**Files:**
- Create: `lib/core/storage/app_database.dart`, `lib/core/storage/app_database_platform.dart`, `lib/core/storage/app_database_platform_io.dart`, `lib/core/storage/app_database_platform_web.dart`, `lib/core/storage/secret_store.dart`
- Test: `test/core/storage/app_database_test.dart`, `test/core/storage/secret_store_test.dart`

**Interfaces:**
- Produces:
  - `class AppDatabase { AppDatabase(Database db); final Database db; static Future<AppDatabase> open(); static Future<AppDatabase> inMemory(); Future<void> close(); }`
  - `abstract interface class SecretStore { Future<String?> read(String key); Future<void> write(String key, String value, {bool persist = true}); Future<void> delete(String key); }`
  - `MemorySecretStore`, `LayeredSecretStore({required SecretStore persistent, required bool alwaysPersist})` and `FlutterSecureSecretStore([FlutterSecureStorage? storage])`

- [ ] **Step 1: Write the failing tests**

`test/core/storage/app_database_test.dart`:
```dart
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
```

`test/core/storage/secret_store_test.dart`:
```dart
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LayeredSecretStore', () {
    late MemorySecretStore persistent;

    setUp(() => persistent = MemorySecretStore());

    test('desktop: always persists, even when persist is false', () async {
      final store = LayeredSecretStore(persistent: persistent, alwaysPersist: true);
      await store.write('k', 'v', persist: false);
      expect(await persistent.read('k'), 'v');
    });

    test('web without "remember": keeps the secret in memory only', () async {
      final store = LayeredSecretStore(persistent: persistent, alwaysPersist: false);
      await store.write('k', 'v', persist: false);
      expect(await store.read('k'), 'v');
      expect(await persistent.read('k'), isNull);
    });

    test('a memory-only write removes an older persisted copy', () async {
      final store = LayeredSecretStore(persistent: persistent, alwaysPersist: false);
      await store.write('k', 'old');
      await store.write('k', 'new', persist: false);
      expect(await persistent.read('k'), isNull);
      expect(await store.read('k'), 'new');
    });

    test('after a restart, reads fall back to persistent storage', () async {
      await LayeredSecretStore(persistent: persistent, alwaysPersist: false).write('k', 'v');
      final restarted = LayeredSecretStore(persistent: persistent, alwaysPersist: false);
      expect(await restarted.read('k'), 'v');
    });

    test('delete removes the secret from both layers', () async {
      final store = LayeredSecretStore(persistent: persistent, alwaysPersist: true);
      await store.write('k', 'v');
      await store.delete('k');
      expect(await store.read('k'), isNull);
      expect(await persistent.read('k'), isNull);
    });
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/core/storage/`
Expected: FAIL, compilation errors.

- [ ] **Step 3: Implement**

`lib/core/storage/app_database_platform.dart`:
```dart
export 'package:fcm_studio/core/storage/app_database_platform_io.dart'
    if (dart.library.js_interop) 'package:fcm_studio/core/storage/app_database_platform_web.dart';
```

`lib/core/storage/app_database_platform_io.dart`:
```dart
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

/// Opens the database file in the app support directory (desktop).
Future<Database> openPlatformDatabase(String fileName) async {
  final directory = await getApplicationSupportDirectory();
  await directory.create(recursive: true);
  return databaseFactoryIo.openDatabase(p.join(directory.path, fileName));
}
```

`lib/core/storage/app_database_platform_web.dart`:
```dart
import 'package:sembast/sembast.dart';
import 'package:sembast_web/sembast_web.dart';

/// Opens the database in IndexedDB (web).
Future<Database> openPlatformDatabase(String fileName) =>
    databaseFactoryWeb.openDatabase(fileName);
```

`lib/core/storage/app_database.dart`:
```dart
import 'package:fcm_studio/core/storage/app_database_platform.dart';
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_memory.dart';

/// The local database for projects (and in later milestones presets, targets and history).
/// Secrets never go here; they live in SecretStore.
class AppDatabase {
  AppDatabase(this.db);

  static const fileName = 'fcm_studio.db';

  final Database db;

  static Future<AppDatabase> open() async => AppDatabase(await openPlatformDatabase(fileName));

  /// A fresh, empty database for tests.
  static Future<AppDatabase> inMemory() async =>
      AppDatabase(await newDatabaseFactoryMemory().openDatabase(fileName));

  Future<void> close() => db.close();
}
```

`lib/core/storage/secret_store.dart`:
```dart
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
  LayeredSecretStore({required SecretStore persistent, required this.alwaysPersist})
      : _persistent = persistent;

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
      : _storage = storage ??
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
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/core/storage/`
Expected: PASS (1 + 5 tests). `FlutterSecureSecretStore` is checked by hand in Task 15, because it needs the real Keychain.

- [ ] **Step 5: Checkpoint.** Run `dart format lib test`, `flutter analyze` (expect No issues found), `flutter build web` (this checks the conditional import compiles for web) and `git status --short`, and report. Do not stage or commit.

---

### Task 9: `FirebaseProjectsApi`

**Files:**
- Create: `lib/core/firebase/firebase_projects_api.dart`
- Test: `test/core/firebase/firebase_projects_api_test.dart`

**Interfaces:**
- Consumes: `AccessTokenProvider` (Task 5); the test helper `FakeTokenProvider` (Task 6).
- Produces: `class FirebaseProjectInfo({required String projectId, required String displayName, String? projectNumber})`, `class FirebaseApiException(String message)`, and `class FirebaseProjectsApi({required http.Client httpClient})` with `Future<FirebaseProjectInfo?> getProject(String projectId, AccessTokenProvider auth)`, which returns `null` on 403/404.

- [ ] **Step 1: Write the failing tests** `test/core/firebase/firebase_projects_api_test.dart`

```dart
import 'dart:convert';

import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_token_provider.dart';

void main() {
  test('reads the display name and project number', () async {
    late http.Request captured;
    final api = FirebaseProjectsApi(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'projectId': 'demo-project',
            'projectNumber': '123456789012',
            'displayName': 'Demo Project',
          }),
          200,
        );
      }),
    );

    final info = await api.getProject(
      'demo-project',
      FakeTokenProvider(headers: {'x-goog-user-project': 'demo-project'}),
    );

    expect(
      info,
      const FirebaseProjectInfo(
        projectId: 'demo-project',
        displayName: 'Demo Project',
        projectNumber: '123456789012',
      ),
    );
    expect(captured.url.toString(), 'https://firebase.googleapis.com/v1beta1/projects/demo-project');
    expect(captured.headers['Authorization'], 'Bearer token-1');
    expect(captured.headers['x-goog-user-project'], 'demo-project');
  });

  for (final status in [403, 404]) {
    test('returns null on HTTP $status', () async {
      final api = FirebaseProjectsApi(
        httpClient: MockClient((_) async => http.Response('{"error":{}}', status)),
      );
      expect(await api.getProject('demo-project', FakeTokenProvider()), isNull);
    });
  }

  test('throws on other failures', () async {
    final api = FirebaseProjectsApi(
      httpClient: MockClient((_) async => http.Response('oops', 500)),
    );
    await expectLater(
      api.getProject('demo-project', FakeTokenProvider()),
      throwsA(isA<FirebaseApiException>()),
    );
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/core/firebase/firebase_projects_api_test.dart`
Expected: FAIL, compilation error.

- [ ] **Step 3: Implement** `lib/core/firebase/firebase_projects_api.dart`

```dart
import 'dart:async';
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:http/http.dart' as http;

class FirebaseProjectInfo extends Equatable {
  const FirebaseProjectInfo({
    required this.projectId,
    required this.displayName,
    this.projectNumber,
  });

  final String projectId;
  final String displayName;
  final String? projectNumber;

  @override
  List<Object?> get props => [projectId, displayName, projectNumber];
}

class FirebaseApiException implements Exception {
  const FirebaseApiException(this.message);

  final String message;

  @override
  String toString() => 'FirebaseApiException: $message';
}

/// Reads project details from the Firebase Management API.
class FirebaseProjectsApi {
  FirebaseProjectsApi({required http.Client httpClient}) : _http = httpClient;

  final http.Client _http;

  static Uri projectUri(String projectId) => Uri.parse(
        'https://firebase.googleapis.com/v1beta1/projects/${Uri.encodeComponent(projectId)}',
      );

  /// Returns null when the credential may not read project details (403)
  /// or the project is not a Firebase project (404).
  Future<FirebaseProjectInfo?> getProject(String projectId, AccessTokenProvider auth) async {
    final token = await auth.getToken();
    final response = await _http.get(
      projectUri(projectId),
      headers: {
        'Authorization': 'Bearer ${token.value}',
        ...auth.extraHeaders(projectId),
      },
    ).timeout(const Duration(seconds: 20));

    if (response.statusCode == 403 || response.statusCode == 404) {
      return null;
    }
    if (response.statusCode != 200) {
      throw FirebaseApiException(
        'Firebase Management API returned HTTP ${response.statusCode}.',
      );
    }
    final json = jsonDecode(response.body) as Map<String, Object?>;
    final displayName = json['displayName'];
    final projectNumber = json['projectNumber'];
    return FirebaseProjectInfo(
      projectId: projectId,
      displayName: displayName is String && displayName.isNotEmpty ? displayName : projectId,
      projectNumber: projectNumber is String ? projectNumber : null,
    );
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/core/firebase/firebase_projects_api_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Checkpoint.** Run `dart format lib test`, `flutter analyze` (expect No issues found) and `git status --short`, and report. Do not stage or commit.

---

### Task 10: Project model, repository and auth registry

**Files:**
- Create: `lib/features/projects/domain/project.dart`, `lib/features/projects/domain/access_token_resolver.dart`, `lib/features/projects/data/projects_repository.dart`, `lib/features/projects/data/project_auth_registry.dart`, `test/helpers/project_fixture.dart`
- Test: `test/features/projects/projects_repository_test.dart`, `test/features/projects/project_auth_registry_test.dart`

**Interfaces:**
- Consumes: `AppDatabase` and `SecretStore`/`MemorySecretStore` (Task 8); `ServiceAccountKey` (Task 4); `AccessTokenProvider`, `AuthException` and `ServiceAccountTokenProvider` (Task 5); `Clock` (Task 3).
- Produces:
  - `enum ProjectEnvironment { dev, staging, prod }`
  - `sealed class CredentialRef { String get secretKey; Map<String, Object?> toJson(); static CredentialRef fromJson(Map<String, Object?>); }` and `final class ServiceAccountRef(String clientEmail)` with `secretKey == 'sa:<clientEmail>'`
  - `class Project({required String id, required String displayName, required CredentialRef credential, String? projectNumber, ProjectEnvironment environment = dev})` with `label`, `copyWith({String? displayName, String? Function()? projectNumber, ProjectEnvironment? environment, CredentialRef? credential})`, `toJson()` and `Project.fromJson()`
  - `abstract interface class AccessTokenResolver { Future<AccessTokenProvider> providerFor(Project project); }`
  - `class ProjectsRepository({required AppDatabase database, required SecretStore secrets})` with `loadAll()`, `save(Project)`, `remove(Project)`, `deleteSecretIfUnused(CredentialRef)`, `saveServiceAccountKey(ServiceAccountKey, {required bool persist})`, `readServiceAccountKey(ServiceAccountRef)`, `readSelectedProjectId()` and `writeSelectedProjectId(String?)`
  - `class ProjectAuthRegistry implements AccessTokenResolver` with constructor `({required ProjectsRepository repository, required http.Client httpClient, Clock clock})` and methods `AccessTokenProvider registerKey(ServiceAccountKey)` and `void forget(CredentialRef)`
  - Test helper: `testProject`

- [ ] **Step 1: Write the fixture** `test/helpers/project_fixture.dart`

```dart
import 'package:fcm_studio/features/projects/domain/project.dart';

import 'service_account_fixture.dart';

const testProject = Project(
  id: testProjectId,
  displayName: 'Demo Project',
  projectNumber: testProjectNumber,
  credential: ServiceAccountRef(testClientEmail),
);
```

- [ ] **Step 2: Write the failing repository tests** `test/features/projects/projects_repository_test.dart`

```dart
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/project_fixture.dart';
import '../../helpers/service_account_fixture.dart';

void main() {
  late AppDatabase database;
  late MemorySecretStore secrets;
  late ProjectsRepository repository;

  setUp(() async {
    database = await AppDatabase.inMemory();
    secrets = MemorySecretStore();
    repository = ProjectsRepository(database: database, secrets: secrets);
  });

  tearDown(() => database.close());

  const other = Project(
    id: 'other-project',
    displayName: 'Another',
    credential: ServiceAccountRef('sender@other-project.iam.gserviceaccount.com'),
  );

  test('saves projects and loads them sorted by name', () async {
    await repository.save(testProject);
    await repository.save(other);
    expect((await repository.loadAll()).map((p) => p.id), ['other-project', 'demo-project']);
  });

  test('round-trips every field', () async {
    final project = testProject.copyWith(environment: ProjectEnvironment.prod);
    await repository.save(project);
    expect(await repository.loadAll(), [project]);
  });

  test('removing a project deletes its key when no other project uses it', () async {
    await secrets.write(testProject.credential.secretKey, 'key');
    await repository.save(testProject);
    await repository.remove(testProject);
    expect(await repository.loadAll(), isEmpty);
    expect(await secrets.read(testProject.credential.secretKey), isNull);
  });

  test('removing a project keeps a key another project still uses', () async {
    const sibling = Project(
      id: 'sibling',
      displayName: 'Sibling',
      credential: ServiceAccountRef(testClientEmail),
    );
    await secrets.write(testProject.credential.secretKey, 'key');
    await repository.save(testProject);
    await repository.save(sibling);
    await repository.remove(testProject);
    expect(await secrets.read(testProject.credential.secretKey), 'key');
  });

  test('stores and clears the selected project id', () async {
    expect(await repository.readSelectedProjectId(), isNull);
    await repository.writeSelectedProjectId(testProjectId);
    expect(await repository.readSelectedProjectId(), testProjectId);
    await repository.writeSelectedProjectId(null);
    expect(await repository.readSelectedProjectId(), isNull);
  });

  test('stores and reads a service account key', () async {
    final key = ServiceAccountKey.parse(serviceAccountJson());
    await repository.saveServiceAccountKey(key, persist: true);
    expect(await repository.readServiceAccountKey(const ServiceAccountRef(testClientEmail)), key);
  });

  test('returns null when the key is missing', () async {
    expect(await repository.readServiceAccountKey(const ServiceAccountRef(testClientEmail)), isNull);
  });

  test('Project.fromJson rejects unknown credential kinds', () {
    expect(
      () => Project.fromJson({
        ...testProject.toJson(),
        'credential': {'kind': 'mystery'},
      }),
      throwsFormatException,
    );
  });

  test('label shows the id only when it differs from the name', () {
    expect(testProject.label, 'Demo Project (demo-project)');
    expect(testProject.copyWith(displayName: testProjectId).label, testProjectId);
  });
}
```

- [ ] **Step 3: Write the failing registry tests** `test/features/projects/project_auth_registry_test.dart`

```dart
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/auth/service_account_token_provider.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/project_fixture.dart';
import '../../helpers/service_account_fixture.dart';

void main() {
  late AppDatabase database;
  late ProjectsRepository repository;
  late ProjectAuthRegistry registry;

  setUp(() async {
    database = await AppDatabase.inMemory();
    repository = ProjectsRepository(database: database, secrets: MemorySecretStore());
    registry = ProjectAuthRegistry(
      repository: repository,
      httpClient: MockClient((_) async => http.Response('unused', 500)),
    );
  });

  tearDown(() => database.close());

  test('loads the stored key once and caches the provider', () async {
    await repository.saveServiceAccountKey(
      ServiceAccountKey.parse(serviceAccountJson()),
      persist: true,
    );
    final first = await registry.providerFor(testProject);
    final second = await registry.providerFor(testProject);
    expect(first, isA<ServiceAccountTokenProvider>());
    expect(second, same(first));
  });

  test('explains a missing key (e.g. web reload without "remember")', () async {
    await expectLater(
      registry.providerFor(testProject),
      throwsA(
        isA<AuthException>()
            .having((e) => e.message, 'message', contains('Add the project again')),
      ),
    );
  });

  test('registerKey replaces the provider for the same service account', () async {
    final key = ServiceAccountKey.parse(serviceAccountJson());
    final first = registry.registerKey(key);
    final second = registry.registerKey(key);
    expect(second, isNot(same(first)));
    expect(await registry.providerFor(testProject), same(second));
  });

  test('forget drops the cached provider', () async {
    final key = ServiceAccountKey.parse(serviceAccountJson());
    await repository.saveServiceAccountKey(key, persist: true);
    final first = registry.registerKey(key);
    registry.forget(testProject.credential);
    expect(await registry.providerFor(testProject), isNot(same(first)));
  });
}
```

- [ ] **Step 4: Run them to see them fail**

Run: `flutter test test/features/projects/`
Expected: FAIL, compilation errors.

- [ ] **Step 5: Implement**

`lib/features/projects/domain/project.dart`:
```dart
import 'package:equatable/equatable.dart';

/// Written into every stored project record, for future migrations.
const kProjectSchemaVersion = 1;

enum ProjectEnvironment { dev, staging, prod }

/// Which credential a project uses. Google accounts arrive in M4.
sealed class CredentialRef extends Equatable {
  const CredentialRef();

  /// The SecretStore key that holds this credential's secret.
  String get secretKey;

  Map<String, Object?> toJson();

  static CredentialRef fromJson(Map<String, Object?> json) => switch (json['kind']) {
        'service_account' => ServiceAccountRef(json['clientEmail']! as String),
        final kind => throw FormatException('Unknown credential kind: $kind'),
      };
}

final class ServiceAccountRef extends CredentialRef {
  const ServiceAccountRef(this.clientEmail);

  final String clientEmail;

  @override
  String get secretKey => 'sa:$clientEmail';

  @override
  Map<String, Object?> toJson() => {'kind': 'service_account', 'clientEmail': clientEmail};

  @override
  List<Object?> get props => [clientEmail];
}

class Project extends Equatable {
  const Project({
    required this.id,
    required this.displayName,
    required this.credential,
    this.projectNumber,
    this.environment = ProjectEnvironment.dev,
  });

  factory Project.fromJson(Map<String, Object?> json) => Project(
        id: json['id']! as String,
        displayName: json['displayName']! as String,
        projectNumber: json['projectNumber'] as String?,
        environment: ProjectEnvironment.values.byName(json['environment']! as String),
        credential: CredentialRef.fromJson(json['credential']! as Map<String, Object?>),
      );

  /// The Firebase project ID, e.g. `demo-project`.
  final String id;
  final String displayName;

  /// Firebase project number (= FCM sender ID). Optional.
  final String? projectNumber;
  final ProjectEnvironment environment;
  final CredentialRef credential;

  String get label => displayName == id ? id : '$displayName ($id)';

  Project copyWith({
    String? displayName,
    String? Function()? projectNumber,
    ProjectEnvironment? environment,
    CredentialRef? credential,
  }) {
    return Project(
      id: id,
      displayName: displayName ?? this.displayName,
      projectNumber: projectNumber != null ? projectNumber() : this.projectNumber,
      environment: environment ?? this.environment,
      credential: credential ?? this.credential,
    );
  }

  Map<String, Object?> toJson() => {
        'schemaVersion': kProjectSchemaVersion,
        'id': id,
        'displayName': displayName,
        'projectNumber': projectNumber,
        'environment': environment.name,
        'credential': credential.toJson(),
      };

  @override
  List<Object?> get props => [id, displayName, projectNumber, environment, credential];
}
```

`lib/features/projects/domain/access_token_resolver.dart`:
```dart
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

/// Finds the access token provider for a project's credential.
abstract interface class AccessTokenResolver {
  /// Throws [AuthException] when the credential is not available.
  Future<AccessTokenProvider> providerFor(Project project);
}
```

`lib/features/projects/data/projects_repository.dart`:
```dart
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:sembast/sembast.dart';

class ProjectsRepository {
  ProjectsRepository({required AppDatabase database, required SecretStore secrets})
      : _db = database.db,
        _secrets = secrets;

  static final _projects = stringMapStoreFactory.store('projects');
  static final _settings = StoreRef<String, String>('settings');
  static const _selectedProjectKey = 'selectedProjectId';

  final Database _db;
  final SecretStore _secrets;

  Future<List<Project>> loadAll() async {
    final records = await _projects.find(_db);
    return records.map((record) => Project.fromJson(record.value)).toList()
      ..sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
  }

  Future<void> save(Project project) => _projects.record(project.id).put(_db, project.toJson());

  Future<void> remove(Project project) async {
    await _projects.record(project.id).delete(_db);
    await deleteSecretIfUnused(project.credential);
  }

  /// Deletes the credential's secret unless a stored project still uses it.
  Future<void> deleteSecretIfUnused(CredentialRef credential) async {
    final projects = await loadAll();
    if (projects.any((p) => p.credential == credential)) {
      return;
    }
    await _secrets.delete(credential.secretKey);
  }

  Future<void> saveServiceAccountKey(ServiceAccountKey key, {required bool persist}) =>
      _secrets.write(ServiceAccountRef(key.clientEmail).secretKey, key.rawJson, persist: persist);

  Future<ServiceAccountKey?> readServiceAccountKey(ServiceAccountRef credential) async {
    final raw = await _secrets.read(credential.secretKey);
    if (raw == null) {
      return null;
    }
    try {
      return ServiceAccountKey.parse(raw);
    } on ServiceAccountKeyException {
      return null;
    }
  }

  Future<String?> readSelectedProjectId() => _settings.record(_selectedProjectKey).get(_db);

  Future<void> writeSelectedProjectId(String? projectId) async {
    final record = _settings.record(_selectedProjectKey);
    if (projectId == null) {
      await record.delete(_db);
    } else {
      await record.put(_db, projectId);
    }
  }
}
```

`lib/features/projects/data/project_auth_registry.dart`:
```dart
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/auth/service_account_token_provider.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:http/http.dart' as http;

/// Keeps one token provider per credential, so tokens are cached across sends.
class ProjectAuthRegistry implements AccessTokenResolver {
  ProjectAuthRegistry({
    required ProjectsRepository repository,
    required http.Client httpClient,
    Clock clock = const SystemClock(),
  })  : _repository = repository,
        _http = httpClient,
        _clock = clock;

  final ProjectsRepository _repository;
  final http.Client _http;
  final Clock _clock;
  final Map<String, AccessTokenProvider> _providers = {};

  /// Creates (or replaces) the provider for [key]'s service account.
  AccessTokenProvider registerKey(ServiceAccountKey key) {
    final provider = ServiceAccountTokenProvider(key: key, httpClient: _http, clock: _clock);
    _providers[ServiceAccountRef(key.clientEmail).secretKey] = provider;
    return provider;
  }

  void forget(CredentialRef credential) => _providers.remove(credential.secretKey);

  @override
  Future<AccessTokenProvider> providerFor(Project project) async {
    final credential = project.credential;
    final cached = _providers[credential.secretKey];
    if (cached != null) {
      return cached;
    }
    switch (credential) {
      case ServiceAccountRef():
        final key = await _repository.readServiceAccountKey(credential);
        if (key == null) {
          throw AuthException(
            'The service account key for ${project.id} is not available in this session. '
            'Add the project again with the same key file.',
          );
        }
        return registerKey(key);
    }
  }
}
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `flutter test test/features/projects/`
Expected: PASS (9 + 4 tests).

- [ ] **Step 7: Checkpoint.** Run `dart format lib test`, `flutter analyze` (expect No issues found) and `git status --short`, and report. Do not stage or commit.

---

### Task 11: `ProjectsCubit`

**Files:**
- Create: `lib/features/projects/cubit/projects_state.dart`, `lib/features/projects/cubit/projects_cubit.dart`, `test/helpers/fake_google.dart`
- Test: `test/features/projects/projects_cubit_test.dart`

**Interfaces:**
- Consumes: `ProjectsRepository`, `ProjectAuthRegistry`, `Project`, `ServiceAccountRef` and `ProjectEnvironment` (Task 10); `FirebaseProjectsApi`/`FirebaseProjectInfo` (Task 9); `ServiceAccountKey`/`ServiceAccountKeyException` (Task 4); `AuthException` (Task 5).
- Produces:
  - `enum ProjectsStatus { initial, loading, ready }`
  - `class ProjectsState({ProjectsStatus status, List<Project> projects, String? selectedId})` with `Project? get selected`
  - `sealed class AddProjectResult`, `AddProjectSuccess(Project project, {required bool needsProjectNumber})` and `AddProjectFailure(String message)`
  - `class ProjectsCubit({required ProjectsRepository repository, required ProjectAuthRegistry authRegistry, required FirebaseProjectsApi firebaseApi})` with `load()`, `addFromServiceAccount(String jsonText, {required bool persistKey})`, `select(String)`, `setEnvironment(String, ProjectEnvironment)`, `setProjectNumber(String, String?)` and `remove(String)`. `projects_cubit.dart` exports `projects_state.dart`.
  - Test helper: `http.Client fakeGoogle({int tokenStatus = 200, int firebaseStatus = 200, int fcmStatus = 200, String fcmBody = successBody})`

- [ ] **Step 1: Write the fake Google backend** `test/helpers/fake_google.dart`

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'fcm_fixtures.dart';
import 'service_account_fixture.dart';

/// Answers the three Google hosts the app talks to.
http.Client fakeGoogle({
  int tokenStatus = 200,
  int firebaseStatus = 200,
  int fcmStatus = 200,
  String fcmBody = successBody,
}) {
  return MockClient((request) async {
    switch (request.url.host) {
      case 'oauth2.googleapis.com':
        return tokenStatus == 200
            ? http.Response(
                jsonEncode({'access_token': 'ya29.test-token', 'expires_in': 3599, 'token_type': 'Bearer'}),
                200,
              )
            : http.Response(
                jsonEncode({'error': 'invalid_grant', 'error_description': 'Invalid JWT Signature.'}),
                tokenStatus,
              );
      case 'firebase.googleapis.com':
        return firebaseStatus == 200
            ? http.Response(
                jsonEncode({
                  'projectId': testProjectId,
                  'projectNumber': testProjectNumber,
                  'displayName': 'Demo Project',
                }),
                200,
              )
            : http.Response('{"error":{"code":$firebaseStatus}}', firebaseStatus);
      case 'fcm.googleapis.com':
        return http.Response(fcmBody, fcmStatus);
      default:
        return http.Response('unexpected host ${request.url.host}', 500);
    }
  });
}
```

- [ ] **Step 2: Write the failing tests** `test/features/projects/projects_cubit_test.dart`

```dart
import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/fake_google.dart';
import '../../helpers/project_fixture.dart';
import '../../helpers/service_account_fixture.dart';

void main() {
  late AppDatabase database;
  late MemorySecretStore secrets;
  late ProjectsRepository repository;

  setUp(() async {
    database = await AppDatabase.inMemory();
    secrets = MemorySecretStore();
    repository = ProjectsRepository(database: database, secrets: secrets);
  });

  tearDown(() => database.close());

  ProjectsCubit buildCubit([http.Client? client]) {
    final httpClient = client ?? fakeGoogle();
    return ProjectsCubit(
      repository: repository,
      authRegistry: ProjectAuthRegistry(repository: repository, httpClient: httpClient),
      firebaseApi: FirebaseProjectsApi(httpClient: httpClient),
    );
  }

  test('adds a project from a service account key and selects it', () async {
    final cubit = buildCubit();
    await cubit.load();

    final result = await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);

    expect(
      result,
      isA<AddProjectSuccess>().having((r) => r.needsProjectNumber, 'needsProjectNumber', isFalse),
    );
    expect(cubit.state.selected, testProject);
    expect(await repository.loadAll(), [testProject]);
    expect(await repository.readSelectedProjectId(), testProjectId);
    expect(await secrets.read('sa:$testClientEmail'), isNotNull);
  });

  test('uses the project ID as the name when the key cannot read project details', () async {
    final cubit = buildCubit(fakeGoogle(firebaseStatus: 403));
    await cubit.load();

    final result = await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);

    expect(
      result,
      isA<AddProjectSuccess>().having((r) => r.needsProjectNumber, 'needsProjectNumber', isTrue),
    );
    expect(cubit.state.selected?.displayName, testProjectId);
    expect(cubit.state.selected?.projectNumber, isNull);
  });

  test('reports an invalid key file and changes nothing', () async {
    final cubit = buildCubit();
    await cubit.load();

    final result = await cubit.addFromServiceAccount('{}', persistKey: true);

    expect(result, isA<AddProjectFailure>());
    expect(cubit.state.projects, isEmpty);
  });

  test('reports a key that Google rejects and saves nothing', () async {
    final cubit = buildCubit(fakeGoogle(tokenStatus: 400));
    await cubit.load();

    final result = await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);

    expect(
      result,
      isA<AddProjectFailure>().having((r) => r.message, 'message', contains('rejected this key')),
    );
    expect(await repository.loadAll(), isEmpty);
    expect(await secrets.read('sa:$testClientEmail'), isNull);
  });

  test('adding the same project again keeps its environment', () async {
    final cubit = buildCubit();
    await cubit.load();
    await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);
    await cubit.setEnvironment(testProjectId, ProjectEnvironment.prod);

    await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);

    expect(cubit.state.projects, hasLength(1));
    expect(cubit.state.selected?.environment, ProjectEnvironment.prod);
  });

  test('load restores projects and the selected project', () async {
    await buildCubit().addFromServiceAccount(serviceAccountJson(), persistKey: true);

    final restored = buildCubit();
    await restored.load();

    expect(restored.state.status, ProjectsStatus.ready);
    expect(restored.state.selectedId, testProjectId);
    expect(restored.state.projects, [testProject]);
  });

  test('remove deletes the project and its key and selects another project', () async {
    final cubit = buildCubit();
    await cubit.load();
    await cubit.addFromServiceAccount(
      serviceAccountJson(projectId: 'other-project', clientEmail: 'sender@other-project.iam.gserviceaccount.com'),
      persistKey: true,
    );
    await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);

    await cubit.remove(testProjectId);

    expect(cubit.state.projects.map((p) => p.id), ['other-project']);
    expect(cubit.state.selectedId, 'other-project');
    expect(await secrets.read('sa:$testClientEmail'), isNull);
    expect(await repository.readSelectedProjectId(), 'other-project');
  });

  test('setProjectNumber trims the value, and empty clears it', () async {
    final cubit = buildCubit(fakeGoogle(firebaseStatus: 403));
    await cubit.load();
    await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);

    await cubit.setProjectNumber(testProjectId, ' 42 ');
    expect(cubit.state.selected?.projectNumber, '42');

    await cubit.setProjectNumber(testProjectId, '');
    expect(cubit.state.selected?.projectNumber, isNull);
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/projects/projects_cubit_test.dart`
Expected: FAIL, compilation error.

- [ ] **Step 4: Implement**

`lib/features/projects/cubit/projects_state.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

enum ProjectsStatus { initial, loading, ready }

class ProjectsState extends Equatable {
  const ProjectsState({
    this.status = ProjectsStatus.initial,
    this.projects = const [],
    this.selectedId,
  });

  final ProjectsStatus status;
  final List<Project> projects;
  final String? selectedId;

  Project? get selected {
    for (final project in projects) {
      if (project.id == selectedId) {
        return project;
      }
    }
    return null;
  }

  ProjectsState copyWith({
    ProjectsStatus? status,
    List<Project>? projects,
    String? Function()? selectedId,
  }) {
    return ProjectsState(
      status: status ?? this.status,
      projects: projects ?? this.projects,
      selectedId: selectedId != null ? selectedId() : this.selectedId,
    );
  }

  @override
  List<Object?> get props => [status, projects, selectedId];
}
```

`lib/features/projects/cubit/projects_cubit.dart`:
```dart
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:fcm_studio/features/projects/cubit/projects_state.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/projects/cubit/projects_state.dart';

sealed class AddProjectResult {
  const AddProjectResult();
}

final class AddProjectSuccess extends AddProjectResult {
  const AddProjectSuccess(this.project, {required this.needsProjectNumber});

  final Project project;

  /// True when the key could not read the project number; the user may enter it.
  final bool needsProjectNumber;
}

final class AddProjectFailure extends AddProjectResult {
  const AddProjectFailure(this.message);

  final String message;
}

class ProjectsCubit extends Cubit<ProjectsState> {
  ProjectsCubit({
    required ProjectsRepository repository,
    required ProjectAuthRegistry authRegistry,
    required FirebaseProjectsApi firebaseApi,
  })  : _repository = repository,
        _authRegistry = authRegistry,
        _firebaseApi = firebaseApi,
        super(const ProjectsState());

  final ProjectsRepository _repository;
  final ProjectAuthRegistry _authRegistry;
  final FirebaseProjectsApi _firebaseApi;

  Future<void> load() async {
    emit(state.copyWith(status: ProjectsStatus.loading));
    final projects = await _repository.loadAll();
    final saved = await _repository.readSelectedProjectId();
    final selectedId = projects.any((p) => p.id == saved) ? saved : projects.firstOrNull?.id;
    emit(ProjectsState(status: ProjectsStatus.ready, projects: projects, selectedId: selectedId));
  }

  /// Validates the key, checks it with Google, then saves and selects the project.
  /// Adding a project that already exists updates its key and keeps its settings.
  Future<AddProjectResult> addFromServiceAccount(String jsonText, {required bool persistKey}) async {
    final ServiceAccountKey key;
    try {
      key = ServiceAccountKey.parse(jsonText);
    } on ServiceAccountKeyException catch (e) {
      return AddProjectFailure(e.message);
    }

    final credential = ServiceAccountRef(key.clientEmail);
    final provider = _authRegistry.registerKey(key);
    try {
      await provider.getToken(forceRefresh: true);
    } on AuthException catch (e) {
      _authRegistry.forget(credential);
      return AddProjectFailure(e.message);
    }

    // Project details are optional: any failure here just leaves them blank.
    FirebaseProjectInfo? info;
    try {
      info = await _firebaseApi.getProject(key.projectId, provider);
    } catch (_) {
      info = null;
    }

    final existing = state.projects.where((p) => p.id == key.projectId).firstOrNull;
    final project = Project(
      id: key.projectId,
      displayName: info?.displayName ?? existing?.displayName ?? key.projectId,
      projectNumber: info?.projectNumber ?? existing?.projectNumber,
      environment: existing?.environment ?? ProjectEnvironment.dev,
      credential: credential,
    );

    await _repository.saveServiceAccountKey(key, persist: persistKey);
    await _repository.save(project);
    if (existing != null && existing.credential != credential) {
      _authRegistry.forget(existing.credential);
      await _repository.deleteSecretIfUnused(existing.credential);
    }
    await _repository.writeSelectedProjectId(project.id);

    final projects = [...state.projects.where((p) => p.id != project.id), project]..sort(_byName);
    emit(
      state.copyWith(status: ProjectsStatus.ready, projects: projects, selectedId: () => project.id),
    );
    return AddProjectSuccess(project, needsProjectNumber: project.projectNumber == null);
  }

  Future<void> select(String projectId) async {
    if (!state.projects.any((p) => p.id == projectId)) {
      return;
    }
    await _repository.writeSelectedProjectId(projectId);
    emit(state.copyWith(selectedId: () => projectId));
  }

  Future<void> setEnvironment(String projectId, ProjectEnvironment environment) =>
      _update(projectId, (p) => p.copyWith(environment: environment));

  Future<void> setProjectNumber(String projectId, String? number) {
    final trimmed = number?.trim();
    return _update(
      projectId,
      (p) => p.copyWith(projectNumber: () => trimmed == null || trimmed.isEmpty ? null : trimmed),
    );
  }

  Future<void> remove(String projectId) async {
    final project = state.projects.where((p) => p.id == projectId).firstOrNull;
    if (project == null) {
      return;
    }
    await _repository.remove(project);
    final remaining = state.projects.where((p) => p.id != projectId).toList();
    if (!remaining.any((p) => p.credential == project.credential)) {
      _authRegistry.forget(project.credential);
    }
    final selectedId = state.selectedId == projectId ? remaining.firstOrNull?.id : state.selectedId;
    await _repository.writeSelectedProjectId(selectedId);
    emit(state.copyWith(projects: remaining, selectedId: () => selectedId));
  }

  Future<void> _update(String projectId, Project Function(Project) change) async {
    final index = state.projects.indexWhere((p) => p.id == projectId);
    if (index < 0) {
      return;
    }
    final updated = change(state.projects[index]);
    await _repository.save(updated);
    final projects = [...state.projects]..[index] = updated;
    emit(state.copyWith(projects: projects));
  }

  static int _byName(Project a, Project b) =>
      a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/features/projects/`
Expected: PASS (all project tests, including 8 new cubit tests).

- [ ] **Step 6: Checkpoint.** Run `dart format lib test`, `flutter analyze` (expect No issues found) and `git status --short`, and report. Do not stage or commit.

---

### Task 12: Composer domain: target, FCM rules, `MessageRenderer`

**Files:**
- Create: `lib/features/composer/domain/render_issue.dart`, `lib/features/composer/domain/target.dart`, `lib/features/composer/domain/fcm_rules.dart`, `lib/features/composer/domain/message_renderer.dart`
- Test: `test/features/composer/target_test.dart`, `test/features/composer/message_renderer_test.dart`

**Interfaces:**
- Produces:
  - `class RenderIssue(String path, String message)`
  - `enum TargetKind { token, topic, condition }`
  - `sealed class Target` with `factory Target.of(TargetKind, String)`, `static const messageFields`, `TargetKind get kind`, `Map<String, String> toMessageField()` and `List<RenderIssue> validate()`. Subclasses: `TokenTarget(raw)` with `.token`, `TopicTarget(raw)` with `.name`, `ConditionTarget(raw)` with `.expression`.
  - `class ReservedKeyProblem(String message, {required bool blocking})` and `abstract final class FcmRules` with `topicPattern`, `maxPayloadBytes` and `reservedDataKeyProblem(String key)`
  - `class RenderResult({Map<String, Object?>? request, List<RenderIssue> notes, warnings, errors})` with `bool get canSend`
  - `class MessageRenderer { const MessageRenderer(); RenderResult render({required Map<String, Object?> template, required Target target, bool validateOnly = false}); }`
- Variable substitution (spec §5.2 step 1) is **not** part of M1. It arrives with presets in M2.

- [ ] **Step 1: Write the failing target tests** `test/features/composer/target_test.dart`

```dart
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('token: removes whitespace, line breaks and surrounding quotes', () {
    expect(const TokenTarget('  "abc:APA91b\n  xyz"  ').token, 'abc:APA91bxyz');
    expect(const TokenTarget("'abc'").token, 'abc');
  });

  test('token: empty is an error', () {
    expect(const TokenTarget('  ').validate().single.message, 'Enter a device token.');
    expect(const TokenTarget('abc').validate(), isEmpty);
  });

  test('topic: removes /topics/ and checks the characters', () {
    expect(const TopicTarget(' /topics/news ').name, 'news');
    expect(const TopicTarget('news').validate(), isEmpty);
    expect(const TopicTarget('news feed').validate().single.path, 'target');
    expect(const TopicTarget('').validate().single.message, 'Enter a topic name.');
  });

  test('condition: trims and requires a value', () {
    expect(const ConditionTarget("  'a' in topics ").expression, "'a' in topics");
    expect(const ConditionTarget(' ').validate(), hasLength(1));
  });

  test('toMessageField uses the matching FCM field', () {
    expect(const TokenTarget(' a ').toMessageField(), {'token': 'a'});
    expect(const TopicTarget('/topics/b').toMessageField(), {'topic': 'b'});
    expect(const ConditionTarget("'b' in topics").toMessageField(), {'condition': "'b' in topics"});
  });

  test('Target.of builds the matching type', () {
    expect(Target.of(TargetKind.token, 'a'), const TokenTarget('a'));
    expect(Target.of(TargetKind.topic, 'a'), const TopicTarget('a'));
    expect(Target.of(TargetKind.condition, 'a'), const ConditionTarget('a'));
  });
}
```

- [ ] **Step 2: Write the failing renderer tests** `test/features/composer/message_renderer_test.dart`

```dart
import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const renderer = MessageRenderer();
  const notification = {'title': 'Hi'};

  Map<String, Object?> message(RenderResult result) =>
      result.request!['message']! as Map<String, Object?>;

  test('puts the target first and keeps the template fields', () {
    final result = renderer.render(
      template: {'notification': notification},
      target: const TokenTarget('abc:APA91bxyz'),
    );
    expect(result.canSend, isTrue);
    expect(result.request, {
      'message': {'token': 'abc:APA91bxyz', 'notification': notification},
    });
    expect(message(result).keys.first, 'token');
  });

  test('adds validate_only only for dry runs', () {
    final normal = renderer.render(template: {'notification': notification}, target: const TopicTarget('news'));
    final dryRun = renderer.render(
      template: {'notification': notification},
      target: const TopicTarget('news'),
      validateOnly: true,
    );
    expect(normal.request!.containsKey('validate_only'), isFalse);
    expect(dryRun.request!['validate_only'], isTrue);
  });

  test('turns data values into strings and notes each conversion', () {
    final result = renderer.render(
      template: {
        'notification': notification,
        'data': {
          'order_id': 42,
          'urgent': true,
          'meta': {'a': 1},
          'list': [1, 2],
          'text': 'ok',
          'gone': null,
        },
      },
      target: const TopicTarget('news'),
    );
    expect(message(result)['data'], {
      'order_id': '42',
      'urgent': 'true',
      'meta': '{"a":1}',
      'list': '[1,2]',
      'text': 'ok',
    });
    expect(
      result.notes.map((n) => n.path),
      containsAll(['data.order_id', 'data.urgent', 'data.meta', 'data.list', 'data.gone']),
    );
    expect(result.canSend, isTrue);
  });

  test('blocks data keys that FCM v1 reserves', () {
    for (final key in ['from', 'message_type', 'google.c.a.e', 'gcm.notification.title']) {
      final result = renderer.render(
        template: {
          'notification': notification,
          'data': {key: 'v'},
        },
        target: const TopicTarget('news'),
      );
      expect(result.canSend, isFalse, reason: key);
      expect(result.errors.single.path, 'data.$key', reason: key);
    }
  });

  test('warns about data keys that older SDKs reserve', () {
    for (final key in ['notification', 'gcm_custom', 'googleish']) {
      final result = renderer.render(
        template: {
          'notification': notification,
          'data': {key: 'v'},
        },
        target: const TopicTarget('news'),
      );
      expect(result.canSend, isTrue, reason: key);
      expect(result.warnings.map((w) => w.path), contains('data.$key'), reason: key);
    }
  });

  test('rejects target fields inside the template', () {
    final result = renderer.render(
      template: {'token': 'x', 'notification': notification},
      target: const TokenTarget('abc'),
    );
    expect(result.errors.single.path, 'token');
    expect(result.request, isNull);
    expect(result.canSend, isFalse);
  });

  test('rejects data that is not an object', () {
    final result = renderer.render(
      template: {'notification': notification, 'data': 'oops'},
      target: const TopicTarget('news'),
    );
    expect(result.errors.single.path, 'data');
  });

  test('includes target validation errors', () {
    final result = renderer.render(template: {'notification': notification}, target: const TokenTarget(''));
    expect(result.errors.single.message, 'Enter a device token.');
  });

  test('warns when a data-only message is not set up for background delivery', () {
    final result = renderer.render(
      template: {
        'data': {'a': 'b'},
      },
      target: const TopicTarget('news'),
    );
    expect(result.warnings.map((w) => w.path), containsAll(['android.priority', 'apns']));
  });

  test('a correctly set up background message has no delivery warnings', () {
    final result = renderer.render(
      template: {
        'data': {'a': 'b'},
        'android': {'priority': 'high'},
        'apns': {
          'headers': {'apns-priority': '5'},
          'payload': {
            'aps': {'content-available': 1},
          },
        },
      },
      target: const TopicTarget('news'),
    );
    expect(result.warnings, isEmpty);
  });

  test('warns when the payload is over 4096 bytes', () {
    final result = renderer.render(
      template: {
        'notification': notification,
        'data': {'big': 'x' * 5000},
      },
      target: const TopicTarget('news'),
    );
    expect(result.warnings.map((w) => w.path), contains('message'));
    expect(result.canSend, isTrue);
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/composer/`
Expected: FAIL, compilation errors.

- [ ] **Step 4: Implement**

`lib/features/composer/domain/render_issue.dart`:
```dart
import 'package:equatable/equatable.dart';

/// A note, warning or error about one part of the message.
class RenderIssue extends Equatable {
  const RenderIssue(this.path, this.message);

  /// Where the issue is, e.g. `data.order_id`, `target`, `android.priority`.
  final String path;
  final String message;

  @override
  List<Object?> get props => [path, message];
}
```

`lib/features/composer/domain/fcm_rules.dart`:
```dart
class ReservedKeyProblem {
  const ReservedKeyProblem(this.message, {required this.blocking});

  final String message;

  /// True when FCM rejects the key; false when it only might cause trouble.
  final bool blocking;
}

abstract final class FcmRules {
  static final RegExp topicPattern = RegExp(r'^[a-zA-Z0-9\-_.~%]+$');
  static const maxPayloadBytes = 4096;

  static ReservedKeyProblem? reservedDataKeyProblem(String key) {
    if (key == 'from' || key == 'message_type') {
      return ReservedKeyProblem('"$key" is reserved by FCM. Rename this key.', blocking: true);
    }
    for (final prefix in const ['google.', 'gcm.notification.']) {
      if (key.startsWith(prefix)) {
        return ReservedKeyProblem(
          'Keys starting with "$prefix" are reserved by FCM. Rename this key.',
          blocking: true,
        );
      }
    }
    if (key == 'notification' || key.startsWith('google') || key.startsWith('gcm')) {
      return ReservedKeyProblem(
        '"$key" may be treated as reserved by older FCM SDKs. Consider renaming it.',
        blocking: false,
      );
    }
    return null;
  }
}
```

`lib/features/composer/domain/target.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/composer/domain/fcm_rules.dart';
import 'package:fcm_studio/features/composer/domain/render_issue.dart';

enum TargetKind { token, topic, condition }

sealed class Target extends Equatable {
  const Target();

  factory Target.of(TargetKind kind, String value) => switch (kind) {
        TargetKind.token => TokenTarget(value),
        TargetKind.topic => TopicTarget(value),
        TargetKind.condition => ConditionTarget(value),
      };

  /// The FCM `message` fields that hold the target. Not allowed in templates.
  static const messageFields = {'token', 'topic', 'condition'};

  TargetKind get kind;

  Map<String, String> toMessageField();

  List<RenderIssue> validate();
}

final class TokenTarget extends Target {
  const TokenTarget(this.raw);

  final String raw;

  static final _whitespace = RegExp(r'\s+');
  static final _surroundingQuotes = RegExp(r'''^["']+|["']+$''');

  /// The token with whitespace, line breaks and surrounding quotes removed.
  String get token => raw.replaceAll(_whitespace, '').replaceAll(_surroundingQuotes, '');

  @override
  TargetKind get kind => TargetKind.token;

  @override
  Map<String, String> toMessageField() => {'token': token};

  @override
  List<RenderIssue> validate() =>
      token.isEmpty ? const [RenderIssue('target', 'Enter a device token.')] : const [];

  @override
  List<Object?> get props => [token];
}

final class TopicTarget extends Target {
  const TopicTarget(this.raw);

  final String raw;

  /// The topic name without a leading `/topics/`.
  String get name {
    final trimmed = raw.trim();
    return trimmed.startsWith('/topics/') ? trimmed.substring('/topics/'.length) : trimmed;
  }

  @override
  TargetKind get kind => TargetKind.topic;

  @override
  Map<String, String> toMessageField() => {'topic': name};

  @override
  List<RenderIssue> validate() {
    if (name.isEmpty) {
      return const [RenderIssue('target', 'Enter a topic name.')];
    }
    if (!FcmRules.topicPattern.hasMatch(name)) {
      return const [
        RenderIssue('target', 'Topic names may only contain letters, digits and - _ . ~ %.'),
      ];
    }
    return const [];
  }

  @override
  List<Object?> get props => [name];
}

final class ConditionTarget extends Target {
  const ConditionTarget(this.raw);

  final String raw;

  String get expression => raw.trim();

  @override
  TargetKind get kind => TargetKind.condition;

  @override
  Map<String, String> toMessageField() => {'condition': expression};

  @override
  List<RenderIssue> validate() => expression.isEmpty
      ? const [RenderIssue('target', "Enter a condition, e.g. 'news' in topics.")]
      : const [];

  @override
  List<Object?> get props => [expression];
}
```

`lib/features/composer/domain/message_renderer.dart`:
```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/composer/domain/fcm_rules.dart';
import 'package:fcm_studio/features/composer/domain/render_issue.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';

export 'package:fcm_studio/features/composer/domain/render_issue.dart';

class RenderResult extends Equatable {
  const RenderResult({
    this.request,
    this.notes = const [],
    this.warnings = const [],
    this.errors = const [],
  });

  /// The exact body for `messages:send`. Null when there are errors.
  final Map<String, Object?>? request;
  final List<RenderIssue> notes;
  final List<RenderIssue> warnings;
  final List<RenderIssue> errors;

  bool get canSend => request != null && errors.isEmpty;

  @override
  List<Object?> get props => [request, notes, warnings, errors];
}

/// Turns a template and a target into the request body FCM expects (spec §5.2).
class MessageRenderer {
  const MessageRenderer();

  RenderResult render({
    required Map<String, Object?> template,
    required Target target,
    bool validateOnly = false,
  }) {
    final notes = <RenderIssue>[];
    final warnings = <RenderIssue>[];
    final errors = <RenderIssue>[];

    for (final field in Target.messageFields) {
      if (template.containsKey(field)) {
        errors.add(RenderIssue(
          field,
          'Remove "$field" from the JSON and set the target in the Target field instead.',
        ));
      }
    }
    errors.addAll(target.validate());

    final body = jsonDecode(jsonEncode(template)) as Map<String, Object?>
      ..removeWhere((key, _) => Target.messageFields.contains(key));

    final data = body['data'];
    if (data != null) {
      if (data is Map<String, Object?>) {
        body['data'] = _stringifyData(data, notes, warnings, errors);
      } else {
        errors.add(const RenderIssue('data', '"data" must be an object of string values.'));
      }
    }
    if (!body.containsKey('notification') && body.containsKey('data')) {
      _checkBackgroundDelivery(body, warnings);
    }

    final message = <String, Object?>{...target.toMessageField(), ...body};
    final size = utf8.encode(jsonEncode(message)).length;
    if (size > FcmRules.maxPayloadBytes) {
      warnings.add(RenderIssue(
        'message',
        'The message is $size bytes. FCM may reject payloads over ${FcmRules.maxPayloadBytes} bytes.',
      ));
    }

    if (errors.isNotEmpty) {
      return RenderResult(notes: notes, warnings: warnings, errors: errors);
    }
    return RenderResult(
      request: {
        if (validateOnly) 'validate_only': true,
        'message': message,
      },
      notes: notes,
      warnings: warnings,
    );
  }

  static Map<String, String> _stringifyData(
    Map<String, Object?> data,
    List<RenderIssue> notes,
    List<RenderIssue> warnings,
    List<RenderIssue> errors,
  ) {
    final result = <String, String>{};
    data.forEach((key, value) {
      final path = 'data.$key';
      final problem = FcmRules.reservedDataKeyProblem(key);
      if (problem != null) {
        (problem.blocking ? errors : warnings).add(RenderIssue(path, problem.message));
      }
      switch (value) {
        case null:
          notes.add(RenderIssue(path, 'Removed because the value is null.'));
        case String():
          result[key] = value;
        case bool():
          result[key] = value.toString();
          notes.add(RenderIssue(path, 'Converted boolean to string "$value".'));
        case num():
          result[key] = value.toString();
          notes.add(RenderIssue(path, 'Converted number to string "$value".'));
        default:
          result[key] = jsonEncode(value);
          notes.add(RenderIssue(
            path,
            'Converted ${value is List<Object?> ? 'array' : 'object'} to a JSON string.',
          ));
      }
    });
    return result;
  }

  static void _checkBackgroundDelivery(Map<String, Object?> body, List<RenderIssue> warnings) {
    final android = body['android'];
    final priority = android is Map<String, Object?> ? android['priority'] : null;
    if (priority != 'high' && priority != 'HIGH') {
      warnings.add(const RenderIssue(
        'android.priority',
        'Data-only messages without "priority": "high" can be delayed while the phone is idle.',
      ));
    }

    final apns = body['apns'];
    final headers = apns is Map<String, Object?> ? apns['headers'] : null;
    final payload = apns is Map<String, Object?> ? apns['payload'] : null;
    final aps = payload is Map<String, Object?> ? payload['aps'] : null;
    final apnsPriority = headers is Map<String, Object?> ? headers['apns-priority'] : null;
    final contentAvailable = aps is Map<String, Object?> ? aps['content-available'] : null;
    if (apnsPriority != '5' || contentAvailable != 1) {
      warnings.add(const RenderIssue(
        'apns',
        'For iOS background delivery set apns.headers["apns-priority"] to "5" '
            'and apns.payload.aps["content-available"] to 1.',
      ));
    }
  }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/features/composer/`
Expected: PASS (6 + 11 tests).

- [ ] **Step 6: Checkpoint.** Run `dart format lib test`, `flutter analyze` (expect No issues found) and `git status --short`, and report. Do not stage or commit.

---

### Task 13: `ComposerCubit`

**Files:**
- Create: `lib/features/composer/cubit/composer_state.dart`, `lib/features/composer/cubit/composer_cubit.dart`
- Modify: `test/helpers/fake_token_provider.dart` (add `FakeResolver`)
- Test: `test/features/composer/composer_cubit_test.dart`

**Interfaces:**
- Consumes: `MessageRenderer`, `RenderResult`, `Target` and `TargetKind` (Task 12); `FcmClient`, `FcmSendResult`, `FcmSendFailure`, `FcmError` and `FcmTransportError` (Task 6); `FcmErrorExplainer`/`ErrorExplanation` (Task 7); `AccessTokenResolver` and `Project` (Task 10); `AuthException` (Task 5).
- Produces:
  - `enum SendStatus { idle, sending, done }`
  - `class ComposerState` with the fields `templateText`, `template`, `jsonError`, `targetKind`, `targetValue`, `render`, `sendStatus`, `lastResult` and `lastExplanation`, plus `bool get canSend`
  - `class ComposerCubit({required FcmClient fcmClient, required AccessTokenResolver auth, MessageRenderer renderer, FcmErrorExplainer explainer})` with `static const defaultTemplate`, `static (Map<String, Object?>?, String?) parseTemplate(String)`, `updateTemplateText(String)`, `setTargetKind(TargetKind)`, `setTargetValue(String)` and `Future<void> send(Project)`. `composer_cubit.dart` exports `composer_state.dart`.

- [ ] **Step 1: Add `FakeResolver`.** Add the imports at the top of `test/helpers/fake_token_provider.dart` and the class at the end:

```dart
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
```

```dart
class FakeResolver implements AccessTokenResolver {
  FakeResolver({this.error});

  final AuthException? error;

  @override
  Future<AccessTokenProvider> providerFor(Project project) async {
    final failure = error;
    if (failure != null) throw failure;
    return FakeTokenProvider();
  }
}
```

- [ ] **Step 2: Write the failing tests** `test/features/composer/composer_cubit_test.dart`

```dart
import 'dart:async';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fake_google.dart';
import '../../helpers/fake_token_provider.dart';
import '../../helpers/fcm_fixtures.dart';
import '../../helpers/project_fixture.dart';

void main() {
  const token = 'abc:APA91bxyz';

  ComposerCubit build({http.Client? client, FakeResolver? auth}) => ComposerCubit(
        fcmClient: FcmClient(httpClient: client ?? fakeGoogle()),
        auth: auth ?? FakeResolver(),
      );

  test('starts with the default template and asks for a token', () {
    final cubit = build();
    expect(cubit.state.template, isNotNull);
    expect(cubit.state.render.errors.single.message, 'Enter a device token.');
    expect(cubit.state.canSend, isFalse);
  });

  test('reports invalid JSON with its line number', () {
    final cubit = build()..updateTemplateText('{\n  "data": {},\n}');
    expect(cubit.state.template, isNull);
    expect(cubit.state.jsonError, contains('line 3'));
    expect(cubit.state.canSend, isFalse);
  });

  test('rejects a top-level value that is not an object', () {
    final cubit = build()..updateTemplateText('[]');
    expect(cubit.state.jsonError, contains('must be a JSON object'));
  });

  test('rejects empty text', () {
    final cubit = build()..updateTemplateText('   ');
    expect(cubit.state.jsonError, contains('empty'));
  });

  test('renders the request once a token is entered', () {
    final cubit = build()..setTargetValue(token);
    expect(cubit.state.canSend, isTrue);
    final message = cubit.state.render.request!['message']! as Map<String, Object?>;
    expect(message['token'], token);
  });

  test('switching to topic re-renders with the same value', () {
    final cubit = build()
      ..setTargetValue('/topics/news')
      ..setTargetKind(TargetKind.topic);
    final message = cubit.state.render.request!['message']! as Map<String, Object?>;
    expect(message['topic'], 'news');
  });

  test('sends and stores the result', () async {
    final cubit = build()..setTargetValue(token);
    await cubit.send(testProject);
    expect(cubit.state.sendStatus, SendStatus.done);
    expect(cubit.state.lastResult, isA<FcmSendSuccess>());
    expect(cubit.state.lastExplanation, isNull);
  });

  test('explains a failed send', () async {
    final cubit = build(client: fakeGoogle(fcmStatus: 404, fcmBody: unregisteredBody))
      ..setTargetValue(token);
    await cubit.send(testProject);
    expect(cubit.state.lastResult, isA<FcmSendFailure>());
    expect(cubit.state.lastExplanation?.title, 'Token is no longer valid');
  });

  test('explains a missing key instead of throwing', () async {
    final cubit = build(
      auth: FakeResolver(
        error: const AuthException(
          'The service account key for demo-project is not available in this session. '
          'Add the project again with the same key file.',
        ),
      ),
    )..setTargetValue(token);

    await cubit.send(testProject);

    expect(
      cubit.state.lastResult,
      isA<FcmSendFailure>().having((r) => r.error.transport, 'transport', FcmTransportError.auth),
    );
    expect(cubit.state.lastExplanation?.title, 'Could not get an access token');
    expect(cubit.state.lastExplanation?.explanation, contains('Add the project again'));
  });

  test('ignores Send while a send is in progress', () async {
    final gate = Completer<http.Response>();
    var requests = 0;
    final cubit = build(
      client: MockClient((_) {
        requests++;
        return gate.future;
      }),
    )..setTargetValue(token);

    final first = cubit.send(testProject);
    await Future<void>.delayed(Duration.zero);
    await cubit.send(testProject);
    gate.complete(http.Response(successBody, 200));
    await first;

    expect(requests, 1);
    expect(cubit.state.lastResult, isA<FcmSendSuccess>());
  });

  test('does not send when the message has errors', () async {
    var requests = 0;
    final cubit = build(
      client: MockClient((_) async {
        requests++;
        return http.Response(successBody, 200);
      }),
    );
    await cubit.send(testProject);
    expect(requests, 0);
    expect(cubit.state.sendStatus, SendStatus.idle);
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/features/composer/composer_cubit_test.dart`
Expected: FAIL, compilation error.

- [ ] **Step 4: Implement**

`lib/features/composer/cubit/composer_state.dart`:
```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/fcm/fcm_error_explainer.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';

enum SendStatus { idle, sending, done }

class ComposerState extends Equatable {
  const ComposerState({
    required this.templateText,
    this.template,
    this.jsonError,
    this.targetKind = TargetKind.token,
    this.targetValue = '',
    this.render = const RenderResult(),
    this.sendStatus = SendStatus.idle,
    this.lastResult,
    this.lastExplanation,
  });

  /// Exactly what is in the JSON editor.
  final String templateText;

  /// [templateText] parsed. Null while the JSON is invalid.
  final Map<String, Object?>? template;
  final String? jsonError;
  final TargetKind targetKind;
  final String targetValue;
  final RenderResult render;
  final SendStatus sendStatus;
  final FcmSendResult? lastResult;
  final ErrorExplanation? lastExplanation;

  bool get canSend => template != null && render.canSend && sendStatus != SendStatus.sending;

  static const Object _unset = Object();

  ComposerState copyWith({
    String? templateText,
    Object? template = _unset,
    Object? jsonError = _unset,
    TargetKind? targetKind,
    String? targetValue,
    RenderResult? render,
    SendStatus? sendStatus,
    Object? lastResult = _unset,
    Object? lastExplanation = _unset,
  }) {
    return ComposerState(
      templateText: templateText ?? this.templateText,
      template: identical(template, _unset) ? this.template : template as Map<String, Object?>?,
      jsonError: identical(jsonError, _unset) ? this.jsonError : jsonError as String?,
      targetKind: targetKind ?? this.targetKind,
      targetValue: targetValue ?? this.targetValue,
      render: render ?? this.render,
      sendStatus: sendStatus ?? this.sendStatus,
      lastResult: identical(lastResult, _unset) ? this.lastResult : lastResult as FcmSendResult?,
      lastExplanation: identical(lastExplanation, _unset)
          ? this.lastExplanation
          : lastExplanation as ErrorExplanation?,
    );
  }

  @override
  List<Object?> get props => [
        templateText,
        template,
        jsonError,
        targetKind,
        targetValue,
        render,
        sendStatus,
        lastResult,
        lastExplanation,
      ];
}
```

`lib/features/composer/cubit/composer_cubit.dart`:
```dart
import 'dart:convert';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/fcm/fcm_error.dart';
import 'package:fcm_studio/core/fcm/fcm_error_explainer.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/features/composer/cubit/composer_state.dart';
import 'package:fcm_studio/features/composer/domain/message_renderer.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/composer/cubit/composer_state.dart';

class ComposerCubit extends Cubit<ComposerState> {
  ComposerCubit({
    required FcmClient fcmClient,
    required AccessTokenResolver auth,
    MessageRenderer renderer = const MessageRenderer(),
    FcmErrorExplainer explainer = const FcmErrorExplainer(),
  })  : _fcm = fcmClient,
        _auth = auth,
        _renderer = renderer,
        _explainer = explainer,
        super(_rendered(_parsed(defaultTemplate), renderer));

  static const defaultTemplate = '''
{
  "notification": {
    "title": "Hello from FCM Studio",
    "body": "If you can read this, it works."
  },
  "data": {
    "source": "fcm_studio"
  }
}
''';

  final FcmClient _fcm;
  final AccessTokenResolver _auth;
  final MessageRenderer _renderer;
  final FcmErrorExplainer _explainer;

  void updateTemplateText(String text) {
    if (text == state.templateText) {
      return;
    }
    final (template, error) = parseTemplate(text);
    emit(_rendered(
      state.copyWith(templateText: text, template: template, jsonError: error),
      _renderer,
    ));
  }

  void setTargetKind(TargetKind kind) {
    if (kind == state.targetKind) {
      return;
    }
    emit(_rendered(state.copyWith(targetKind: kind), _renderer));
  }

  void setTargetValue(String value) {
    emit(_rendered(state.copyWith(targetValue: value), _renderer));
  }

  /// Sends the rendered request. Does nothing while a send is in progress.
  Future<void> send(Project project) async {
    if (!state.canSend) {
      return;
    }
    final request = state.render.request!;
    emit(state.copyWith(sendStatus: SendStatus.sending, lastResult: null, lastExplanation: null));

    FcmSendResult result;
    try {
      final auth = await _auth.providerFor(project);
      result = await _fcm.send(projectId: project.id, body: request, auth: auth);
    } on AuthException catch (e) {
      result = FcmSendFailure(
        error: FcmError(transport: FcmTransportError.auth, message: e.message),
        duration: Duration.zero,
      );
    }
    if (isClosed) {
      return;
    }
    emit(state.copyWith(
      sendStatus: SendStatus.done,
      lastResult: result,
      lastExplanation: switch (result) {
        FcmSendFailure(:final error) => _explainer.explain(error, projectId: project.id),
        FcmSendSuccess() => null,
      },
    ));
  }

  /// Parses editor text. Returns the template, or an error message with line and column.
  static (Map<String, Object?>?, String?) parseTemplate(String text) {
    if (text.trim().isEmpty) {
      return (null, 'The message JSON is empty. Start with {}.');
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, Object?>) {
        return (decoded, null);
      }
      return (null, 'The top level must be a JSON object ({ ... }).');
    } on FormatException catch (e) {
      return (null, _describeFormatError(e, text));
    }
  }

  static String _describeFormatError(FormatException e, String text) {
    final offset = e.offset;
    if (offset == null) {
      return 'Invalid JSON: ${e.message}';
    }
    final before = text.substring(0, offset.clamp(0, text.length));
    final line = '\n'.allMatches(before).length + 1;
    final column = before.length - (before.lastIndexOf('\n') + 1) + 1;
    return 'Invalid JSON at line $line, column $column: ${e.message}';
  }

  static ComposerState _parsed(String text) {
    final (template, error) = parseTemplate(text);
    return ComposerState(templateText: text, template: template, jsonError: error);
  }

  static ComposerState _rendered(ComposerState state, MessageRenderer renderer) {
    final template = state.template;
    if (template == null) {
      return state.copyWith(render: const RenderResult());
    }
    return state.copyWith(
      render: renderer.render(
        template: template,
        target: Target.of(state.targetKind, state.targetValue),
      ),
    );
  }
}
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/features/composer/`
Expected: PASS (all composer tests, including 11 new cubit tests).

- [ ] **Step 6: Run the whole suite**

Run: `flutter test`
Expected: all tests PASS.

- [ ] **Step 7: Checkpoint.** Run `dart format lib test`, `flutter analyze` (expect No issues found) and `git status --short`, and report. Do not stage or commit.

---

### Task 14: App wiring and project UI

**Files:**
- Create: `lib/app/dependencies.dart`, `lib/features/projects/view/project_switcher.dart`, `lib/features/projects/view/add_project_dialog.dart`, `lib/features/composer/view/composer_screen.dart` (temporary version; Task 15 replaces it)
- Modify: `lib/app/app.dart` (replace), `lib/main.dart` (replace)
- Create: `test/helpers/app_harness.dart`
- Test: `test/app/app_test.dart` (replace)

**Interfaces:**
- Consumes: everything from Tasks 3–13.
- Produces:
  - `class AppDependencies` (factory constructor `({required http.Client httpClient, required AppDatabase database, required SecretStore secrets, Clock clock})` and `static Future<AppDependencies> create()`) with the fields `httpClient`, `database`, `projectsRepository`, `authRegistry`, `firebaseProjectsApi` and `fcmClient`
  - `FcmStudioApp({required AppDependencies dependencies})`
  - `ProjectSwitcher`, `EnvironmentChip({required ProjectEnvironment environment})` and `showAddProjectDialog(BuildContext)`
  - `ComposerScreen` (temporary)
  - Test helpers in `test/helpers/app_harness.dart`: `buildTestDependencies(WidgetTester, {http.Client? client})`, `pumpApp(WidgetTester, AppDependencies)` and `readCubit<T>(WidgetTester)`

- [ ] **Step 1: Write the widget-test harness** `test/helpers/app_harness.dart`

```dart
import 'package:fcm_studio/app/app.dart';
import 'package:fcm_studio/app/dependencies.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/features/projects/view/project_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'fake_google.dart';

/// Real async work (sembast, RSA signing, MockClient) runs inside `tester.runAsync`.
Future<AppDependencies> buildTestDependencies(WidgetTester tester, {http.Client? client}) async {
  final database = await tester.runAsync(AppDatabase.inMemory);
  return AppDependencies(
    httpClient: client ?? fakeGoogle(),
    database: database!,
    secrets: MemorySecretStore(),
  );
}

Future<void> pumpApp(WidgetTester tester, AppDependencies dependencies) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(FcmStudioApp(dependencies: dependencies));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Reads a cubit from the widget tree (through the always-present ProjectSwitcher).
T readCubit<T extends Cubit<Object?>>(WidgetTester tester) =>
    BlocProvider.of<T>(tester.element(find.byType(ProjectSwitcher)));
```

- [ ] **Step 2: Replace the smoke test with the failing app tests** in `test/app/app_test.dart`

```dart
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/app_harness.dart';
import '../helpers/service_account_fixture.dart';

void main() {
  testWidgets('shows the empty state and opens the add-project dialog', (tester) async {
    await pumpApp(tester, await buildTestDependencies(tester));

    expect(find.text('No projects yet. Add one with a service account key.'), findsOneWidget);
    await tester.tap(find.text('Add project'));
    await tester.pumpAndSettle();
    expect(find.text('Choose key file…'), findsOneWidget);
  });

  testWidgets('shows an added project and its environment', (tester) async {
    await pumpApp(tester, await buildTestDependencies(tester));
    final projects = readCubit<ProjectsCubit>(tester);

    await tester.runAsync(
      () => projects.addFromServiceAccount(serviceAccountJson(), persistKey: true),
    );
    await tester.pump();
    expect(find.text('Demo Project (demo-project)'), findsOneWidget);
    expect(find.text('DEV'), findsOneWidget);

    await tester.runAsync(() => projects.setEnvironment(testProjectId, ProjectEnvironment.prod));
    await tester.pump();
    expect(find.text('PROD'), findsOneWidget);
  });
}
```

- [ ] **Step 3: Run them to see them fail**

Run: `flutter test test/app/app_test.dart`
Expected: FAIL, compilation errors (`dependencies.dart` and `project_switcher.dart` don't exist).

- [ ] **Step 4: Write `lib/app/dependencies.dart`**

```dart
import 'package:fcm_studio/core/fcm/fcm_client.dart';
import 'package:fcm_studio/core/firebase/firebase_projects_api.dart';
import 'package:fcm_studio/core/storage/app_database.dart';
import 'package:fcm_studio/core/storage/secret_store.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/features/projects/data/project_auth_registry.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Every long-lived service, created once at startup.
class AppDependencies {
  factory AppDependencies({
    required http.Client httpClient,
    required AppDatabase database,
    required SecretStore secrets,
    Clock clock = const SystemClock(),
  }) {
    final repository = ProjectsRepository(database: database, secrets: secrets);
    return AppDependencies._(
      httpClient: httpClient,
      database: database,
      projectsRepository: repository,
      authRegistry: ProjectAuthRegistry(
        repository: repository,
        httpClient: httpClient,
        clock: clock,
      ),
      firebaseProjectsApi: FirebaseProjectsApi(httpClient: httpClient),
      fcmClient: FcmClient(httpClient: httpClient),
    );
  }

  AppDependencies._({
    required this.httpClient,
    required this.database,
    required this.projectsRepository,
    required this.authRegistry,
    required this.firebaseProjectsApi,
    required this.fcmClient,
  });

  static Future<AppDependencies> create() async => AppDependencies(
        httpClient: http.Client(),
        database: await AppDatabase.open(),
        // On web, keys stay in memory unless the user ticks "Remember on this browser".
        secrets: LayeredSecretStore(persistent: FlutterSecureSecretStore(), alwaysPersist: !kIsWeb),
      );

  final http.Client httpClient;
  final AppDatabase database;
  final ProjectsRepository projectsRepository;
  final ProjectAuthRegistry authRegistry;
  final FirebaseProjectsApi firebaseProjectsApi;
  final FcmClient fcmClient;
}
```

- [ ] **Step 5: Replace `lib/app/app.dart` and `lib/main.dart`**

`lib/app/app.dart`:
```dart
import 'package:fcm_studio/app/dependencies.dart';
import 'package:fcm_studio/app/theme.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/view/composer_screen.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class FcmStudioApp extends StatelessWidget {
  const FcmStudioApp({required this.dependencies, super.key});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(
          create: (_) => ProjectsCubit(
            repository: dependencies.projectsRepository,
            authRegistry: dependencies.authRegistry,
            firebaseApi: dependencies.firebaseProjectsApi,
          )..load(),
        ),
        BlocProvider(
          create: (_) => ComposerCubit(
            fcmClient: dependencies.fcmClient,
            auth: dependencies.authRegistry,
          ),
        ),
      ],
      child: MaterialApp(
        title: 'FCM Studio',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        home: const ComposerScreen(),
      ),
    );
  }
}
```

`lib/main.dart`:
```dart
import 'package:fcm_studio/app/app.dart';
import 'package:fcm_studio/app/dependencies.dart';
import 'package:flutter/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppDependencies.create();
  runApp(FcmStudioApp(dependencies: dependencies));
}
```

- [ ] **Step 6: Write the project views**

`lib/features/projects/view/project_switcher.dart`:
```dart
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:fcm_studio/features/projects/view/add_project_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ProjectSwitcher extends StatelessWidget {
  const ProjectSwitcher({super.key});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return BlocBuilder<ProjectsCubit, ProjectsState>(
      builder: (context, state) {
        final selected = state.selected;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Project', style: textTheme.titleSmall),
            const SizedBox(height: 8),
            if (state.status != ProjectsStatus.ready)
              const Text('Loading projects…')
            else if (selected == null)
              const Text('No projects yet. Add one with a service account key.')
            else
              Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      key: const Key('project-dropdown'),
                      isExpanded: true,
                      value: selected.id,
                      items: [
                        for (final project in state.projects)
                          DropdownMenuItem(
                            value: project.id,
                            child: Text(project.label, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (id) {
                        if (id != null) context.read<ProjectsCubit>().select(id);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  EnvironmentChip(environment: selected.environment),
                  _ProjectMenu(project: selected),
                ],
              ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () => showAddProjectDialog(context),
              icon: const Icon(Icons.add),
              label: const Text('Add project'),
            ),
          ],
        );
      },
    );
  }
}

class EnvironmentChip extends StatelessWidget {
  const EnvironmentChip({required this.environment, super.key});

  final ProjectEnvironment environment;

  static Color colorOf(ProjectEnvironment environment) => switch (environment) {
        ProjectEnvironment.dev => Colors.green,
        ProjectEnvironment.staging => Colors.amber,
        ProjectEnvironment.prod => Colors.red,
      };

  @override
  Widget build(BuildContext context) {
    final color = colorOf(environment);
    return Chip(
      label: Text(environment.name.toUpperCase()),
      visualDensity: VisualDensity.compact,
      side: BorderSide(color: color),
      backgroundColor: color.withValues(alpha: 0.12),
    );
  }
}

enum _MenuAction { dev, staging, prod, projectNumber, remove }

class _ProjectMenu extends StatelessWidget {
  const _ProjectMenu({required this.project});

  final Project project;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_MenuAction>(
      key: const Key('project-menu'),
      tooltip: 'Project options',
      onSelected: (action) => _onSelected(context, action),
      itemBuilder: (context) => [
        for (final environment in ProjectEnvironment.values)
          CheckedPopupMenuItem(
            value: _MenuAction.values.byName(environment.name),
            checked: project.environment == environment,
            child: Text('Environment: ${environment.name}'),
          ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: _MenuAction.projectNumber,
          child: Text(
            project.projectNumber == null
                ? 'Set project number…'
                : 'Project number: ${project.projectNumber}',
          ),
        ),
        const PopupMenuItem(value: _MenuAction.remove, child: Text('Remove project…')),
      ],
    );
  }

  Future<void> _onSelected(BuildContext context, _MenuAction action) async {
    final cubit = context.read<ProjectsCubit>();
    switch (action) {
      case _MenuAction.dev || _MenuAction.staging || _MenuAction.prod:
        await cubit.setEnvironment(project.id, ProjectEnvironment.values.byName(action.name));
      case _MenuAction.projectNumber:
        final number = await showDialog<String>(
          context: context,
          builder: (_) => _ProjectNumberDialog(initial: project.projectNumber ?? ''),
        );
        if (number != null) {
          await cubit.setProjectNumber(project.id, number);
        }
      case _MenuAction.remove:
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('Remove ${project.id}?'),
            content: const Text(
              'The project and its stored key are removed from FCM Studio. '
              'Nothing changes in Firebase.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        if (confirmed ?? false) {
          await cubit.remove(project.id);
        }
    }
  }
}

class _ProjectNumberDialog extends StatefulWidget {
  const _ProjectNumberDialog({required this.initial});

  final String initial;

  @override
  State<_ProjectNumberDialog> createState() => _ProjectNumberDialogState();
}

class _ProjectNumberDialogState extends State<_ProjectNumberDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Project number'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          helperText: 'Firebase console → Project settings → General → Project number. '
              'Leave empty to clear.',
          helperMaxLines: 2,
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, _controller.text),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
```

`lib/features/projects/view/add_project_dialog.dart`:
```dart
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> showAddProjectDialog(BuildContext context) {
  final cubit = context.read<ProjectsCubit>();
  return showDialog<void>(
    context: context,
    builder: (_) => BlocProvider.value(value: cubit, child: const AddProjectDialog()),
  );
}

class AddProjectDialog extends StatefulWidget {
  const AddProjectDialog({super.key});

  @override
  State<AddProjectDialog> createState() => _AddProjectDialogState();
}

class _AddProjectDialogState extends State<AddProjectDialog> {
  bool _remember = false;
  bool _busy = false;
  String? _error;
  String? _info;

  Future<void> _chooseFile() async {
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Service account key',
          extensions: ['json'],
          mimeTypes: ['application/json'],
          uniformTypeIdentifiers: ['public.json'],
        ),
      ],
    );
    if (file == null || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final text = await file.readAsString();
    if (!mounted) {
      return;
    }
    final result = await context
        .read<ProjectsCubit>()
        .addFromServiceAccount(text, persistKey: !kIsWeb || _remember);
    if (!mounted) {
      return;
    }
    switch (result) {
      case AddProjectSuccess(:final project, needsProjectNumber: true):
        setState(() {
          _busy = false;
          _info = 'Added ${project.id}. This key cannot read the project number, so set it '
              'later from the project menu (optional; used to check device tokens).';
        });
      case AddProjectSuccess():
        Navigator.of(context).pop();
      case AddProjectFailure(:final message):
        setState(() {
          _busy = false;
          _error = message;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final error = _error;
    final info = _info;
    return AlertDialog(
      title: const Text('Add project'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose a service account key file (.json). Get one in Firebase console → '
              'Project settings → Service accounts → Generate new private key.',
            ),
            const SizedBox(height: 12),
            Text(
              'Tip: create a separate service account that only has the '
              '"Firebase Cloud Messaging API Admin" role, and use its key here.',
              style: theme.textTheme.bodySmall,
            ),
            if (kIsWeb) ...[
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _remember,
                onChanged: _busy ? null : (value) => setState(() => _remember = value ?? false),
                title: const Text('Remember on this browser'),
                subtitle: const Text(
                  'Otherwise the key is kept only until this tab is closed or reloaded. '
                  'Browser storage can be read by scripts on this site.',
                ),
              ),
            ],
            if (_busy) ...[const SizedBox(height: 16), const LinearProgressIndicator()],
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (info != null) ...[const SizedBox(height: 16), Text(info)],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: Text(info == null ? 'Cancel' : 'Done'),
        ),
        FilledButton(
          onPressed: _busy ? null : _chooseFile,
          child: const Text('Choose key file…'),
        ),
      ],
    );
  }
}
```

`lib/features/composer/view/composer_screen.dart` (temporary; Task 15 replaces it):
```dart
import 'package:fcm_studio/features/projects/view/project_switcher.dart';
import 'package:flutter/material.dart';

class ComposerScreen extends StatelessWidget {
  const ComposerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('FCM Studio')),
      body: ListView(padding: const EdgeInsets.all(16), children: const [ProjectSwitcher()]),
    );
  }
}
```

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `flutter test test/app/app_test.dart`
Expected: PASS (2 tests). If a test hangs, some database or HTTP work is running in the fake-async zone. Wrap that call in `tester.runAsync(...)` and add a `tester.pump()` afterwards.

- [ ] **Step 8: Checkpoint.** Run `dart format lib test`, `flutter analyze` (expect No issues found), `flutter test` (all pass) and `git status --short`, and report. Do not stage or commit.

---

### Task 15: Composer screen, plus the M0 web check and the M1 end-to-end check

**Files:**
- Create: `lib/features/composer/view/json_template_editor.dart`, `lib/features/composer/view/target_picker.dart`, `lib/features/composer/view/preview_panel.dart`, `lib/features/composer/view/send_panel.dart`
- Modify: `lib/features/composer/view/composer_screen.dart` (replace)
- Test: `test/features/composer/composer_screen_test.dart`
- Modify after the manual checks: `docs/superpowers/specs/2026-10-03-fcm-studio-design.md` (§5.4 and §13)

**Interfaces:**
- Consumes: `ComposerCubit`/`ComposerState`/`SendStatus` (Task 13); `ProjectsCubit` and `ProjectSwitcher` (Tasks 11, 14); `RenderIssue` (Task 12); `FcmSendResult`, `FcmSendSuccess` and `FcmSendFailure` (Task 6); `ErrorExplanation` (Task 7); and the test helpers `buildTestDependencies`, `pumpApp` and `readCubit` from `test/helpers/app_harness.dart` (Task 14).
- Produces: `ComposerScreen`, `JsonTemplateEditor`, `TargetPicker`, `PreviewPanel`, `SendPanel` (with `static const sendButtonKey`), `ResultView` and `void sendSelected(BuildContext)`.

- [ ] **Step 1: Write the failing widget tests** `test/features/composer/composer_screen_test.dart`

```dart
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/view/send_panel.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_google.dart';
import '../../helpers/fcm_fixtures.dart';
import '../../helpers/service_account_fixture.dart';

void main() {
  const token = 'abc:APA91bxyz';

  Future<(ProjectsCubit, ComposerCubit)> setUpApp(WidgetTester tester, {int fcmStatus = 200, String fcmBody = successBody}) async {
    final dependencies = await buildTestDependencies(
      tester,
      client: fakeGoogle(fcmStatus: fcmStatus, fcmBody: fcmBody),
    );
    await pumpApp(tester, dependencies);
    final projects = readCubit<ProjectsCubit>(tester);
    await tester.runAsync(() => projects.addFromServiceAccount(serviceAccountJson(), persistKey: true));
    await tester.pump();
    return (projects, readCubit<ComposerCubit>(tester));
  }

  ButtonStyleButton sendButton(WidgetTester tester) =>
      tester.widget<ButtonStyleButton>(find.byKey(SendPanel.sendButtonKey));

  testWidgets('invalid JSON shows the error and disables Send', (tester) async {
    final (_, composer) = await setUpApp(tester);
    composer
      ..setTargetValue(token)
      ..updateTemplateText('{"notification": ');
    await tester.pump();

    expect(find.textContaining('Invalid JSON'), findsOneWidget);
    expect(sendButton(tester).onPressed, isNull);
  });

  testWidgets('Send is enabled once the message is valid and a token is set', (tester) async {
    final (_, composer) = await setUpApp(tester);
    expect(sendButton(tester).onPressed, isNull);

    composer.setTargetValue(token);
    await tester.pump();

    expect(sendButton(tester).onPressed, isNotNull);
    expect(find.textContaining('"token": "abc:APA91bxyz"'), findsOneWidget);
  });

  testWidgets('a successful send shows the message name', (tester) async {
    final (projects, composer) = await setUpApp(tester);
    composer.setTargetValue(token);
    await tester.runAsync(() => composer.send(projects.state.selected!));
    await tester.pump();

    expect(find.text('Sent'), findsOneWidget);
    expect(find.textContaining('projects/demo-project/messages/0:1'), findsOneWidget);
  });

  testWidgets('a failed send shows the explanation', (tester) async {
    final (projects, composer) = await setUpApp(tester, fcmStatus: 404, fcmBody: unregisteredBody);
    composer.setTargetValue(token);
    await tester.runAsync(() => composer.send(projects.state.selected!));
    await tester.pump();

    expect(find.text('Token is no longer valid'), findsOneWidget);
    expect(find.text('Raw response (HTTP 404)'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run them to see them fail**

Run: `flutter test test/features/composer/composer_screen_test.dart`
Expected: FAIL, compilation error (`send_panel.dart` doesn't exist).

- [ ] **Step 3: Write the composer views**

`lib/features/composer/view/send_panel.dart`:
```dart
import 'package:fcm_studio/core/fcm/fcm_error_explainer.dart';
import 'package:fcm_studio/core/fcm/fcm_send_result.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

/// Sends the composer's message to the selected project, if there is one.
void sendSelected(BuildContext context) {
  final project = context.read<ProjectsCubit>().state.selected;
  if (project == null) {
    return;
  }
  context.read<ComposerCubit>().send(project);
}

class SendPanel extends StatelessWidget {
  const SendPanel({super.key});

  static const sendButtonKey = Key('send-button');

  @override
  Widget build(BuildContext context) {
    final hasProject = context.select((ProjectsCubit cubit) => cubit.state.selected != null);
    return BlocBuilder<ComposerCubit, ComposerState>(
      builder: (context, state) {
        final sending = state.sendStatus == SendStatus.sending;
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Tooltip(
                message: hasProject ? 'Cmd/Ctrl + Enter' : 'Add a project first',
                child: FilledButton.icon(
                  key: sendButtonKey,
                  onPressed: hasProject && state.canSend ? () => sendSelected(context) : null,
                  icon: sending
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  label: Text(sending ? 'Sending…' : 'Send'),
                ),
              ),
              if (state.lastResult case final result?) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 320),
                  child: SingleChildScrollView(
                    child: ResultView(result: result, explanation: state.lastExplanation),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class ResultView extends StatelessWidget {
  const ResultView({required this.result, this.explanation, super.key});

  final FcmSendResult result;
  final ErrorExplanation? explanation;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final milliseconds = result.duration.inMilliseconds;
    switch (result) {
      case FcmSendSuccess(:final messageName):
        return ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.check_circle, color: Colors.green),
          title: const Text('Sent'),
          subtitle: SelectableText('$messageName · $milliseconds ms'),
        );
      case FcmSendFailure(:final error):
        final e = explanation;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error, color: theme.colorScheme.error),
                const SizedBox(width: 8),
                Expanded(child: Text(e?.title ?? 'Send failed', style: theme.textTheme.titleSmall)),
              ],
            ),
            if (e != null) ...[
              const SizedBox(height: 8),
              SelectableText(e.explanation),
              const SizedBox(height: 8),
              Text(e.action, style: const TextStyle(fontWeight: FontWeight.w600)),
            ],
            if (e?.link case final link?)
              TextButton.icon(
                onPressed: () => launchUrl(link),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: const Text('Open in console'),
              ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                'Raw response${result.httpStatus == null ? '' : ' (HTTP ${result.httpStatus})'}',
              ),
              children: [
                SelectableText(
                  result.responseBody ?? error.message ?? 'No response body.',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ],
        );
    }
  }
}
```

`lib/features/composer/view/preview_panel.dart`:
```dart
import 'dart:convert';

import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/render_issue.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class PreviewPanel extends StatelessWidget {
  const PreviewPanel({super.key});

  static const _encoder = JsonEncoder.withIndent('  ');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BlocBuilder<ComposerCubit, ComposerState>(
      buildWhen: (previous, current) =>
          previous.render != current.render || previous.jsonError != current.jsonError,
      builder: (context, state) {
        final request = state.render.request;
        final requestText = request == null ? null : _encoder.convert(request);
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                Expanded(child: Text('Request preview', style: theme.textTheme.titleSmall)),
                IconButton(
                  tooltip: 'Copy request body',
                  icon: const Icon(Icons.copy, size: 18),
                  onPressed: requestText == null
                      ? null
                      : () => Clipboard.setData(ClipboardData(text: requestText)),
                ),
              ],
            ),
            if (state.jsonError != null)
              _IssueRow(
                icon: Icons.error_outline,
                color: theme.colorScheme.error,
                text: 'Fix the JSON first.',
              ),
            for (final issue in state.render.errors)
              _IssueRow(icon: Icons.error_outline, color: theme.colorScheme.error, text: _format(issue)),
            for (final issue in state.render.warnings)
              _IssueRow(icon: Icons.warning_amber, color: Colors.amber.shade800, text: _format(issue)),
            for (final issue in state.render.notes)
              _IssueRow(icon: Icons.info_outline, color: theme.colorScheme.outline, text: _format(issue)),
            const SizedBox(height: 8),
            if (requestText != null)
              SelectableText(
                requestText,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
          ],
        );
      },
    );
  }

  static String _format(RenderIssue issue) => '${issue.path}: ${issue.message}';
}

class _IssueRow extends StatelessWidget {
  const _IssueRow({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
```

`lib/features/composer/view/target_picker.dart`:
```dart
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TargetPicker extends StatefulWidget {
  const TargetPicker({super.key});

  @override
  State<TargetPicker> createState() => _TargetPickerState();
}

class _TargetPickerState extends State<TargetPicker> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: context.read<ComposerCubit>().state.targetValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final kind = context.select((ComposerCubit cubit) => cubit.state.targetKind);
    final cubit = context.read<ComposerCubit>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Target', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        SegmentedButton<TargetKind>(
          segments: const [
            ButtonSegment(value: TargetKind.token, label: Text('Token')),
            ButtonSegment(value: TargetKind.topic, label: Text('Topic')),
            ButtonSegment(value: TargetKind.condition, label: Text('Condition')),
          ],
          selected: {kind},
          onSelectionChanged: (selection) => cubit.setTargetKind(selection.first),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('target-field'),
          controller: _controller,
          minLines: 1,
          maxLines: kind == TargetKind.token ? 4 : 2,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            labelText: switch (kind) {
              TargetKind.token => 'Device token',
              TargetKind.topic => 'Topic name',
              TargetKind.condition => 'Condition',
            },
            hintText: switch (kind) {
              TargetKind.token => 'Paste the FCM registration token',
              TargetKind.topic => 'e.g. news (without /topics/)',
              TargetKind.condition => "e.g. 'news' in topics && 'sports' in topics",
            },
          ),
          onChanged: cubit.setTargetValue,
        ),
      ],
    );
  }
}
```

`lib/features/composer/view/json_template_editor.dart`:
```dart
import 'dart:async';

import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/json.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

/// The JSON editor for the message template. Edits reach the cubit after a 300 ms pause.
class JsonTemplateEditor extends StatefulWidget {
  const JsonTemplateEditor({super.key});

  static const debounce = Duration(milliseconds: 300);

  @override
  State<JsonTemplateEditor> createState() => _JsonTemplateEditorState();
}

class _JsonTemplateEditorState extends State<JsonTemplateEditor> {
  late final CodeLineEditingController _controller;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _controller = CodeLineEditingController.fromText(
      context.read<ComposerCubit>().state.templateText,
    );
    _controller.addListener(_onChanged);
  }

  void _onChanged() {
    _debounce?.cancel();
    _debounce = Timer(JsonTemplateEditor.debounce, () {
      if (mounted) {
        context.read<ComposerCubit>().updateTemplateText(_controller.text);
      }
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller
      ..removeListener(_onChanged)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            'Message JSON (the FCM "message" object, without the target)',
            style: theme.textTheme.titleSmall,
          ),
        ),
        Expanded(
          child: CodeEditor(
            controller: _controller,
            style: CodeEditorStyle(
              fontSize: 13,
              codeTheme: CodeHighlightTheme(
                languages: {'json': CodeHighlightThemeMode(mode: langJson)},
                theme: dark ? atomOneDarkTheme : atomOneLightTheme,
              ),
            ),
          ),
        ),
        BlocSelector<ComposerCubit, ComposerState, String?>(
          selector: (state) => state.jsonError,
          builder: (context, error) => error == null
              ? const SizedBox.shrink()
              : Container(
                  width: double.infinity,
                  color: theme.colorScheme.errorContainer,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(error, style: TextStyle(color: theme.colorScheme.onErrorContainer)),
                ),
        ),
      ],
    );
  }
}
```

`lib/features/composer/view/composer_screen.dart` (replace the temporary version):
```dart
import 'package:fcm_studio/features/composer/view/json_template_editor.dart';
import 'package:fcm_studio/features/composer/view/preview_panel.dart';
import 'package:fcm_studio/features/composer/view/send_panel.dart';
import 'package:fcm_studio/features/composer/view/target_picker.dart';
import 'package:fcm_studio/features/projects/view/project_switcher.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ComposerScreen extends StatelessWidget {
  const ComposerScreen({super.key});

  static const wideLayoutMinWidth = 1000.0;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter, meta: true): () => sendSelected(context),
        const SingleActivator(LogicalKeyboardKey.enter, control: true): () => sendSelected(context),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          appBar: AppBar(title: const Text('FCM Studio')),
          body: LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth >= wideLayoutMinWidth) {
                return const Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(width: 320, child: _SetupPane()),
                    VerticalDivider(width: 1),
                    Expanded(child: JsonTemplateEditor()),
                    VerticalDivider(width: 1),
                    SizedBox(width: 420, child: _OutputPane()),
                  ],
                );
              }
              return const DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    TabBar(
                      tabs: [Tab(text: 'Setup'), Tab(text: 'JSON'), Tab(text: 'Preview & result')],
                    ),
                    Expanded(
                      child: TabBarView(
                        children: [_SetupPane(), JsonTemplateEditor(), _OutputPane()],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SetupPane extends StatelessWidget {
  const _SetupPane();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const [ProjectSwitcher(), SizedBox(height: 24), TargetPicker()],
    );
  }
}

class _OutputPane extends StatelessWidget {
  const _OutputPane();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [Expanded(child: PreviewPanel()), Divider(height: 1), SendPanel()],
    );
  }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/features/composer/composer_screen_test.dart test/app/app_test.dart`
Expected: PASS (4 + 2 tests).
- If the `re_editor`/`re_highlight` imports or constructor arguments differ in the installed versions, check the package examples (`~/.pub-cache/hosted/pub.dev/re_editor-*/example`). Keep the same behaviour: JSON highlighting, a light/dark theme, and the controller text sent to `updateTemplateText`.
- If `app_test.dart`'s `pumpAndSettle()` now times out because of an editor animation, replace it with `await tester.pump(const Duration(milliseconds: 500));`.

- [ ] **Step 5: Run the whole suite and the analyzer**

Run: `flutter test` and then `flutter analyze`
Expected: all tests PASS; `No issues found!`.

- [ ] **Step 6: macOS manual check (M1 done criterion).** This needs a real service account key (Task 5 Step 6) and a device token for the Redmi. Get the token from Task 2's debug app (the user reads it with `run-as`), from the app's backend, or from logcat if the app prints it. Run `flutter run -d macos` and check:
  1. "Add project", then choose the key. The project shows its name and a `DEV` chip, and the dialog closes, or shows the project-number note if the key can't read it.
  2. Paste the token, then Send. **The notification appears on the Redmi**, and the result shows "Sent · projects/…/messages/… · N ms".
  3. Cmd+Enter sends while the focus is in the target field and while it is in the JSON editor. If the editor swallows Cmd+Enter, note it in the spec under §5.5 as a known issue for M2.
  4. Change one character of the token, then Send. The result explains the error (`INVALID_ARGUMENT` or `UNREGISTERED`) and shows the raw response.
  5. Quit and relaunch. The project is still there and Send works without adding it again (Keychain persistence). If macOS asks to allow Keychain access, choose "Always Allow".
  6. Set the environment to `prod` from the project menu. The chip shows `PROD`, and it persists after a relaunch.

- [ ] **Step 7: Web manual check (M0 `re_editor` check).** Run `flutter run -d chrome --web-port 5050`.
  1. In the JSON editor: typing, selection, copy/paste (Cmd+C/V), undo (Cmd+Z), and scrolling a 200-line JSON all work.
  2. Add a project **without** "Remember", then send to a topic, e.g. `fcm_studio_test`. This should succeed, because FCM accepts topics nobody has subscribed to.
  3. Reload the page, then Send. The result says "Could not get an access token…Add the project again with the same key file".
  4. Add the project again **with** "Remember", reload, and Send. It works.

  **If check 1 fails** (`re_editor` unusable on web), add this fallback in `json_template_editor.dart`, then re-run check 1. Add `import 'package:flutter/foundation.dart';` and a `TextEditingController` for web:
  ```dart
  // In _JsonTemplateEditorState:
  late final TextEditingController _plain = TextEditingController(
    text: context.read<ComposerCubit>().state.templateText,
  );
  // In dispose(): _plain.dispose();
  // In build(), replace the Expanded(CodeEditor(...)) child with:
  Expanded(
    child: kIsWeb
        ? TextField(
            controller: _plain,
            expands: true,
            maxLines: null,
            minLines: null,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            decoration: const InputDecoration(contentPadding: EdgeInsets.all(12)),
            onChanged: (text) {
              _debounce?.cancel();
              _debounce = Timer(JsonTemplateEditor.debounce, () {
                if (mounted) context.read<ComposerCubit>().updateTemplateText(text);
              });
            },
          )
        : CodeEditor(/* unchanged */),
  ),
  ```

- [ ] **Step 8: Record the results in the spec.**
  - §5.4: replace "This is checked in milestone 0." with the outcome: "Checked <date>: `re_editor` works on web." or "Checked <date>: `re_editor` failed on web (<what failed>); the web build uses the TextField fallback."
  - §13: add one line under the table: `M0/M1 status (<date>): <which checks passed, which are pending>`.

- [ ] **Step 9: Checkpoint.** Run `dart format lib test`, `flutter analyze` (expect No issues found), `flutter test` (all pass) and `git status --short`, and report. Summarise the manual results for the user. Do not stage or commit.
