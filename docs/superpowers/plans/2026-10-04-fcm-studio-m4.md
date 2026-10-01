# FCM Studio M4 (Google sign-in) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A teammate can add Firebase projects by signing in with their Google account, with no service account key file, and send pushes with it on macOS, Windows and the web.

**Architecture:**
- A platform-split `GoogleAuthFlow` does the sign-in:
  - Desktop opens the system browser and catches Google's redirect on a one-off `127.0.0.1` server (PKCE).
  - The web uses Google's popup through `googleapis_auth`.
- A shared `GoogleAccountTokenProvider` caches access tokens. It refreshes them with the stored refresh token on desktop, or asks Google again (a popup) on the web. Every API call carries `x-goog-user-project: <projectId>`.
- `ProjectAuthRegistry` and `ProjectsCubit` gain the Google paths: sign in, list the account's Firebase projects, add the ticked ones, and sign in again.
- The OAuth client IDs come from a git-ignored `config/oauth.json` asset.

**Tech Stack:** Flutter 3.44 / Dart 3.12, flutter_bloc, Equatable, sembast, flutter_secure_storage, http, `crypto` (PKCE), `googleapis_auth` 2.3.4 (web popup only), url_launcher.

**Spec:** docs/superpowers/specs/2026-10-03-fcm-studio-design.md. Mainly:
- §4.1 Access tokens, §4.2 Projects, §4.4 OAuth client configuration;
- §3.2 project structure;
- §10 storage;
- §11 error handling;
- §13 (M4 row, and the M0 check moved to M4).

## Decisions

These are made here, where the spec is silent or a fact found while planning forces a change. Task 11 records them in the spec.

1. **The desktop sign-in is hand-written**, not `googleapis_auth`'s `obtainAccessCredentialsViaUserConsent`.
   - Why: that function waits for the browser forever, with no cancel and no timeout, and leaves its port open if the user closes the tab. Its errors also hide Google's `invalid_grant`.
   - What we build:
     - a `dart:io` `HttpServer` on `127.0.0.1` (port 0);
     - PKCE S256, using `crypto`;
     - a `state` check;
     - `prompt=select_account consent`, so a refresh token comes back every time;
     - a 5-minute timeout and a Cancel;
     - the token-endpoint POSTs.
   - `googleapis_auth` is used only for the web popup (`requestAccessCredentials`).
2. **Two extra scopes**, `openid` and `https://www.googleapis.com/auth/userinfo.email`. They let the app read the account's email from `https://openidconnect.googleapis.com/v1/userinfo` on both platforms; the web popup returns no ID token. The spec's two Firebase scopes stay.
3. **Granted scopes are checked after every sign-in.** Google lets the user untick a scope. Without both Firebase scopes the sign-in is refused, and nothing is saved.
4. **`config/` is a Flutter asset directory.**
   - `config/oauth.example.json` is committed, so the directory always exists.
   - `config/oauth.json` (git-ignored, already in `.gitignore`) is bundled when present and loaded at startup. If it is missing or invalid, Google sign-in is shown disabled with a hint.
   - The web build serves the file publicly. Client IDs are public, and Google does not treat a desktop client secret as confidential (spec §4.4).
5. **The web flow.**
   - It has no refresh token. When the 1-hour token expires, the next API call opens the popup again, with `prompt: ''` so Google skips the account picker when it can.
   - If the user picks a different account in that popup, the call is refused. It is never sent as the wrong account.
6. **An expired or revoked desktop sign-in** (Google answers the refresh with `invalid_grant`) becomes an `AuthException`. The message names the account, says to use **Sign in again…** in the project menu, and mentions the 7-day limit in Testing mode. Signing in again must use the same account.
7. **Picking a project that is already added** switches it to the Google account. Its environment stays, and so does its project number when Google has none. The old key's secret is deleted once no project uses it. This matches re-adding with a key.
8. **The project list call** (`GET firebase.googleapis.com/v1beta1/projects`) has no `x-goog-user-project` header, because no project is chosen yet. It is billed to the Google Cloud project that owns the OAuth client, so `docs/oauth-setup.md` says to enable the Firebase Management API there.
9. **The M0 check "`x-goog-user-project` with a user token"** is done by the M4 success test (Task 11 Step 3). The errors it can hit are explained: `USER_PROJECT_DENIED` needs the Service Usage Consumer role, and a scope error needs a fresh sign-in.
10. **File layout.** The platform split sits on the sign-in flow (`google_auth_flow_io.dart` / `google_auth_flow_web.dart`, chosen by `google_auth_flow_platform.dart`). One `google_account_token_provider.dart` serves both platforms. This differs slightly from spec §3.2.
11. **Storage.** A desktop refresh token is stored as `{"refreshToken": "…"}` under `google:<email>` (spec §10). Nothing is stored on the web.
12. **Selection after adding Google projects.** If exactly one project was ticked, it becomes selected. Otherwise the current selection stays, or the first added project (by name) is selected when nothing was selected.
13. **Emails** are stored lowercase.

## Global Constraints

- Platforms: macOS, Windows, web. Flutter 3.44, Dart 3.12. Work on `main`.
- Scopes, in this order:
  - `https://www.googleapis.com/auth/firebase.messaging`
  - `https://www.googleapis.com/auth/firebase.readonly`
  - `openid`
  - `https://www.googleapis.com/auth/userinfo.email`
- Required scopes (a sign-in without them is refused): the two Firebase scopes.
- Desktop: a "Desktop app" OAuth client.
  - Authorization endpoint: `https://accounts.google.com/o/oauth2/v2/auth`.
  - Token endpoint: `https://oauth2.googleapis.com/token`.
  - Redirect: `http://127.0.0.1:<port>`.
- Web: a "Web" OAuth client and Google's popup. No refresh token.
- `config/oauth.json` keys: `desktopClientId`, `desktopClientSecret`, `webClientId`.
- Refresh tokens live in `SecretStore` under `google:<email>`. They never go into logs, error text, `toString`, or history.
- Tokens are cached in memory per credential and refreshed when less than 5 minutes remain. Concurrent requests share one refresh. After a `401`, `FcmClient` refreshes once and retries once; it already does this.
- `GoogleAccountTokenProvider.extraHeaders(projectId)` returns `{'x-goog-user-project': projectId}`.
- Errors say what failed and what to do (spec §11). `redact()` is applied to anything that echoes a server or exception text.
- No test opens a real browser, reaches Google, or binds anything except `127.0.0.1` port 0. Flows are injected, and HTTP goes through `MockClient`.
- Lints:
  - `flutter_lints`, `strict-casts`, `strict-inference`, `strict-raw-types`;
  - `always_declare_return_types`, `avoid_dynamic_calls`, `prefer_final_locals`, `prefer_single_quotes`, `unawaited_futures`;
  - curly braces, `sort_child_properties_last`, `use_null_aware_elements`.
- Models are hand-written with Equatable. Private named constructor parameters are written `required this._x` and called as `x:`.
- Commits end with `Co-Authored-By: Claude Opus 5.5 (1M context) <noreply@anthropic.com>`. Never stage `devtools_options.yaml` or anything under `.superpowers/`.

## Review Focus

These are the five failure modes most likely to bite a person that no single happy-path test exercises. Each one has its test in the task named.

1. **The user closes the browser tab, or never finishes Google's page (desktop).**
   - Expected: the dialog says "Finish signing in in your browser…" and offers Cancel. Cancel stops waiting at once and frees the port. Closing the dialog does the same. After 5 minutes the sign-in stops with a message.
   - Tests: Task 2 (cancel, timeout, port freed); Task 9 (the Cancel button, and closing the dialog).
2. **The user unticks a permission on Google's consent screen.**
   - Expected: "FCM Studio needs permission to send messages and to read your Firebase projects. Sign in again and allow both." Nothing is saved.
   - Tests: Task 4 (provider), Task 5 (registry), Task 7 (cubit).
3. **A desktop sign-in expired (7 days in Testing) or was revoked.**
   - Expected: the send fails with an explanation that names the account and points to **Sign in again…** in the project menu. Signing in there with a different account is refused, and the old sign-in stays.
   - Tests: Task 4 (expired refresh), Task 7 (a different account refused), Task 8 (the explanation's action), Task 10 (the menu).
4. **On the web, after the token expires, the user picks a different Google account in the popup.**
   - Expected: the send is refused with "You signed in as B, but this project uses A". Nothing is sent and nothing is cached.
   - Tests: Task 4.
5. **The account can't bill quota to the project (`USER_PROJECT_DENIED`) or lacks FCM permission.**
   - Expected: the explanation names the missing role for "your Google account", not service-account advice.
   - Tests: Task 8.

## File Map

| File | Responsibility | Task |
|---|---|---|
| `config/oauth.example.json` | Committed template; keeps the asset directory present | 1 |
| `lib/core/auth/oauth_config.dart` | Parse/load `config/oauth.json` | 1 |
| `lib/core/auth/google_auth_flow.dart` | `GoogleAuthFlow` interface, `GoogleCredentials`, scopes, `GoogleSignInCancelled`, `GoogleSignInExpired`, `describeGoogleWebError`, `missingScopesMessage` | 2 |
| `lib/core/auth/google_auth_flow_io.dart` | `DesktopGoogleAuthFlow` (loopback + PKCE) and the desktop `createGoogleAuthFlow` | 2 |
| `lib/core/auth/google_auth_flow_web.dart` | `WebGoogleAuthFlow` (popup) and the web `createGoogleAuthFlow` | 3 |
| `lib/core/auth/google_auth_flow_platform.dart` | Conditional export of the right file | 3 |
| `lib/core/auth/google_user_info.dart` | Which account a token belongs to | 4 |
| `lib/core/auth/google_account_token_provider.dart` | Token cache, refresh, web re-prompt, `x-goog-user-project` | 4 |
| `lib/features/projects/domain/project.dart` | `GoogleAccountRef` | 5 |
| `lib/features/projects/domain/google_session.dart` | A finished sign-in: email, credentials, provider | 5 |
| `lib/features/projects/data/projects_repository.dart` | Store/read the refresh token | 5 |
| `lib/features/projects/data/project_auth_registry.dart` | Google sign-in, providers for Google projects | 5 |
| `lib/core/firebase/firebase_projects_api.dart` | `listProjects` with paging | 6 |
| `lib/features/projects/cubit/projects_cubit.dart` | `signInWithGoogle`, `addGoogleProjects`, `signInAgain` | 7 |
| `lib/core/fcm/fcm_error_explainer.dart`, `lib/features/composer/data/message_sender.dart` | Explanations for Google accounts | 8 |
| `lib/app/dependencies.dart`, `test/helpers/app_harness.dart` | Wiring | 9 |
| `lib/features/projects/view/add_project_dialog.dart`, `google_projects_dialog.dart` | Sign in with Google, project checklist | 9 |
| `lib/features/projects/view/project_switcher.dart`, `sign_in_again_dialog.dart` | Account label, Sign in again, copy | 10 |
| `docs/oauth-setup.md` | One-time Google Cloud setup | 11 |

Test helpers: `test/helpers/fake_google_auth_flow.dart` (Task 4), `test/helpers/fake_google.dart` (Task 7 adds the list endpoint), `test/helpers/project_fixture.dart` (Task 5 adds `testGoogleProject`).

---

### Task 1: The OAuth config file

**Files:**
- Create: `lib/core/auth/oauth_config.dart`, `config/oauth.example.json`
- Modify: `pubspec.yaml` (assets)
- Test: `test/core/auth/oauth_config_test.dart`

**Interfaces:**
- Produces: `class OAuthConfig({String? desktopClientId, String? desktopClientSecret, String? webClientId})`, with:
  - `factory OAuthConfig.parse(String text)`, which throws `FormatException`;
  - `static const assetPath = 'config/oauth.json'`;
  - `static Future<OAuthConfig?> load(Future<String> Function() read)`;
  - getters `hasDesktopClient` and `hasWebClient`;
  - a `toString` that never shows the secret.

- [ ] **Step 1: Write the failing test** `test/core/auth/oauth_config_test.dart`

```dart
import 'dart:io';

import 'package:fcm_studio/core/auth/oauth_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the three client values', () {
    final config = OAuthConfig.parse(
      '{"desktopClientId":"d.apps.googleusercontent.com",'
      '"desktopClientSecret":"s","webClientId":"w.apps.googleusercontent.com"}',
    );
    expect(
      config,
      const OAuthConfig(
        desktopClientId: 'd.apps.googleusercontent.com',
        desktopClientSecret: 's',
        webClientId: 'w.apps.googleusercontent.com',
      ),
    );
    expect(config.hasDesktopClient, isTrue);
    expect(config.hasWebClient, isTrue);
  });

  test('blank values count as missing', () {
    final config = OAuthConfig.parse(
      '{"desktopClientId":"  ","desktopClientSecret":"","webClientId":" w "}',
    );
    expect(config.hasDesktopClient, isFalse);
    expect(config.webClientId, 'w');
  });

  test('the committed example has no clients', () {
    final config = OAuthConfig.parse(
      File('config/oauth.example.json').readAsStringSync(),
    );
    expect(config.hasDesktopClient, isFalse);
    expect(config.hasWebClient, isFalse);
  });

  test('a missing or broken file gives no config', () async {
    expect(
      await OAuthConfig.load(() async => throw Exception('Unable to load asset')),
      isNull,
    );
    expect(await OAuthConfig.load(() async => '[1, 2]'), isNull);
    expect(await OAuthConfig.load(() async => 'not json'), isNull);
    expect(
      await OAuthConfig.load(() async => '{"webClientId":"w"}'),
      const OAuthConfig(webClientId: 'w'),
    );
  });

  test('toString never shows the client secret', () {
    final config = OAuthConfig.parse(
      '{"desktopClientId":"d","desktopClientSecret":"top-secret"}',
    );
    expect('$config', isNot(contains('top-secret')));
  });
}
```

- [ ] **Step 2: Run it and confirm it fails**

Run: `flutter test test/core/auth/oauth_config_test.dart`
Expected: FAIL, because `oauth_config.dart` doesn't exist.

- [ ] **Step 3: Add the example file** `config/oauth.example.json`

```json
{
  "desktopClientId": "",
  "desktopClientSecret": "",
  "webClientId": ""
}
```

- [ ] **Step 4: Bundle the `config/` directory.** In `pubspec.yaml`, under `flutter:` → `assets:`, add the directory after the existing preset asset:

```yaml
  assets:
    - assets/presets/builtin.json
    - config/
```

- [ ] **Step 5: Write** `lib/core/auth/oauth_config.dart`

```dart
import 'dart:convert';

import 'package:equatable/equatable.dart';

/// OAuth client IDs for Google sign-in, read from the git-ignored
/// `config/oauth.json` (spec §4.4, plan Decision 4).
class OAuthConfig extends Equatable {
  const OAuthConfig({
    this.desktopClientId,
    this.desktopClientSecret,
    this.webClientId,
  });

  /// Reads the JSON text of `config/oauth.json`. Blank values count as missing.
  factory OAuthConfig.parse(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('config/oauth.json must hold a JSON object.');
    }
    String? field(String name) {
      final value = decoded[name];
      if (value is! String) {
        return null;
      }
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return OAuthConfig(
      desktopClientId: field('desktopClientId'),
      desktopClientSecret: field('desktopClientSecret'),
      webClientId: field('webClientId'),
    );
  }

  static const assetPath = 'config/oauth.json';

  /// Loads the config with [read], or returns null when the file is missing
  /// or invalid, so Google sign-in is shown as not set up.
  static Future<OAuthConfig?> load(Future<String> Function() read) async {
    try {
      return OAuthConfig.parse(await read());
    } on Object {
      return null;
    }
  }

  final String? desktopClientId;
  final String? desktopClientSecret;
  final String? webClientId;

  bool get hasDesktopClient =>
      desktopClientId != null && desktopClientSecret != null;

  bool get hasWebClient => webClientId != null;

  @override
  List<Object?> get props => [desktopClientId, desktopClientSecret, webClientId];

  @override
  String toString() =>
      'OAuthConfig(desktop: $hasDesktopClient, web: $hasWebClient)';
}
```

- [ ] **Step 6: Run the test and confirm it passes**

Run: `flutter test test/core/auth/oauth_config_test.dart`, then `flutter analyze`.
Expected: PASS, and `No issues found!`.

- [ ] **Step 7: Commit**

```bash
dart format lib test
git add lib/core/auth/oauth_config.dart config/oauth.example.json pubspec.yaml test/core/auth/oauth_config_test.dart
git commit -m "feat: read the OAuth client IDs from config/oauth.json"
```

---

### Task 2: Desktop Google sign-in (browser + loopback)

**Files:**
- Create: `lib/core/auth/google_auth_flow.dart`, `lib/core/auth/google_auth_flow_io.dart`
- Modify: `pubspec.yaml` (add `crypto: ^3.0.7`)
- Test: `test/core/auth/google_auth_flow_test.dart`, `test/core/auth/desktop_google_auth_flow_test.dart`

**Interfaces:**
- Consumes: `AccessToken`, `AuthException` (`lib/core/auth/access_token_provider.dart`); `Clock`, `SystemClock`; `redact`; `OAuthConfig` (Task 1).
- Produces, in `google_auth_flow.dart`:
  - `const googleScopes` (4 scopes) and `const requiredGoogleScopes` (the 2 Firebase scopes);
  - `const missingScopesMessage`;
  - `class GoogleCredentials({required AccessToken accessToken, required List<String> scopes, String? refreshToken})`, with getter `missingScopes`;
  - `class GoogleSignInCancelled implements Exception` (const);
  - `class GoogleSignInExpired extends AuthException` (const, positional message);
  - `abstract interface class GoogleAuthFlow { bool get canRefresh; Future<GoogleCredentials> signIn({String? loginHint, Future<void>? cancel}); Future<GoogleCredentials> refresh(String refreshToken); }`;
  - `Exception describeGoogleWebError(String error, {String? description})`.
- Produces, in `google_auth_flow_io.dart`:
  - `class DesktopGoogleAuthFlow implements GoogleAuthFlow({required String clientId, required String clientSecret, required http.Client httpClient, Future<bool> Function(Uri url)? openBrowser, Duration timeout = 5 min, Clock clock})`;
  - `GoogleAuthFlow? createGoogleAuthFlow(OAuthConfig? config, http.Client httpClient)`, which returns null without a desktop client.

- [ ] **Step 1: Add the dependency.** Under `dependencies:` in `pubspec.yaml`, alphabetically after `equatable`, add `crypto: ^3.0.7`. Then run `flutter pub get`. It is already in the lockfile as a transitive dependency, so nothing new is downloaded.

- [ ] **Step 2: Write the failing tests.** First, `test/core/auth/google_auth_flow_test.dart`:

```dart
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('missingScopes lists the Firebase scopes the user did not grant', () {
    final credentials = GoogleCredentials(
      accessToken: AccessToken('ya29.x', DateTime.utc(2100)),
      scopes: const ['openid', 'https://www.googleapis.com/auth/userinfo.email'],
    );
    expect(credentials.missingScopes, requiredGoogleScopes);
    expect(
      GoogleCredentials(
        accessToken: AccessToken('ya29.x', DateTime.utc(2100)),
        scopes: googleScopes,
      ).missingScopes,
      isEmpty,
    );
  });

  test('credentials never print their tokens', () {
    final credentials = GoogleCredentials(
      accessToken: AccessToken('ya29.secret', DateTime.utc(2100)),
      refreshToken: '1//secret',
      scopes: googleScopes,
    );
    expect('$credentials', isNot(contains('secret')));
  });

  test('web errors: a closed popup is a cancel, a blocked one says what to do', () {
    expect(
      describeGoogleWebError('GoogleIdentityServicesErrorType.popup_closed'),
      isA<GoogleSignInCancelled>(),
    );
    expect(describeGoogleWebError('access_denied'), isA<GoogleSignInCancelled>());
    expect(
      describeGoogleWebError('popup_failed_to_open'),
      isA<AuthException>().having(
        (e) => e.message,
        'message',
        contains('Allow pop-ups'),
      ),
    );
    expect(
      describeGoogleWebError('invalid_client', description: 'bad id'),
      isA<AuthException>().having(
        (e) => e.message,
        'message',
        'Google sign-in failed (invalid_client: bad id).',
      ),
    );
  });
}
```

Then `test/core/auth/desktop_google_auth_flow_test.dart`. It has plain `test()`s only, so no widget binding changes how `dart:io` behaves:

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/google_auth_flow_io.dart';
import 'package:fcm_studio/core/auth/oauth_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../../helpers/fixed_clock.dart';

/// Plays the browser: sends Google's redirect to the app's loopback server.
Future<String> redirectTo(
  Uri authUrl,
  Map<String, String> query, {
  String path = '/',
}) async {
  final redirect = Uri.parse(authUrl.queryParameters['redirect_uri']!);
  final socket = await Socket.connect(redirect.host, redirect.port);
  final target = Uri(path: path, queryParameters: query).toString();
  socket.write(
    'GET $target HTTP/1.1\r\nHost: ${redirect.host}:${redirect.port}\r\n'
    'Connection: close\r\n\r\n',
  );
  await socket.flush();
  final response = await utf8.decoder.bind(socket).join();
  socket.destroy();
  return response;
}

void main() {
  final clock = FixedClock(DateTime.utc(2026, 10, 4, 12));
  late List<Map<String, String>> tokenRequests;
  late Completer<Uri> opened;

  setUp(() {
    tokenRequests = [];
    opened = Completer<Uri>();
  });

  http.Client tokenEndpoint({int status = 200, Map<String, Object?>? body}) =>
      MockClient((request) async {
        expect(request.url, DesktopGoogleAuthFlow.tokenEndpoint);
        tokenRequests.add(request.bodyFields);
        return http.Response(
          jsonEncode(
            body ??
                {
                  'access_token': 'ya29.desktop',
                  'expires_in': 3599,
                  'refresh_token': '1//refresh',
                  'scope': googleScopes.join(' '),
                  'token_type': 'Bearer',
                },
          ),
          status,
        );
      });

  DesktopGoogleAuthFlow flow({
    http.Client? client,
    bool browserOpens = true,
    Duration timeout = const Duration(minutes: 5),
  }) => DesktopGoogleAuthFlow(
    clientId: 'desktop-id',
    clientSecret: 'desktop-secret',
    httpClient: client ?? tokenEndpoint(),
    openBrowser: (url) async {
      opened.complete(url);
      return browserOpens;
    },
    timeout: timeout,
    clock: clock,
  );

  test('signs in through the browser and exchanges the code with PKCE', () async {
    final signIn = flow().signIn(loginHint: 'dev@example.com');
    final url = await opened.future;
    expect(url.origin, 'https://accounts.google.com');
    expect(url.path, '/o/oauth2/v2/auth');
    expect(url.queryParameters['client_id'], 'desktop-id');
    expect(url.queryParameters['scope'], googleScopes.join(' '));
    expect(url.queryParameters['code_challenge_method'], 'S256');
    expect(url.queryParameters['prompt'], 'select_account consent');
    expect(url.queryParameters['login_hint'], 'dev@example.com');
    expect(url.queryParameters['redirect_uri'], startsWith('http://127.0.0.1:'));

    final page = await redirectTo(url, {
      'code': 'auth-code',
      'state': url.queryParameters['state']!,
    });
    expect(page, contains('You can close this tab'));

    final credentials = await signIn;
    expect(
      credentials.accessToken,
      AccessToken('ya29.desktop', clock.now().add(const Duration(seconds: 3599))),
    );
    expect(credentials.refreshToken, '1//refresh');
    expect(credentials.missingScopes, isEmpty);

    final form = tokenRequests.single;
    expect(form['grant_type'], 'authorization_code');
    expect(form['code'], 'auth-code');
    expect(form['client_secret'], 'desktop-secret');
    expect(form['redirect_uri'], url.queryParameters['redirect_uri']);
    final challenge = base64Url
        .encode(sha256.convert(ascii.encode(form['code_verifier']!)).bytes)
        .replaceAll('=', '');
    expect(challenge, url.queryParameters['code_challenge']);
  });

  test('ignores stray requests and a wrong state, then takes the real answer', () async {
    final signIn = flow().signIn();
    final url = await opened.future;
    expect(await redirectTo(url, {}, path: '/favicon.ico'), contains('404'));
    expect(
      await redirectTo(url, {'code': 'forged', 'state': 'wrong'}),
      contains('404'),
    );
    await redirectTo(url, {
      'code': 'auth-code',
      'state': url.queryParameters['state']!,
    });
    expect((await signIn).refreshToken, '1//refresh');
    expect(tokenRequests.single['code'], 'auth-code');
  });

  test('cancelling on the Google page ends the sign-in without a token request', () async {
    final signIn = flow().signIn();
    final url = await opened.future;
    await redirectTo(url, {
      'error': 'access_denied',
      'state': url.queryParameters['state']!,
    });
    await expectLater(signIn, throwsA(isA<GoogleSignInCancelled>()));
    expect(tokenRequests, isEmpty);
  });

  test('Cancel in the app stops waiting and frees the port', () async {
    final cancel = Completer<void>();
    final signIn = flow().signIn(cancel: cancel.future);
    final url = await opened.future;
    cancel.complete();
    await expectLater(signIn, throwsA(isA<GoogleSignInCancelled>()));
    final port = Uri.parse(url.queryParameters['redirect_uri']!).port;
    await expectLater(
      Socket.connect('127.0.0.1', port),
      throwsA(isA<SocketException>()),
    );
  });

  test('stops waiting after the timeout', () async {
    final signIn = flow(timeout: const Duration(milliseconds: 200)).signIn();
    await opened.future;
    await expectLater(
      signIn,
      throwsA(
        isA<AuthException>().having((e) => e.message, 'message', contains('timed out')),
      ),
    );
  });

  test('a browser that cannot open fails at once', () async {
    await expectLater(
      flow(browserOpens: false).signIn(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          contains('open the browser'),
        ),
      ),
    );
  });

  test('refresh gets a new access token and keeps the refresh token', () async {
    final credentials = await flow(
      client: tokenEndpoint(
        body: {
          'access_token': 'ya29.refreshed',
          'expires_in': 3599,
          'scope': googleScopes.join(' '),
          'token_type': 'Bearer',
        },
      ),
    ).refresh('1//stored');
    expect(credentials.accessToken.value, 'ya29.refreshed');
    expect(credentials.refreshToken, '1//stored');
    expect(tokenRequests.single, {
      'client_id': 'desktop-id',
      'client_secret': 'desktop-secret',
      'refresh_token': '1//stored',
      'grant_type': 'refresh_token',
    });
  });

  test('an expired or revoked refresh token is reported as expired', () async {
    await expectLater(
      flow(
        client: tokenEndpoint(
          status: 400,
          body: {
            'error': 'invalid_grant',
            'error_description': 'Token has been expired or revoked.',
          },
        ),
      ).refresh('1//old'),
      throwsA(isA<GoogleSignInExpired>()),
    );
  });

  test('a code Google rejects is not called an expired sign-in', () async {
    final signIn = flow(
      client: tokenEndpoint(status: 400, body: {'error': 'invalid_grant'}),
    ).signIn();
    final url = await opened.future;
    await redirectTo(url, {
      'code': 'used',
      'state': url.queryParameters['state']!,
    });
    await expectLater(
      signIn,
      throwsA(
        isA<AuthException>()
            .having((e) => e, 'type', isNot(isA<GoogleSignInExpired>()))
            .having((e) => e.message, 'message', contains('Try again')),
      ),
    );
  });

  test('the desktop factory needs a desktop client', () {
    expect(createGoogleAuthFlow(null, tokenEndpoint()), isNull);
    expect(
      createGoogleAuthFlow(const OAuthConfig(webClientId: 'w'), tokenEndpoint()),
      isNull,
    );
    expect(
      createGoogleAuthFlow(
        const OAuthConfig(desktopClientId: 'd', desktopClientSecret: 's'),
        tokenEndpoint(),
      ),
      isA<DesktopGoogleAuthFlow>(),
    );
  });
}
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `flutter test test/core/auth/google_auth_flow_test.dart test/core/auth/desktop_google_auth_flow_test.dart`
Expected: FAIL, because the files don't exist.

- [ ] **Step 4: Write** `lib/core/auth/google_auth_flow.dart`

```dart
import 'package:equatable/equatable.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';

/// The scopes every Google sign-in asks for: the two Firebase scopes
/// (spec §4.1), plus `openid` and `userinfo.email` so the app can tell which
/// account signed in (plan Decision 2).
const googleScopes = [
  'https://www.googleapis.com/auth/firebase.messaging',
  'https://www.googleapis.com/auth/firebase.readonly',
  'openid',
  'https://www.googleapis.com/auth/userinfo.email',
];

/// Without these nothing works, so a sign-in that lacks one is refused.
const requiredGoogleScopes = [
  'https://www.googleapis.com/auth/firebase.messaging',
  'https://www.googleapis.com/auth/firebase.readonly',
];

const missingScopesMessage =
    'FCM Studio needs permission to send messages and to read your Firebase '
    'projects. Sign in again and allow both.';

/// What a finished sign-in or refresh gives back.
class GoogleCredentials extends Equatable {
  const GoogleCredentials({
    required this.accessToken,
    required this.scopes,
    this.refreshToken,
  });

  final AccessToken accessToken;

  /// Only desktop sign-ins have one (spec §4.1).
  final String? refreshToken;
  final List<String> scopes;

  /// The required scopes the user did not grant (Google lets them untick some).
  List<String> get missingScopes => [
    for (final scope in requiredGoogleScopes)
      if (!scopes.contains(scope)) scope,
  ];

  @override
  List<Object?> get props => [accessToken, refreshToken, scopes];

  @override
  String toString() =>
      'GoogleCredentials(expiresAt: ${accessToken.expiresAt}, scopes: $scopes)';
}

/// The user closed or cancelled Google's sign-in.
class GoogleSignInCancelled implements Exception {
  const GoogleSignInCancelled();

  @override
  String toString() => 'GoogleSignInCancelled';
}

/// Google says the stored sign-in expired or was revoked (`invalid_grant`).
class GoogleSignInExpired extends AuthException {
  const GoogleSignInExpired(super.message);
}

/// Signs in to Google: a browser tab on desktop, a popup on the web.
abstract interface class GoogleAuthFlow {
  /// True when sign-ins come with a refresh token (desktop).
  bool get canRefresh;

  /// Opens Google's sign-in. [loginHint] preselects an account. Completing
  /// [cancel] stops waiting (desktop only). Throws [GoogleSignInCancelled] or
  /// [AuthException].
  Future<GoogleCredentials> signIn({String? loginHint, Future<void>? cancel});

  /// Gets a new access token with [refreshToken] (desktop only). Throws
  /// [GoogleSignInExpired] when Google no longer accepts it.
  Future<GoogleCredentials> refresh(String refreshToken);
}

/// Turns a Google Identity Services error into what the user should know.
Exception describeGoogleWebError(String error, {String? description}) {
  if (error.contains('popup_closed') || error == 'access_denied') {
    return const GoogleSignInCancelled();
  }
  if (error.contains('popup_failed_to_open')) {
    return const AuthException(
      'Your browser blocked the Google sign-in pop-up. '
      'Allow pop-ups for this site, then try again.',
    );
  }
  return AuthException(
    'Google sign-in failed ($error${description == null ? '' : ': $description'}).',
  );
}
```

- [ ] **Step 5: Write** `lib/core/auth/google_auth_flow_io.dart`

```dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/oauth_config.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// The desktop sign-in, or null when `config/oauth.json` has no desktop client.
GoogleAuthFlow? createGoogleAuthFlow(
  OAuthConfig? config,
  http.Client httpClient,
) {
  final clientId = config?.desktopClientId;
  final clientSecret = config?.desktopClientSecret;
  if (clientId == null || clientSecret == null) {
    return null;
  }
  return DesktopGoogleAuthFlow(
    clientId: clientId,
    clientSecret: clientSecret,
    httpClient: httpClient,
  );
}

/// Google sign-in for desktop apps: the system browser, with Google's answer
/// sent to a one-off server on 127.0.0.1 (spec §4.1, plan Decision 1).
class DesktopGoogleAuthFlow implements GoogleAuthFlow {
  DesktopGoogleAuthFlow({
    required this.clientId,
    required this.clientSecret,
    required http.Client httpClient,
    Future<bool> Function(Uri url)? openBrowser,
    this.timeout = const Duration(minutes: 5),
    this._clock = const SystemClock(),
  }) : _http = httpClient,
       _openBrowser = openBrowser ?? _launch;

  static final Uri authorizationEndpoint = Uri.parse(
    'https://accounts.google.com/o/oauth2/v2/auth',
  );
  static final Uri tokenEndpoint = Uri.parse(
    'https://oauth2.googleapis.com/token',
  );
  static const _requestTimeout = Duration(seconds: 20);

  final String clientId;
  final String clientSecret;
  final Duration timeout;
  final http.Client _http;
  final Future<bool> Function(Uri url) _openBrowser;
  final Clock _clock;

  @override
  bool get canRefresh => true;

  @override
  Future<GoogleCredentials> signIn({
    String? loginHint,
    Future<void>? cancel,
  }) async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirectUri = 'http://127.0.0.1:${server.port}';
      final state = _randomString(32);
      final verifier = _randomString(64);
      final url = authorizationEndpoint.replace(
        queryParameters: {
          'client_id': clientId,
          'redirect_uri': redirectUri,
          'response_type': 'code',
          'scope': googleScopes.join(' '),
          'code_challenge': _challenge(verifier),
          'code_challenge_method': 'S256',
          'state': state,
          'access_type': 'offline',
          // "consent" makes Google return a refresh token every time.
          'prompt': 'select_account consent',
          'login_hint': ?loginHint,
        },
      );
      if (!await _openBrowser(url)) {
        throw const AuthException(
          'Could not open the browser for Google sign-in.',
        );
      }
      final code = await _waitForCode(server, state, cancel);
      final body = await _post({
        'code': code,
        'client_id': clientId,
        'client_secret': clientSecret,
        'redirect_uri': redirectUri,
        'grant_type': 'authorization_code',
        'code_verifier': verifier,
      }, isRefresh: false);
      final refreshToken = body['refresh_token'];
      return _credentials(
        body,
        refreshToken: refreshToken is String ? refreshToken : null,
      );
    } finally {
      await server.close(force: true);
    }
  }

  @override
  Future<GoogleCredentials> refresh(String refreshToken) async {
    final body = await _post({
      'client_id': clientId,
      'client_secret': clientSecret,
      'refresh_token': refreshToken,
      'grant_type': 'refresh_token',
    }, isRefresh: true);
    // Google doesn't send the refresh token again; keep the one we have.
    return _credentials(body, refreshToken: refreshToken);
  }

  Future<String> _waitForCode(
    HttpServer server,
    String state,
    Future<void>? cancel,
  ) {
    final result = Completer<String>();
    final subscription = server.listen((request) async {
      final query = request.uri.queryParameters;
      if (request.uri.path != '/' || query['state'] != state) {
        // e.g. the browser asking for /favicon.ico, or a forged request.
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }
      final error = query['error'];
      final code = query['code'];
      final succeeded = error == null && code != null && code.isNotEmpty;
      await _answer(request, succeeded ? _donePage : _stoppedPage);
      if (result.isCompleted) {
        return;
      }
      if (succeeded) {
        result.complete(code);
      } else if (error == 'access_denied') {
        result.completeError(const GoogleSignInCancelled());
      } else {
        result.completeError(
          AuthException('Google sign-in failed (${error ?? 'no code returned'}).'),
        );
      }
    });
    unawaited(
      cancel?.then((_) {
        if (!result.isCompleted) {
          result.completeError(const GoogleSignInCancelled());
        }
      }),
    );
    return result.future
        .timeout(
          timeout,
          onTimeout: () => throw const AuthException(
            'Google sign-in timed out. Try again, and finish signing in in '
            'your browser.',
          ),
        )
        .whenComplete(subscription.cancel);
  }

  Future<Map<String, Object?>> _post(
    Map<String, String> form, {
    required bool isRefresh,
  }) async {
    final http.Response response;
    try {
      response = await _http
          .post(tokenEndpoint, body: form)
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const AuthException(
        'Google did not answer the sign-in request within 20 seconds.',
      );
    } on Exception catch (e) {
      throw AuthException('Network error during Google sign-in: ${redact('$e')}');
    }
    final body = _decode(response.body);
    if (response.statusCode == 200 && body != null) {
      return body;
    }
    final error = body?['error'];
    final description = body?['error_description'];
    if (error == 'invalid_grant') {
      if (isRefresh) {
        throw GoogleSignInExpired(
          'Google says this sign-in has expired or was revoked'
          '${description is String ? ' ($description)' : ''}.',
        );
      }
      throw const AuthException('Google rejected the sign-in code. Try again.');
    }
    throw AuthException(
      'Google sign-in request failed (HTTP ${response.statusCode}'
      '${error is String ? ', $error' : ''}).',
      statusCode: response.statusCode,
    );
  }

  GoogleCredentials _credentials(
    Map<String, Object?> body, {
    required String? refreshToken,
  }) {
    final token = body['access_token'];
    final expiresIn = body['expires_in'];
    final scope = body['scope'];
    if (token is! String || expiresIn is! num) {
      throw const AuthException('Google returned an unexpected sign-in response.');
    }
    return GoogleCredentials(
      accessToken: AccessToken(
        token,
        _clock.now().add(Duration(seconds: expiresIn.toInt())),
      ),
      refreshToken: refreshToken,
      scopes: scope is String ? scope.split(' ') : const [],
    );
  }

  static const _donePage =
      '<!doctype html><meta charset="utf-8"><title>FCM Studio</title>'
      '<p style="font-family: sans-serif">Signed in. You can close this tab '
      'and go back to FCM Studio.</p>';
  static const _stoppedPage =
      '<!doctype html><meta charset="utf-8"><title>FCM Studio</title>'
      '<p style="font-family: sans-serif">Sign-in was not completed. You can '
      'close this tab.</p>';

  static Future<void> _answer(HttpRequest request, String html) async {
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType.html
      ..write(html);
    await request.response.close();
  }

  static Map<String, Object?>? _decode(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static final _random = Random.secure();
  static const _alphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  static String _randomString(int length) => String.fromCharCodes([
    for (var i = 0; i < length; i++)
      _alphabet.codeUnitAt(_random.nextInt(_alphabet.length)),
  ]);

  static String _challenge(String verifier) => base64Url
      .encode(sha256.convert(ascii.encode(verifier)).bytes)
      .replaceAll('=', '');

  static Future<bool> _launch(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);
}
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `flutter test test/core/auth/google_auth_flow_test.dart test/core/auth/desktop_google_auth_flow_test.dart`, three times in a row, to catch timing flakiness. Then run `flutter analyze`.
Expected: PASS every time, and `No issues found!`.

- [ ] **Step 7: Commit**

```bash
dart format lib test
git add pubspec.yaml pubspec.lock lib/core/auth/google_auth_flow.dart lib/core/auth/google_auth_flow_io.dart test/core/auth/google_auth_flow_test.dart test/core/auth/desktop_google_auth_flow_test.dart
git commit -m "feat: sign in to Google on desktop through the browser and a loopback server"
```

---

### Task 3: Browser Google sign-in (popup) and the platform switch

**Files:**
- Create: `lib/core/auth/google_auth_flow_web.dart`, `lib/core/auth/google_auth_flow_platform.dart`
- Modify: `pubspec.yaml` (add `googleapis_auth: ^2.3.4`)
- Test: `test/core/auth/google_auth_flow_platform_test.dart`

**Interfaces:**
- Consumes: everything in `google_auth_flow.dart` (Task 2) and `OAuthConfig` (Task 1).
- Produces:
  - `class WebGoogleAuthFlow implements GoogleAuthFlow({required String clientId})`, with `canRefresh == false`;
  - the web `createGoogleAuthFlow`, which returns null without `webClientId`;
  - `google_auth_flow_platform.dart`, which exports the right `createGoogleAuthFlow` for the platform.

- [ ] **Step 1: Add the dependency.** Under `dependencies:` in `pubspec.yaml`, alphabetically after `flutter_secure_storage`, add `googleapis_auth: ^2.3.4`. Then run `flutter pub get`.

- [ ] **Step 2: Write the failing test** `test/core/auth/google_auth_flow_platform_test.dart`

```dart
import 'package:fcm_studio/core/auth/google_auth_flow_io.dart';
import 'package:fcm_studio/core/auth/google_auth_flow_platform.dart' as platform;
import 'package:fcm_studio/core/auth/oauth_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final client = MockClient((_) async => http.Response('unused', 500));

  test('off the web the platform switch picks the desktop sign-in', () {
    expect(
      platform.createGoogleAuthFlow(
        const OAuthConfig(
          desktopClientId: 'd',
          desktopClientSecret: 's',
          webClientId: 'w',
        ),
        client,
      ),
      isA<DesktopGoogleAuthFlow>(),
    );
    expect(
      platform.createGoogleAuthFlow(const OAuthConfig(webClientId: 'w'), client),
      isNull,
    );
  });
}
```

- [ ] **Step 3: Run it and confirm it fails**

Run: `flutter test test/core/auth/google_auth_flow_platform_test.dart`
Expected: FAIL, because `google_auth_flow_platform.dart` doesn't exist.

- [ ] **Step 4: Write** `lib/core/auth/google_auth_flow_web.dart`

```dart
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/oauth_config.dart';
import 'package:googleapis_auth/auth_browser.dart' as gauth;
import 'package:http/http.dart' as http;

/// The browser sign-in, or null when `config/oauth.json` has no web client.
GoogleAuthFlow? createGoogleAuthFlow(
  OAuthConfig? config,
  http.Client httpClient,
) {
  final clientId = config?.webClientId;
  return clientId == null ? null : WebGoogleAuthFlow(clientId: clientId);
}

/// Google sign-in in the browser: Google's popup (spec §4.1). It gives no
/// refresh token, so an expired token means a new popup (plan Decision 5).
class WebGoogleAuthFlow implements GoogleAuthFlow {
  WebGoogleAuthFlow({required this.clientId});

  final String clientId;

  @override
  bool get canRefresh => false;

  @override
  Future<GoogleCredentials> signIn({
    String? loginHint,
    Future<void>? cancel,
  }) async {
    final gauth.AccessCredentials credentials;
    try {
      credentials = await gauth.requestAccessCredentials(
        clientId: clientId,
        scopes: googleScopes,
        // With a known account, Google skips the account picker when it can.
        prompt: loginHint == null ? 'select_account' : '',
      );
    } on gauth.AuthenticationException catch (e) {
      throw describeGoogleWebError(e.error, description: e.errorDescription);
    }
    final token = credentials.accessToken;
    return GoogleCredentials(
      accessToken: AccessToken(token.data, token.expiry),
      scopes: credentials.scopes,
    );
  }

  @override
  Future<GoogleCredentials> refresh(String refreshToken) =>
      throw UnsupportedError('Browser sign-ins have no refresh token.');
}
```

- [ ] **Step 5: Write** `lib/core/auth/google_auth_flow_platform.dart`

```dart
export 'package:fcm_studio/core/auth/google_auth_flow_io.dart'
    if (dart.library.js_interop) 'package:fcm_studio/core/auth/google_auth_flow_web.dart';
```

- [ ] **Step 6: Run the test, analyze, and build the web**

Run: `flutter test test/core/auth/google_auth_flow_platform_test.dart`, then `flutter analyze`, then `flutter build web`.
Expected: PASS, `No issues found!`, and a successful web build. The web build proves the conditional export compiles `google_auth_flow_web.dart`, and that `dart:io` never reaches the browser.

- [ ] **Step 7: Commit**

```bash
dart format lib test
git add pubspec.yaml pubspec.lock lib/core/auth/google_auth_flow_web.dart lib/core/auth/google_auth_flow_platform.dart test/core/auth/google_auth_flow_platform_test.dart
git commit -m "feat: sign in to Google in the browser with Google's popup"
```

---
### Task 4: Google access tokens and the signed-in account

**Files:**
- Create: `lib/core/auth/google_user_info.dart`, `lib/core/auth/google_account_token_provider.dart`, `test/helpers/fake_google_auth_flow.dart`
- Test: `test/core/auth/google_user_info_test.dart`, `test/core/auth/google_account_token_provider_test.dart`

**Interfaces:**
- Consumes: `GoogleAuthFlow`, `GoogleCredentials`, `GoogleSignInCancelled`, `GoogleSignInExpired`, `missingScopesMessage` (Task 2); `AccessTokenProvider`, `AccessToken`, `AuthException`; `Clock`.
- Produces:
  - `abstract interface class GoogleUserInfo { Future<String> emailOf(AccessToken token); }`.
  - `class GoogleUserInfoApi implements GoogleUserInfo({required http.Client httpClient})`, with `static final Uri endpoint`. It returns the email in lowercase.
  - `class GoogleAccountTokenProvider implements AccessTokenProvider({required String email, required GoogleAuthFlow flow, required GoogleUserInfo userInfo, String? refreshToken, AccessToken? initialToken, Clock clock})`, with:
    - `static const refreshMargin`;
    - `static String expiredMessage(String email)`;
    - `static String notStoredMessage(String email)`.
  - Test helpers in `test/helpers/fake_google_auth_flow.dart`:
    - `const testGoogleEmail = 'dev@example.com'`;
    - `GoogleCredentials googleCredentials({String token, String? refreshToken, List<String> scopes, DateTime? expiresAt})`;
    - `class FakeGoogleAuthFlow implements GoogleAuthFlow({bool canRefresh = true, List<Object>? signIns, Object? refresh})`, with `signIns`, `refreshAnswers`, `calls` (`'signIn <hint or ->'`, `'refresh <token>'`), `Completer<void>? signInGate` and `int cancels`;
    - `class FakeGoogleUserInfo implements GoogleUserInfo([List<String> emails])`, with `tokens`.

- [ ] **Step 1: Add the test helpers** `test/helpers/fake_google_auth_flow.dart`

```dart
import 'dart:async';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/google_user_info.dart';

const testGoogleEmail = 'dev@example.com';

GoogleCredentials googleCredentials({
  String token = 'ya29.google-1',
  String? refreshToken = '1//refresh-1',
  List<String> scopes = googleScopes,
  DateTime? expiresAt,
}) => GoogleCredentials(
  accessToken: AccessToken(token, expiresAt ?? DateTime.utc(2100)),
  refreshToken: refreshToken,
  scopes: scopes,
);

/// A scripted Google sign-in. Each answer is a [GoogleCredentials], or an
/// exception to throw. The last answer repeats.
class FakeGoogleAuthFlow implements GoogleAuthFlow {
  FakeGoogleAuthFlow({
    this.canRefresh = true,
    List<Object>? signIns,
    Object? refresh,
  }) : signIns = signIns ?? [googleCredentials()],
       refreshAnswers = [refresh ?? googleCredentials(token: 'ya29.refreshed')];

  @override
  final bool canRefresh;
  final List<Object> signIns;
  final List<Object> refreshAnswers;
  final List<String> calls = [];

  /// When set, [signIn] waits for it, or for its `cancel` future.
  Completer<void>? signInGate;

  /// How many sign-ins ended because their `cancel` future completed.
  int cancels = 0;
  int _signIns = 0;
  int _refreshes = 0;

  @override
  Future<GoogleCredentials> signIn({
    String? loginHint,
    Future<void>? cancel,
  }) async {
    calls.add('signIn ${loginHint ?? '-'}');
    final gate = signInGate;
    if (gate != null) {
      var cancelled = false;
      await Future.any<void>([
        gate.future,
        if (cancel != null) cancel.then((_) => cancelled = true),
      ]);
      if (cancelled) {
        cancels++;
        throw const GoogleSignInCancelled();
      }
    }
    return _answer(signIns, _signIns++);
  }

  @override
  Future<GoogleCredentials> refresh(String refreshToken) async {
    calls.add('refresh $refreshToken');
    return _answer(refreshAnswers, _refreshes++);
  }

  static GoogleCredentials _answer(List<Object> answers, int index) {
    final answer = answers[index < answers.length ? index : answers.length - 1];
    if (answer is GoogleCredentials) {
      return answer;
    }
    throw answer;
  }
}

/// Says which account signed in. Answers in order; the last one repeats.
class FakeGoogleUserInfo implements GoogleUserInfo {
  FakeGoogleUserInfo([this.emails = const [testGoogleEmail]]);

  final List<String> emails;

  /// The access tokens it was asked about.
  final List<String> tokens = [];

  @override
  Future<String> emailOf(AccessToken token) async {
    tokens.add(token.value);
    final index = tokens.length - 1;
    return emails[index < emails.length ? index : emails.length - 1];
  }
}
```

- [ ] **Step 2: Write the failing tests.** First, `test/core/auth/google_user_info_test.dart`:

```dart
import 'dart:convert';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_user_info.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final token = AccessToken('ya29.who', DateTime.utc(2100));

  test('reads the account email (lowercase) with the access token', () async {
    late http.Request captured;
    final info = GoogleUserInfoApi(
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'sub': '1', 'email': 'Dev@Example.com'}),
          200,
        );
      }),
    );
    expect(await info.emailOf(token), 'dev@example.com');
    expect(captured.url, GoogleUserInfoApi.endpoint);
    expect(captured.headers['Authorization'], 'Bearer ya29.who');
  });

  test('an answer without an email is an error that names the status', () async {
    final info = GoogleUserInfoApi(
      httpClient: MockClient((_) async => http.Response('{}', 401)),
    );
    await expectLater(
      info.emailOf(token),
      throwsA(
        isA<AuthException>().having((e) => e.message, 'message', contains('HTTP 401')),
      ),
    );
  });
}
```

Then `test/core/auth/google_account_token_provider_test.dart`:

```dart
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_account_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_google_auth_flow.dart';
import '../../helpers/fixed_clock.dart';

void main() {
  late FixedClock clock;

  setUp(() => clock = FixedClock(DateTime.utc(2026, 10, 4, 12)));

  GoogleAccountTokenProvider desktop(
    FakeGoogleAuthFlow flow, {
    AccessToken? initial,
  }) => GoogleAccountTokenProvider(
    email: testGoogleEmail,
    flow: flow,
    userInfo: FakeGoogleUserInfo(),
    refreshToken: '1//stored',
    initialToken: initial,
    clock: clock,
  );

  GoogleAccountTokenProvider browser(
    FakeGoogleAuthFlow flow,
    FakeGoogleUserInfo info,
  ) => GoogleAccountTokenProvider(
    email: testGoogleEmail,
    flow: flow,
    userInfo: info,
    clock: clock,
  );

  test('desktop: one refresh serves concurrent callers, then it is cached', () async {
    final flow = FakeGoogleAuthFlow(
      refresh: googleCredentials(
        token: 'ya29.r1',
        expiresAt: clock.now().add(const Duration(hours: 1)),
      ),
    );
    final provider = desktop(flow);
    final tokens = await Future.wait([provider.getToken(), provider.getToken()]);
    expect(tokens.map((t) => t.value), ['ya29.r1', 'ya29.r1']);
    expect(await provider.getToken(), tokens.first);
    expect(flow.calls, ['refresh 1//stored']);
    expect(provider.extraHeaders('demo-project'), {
      'x-goog-user-project': 'demo-project',
    });
  });

  test('refreshes when less than 5 minutes remain, and on forceRefresh', () async {
    final flow = FakeGoogleAuthFlow(
      refresh: googleCredentials(
        token: 'ya29.r',
        expiresAt: clock.now().add(const Duration(hours: 1)),
      ),
    );
    final provider = desktop(flow);
    await provider.getToken();
    clock.advance(const Duration(minutes: 56));
    await provider.getToken();
    await provider.getToken(forceRefresh: true);
    expect(flow.calls, [
      'refresh 1//stored',
      'refresh 1//stored',
      'refresh 1//stored',
    ]);
  });

  test('the token from the sign-in itself is used first', () async {
    final flow = FakeGoogleAuthFlow();
    final initial = AccessToken('ya29.fresh', clock.now().add(const Duration(hours: 1)));
    expect(await desktop(flow, initial: initial).getToken(), initial);
    expect(flow.calls, isEmpty);
  });

  test('desktop: an expired sign-in says to sign in again', () async {
    final flow = FakeGoogleAuthFlow(
      refresh: const GoogleSignInExpired('Google says this sign-in has expired.'),
    );
    await expectLater(
      desktop(flow).getToken(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          allOf(contains(testGoogleEmail), contains('Sign in again'), contains('7 days')),
        ),
      ),
    );
  });

  test('desktop: without a stored refresh token it never opens the browser', () async {
    final flow = FakeGoogleAuthFlow();
    final provider = GoogleAccountTokenProvider(
      email: testGoogleEmail,
      flow: flow,
      userInfo: FakeGoogleUserInfo(),
      clock: clock,
    );
    await expectLater(
      provider.getToken(),
      throwsA(
        isA<AuthException>().having((e) => e.message, 'message', contains('Sign in again')),
      ),
    );
    expect(flow.calls, isEmpty);
  });

  test('browser: no token yet opens the popup for the same account', () async {
    final flow = FakeGoogleAuthFlow(
      canRefresh: false,
      signIns: [googleCredentials(token: 'ya29.popup', refreshToken: null)],
    );
    final info = FakeGoogleUserInfo();
    expect((await browser(flow, info).getToken()).value, 'ya29.popup');
    expect(flow.calls, ['signIn $testGoogleEmail']);
    expect(info.tokens, ['ya29.popup']);
  });

  test('browser: another account in the popup is refused and nothing is cached', () async {
    final flow = FakeGoogleAuthFlow(
      canRefresh: false,
      signIns: [googleCredentials(refreshToken: null)],
    );
    final provider = browser(
      flow,
      FakeGoogleUserInfo(['other@example.com', testGoogleEmail]),
    );
    await expectLater(
      provider.getToken(),
      throwsA(
        isA<AuthException>().having(
          (e) => e.message,
          'message',
          allOf(contains('other@example.com'), contains(testGoogleEmail)),
        ),
      ),
    );
    await provider.getToken();
    expect(flow.calls, ['signIn $testGoogleEmail', 'signIn $testGoogleEmail']);
  });

  test('browser: closing the popup says what to do', () async {
    final flow = FakeGoogleAuthFlow(
      canRefresh: false,
      signIns: const [GoogleSignInCancelled()],
    );
    await expectLater(
      browser(flow, FakeGoogleUserInfo()).getToken(),
      throwsA(
        isA<AuthException>().having((e) => e.message, 'message', contains('closed')),
      ),
    );
  });

  test('browser: unticked permissions are refused', () async {
    final flow = FakeGoogleAuthFlow(
      canRefresh: false,
      signIns: [googleCredentials(refreshToken: null, scopes: const ['openid'])],
    );
    await expectLater(
      browser(flow, FakeGoogleUserInfo()).getToken(),
      throwsA(
        isA<AuthException>().having((e) => e.message, 'message', missingScopesMessage),
      ),
    );
  });
}
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `flutter test test/core/auth/google_user_info_test.dart test/core/auth/google_account_token_provider_test.dart`
Expected: FAIL, because the files don't exist.

- [ ] **Step 4: Write** `lib/core/auth/google_user_info.dart`

```dart
import 'dart:async';
import 'dart:convert';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/utils/redact.dart';
import 'package:http/http.dart' as http;

/// Finds which Google account an access token belongs to.
abstract interface class GoogleUserInfo {
  /// The account's email, in lowercase. Throws [AuthException].
  Future<String> emailOf(AccessToken token);
}

/// Google's OpenID Connect userinfo endpoint (plan Decision 2).
class GoogleUserInfoApi implements GoogleUserInfo {
  GoogleUserInfoApi({required http.Client httpClient}) : _http = httpClient;

  static final Uri endpoint = Uri.parse(
    'https://openidconnect.googleapis.com/v1/userinfo',
  );

  final http.Client _http;

  @override
  Future<String> emailOf(AccessToken token) async {
    final http.Response response;
    try {
      response = await _http
          .get(endpoint, headers: {'Authorization': 'Bearer ${token.value}'})
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const AuthException(
        'Google did not say which account signed in within 20 seconds.',
      );
    } on Exception catch (e) {
      throw AuthException(
        'Network error while reading the signed-in account: ${redact('$e')}',
      );
    }
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      decoded = null;
    }
    final email = decoded is Map<String, Object?> ? decoded['email'] : null;
    if (response.statusCode != 200 || email is! String || email.isEmpty) {
      throw AuthException(
        'Could not read which Google account signed in '
        '(HTTP ${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
    return email.toLowerCase();
  }
}
```

- [ ] **Step 5: Write** `lib/core/auth/google_account_token_provider.dart`

```dart
import 'dart:async';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/google_user_info.dart';
import 'package:fcm_studio/core/utils/clock.dart';

/// Access tokens for one Google account (spec §4.1). On desktop they come
/// from the stored refresh token; in the browser, from Google's popup.
class GoogleAccountTokenProvider implements AccessTokenProvider {
  GoogleAccountTokenProvider({
    required this.email,
    required GoogleAuthFlow flow,
    required GoogleUserInfo userInfo,
    String? refreshToken,
    AccessToken? initialToken,
    this._clock = const SystemClock(),
  }) : _flow = flow,
       _userInfo = userInfo,
       _refreshToken = refreshToken,
       _cached = initialToken;

  static const refreshMargin = Duration(minutes: 5);

  final String email;
  final GoogleAuthFlow _flow;
  final GoogleUserInfo _userInfo;
  final String? _refreshToken;
  final Clock _clock;
  AccessToken? _cached;
  Future<AccessToken>? _inFlight;

  /// The stored sign-in no longer works (plan Decision 6).
  static String expiredMessage(String email) =>
      'The Google sign-in for $email has expired or was revoked. '
      'Use "Sign in again…" in the project menu. '
      '(While the OAuth app is in Testing, Google ends sign-ins after 7 days.)';

  static String notStoredMessage(String email) =>
      'The Google sign-in for $email is not stored on this computer. '
      'Use "Sign in again…" in the project menu.';

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

  /// Quota and billing go to the target project, not the OAuth client's
  /// (spec §4.1).
  @override
  Map<String, String> extraHeaders(String projectId) => {
    'x-goog-user-project': projectId,
  };

  Future<AccessToken> _fetch() async {
    final credentials = await _newCredentials();
    _cached = credentials.accessToken;
    return credentials.accessToken;
  }

  Future<GoogleCredentials> _newCredentials() async {
    final refreshToken = _refreshToken;
    if (refreshToken != null) {
      try {
        return await _flow.refresh(refreshToken);
      } on GoogleSignInExpired {
        throw AuthException(expiredMessage(email));
      }
    }
    if (_flow.canRefresh) {
      throw AuthException(notStoredMessage(email));
    }
    // The browser has no refresh token: ask Google again with a popup.
    final GoogleCredentials credentials;
    try {
      credentials = await _flow.signIn(loginHint: email);
    } on GoogleSignInCancelled {
      throw AuthException(
        'The Google sign-in for $email was closed. Try again and finish '
        'signing in.',
      );
    }
    if (credentials.missingScopes.isNotEmpty) {
      throw const AuthException(missingScopesMessage);
    }
    final signedIn = await _userInfo.emailOf(credentials.accessToken);
    if (signedIn != email) {
      throw AuthException(
        'You signed in as $signedIn, but this project uses $email. '
        'Try again and choose $email.',
      );
    }
    return credentials;
  }
}
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `flutter test test/core/auth/google_user_info_test.dart test/core/auth/google_account_token_provider_test.dart`, then `flutter analyze`.
Expected: PASS, and `No issues found!`.

- [ ] **Step 7: Commit**

```bash
dart format lib test
git add lib/core/auth/google_user_info.dart lib/core/auth/google_account_token_provider.dart test/helpers/fake_google_auth_flow.dart test/core/auth/google_user_info_test.dart test/core/auth/google_account_token_provider_test.dart
git commit -m "feat: get access tokens for a Google account and check which account signed in"
```

---

### Task 5: Google-account projects: credential, stored sign-in, registry

**Files:**
- Create: `lib/features/projects/domain/google_session.dart`
- Modify: `lib/features/projects/domain/project.dart`, `lib/features/projects/data/projects_repository.dart`, `lib/features/projects/data/project_auth_registry.dart`, `lib/core/utils/redact.dart`, `test/helpers/project_fixture.dart`
- Test: `test/features/projects/projects_repository_test.dart`, `test/features/projects/project_auth_registry_test.dart`, `test/core/utils/redact_test.dart`

**Interfaces:**
- Consumes: `GoogleAuthFlow`, `missingScopesMessage` (Task 2); `GoogleUserInfo`, `GoogleUserInfoApi`, `GoogleAccountTokenProvider` (Task 4); test helpers `FakeGoogleAuthFlow`, `FakeGoogleUserInfo`, `googleCredentials`, `testGoogleEmail` (Task 4).
- Produces:
  - `final class GoogleAccountRef extends CredentialRef(String email)`: `secretKey` is `'google:<email>'`, and `toJson` gives `{'kind': 'google_account', 'email': email}`.
  - `class GoogleSession({required String email, required GoogleCredentials credentials, required AccessTokenProvider provider})`, with `GoogleAccountRef get account`.
  - `ProjectsRepository.saveGoogleRefreshToken(GoogleAccountRef, String)` and `Future<String?> readGoogleRefreshToken(GoogleAccountRef)`.
  - `ProjectAuthRegistry({..., GoogleAuthFlow? googleFlow, GoogleUserInfo? googleUserInfo})`, with:
    - `bool get canSignInWithGoogle`;
    - `Future<GoogleSession> signInWithGoogle({String? loginHint, Future<void>? cancel})`;
    - `void registerGoogle(GoogleSession session)`;
    - a `providerFor` that handles `GoogleAccountRef`.
  - Test fixture: `const testGoogleProject = Project(id: 'google-project', displayName: 'Google Project', projectNumber: '987654321098', credential: GoogleAccountRef(testGoogleEmail))`.
  - `redact()` also masks the stored-sign-in JSON key `refreshToken` and bare Google refresh tokens (`1//…`). Spec §3.3 says `redact` removes refresh tokens.

- [ ] **Step 1: Add the fixture.** In `test/helpers/project_fixture.dart`, add `import 'fake_google_auth_flow.dart';` and, below `testProject`:

```dart
const testGoogleProject = Project(
  id: 'google-project',
  displayName: 'Google Project',
  projectNumber: '987654321098',
  credential: GoogleAccountRef(testGoogleEmail),
);
```

- [ ] **Step 2: Write the failing tests.** Add these to `test/features/projects/projects_repository_test.dart`, inside `main()`, after the existing tests. Also add `import '../../helpers/fake_google_auth_flow.dart';` to its imports.

```dart
  test('a Google-account project round-trips', () async {
    await repository.save(testGoogleProject);
    expect(await repository.loadAll(), [testGoogleProject]);
  });

  test('stores a Google refresh token under google:<email>', () async {
    const account = GoogleAccountRef(testGoogleEmail);
    await repository.saveGoogleRefreshToken(account, '1//r');
    expect(await secrets.read('google:dev@example.com'), '{"refreshToken":"1//r"}');
    expect(await repository.readGoogleRefreshToken(account), '1//r');
  });

  test('an unreadable stored sign-in reads as missing', () async {
    await secrets.write('google:dev@example.com', 'not json');
    expect(
      await repository.readGoogleRefreshToken(const GoogleAccountRef(testGoogleEmail)),
      isNull,
    );
  });
```

Add these to `test/features/projects/project_auth_registry_test.dart`, inside `main()`, after the existing tests. Also add `import 'package:fcm_studio/core/auth/google_account_token_provider.dart';`, `import 'package:fcm_studio/core/auth/google_auth_flow.dart';`, `import 'package:fcm_studio/features/projects/domain/project.dart';` and `import '../../helpers/fake_google_auth_flow.dart';` to its imports.

```dart
  group('Google accounts', () {
    ProjectAuthRegistry google(FakeGoogleAuthFlow? flow, [FakeGoogleUserInfo? info]) =>
        ProjectAuthRegistry(
          repository: repository,
          httpClient: MockClient((_) async => http.Response('unused', 500)),
          googleFlow: flow,
          googleUserInfo: info ?? FakeGoogleUserInfo(),
        );

    test('signs in, checks permissions and finds the account', () async {
      final flow = FakeGoogleAuthFlow();
      final session = await google(flow).signInWithGoogle();
      expect(session.email, testGoogleEmail);
      expect(session.account, const GoogleAccountRef(testGoogleEmail));
      expect(session.credentials.refreshToken, '1//refresh-1');
      expect(await session.provider.getToken(), googleCredentials().accessToken);
      expect(flow.calls, ['signIn -']);
    });

    test('a sign-in without the Firebase permissions is refused', () async {
      final flow = FakeGoogleAuthFlow(
        signIns: [googleCredentials(scopes: const ['openid'])],
      );
      await expectLater(
        google(flow).signInWithGoogle(),
        throwsA(
          isA<AuthException>().having((e) => e.message, 'message', missingScopesMessage),
        ),
      );
    });

    test('without the OAuth set-up, Google sign-in is unavailable', () async {
      final registry = google(null);
      expect(registry.canSignInWithGoogle, isFalse);
      await expectLater(
        registry.signInWithGoogle(),
        throwsA(
          isA<AuthException>().having(
            (e) => e.message,
            'message',
            contains('docs/oauth-setup.md'),
          ),
        ),
      );
      await expectLater(
        registry.providerFor(testGoogleProject),
        throwsA(
          isA<AuthException>().having((e) => e.message, 'message', contains('not set up')),
        ),
      );
    });

    test('desktop: loads the stored refresh token once and refreshes with it', () async {
      await repository.saveGoogleRefreshToken(
        const GoogleAccountRef(testGoogleEmail),
        '1//stored',
      );
      final flow = FakeGoogleAuthFlow();
      final registry = google(flow);
      final provider = await registry.providerFor(testGoogleProject);
      expect(provider, isA<GoogleAccountTokenProvider>());
      expect(await registry.providerFor(testGoogleProject), same(provider));
      await provider.getToken();
      expect(flow.calls, ['refresh 1//stored']);
    });

    test('desktop: a missing stored sign-in asks to sign in again', () async {
      await expectLater(
        google(FakeGoogleAuthFlow()).providerFor(testGoogleProject),
        throwsA(
          isA<AuthException>().having((e) => e.message, 'message', contains('Sign in again')),
        ),
      );
    });

    test('browser: nothing is stored; the popup supplies tokens', () async {
      final flow = FakeGoogleAuthFlow(
        canRefresh: false,
        signIns: [googleCredentials(refreshToken: null)],
      );
      final provider = await google(flow).providerFor(testGoogleProject);
      await provider.getToken();
      expect(flow.calls, ['signIn $testGoogleEmail']);
    });

    test('registerGoogle replaces the cached provider for that account', () async {
      await repository.saveGoogleRefreshToken(
        const GoogleAccountRef(testGoogleEmail),
        '1//stored',
      );
      final registry = google(FakeGoogleAuthFlow());
      final old = await registry.providerFor(testGoogleProject);
      final session = await registry.signInWithGoogle();
      registry.registerGoogle(session);
      final current = await registry.providerFor(testGoogleProject);
      expect(current, same(session.provider));
      expect(current, isNot(same(old)));
    });
  });
```

Add this test to `test/core/utils/redact_test.dart`, inside the `redact` group:

```dart
    test('removes Google refresh tokens, in the stored JSON and bare', () {
      expect(
        redact('{"refreshToken":"1//0gAbCdEfGhIjKlMnOpQrStUv"}'),
        '{"refreshToken":"[REDACTED]"}',
      );
      expect(
        redact('token 1//0gAbCdEfGhIjKlMnOpQrStUvWx failed'),
        'token 1//[REDACTED] failed',
      );
    });
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `flutter test test/features/projects test/core/utils/redact_test.dart`
Expected: FAIL, because `GoogleAccountRef`, the repository methods and the registry methods don't exist, and `redact` keeps refresh tokens.

- [ ] **Step 4: Add `GoogleAccountRef`** to `lib/features/projects/domain/project.dart`.
  - Change the doc comment on `CredentialRef` to `/// Which credential a project uses: a service account key or a Google account (spec §4.2).`
  - Add the new kind to `fromJson`:

```dart
  static CredentialRef fromJson(Map<String, Object?> json) =>
      switch (json['kind']) {
        'service_account' => ServiceAccountRef(json['clientEmail']! as String),
        'google_account' => GoogleAccountRef(json['email']! as String),
        final kind => throw FormatException('Unknown credential kind: $kind'),
      };
```

  Then add this class after `ServiceAccountRef`:

```dart
final class GoogleAccountRef extends CredentialRef {
  const GoogleAccountRef(this.email);

  /// Lowercase (plan Decision 13).
  final String email;

  @override
  String get secretKey => 'google:$email';

  @override
  Map<String, Object?> toJson() => {'kind': 'google_account', 'email': email};

  @override
  List<Object?> get props => [email];
}
```

- [ ] **Step 5: Write** `lib/features/projects/domain/google_session.dart`

```dart
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';

/// A finished Google sign-in: whose it is, what Google gave back, and the
/// token provider that already holds the new access token.
class GoogleSession {
  const GoogleSession({
    required this.email,
    required this.credentials,
    required this.provider,
  });

  final String email;
  final GoogleCredentials credentials;
  final AccessTokenProvider provider;

  GoogleAccountRef get account => GoogleAccountRef(email);

  @override
  String toString() => 'GoogleSession($email)';
}
```

- [ ] **Step 6: Store the refresh token.** In `lib/features/projects/data/projects_repository.dart`, add `import 'dart:convert';`, then add these after `readServiceAccountKey`:

```dart
  /// Desktop only: the browser gets no refresh token (plan Decision 11).
  Future<void> saveGoogleRefreshToken(
    GoogleAccountRef account,
    String refreshToken,
  ) => _secrets.write(
    account.secretKey,
    jsonEncode({'refreshToken': refreshToken}),
  );

  Future<String?> readGoogleRefreshToken(GoogleAccountRef account) async {
    final raw = await _secrets.read(account.secretKey);
    if (raw == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      final token = decoded is Map<String, Object?>
          ? decoded['refreshToken']
          : null;
      return token is String && token.isNotEmpty ? token : null;
    } on FormatException {
      return null;
    }
  }
```

- [ ] **Step 6b: Redact refresh tokens.** In `lib/core/utils/redact.dart`:
  - Add `refreshToken` to the JSON field names.
  - Add a bare-token pattern.
  - Apply the bare-token pattern after the access-token one.

```dart
final _secretJsonField = RegExp(
  r'("(?:private_key|refresh_token|refreshToken|access_token|assertion)"\s*:\s*")[^"]*(")',
);
final _googleRefreshToken = RegExp(r'\b1//[A-Za-z0-9_-]{20,}');
```

  In `redact`, after `.replaceAll(_googleAccessToken, 'ya29.[REDACTED]')`, add `.replaceAll(_googleRefreshToken, '1//[REDACTED]')`.

- [ ] **Step 7: Replace** `lib/features/projects/data/project_auth_registry.dart` with:

```dart
import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/core/auth/google_account_token_provider.dart';
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/google_user_info.dart';
import 'package:fcm_studio/core/auth/service_account_key.dart';
import 'package:fcm_studio/core/auth/service_account_token_provider.dart';
import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/features/projects/data/projects_repository.dart';
import 'package:fcm_studio/features/projects/domain/access_token_resolver.dart';
import 'package:fcm_studio/features/projects/domain/google_session.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:http/http.dart' as http;

/// Keeps one token provider per credential, so tokens are cached across sends.
class ProjectAuthRegistry implements AccessTokenResolver {
  ProjectAuthRegistry({
    required this._repository,
    required http.Client httpClient,
    this._clock = const SystemClock(),
    this._googleFlow,
    GoogleUserInfo? googleUserInfo,
  }) : _http = httpClient,
       _userInfo = googleUserInfo ?? GoogleUserInfoApi(httpClient: httpClient);

  static const _notSetUp =
      'Google sign-in is not set up in this copy of FCM Studio. '
      'See docs/oauth-setup.md.';

  final ProjectsRepository _repository;
  final http.Client _http;
  final Clock _clock;
  final GoogleAuthFlow? _googleFlow;
  final GoogleUserInfo _userInfo;
  final Map<String, AccessTokenProvider> _providers = {};

  /// False when `config/oauth.json` has no client for this platform.
  bool get canSignInWithGoogle => _googleFlow != null;

  /// Creates (or replaces) the provider for [key]'s service account.
  AccessTokenProvider registerKey(ServiceAccountKey key) {
    final provider = ServiceAccountTokenProvider(
      key: key,
      httpClient: _http,
      clock: _clock,
    );
    _providers[ServiceAccountRef(key.clientEmail).secretKey] = provider;
    return provider;
  }

  /// Signs in to Google, checks the granted permissions and finds the account
  /// (plan Decisions 2–3). Nothing is stored or registered yet. Throws
  /// [GoogleSignInCancelled] or [AuthException].
  Future<GoogleSession> signInWithGoogle({
    String? loginHint,
    Future<void>? cancel,
  }) async {
    final flow = _googleFlow;
    if (flow == null) {
      throw const AuthException(_notSetUp);
    }
    final credentials = await flow.signIn(loginHint: loginHint, cancel: cancel);
    if (credentials.missingScopes.isNotEmpty) {
      throw const AuthException(missingScopesMessage);
    }
    final email = await _userInfo.emailOf(credentials.accessToken);
    return GoogleSession(
      email: email,
      credentials: credentials,
      provider: GoogleAccountTokenProvider(
        email: email,
        flow: flow,
        userInfo: _userInfo,
        refreshToken: credentials.refreshToken,
        initialToken: credentials.accessToken,
        clock: _clock,
      ),
    );
  }

  /// From now on, [session]'s provider serves its account.
  void registerGoogle(GoogleSession session) =>
      _providers[session.account.secretKey] = session.provider;

  void forget(CredentialRef credential) =>
      _providers.remove(credential.secretKey);

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
      case GoogleAccountRef(:final email):
        final flow = _googleFlow;
        if (flow == null) {
          throw AuthException(
            '$_notSetUp Projects that use $email cannot send until then.',
          );
        }
        final refreshToken = flow.canRefresh
            ? await _repository.readGoogleRefreshToken(credential)
            : null;
        if (flow.canRefresh && refreshToken == null) {
          throw AuthException(GoogleAccountTokenProvider.notStoredMessage(email));
        }
        final provider = GoogleAccountTokenProvider(
          email: email,
          flow: flow,
          userInfo: _userInfo,
          refreshToken: refreshToken,
          clock: _clock,
        );
        _providers[credential.secretKey] = provider;
        return provider;
    }
  }
}
```

- [ ] **Step 8: Run the tests and confirm they pass**

Run: `flutter test test/features/projects test/core/utils/redact_test.dart`, then `flutter test`, then `flutter analyze`.
Expected: everything passes, and `No issues found!`. The full run matters because adding a `CredentialRef` subclass can break any exhaustive switch elsewhere. The only one in `lib` today is in the registry.

- [ ] **Step 9: Commit**

```bash
dart format lib test
git add lib/features/projects/domain/project.dart lib/features/projects/domain/google_session.dart lib/features/projects/data/projects_repository.dart lib/features/projects/data/project_auth_registry.dart lib/core/utils/redact.dart test/helpers/project_fixture.dart test/features/projects/projects_repository_test.dart test/features/projects/project_auth_registry_test.dart test/core/utils/redact_test.dart
git commit -m "feat: projects can use a Google account, with the sign-in stored on desktop"
```

---

### Task 6: List the account's Firebase projects

**Files:**
- Modify: `lib/core/firebase/firebase_projects_api.dart`
- Test: `test/core/firebase/firebase_projects_api_test.dart`

**Interfaces:**
- Consumes: `AccessTokenProvider`; `FcmError.fromResponse` (`lib/core/fcm/fcm_error.dart`); `redact`.
- Produces:
  - `static final Uri FirebaseProjectsApi.listUri`.
  - `Future<List<FirebaseProjectInfo>> listProjects(AccessTokenProvider auth)`. It follows pages, up to 50, and returns the projects sorted by display name. It sends no `x-goog-user-project`. It throws `FirebaseApiException`.

- [ ] **Step 1: Write the failing tests.** Add these to `test/core/firebase/firebase_projects_api_test.dart`, inside `main()`:

```dart
  group('listProjects', () {
    Map<String, Object?> listed(String id, String name, String number) => {
      'projectId': id,
      'displayName': name,
      'projectNumber': number,
    };

    test('follows every page, sorts by name, and sends no quota project', () async {
      final requests = <http.Request>[];
      final api = FirebaseProjectsApi(
        httpClient: MockClient((request) async {
          requests.add(request);
          final second = request.url.queryParameters['pageToken'] == 'p2';
          return http.Response(
            jsonEncode(
              second
                  ? {
                      'results': [listed('alpha-app', 'Alpha', '111')],
                    }
                  : {
                      'results': [listed('zulu-app', 'Zulu', '999')],
                      'nextPageToken': 'p2',
                    },
            ),
            200,
          );
        }),
      );

      final projects = await api.listProjects(
        FakeTokenProvider(headers: {'x-goog-user-project': 'must-not-be-sent'}),
      );

      expect(projects.map((p) => p.projectId), ['alpha-app', 'zulu-app']);
      expect(
        projects.first,
        const FirebaseProjectInfo(
          projectId: 'alpha-app',
          displayName: 'Alpha',
          projectNumber: '111',
        ),
      );
      expect(requests, hasLength(2));
      expect(requests.first.url.path, '/v1beta1/projects');
      expect(requests.first.url.queryParameters['pageSize'], '100');
      expect(requests.first.headers['Authorization'], 'Bearer token-1');
      expect(requests.first.headers.containsKey('x-goog-user-project'), isFalse);
    });

    test('an account without Firebase projects gets an empty list', () async {
      final api = FirebaseProjectsApi(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      expect(await api.listProjects(FakeTokenProvider()), isEmpty);
    });

    test('a project without a name shows its ID; items without an ID are skipped', () async {
      final api = FirebaseProjectsApi(
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'results': [
                {'projectId': 'bare-app'},
                {'displayName': 'No ID'},
              ],
            }),
            200,
          ),
        ),
      );
      expect(await api.listProjects(FakeTokenProvider()), [
        const FirebaseProjectInfo(projectId: 'bare-app', displayName: 'bare-app'),
      ]);
    });

    test('a disabled Firebase Management API says where to enable it', () async {
      final api = FirebaseProjectsApi(
        httpClient: MockClient(
          (_) async => http.Response(
            '{"error":{"code":403,"message":"Firebase Management API has not been used '
            'in project 42 before or it is disabled.","status":"PERMISSION_DENIED",'
            '"details":[{"@type":"type.googleapis.com/google.rpc.ErrorInfo",'
            '"reason":"SERVICE_DISABLED"}]}}',
            403,
          ),
        ),
      );
      await expectLater(
        api.listProjects(FakeTokenProvider()),
        throwsA(
          isA<FirebaseApiException>().having(
            (e) => e.message,
            'message',
            allOf(contains('OAuth client'), contains('docs/oauth-setup.md')),
          ),
        ),
      );
    });

    test('other errors name the HTTP status', () async {
      final api = FirebaseProjectsApi(
        httpClient: MockClient((_) async => http.Response('oops', 500)),
      );
      await expectLater(
        api.listProjects(FakeTokenProvider()),
        throwsA(
          isA<FirebaseApiException>().having((e) => e.message, 'message', contains('HTTP 500')),
        ),
      );
    });

    test('a page token that never ends stops after 50 pages', () async {
      var calls = 0;
      final api = FirebaseProjectsApi(
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('{"results":[],"nextPageToken":"again"}', 200);
        }),
      );
      expect(await api.listProjects(FakeTokenProvider()), isEmpty);
      expect(calls, 50);
    });
  });
```

- [ ] **Step 2: Run them and confirm they fail**

Run: `flutter test test/core/firebase/firebase_projects_api_test.dart`
Expected: FAIL, because `listProjects` isn't defined.

- [ ] **Step 3: Implement it.** In `lib/core/firebase/firebase_projects_api.dart`, add `import 'package:fcm_studio/core/fcm/fcm_error.dart';` and `import 'package:fcm_studio/core/utils/redact.dart';`. Then add these members to `FirebaseProjectsApi`, after `getProject`:

```dart
  static final Uri listUri = Uri.parse(
    'https://firebase.googleapis.com/v1beta1/projects',
  );
  static const _maxPages = 50;

  /// Every Firebase project the account can see, following pages (spec §4.2),
  /// sorted by name. No `x-goog-user-project` header is sent, because no
  /// project is chosen yet (plan Decision 8). Throws [FirebaseApiException].
  Future<List<FirebaseProjectInfo>> listProjects(
    AccessTokenProvider auth,
  ) async {
    final token = await auth.getToken();
    final projects = <FirebaseProjectInfo>[];
    String? pageToken;
    for (var page = 0; page < _maxPages; page++) {
      final response = await _getListPage(token, pageToken);
      final json = _decodeObject(response.body);
      final results = json?['results'];
      if (results is List<Object?>) {
        for (final item in results.whereType<Map<String, Object?>>()) {
          final info = _listedProject(item);
          if (info != null) {
            projects.add(info);
          }
        }
      }
      final next = json?['nextPageToken'];
      if (next is! String || next.isEmpty) {
        break;
      }
      pageToken = next;
    }
    projects.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return projects;
  }

  Future<http.Response> _getListPage(
    AccessToken token,
    String? pageToken,
  ) async {
    final http.Response response;
    try {
      response = await _http
          .get(
            listUri.replace(
              queryParameters: {'pageSize': '100', 'pageToken': ?pageToken},
            ),
            headers: {'Authorization': 'Bearer ${token.value}'},
          )
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw const FirebaseApiException(
        'The Firebase Management API did not answer within 20 seconds.',
      );
    } on Exception catch (e) {
      throw FirebaseApiException(
        'Network error while listing your Firebase projects: ${redact('$e')}',
      );
    }
    if (response.statusCode != 200) {
      throw FirebaseApiException(_describeListError(response));
    }
    return response;
  }

  static FirebaseProjectInfo? _listedProject(Map<String, Object?> item) {
    final id = item['projectId'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    final name = item['displayName'];
    final number = item['projectNumber'];
    return FirebaseProjectInfo(
      projectId: id,
      displayName: name is String && name.isNotEmpty ? name : id,
      projectNumber: number is String ? number : null,
    );
  }

  static Map<String, Object?>? _decodeObject(String body) {
    try {
      final decoded = jsonDecode(body);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }

  static String _describeListError(http.Response response) {
    final error = FcmError.fromResponse(response.statusCode, response.body);
    final detail = error.message == null ? '' : ': ${error.message}';
    if (error.reason == 'SERVICE_DISABLED') {
      return 'The Firebase Management API is not enabled in the Google Cloud '
          "project that owns FCM Studio's OAuth client. Enable it there (see "
          'docs/oauth-setup.md), wait a few minutes, then try again.';
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      return 'Google refused to list your Firebase projects '
          '(HTTP ${response.statusCode}$detail).';
    }
    return 'Listing your Firebase projects failed '
        '(HTTP ${response.statusCode}$detail).';
  }
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `flutter test test/core/firebase/firebase_projects_api_test.dart`, then `flutter analyze`.
Expected: PASS, and `No issues found!`.

- [ ] **Step 5: Commit**

```bash
dart format lib test
git add lib/core/firebase/firebase_projects_api.dart test/core/firebase/firebase_projects_api_test.dart
git commit -m "feat: list every Firebase project a Google account can see"
```

---
### Task 7: `ProjectsCubit`: sign in with Google, add projects, sign in again

**Files:**
- Modify: `lib/features/projects/cubit/projects_cubit.dart`, `test/helpers/fake_google.dart`
- Test: `test/features/projects/projects_cubit_test.dart`

**Interfaces:**
- Consumes:
  - `ProjectAuthRegistry.canSignInWithGoogle`, `signInWithGoogle`, `registerGoogle` and `forget` (Task 5);
  - `GoogleSession`, `GoogleAccountRef` and `ProjectsRepository.saveGoogleRefreshToken` (Task 5);
  - `FirebaseProjectsApi.listProjects` (Task 6);
  - `GoogleSignInCancelled` (Task 2);
  - test helpers from Task 4.
- Produces:
  - `sealed class GoogleSignInResult` with three cases:
    - `GoogleProjectsFound(GoogleSession session, {required List<FirebaseProjectInfo> projects})`, with getter `email`;
    - `GoogleSignInFailed(String message)`;
    - `GoogleSignInStopped()`.
  - On `ProjectsCubit`:
    - `bool get canSignInWithGoogle`;
    - `Future<GoogleSignInResult> signInWithGoogle({Future<void>? cancel})`;
    - `Future<String?> addGoogleProjects(GoogleSession session, List<FirebaseProjectInfo> picked)`, which returns null on success or a message;
    - `Future<String?> signInAgain(GoogleAccountRef account, {Future<void>? cancel})`, which returns null on success or a message. A cancel gives `'Sign-in was cancelled.'`.
  - Test helper: `fakeGoogle(..., List<Map<String, Object?>> firebaseProjects = const [listedTestProject])` answers `GET /v1beta1/projects`, plus `const listedTestProject`.

- [ ] **Step 1: Teach the fake Google client the project list.** In `test/helpers/fake_google.dart`, add the constant above `fakeGoogle`:

```dart
/// What the fake Firebase Management API lists by default.
const listedTestProject = <String, Object?>{
  'projectId': testProjectId,
  'projectNumber': testProjectNumber,
  'displayName': 'Demo Project',
};
```

  Then add the parameter `List<Map<String, Object?>> firebaseProjects = const [listedTestProject],` to `fakeGoogle`. Make this the first statement in the `'firebase.googleapis.com'` case:

```dart
        if (request.url.path == '/v1beta1/projects') {
          return http.Response(jsonEncode({'results': firebaseProjects}), 200);
        }
```

- [ ] **Step 2: Write the failing tests.** Add to the imports of `test/features/projects/projects_cubit_test.dart`:

```dart
import 'package:fcm_studio/core/auth/google_auth_flow.dart';

import '../../helpers/fake_google_auth_flow.dart';
```

  Inside `main()`, after `buildCubit`, add:

```dart
  late ProjectAuthRegistry registry;

  ProjectsCubit buildGoogleCubit(
    FakeGoogleAuthFlow flow, {
    List<String> emails = const [testGoogleEmail],
    List<Map<String, Object?>> listed = const [listedTestProject],
  }) {
    final client = fakeGoogle(firebaseProjects: listed);
    registry = ProjectAuthRegistry(
      repository: repository,
      httpClient: client,
      googleFlow: flow,
      googleUserInfo: FakeGoogleUserInfo(emails),
    );
    return ProjectsCubit(
      repository: repository,
      authRegistry: registry,
      firebaseApi: FirebaseProjectsApi(httpClient: client),
    );
  }

  const googleDemo = Project(
    id: testProjectId,
    displayName: 'Demo Project',
    projectNumber: testProjectNumber,
    credential: GoogleAccountRef(testGoogleEmail),
  );
```

  Then add this group at the end of `main()`:

```dart
  group('Google sign-in', () {
    test('Google sign-in is offered only when it is set up', () {
      expect(buildCubit().canSignInWithGoogle, isFalse);
      expect(buildGoogleCubit(FakeGoogleAuthFlow()).canSignInWithGoogle, isTrue);
    });

    test('lists the Firebase projects of the account and saves nothing yet', () async {
      final cubit = buildGoogleCubit(FakeGoogleAuthFlow());
      await cubit.load();
      final result = await cubit.signInWithGoogle();
      expect(
        result,
        isA<GoogleProjectsFound>()
            .having((r) => r.email, 'email', testGoogleEmail)
            .having((r) => r.projects, 'projects', [
              const FirebaseProjectInfo(
                projectId: testProjectId,
                displayName: 'Demo Project',
                projectNumber: testProjectNumber,
              ),
            ]),
      );
      expect(await repository.loadAll(), isEmpty);
      expect(await secrets.read('google:$testGoogleEmail'), isNull);
    });

    test('a cancelled sign-in stops quietly', () async {
      final cubit = buildGoogleCubit(
        FakeGoogleAuthFlow(signIns: const [GoogleSignInCancelled()]),
      );
      expect(await cubit.signInWithGoogle(), isA<GoogleSignInStopped>());
    });

    test('a sign-in without the Firebase permissions is refused', () async {
      final cubit = buildGoogleCubit(
        FakeGoogleAuthFlow(signIns: [googleCredentials(scopes: const ['openid'])]),
      );
      expect(
        await cubit.signInWithGoogle(),
        isA<GoogleSignInFailed>().having((r) => r.message, 'message', missingScopesMessage),
      );
      expect(await secrets.read('google:$testGoogleEmail'), isNull);
    });

    test('adding the picked project saves the sign-in, selects it and serves its tokens', () async {
      final cubit = buildGoogleCubit(FakeGoogleAuthFlow());
      await cubit.load();
      final found = await cubit.signInWithGoogle() as GoogleProjectsFound;
      expect(await cubit.addGoogleProjects(found.session, found.projects), isNull);
      expect(cubit.state.selected, googleDemo);
      expect(await repository.loadAll(), [googleDemo]);
      expect(await repository.readSelectedProjectId(), testProjectId);
      expect(
        await secrets.read('google:$testGoogleEmail'),
        '{"refreshToken":"1//refresh-1"}',
      );
      expect(await registry.providerFor(googleDemo), same(found.session.provider));
    });

    test('picking a project added with a key switches it to the account', () async {
      final cubit = buildGoogleCubit(FakeGoogleAuthFlow());
      await cubit.load();
      await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);
      await cubit.setEnvironment(testProjectId, ProjectEnvironment.prod);
      final found = await cubit.signInWithGoogle() as GoogleProjectsFound;
      expect(await cubit.addGoogleProjects(found.session, found.projects), isNull);
      expect(
        cubit.state.selected,
        googleDemo.copyWith(environment: ProjectEnvironment.prod),
      );
      expect(await secrets.read('sa:$testClientEmail'), isNull);
    });

    test('picking several keeps the current selection', () async {
      final cubit = buildGoogleCubit(
        FakeGoogleAuthFlow(),
        listed: const [
          {'projectId': 'alpha-app', 'displayName': 'Alpha'},
          {'projectId': 'beta-app', 'displayName': 'Beta'},
        ],
      );
      await cubit.load();
      await cubit.addFromServiceAccount(serviceAccountJson(), persistKey: true);
      final found = await cubit.signInWithGoogle() as GoogleProjectsFound;
      await cubit.addGoogleProjects(found.session, found.projects);
      expect(cubit.state.projects.map((p) => p.id), [
        'alpha-app',
        'beta-app',
        testProjectId,
      ]);
      expect(cubit.state.selectedId, testProjectId);
    });

    test('picking several with nothing selected selects the first by name', () async {
      final cubit = buildGoogleCubit(
        FakeGoogleAuthFlow(),
        listed: const [
          {'projectId': 'beta-app', 'displayName': 'Beta'},
          {'projectId': 'alpha-app', 'displayName': 'Alpha'},
        ],
      );
      await cubit.load();
      final found = await cubit.signInWithGoogle() as GoogleProjectsFound;
      await cubit.addGoogleProjects(found.session, found.projects);
      expect(cubit.state.selectedId, 'alpha-app');
    });

    test('signing in again stores the new sign-in and uses it', () async {
      final flow = FakeGoogleAuthFlow(
        signIns: [
          googleCredentials(),
          googleCredentials(token: 'ya29.google-2', refreshToken: '1//refresh-2'),
        ],
      );
      final cubit = buildGoogleCubit(flow);
      await cubit.load();
      final found = await cubit.signInWithGoogle() as GoogleProjectsFound;
      await cubit.addGoogleProjects(found.session, found.projects);

      expect(await cubit.signInAgain(const GoogleAccountRef(testGoogleEmail)), isNull);
      expect(flow.calls, ['signIn -', 'signIn $testGoogleEmail']);
      expect(
        await secrets.read('google:$testGoogleEmail'),
        '{"refreshToken":"1//refresh-2"}',
      );
      final provider = await registry.providerFor(googleDemo);
      expect((await provider.getToken()).value, 'ya29.google-2');
    });

    test('signing in again as another account is refused and keeps the old sign-in', () async {
      final cubit = buildGoogleCubit(
        FakeGoogleAuthFlow(),
        emails: const [testGoogleEmail, 'other@example.com'],
      );
      await cubit.load();
      final found = await cubit.signInWithGoogle() as GoogleProjectsFound;
      await cubit.addGoogleProjects(found.session, found.projects);

      final message = await cubit.signInAgain(const GoogleAccountRef(testGoogleEmail));
      expect(message, allOf(contains('other@example.com'), contains(testGoogleEmail)));
      expect(
        await secrets.read('google:$testGoogleEmail'),
        '{"refreshToken":"1//refresh-1"}',
      );
    });

    test('a cancelled sign-in-again says so', () async {
      final cubit = buildGoogleCubit(
        FakeGoogleAuthFlow(signIns: const [GoogleSignInCancelled()]),
      );
      expect(
        await cubit.signInAgain(const GoogleAccountRef(testGoogleEmail)),
        'Sign-in was cancelled.',
      );
    });
  });
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `flutter test test/features/projects/projects_cubit_test.dart`
Expected: FAIL, because `canSignInWithGoogle`, `signInWithGoogle`, `GoogleProjectsFound` and the rest don't exist.

- [ ] **Step 4: Implement them** in `lib/features/projects/cubit/projects_cubit.dart`.

  First, add these imports:

```dart
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/features/projects/domain/google_session.dart';
```

  Next, add the result types below `AddProjectFailure`:

```dart
sealed class GoogleSignInResult {
  const GoogleSignInResult();
}

/// Signed in; these are the account's Firebase projects. Nothing is saved yet.
final class GoogleProjectsFound extends GoogleSignInResult {
  const GoogleProjectsFound(this.session, {required this.projects});

  final GoogleSession session;
  final List<FirebaseProjectInfo> projects;

  String get email => session.email;
}

final class GoogleSignInFailed extends GoogleSignInResult {
  const GoogleSignInFailed(this.message);

  final String message;
}

/// The user cancelled; there is nothing to report.
final class GoogleSignInStopped extends GoogleSignInResult {
  const GoogleSignInStopped();
}
```

  Then add these members to `ProjectsCubit`, after `addFromServiceAccount`:

```dart
  /// False when `config/oauth.json` has no client for this platform.
  bool get canSignInWithGoogle => _authRegistry.canSignInWithGoogle;

  /// Signs in to Google and lists the account's Firebase projects (spec §4.2).
  /// Nothing is saved until [addGoogleProjects].
  Future<GoogleSignInResult> signInWithGoogle({Future<void>? cancel}) async {
    final GoogleSession session;
    try {
      session = await _authRegistry.signInWithGoogle(cancel: cancel);
    } on GoogleSignInCancelled {
      return const GoogleSignInStopped();
    } on AuthException catch (e) {
      return GoogleSignInFailed(e.message);
    } catch (e) {
      return GoogleSignInFailed('Google sign-in failed: ${redact('$e')}');
    }
    try {
      final projects = await _firebaseApi.listProjects(session.provider);
      return GoogleProjectsFound(session, projects: projects);
    } on FirebaseApiException catch (e) {
      return GoogleSignInFailed(e.message);
    } on AuthException catch (e) {
      return GoogleSignInFailed(e.message);
    } catch (e) {
      return GoogleSignInFailed(
        'Could not list your Firebase projects: ${redact('$e')}',
      );
    }
  }

  /// Saves the account's sign-in and adds the picked projects. A project that
  /// is already added switches to the account and keeps its environment
  /// (plan Decision 7). Returns null on success, or what went wrong.
  Future<String?> addGoogleProjects(
    GoogleSession session,
    List<FirebaseProjectInfo> picked,
  ) async {
    if (picked.isEmpty) {
      return null;
    }
    final credential = session.account;
    final byId = {for (final project in state.projects) project.id: project};
    final added = [
      for (final info in picked)
        Project(
          id: info.projectId,
          displayName: info.displayName,
          projectNumber:
              info.projectNumber ?? byId[info.projectId]?.projectNumber,
          environment:
              byId[info.projectId]?.environment ?? ProjectEnvironment.dev,
          credential: credential,
        ),
    ];
    final replaced = <CredentialRef>{};
    for (final project in added) {
      final old = byId[project.id];
      if (old != null && old.credential != credential) {
        replaced.add(old.credential);
      }
    }
    final addedIds = {for (final project in added) project.id};
    final projects = [
      ...state.projects.where((p) => !addedIds.contains(p.id)),
      ...added,
    ]..sort(_byName);
    final selectedId = _selectionAfterAdding(added, projects);

    try {
      final refreshToken = session.credentials.refreshToken;
      if (refreshToken != null) {
        await _repository.saveGoogleRefreshToken(credential, refreshToken);
      }
      for (final project in added) {
        await _repository.save(project);
      }
      for (final old in replaced) {
        await _repository.deleteSecretIfUnused(old);
      }
      await _repository.writeSelectedProjectId(selectedId);
    } catch (e) {
      return 'Could not save the projects: ${redact('$e')}';
    }

    _authRegistry.registerGoogle(session);
    for (final old in replaced) {
      if (!projects.any((p) => p.credential == old)) {
        _authRegistry.forget(old);
      }
    }
    emit(
      state.copyWith(
        status: ProjectsStatus.ready,
        projects: projects,
        selectedId: () => selectedId,
      ),
    );
    return null;
  }

  /// Signs in to [account] again, e.g. after its sign-in expired (plan
  /// Decision 6). Another account is refused, and the old sign-in stays.
  /// Returns null on success, or what went wrong.
  Future<String?> signInAgain(
    GoogleAccountRef account, {
    Future<void>? cancel,
  }) async {
    final GoogleSession session;
    try {
      session = await _authRegistry.signInWithGoogle(
        loginHint: account.email,
        cancel: cancel,
      );
    } on GoogleSignInCancelled {
      return 'Sign-in was cancelled.';
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'Google sign-in failed: ${redact('$e')}';
    }
    if (session.account != account) {
      return 'You signed in as ${session.email}, but these projects use '
          '${account.email}. Sign in again and choose ${account.email}.';
    }
    final refreshToken = session.credentials.refreshToken;
    if (refreshToken != null) {
      try {
        await _repository.saveGoogleRefreshToken(account, refreshToken);
      } catch (e) {
        return 'Could not save the sign-in: ${redact('$e')}';
      }
    }
    _authRegistry.registerGoogle(session);
    return null;
  }

  /// Plan Decision 12.
  String? _selectionAfterAdding(List<Project> added, List<Project> projects) {
    if (added.length == 1) {
      return added.single.id;
    }
    final current = state.selectedId;
    if (current != null && projects.any((p) => p.id == current)) {
      return current;
    }
    return ([...added]..sort(_byName)).first.id;
  }
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/features/projects`, then `flutter analyze`.
Expected: PASS, and `No issues found!`.

- [ ] **Step 6: Commit**

```bash
dart format lib test
git add lib/features/projects/cubit/projects_cubit.dart test/helpers/fake_google.dart test/features/projects/projects_cubit_test.dart
git commit -m "feat: add Firebase projects by signing in with Google, and sign in again"
```

---

### Task 8: Error explanations for Google accounts

**Files:**
- Modify: `lib/core/fcm/fcm_error_explainer.dart`, `lib/features/composer/data/message_sender.dart`, `test/helpers/fcm_fixtures.dart`
- Test: `test/core/fcm/fcm_error_explainer_test.dart`, `test/features/composer/message_sender_test.dart`

**Interfaces:**
- Consumes: `GoogleAccountRef` (Task 5); `testGoogleProject` (Task 5 fixture).
- Produces:
  - `FcmErrorExplainer.explain(FcmError error, {required String projectId, bool googleAccount = false})`. It explains the reasons `USER_PROJECT_DENIED` and `ACCESS_TOKEN_SCOPE_INSUFFICIENT`, and for Google accounts it gives its own advice on auth failures, 401, 403 and 404.
  - `MessageSender` passes `googleAccount: project.credential is GoogleAccountRef`.
  - Fixtures `userProjectDeniedBody` and `scopeInsufficientBody`.

- [ ] **Step 1: Add the fixtures** to `test/helpers/fcm_fixtures.dart`:

```dart
const userProjectDeniedBody =
    '{"error":{"code":403,"message":"Caller does not have required permission to use '
    'project demo-project. Grant the caller the roles/serviceusage.serviceUsageConsumer '
    'role.","status":"PERMISSION_DENIED","details":[{"@type":'
    '"type.googleapis.com/google.rpc.ErrorInfo","reason":"USER_PROJECT_DENIED",'
    '"domain":"googleapis.com"}]}}';

const scopeInsufficientBody =
    '{"error":{"code":403,"message":"Request had insufficient authentication scopes.",'
    '"status":"PERMISSION_DENIED","details":[{"@type":'
    '"type.googleapis.com/google.rpc.ErrorInfo","reason":"ACCESS_TOKEN_SCOPE_INSUFFICIENT",'
    '"domain":"googleapis.com"}]}}';
```

- [ ] **Step 2: Write the failing tests.** Add these to `test/core/fcm/fcm_error_explainer_test.dart`, inside `main()` after `explain`:

```dart
  ErrorExplanation explainGoogle(FcmError error) =>
      explainer.explain(error, projectId: 'demo-project', googleAccount: true);

  test('USER_PROJECT_DENIED names the Service Usage Consumer role', () {
    final e = explainGoogle(FcmError.fromResponse(403, userProjectDeniedBody));
    expect(e.action, contains('Service Usage Consumer'));
    expect(e.link?.host, 'console.cloud.google.com');
  });

  test('a missing scope asks to sign in again and allow every permission', () {
    final e = explainGoogle(FcmError.fromResponse(403, scopeInsufficientBody));
    expect(e.action, allOf(contains('Sign in again'), contains('every permission')));
  });

  test('Google accounts: an auth failure points to Sign in again', () {
    final e = explainGoogle(
      const FcmError(transport: FcmTransportError.auth, message: 'expired'),
    );
    expect(e.explanation, 'expired');
    expect(e.action, contains('Sign in again'));
  });

  test('Google accounts: a 401 points to Sign in again', () {
    final e = explainGoogle(const FcmError(httpStatus: 401, status: 'UNAUTHENTICATED'));
    expect(e.action, contains('Sign in again'));
  });

  test('Google accounts: a 403 is about your account, not a service account', () {
    final e = explainGoogle(const FcmError(httpStatus: 403, status: 'PERMISSION_DENIED'));
    expect(e.explanation, contains('Your Google account'));
    expect(e.action, contains('Firebase Cloud Messaging API Admin'));
    expect('${e.explanation} ${e.action}', isNot(contains('service account')));
  });

  test('service accounts keep their advice', () {
    final e = explain(
      const FcmError(transport: FcmTransportError.auth, message: 'bad key'),
    );
    expect(e.action, contains('service account key file'));
  });
```

  Add this test to `test/features/composer/message_sender_test.dart`, after `'a failure before FCM answers is still recorded'`:

```dart
  test('a Google-account project gets Google sign-in advice', () async {
    final outcome =
        await build(
          auth: FakeResolver(error: const AuthException('expired')),
        ).send(
          project: testGoogleProject,
          request: request,
          target: const TokenTarget(token),
        );
    expect(outcome.explanation?.action, contains('Sign in again'));
  });
```

- [ ] **Step 3: Run them and confirm they fail**

Run: `flutter test test/core/fcm/fcm_error_explainer_test.dart test/features/composer/message_sender_test.dart`
Expected: FAIL, because `googleAccount` isn't a parameter and the new reasons aren't explained.

- [ ] **Step 4: Change the explainer** in `lib/core/fcm/fcm_error_explainer.dart`.

  (a) The signature becomes `ErrorExplanation explain(FcmError error, {required String projectId, bool googleAccount = false})`.

  (b) In the `FcmTransportError.auth` case, the action becomes:

```dart
          action: googleAccount
              ? 'Use "Sign in again…" in the project menu.'
              : 'Add the project again with its service account key file.',
```

  (c) Right before `if (error.reason == 'SERVICE_DISABLED')`, add:

```dart
    if (error.reason == 'USER_PROJECT_DENIED') {
      return ErrorExplanation(
        title: "Your account can't use this project's API quota",
        explanation:
            'Sends from a Google account are billed to $projectId, and your '
            'account is not allowed to use it.',
        action:
            'Ask an owner of $projectId to give your account the "Service Usage '
            'Consumer" role, then retry. Or add the project with a service '
            'account key.',
        link: Uri.parse(
          'https://console.cloud.google.com/iam-admin/iam?project=$projectId',
        ),
      );
    }
    if (error.reason == 'ACCESS_TOKEN_SCOPE_INSUFFICIENT') {
      return const ErrorExplanation(
        title: 'FCM Studio is missing a permission',
        explanation: 'The Google sign-in did not allow sending messages.',
        action:
            'Use "Sign in again…" in the project menu and allow every permission.',
      );
    }
```

  (d) Replace the `status == 401`, `status == 403` and `status == 404` blocks with:

```dart
    if (status == 401) {
      return googleAccount
          ? const ErrorExplanation(
              title: 'Access token rejected',
              explanation:
                  'Google rejected the access token even after getting a fresh '
                  'one. The sign-in may have been revoked.',
              action: 'Use "Sign in again…" in the project menu.',
            )
          : const ErrorExplanation(
              title: 'Access token rejected',
              explanation:
                  'Google rejected the access token even after getting a fresh one. '
                  'The key may have been deleted or the service account disabled.',
              action:
                  'Create a new key for the service account and add the project again.',
            );
    }
    if (status == 403) {
      return ErrorExplanation(
        title: 'Permission denied',
        explanation: googleAccount
            ? 'Your Google account is not allowed to send messages for $projectId.'
            : 'This service account is not allowed to send messages for $projectId.',
        action: googleAccount
            ? 'Ask an owner of $projectId to give your account the "Firebase '
                  'Cloud Messaging API Admin" role (or Firebase Admin).'
            : 'In Google Cloud IAM, give the service account the '
                  '"Firebase Cloud Messaging API Admin" role.',
        link: Uri.parse(
          'https://console.cloud.google.com/iam-admin/iam?project=$projectId',
        ),
      );
    }
    if (status == 404) {
      return ErrorExplanation(
        title: 'Not found',
        explanation: error.message ?? 'FCM could not find this project.',
        action: googleAccount
            ? 'Check that $projectId still exists and that your account can see it.'
            : 'Check that the key file belongs to $projectId.',
      );
    }
```

- [ ] **Step 5: Pass the credential kind.** In `lib/features/composer/data/message_sender.dart`, change the explanation call to:

```dart
      FcmSendFailure(:final error) => _explainer.explain(
        error,
        projectId: project.id,
        googleAccount: project.credential is GoogleAccountRef,
      ),
```

- [ ] **Step 6: Run the tests and confirm they pass**

Run: `flutter test test/core/fcm test/features/composer/message_sender_test.dart`, then `flutter analyze`.
Expected: PASS, and `No issues found!`. Every existing explainer test still passes, because service accounts keep their wording.

- [ ] **Step 7: Commit**

```bash
dart format lib test
git add lib/core/fcm/fcm_error_explainer.dart lib/features/composer/data/message_sender.dart test/helpers/fcm_fixtures.dart test/core/fcm/fcm_error_explainer_test.dart test/features/composer/message_sender_test.dart
git commit -m "feat: explain send errors for Google accounts, including the quota project"
```

---
### Task 9: Wiring, and "Sign in with Google" in the Add project dialog

**Files:**
- Create: `lib/features/projects/view/google_projects_dialog.dart`
- Modify: `lib/app/dependencies.dart`, `lib/features/projects/view/add_project_dialog.dart`, `test/helpers/app_harness.dart`
- Test: `test/features/projects/add_project_google_test.dart`

**Interfaces:**
- Consumes:
  - `createGoogleAuthFlow` (Task 3, via `google_auth_flow_platform.dart`);
  - `OAuthConfig.load` and `OAuthConfig.assetPath` (Task 1);
  - `GoogleAuthFlow` (Task 2) and `GoogleUserInfo` (Task 4);
  - `ProjectsCubit.canSignInWithGoogle`, `signInWithGoogle` and `addGoogleProjects`, plus `GoogleProjectsFound`, `GoogleSignInFailed` and `GoogleSignInStopped` (Task 7);
  - test helpers from Tasks 4 and 7.
- Produces:
  - `AppDependencies({..., GoogleAuthFlow? googleFlow, GoogleUserInfo? googleUserInfo})`. `AppDependencies.create()` loads `config/oauth.json` and builds the platform flow.
  - Test harness:
    - `buildTestDependencies(tester, {..., GoogleAuthFlow? googleFlow, GoogleUserInfo? googleUserInfo})`, which defaults to `FakeGoogleUserInfo()` so no test reaches Google;
    - `Future<ProjectsCubit> addGoogleTestProject(WidgetTester tester)`.
  - `AddProjectDialog.googleKey` (`Key('add-project-google')`) and `AddProjectDialog.cancelGoogleKey` (`Key('add-project-google-cancel')`).
  - `GoogleProjectsDialog({required GoogleProjectsFound found})`, with `addKey` (`Key('google-projects-add')`) and `static Key projectKey(String projectId)` (`ValueKey('google-project-<id>')`).

- [ ] **Step 1: Wire the flow into the app.** In `lib/app/dependencies.dart`, add these imports:

```dart
import 'package:fcm_studio/core/auth/google_auth_flow.dart';
import 'package:fcm_studio/core/auth/google_auth_flow_platform.dart';
import 'package:fcm_studio/core/auth/google_user_info.dart';
import 'package:fcm_studio/core/auth/oauth_config.dart';
```

  Then:
  - Add the factory parameters `GoogleAuthFlow? googleFlow,` and `GoogleUserInfo? googleUserInfo,` after `adbServiceFor`.
  - Pass `googleFlow: googleFlow, googleUserInfo: googleUserInfo,` to the `ProjectAuthRegistry(...)` it builds.
  - Replace `create()` with:

```dart
  static Future<AppDependencies> create() async {
    final httpClient = http.Client();
    // A missing or broken config/oauth.json just leaves Google sign-in off
    // (spec §4.4).
    final oauth = await OAuthConfig.load(
      () => rootBundle.loadString(OAuthConfig.assetPath),
    );
    return AppDependencies(
      httpClient: httpClient,
      database: await AppDatabase.open(),
      // On web, keys stay in memory unless the user ticks "Remember on this browser".
      secrets: LayeredSecretStore(
        persistent: FlutterSecureSecretStore(),
        alwaysPersist: !kIsWeb,
      ),
      googleFlow: createGoogleAuthFlow(oauth, httpClient),
    );
  }
```

- [ ] **Step 2: Extend the test harness.** In `test/helpers/app_harness.dart`:
  - Add the imports `package:fcm_studio/core/auth/google_auth_flow.dart`, `package:fcm_studio/core/auth/google_user_info.dart` and `'fake_google_auth_flow.dart'`.
  - Add the parameters `GoogleAuthFlow? googleFlow,` and `GoogleUserInfo? googleUserInfo,` to `buildTestDependencies`.
  - Pass them on as:

```dart
    googleFlow: googleFlow,
    // No test ever asks Google which account signed in.
    googleUserInfo: googleUserInfo ?? FakeGoogleUserInfo(),
```

  Then add this helper below `addTestProject`:

```dart
/// Signs in with the fake Google flow and adds every listed project.
Future<ProjectsCubit> addGoogleTestProject(WidgetTester tester) async {
  final projects = readCubit<ProjectsCubit>(tester);
  await tester.runAsync(() async {
    final found = await projects.signInWithGoogle() as GoogleProjectsFound;
    await projects.addGoogleProjects(found.session, found.projects);
  });
  await tester.pump();
  return projects;
}
```

- [ ] **Step 3: Write the failing tests** `test/features/projects/add_project_google_test.dart`

```dart
import 'dart:async';

import 'package:fcm_studio/core/auth/access_token_provider.dart';
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:fcm_studio/features/projects/view/add_project_dialog.dart';
import 'package:fcm_studio/features/projects/view/google_projects_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_google.dart';
import '../../helpers/fake_google_auth_flow.dart';

Future<void> openAddProject(WidgetTester tester) async {
  await tester.tap(find.text('Add project'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Google sign-in is shown disabled, with a hint, when not set up', (
    tester,
  ) async {
    await pumpApp(tester, await buildTestDependencies(tester));
    await openAddProject(tester);
    final button = tester.widget<OutlinedButton>(
      find.byKey(AddProjectDialog.googleKey),
    );
    expect(button.onPressed, isNull);
    expect(find.textContaining('docs/oauth-setup.md'), findsOneWidget);
  });

  testWidgets('signing in lists the projects of the account and adds the ticked one', (
    tester,
  ) async {
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        googleFlow: FakeGoogleAuthFlow(),
        client: fakeGoogle(
          firebaseProjects: const [
            listedTestProject,
            {'projectId': 'other-app', 'displayName': 'Other App', 'projectNumber': '555'},
          ],
        ),
      ),
    );
    await openAddProject(tester);
    await tester.tap(find.byKey(AddProjectDialog.googleKey));
    await settleAsync(tester);

    expect(find.text('Projects for $testGoogleEmail'), findsOneWidget);
    expect(find.text('Demo Project'), findsOneWidget);
    expect(find.text('Other App'), findsOneWidget);
    await tester.tap(find.byKey(GoogleProjectsDialog.projectKey('other-app')));
    await tester.pump();
    await tester.tap(find.byKey(GoogleProjectsDialog.addKey));
    await settleAsync(tester);

    expect(find.byType(GoogleProjectsDialog), findsNothing);
    final state = readCubit<ProjectsCubit>(tester).state;
    expect(state.projects, hasLength(1));
    expect(
      state.selected,
      const Project(
        id: 'other-app',
        displayName: 'Other App',
        projectNumber: '555',
        credential: GoogleAccountRef(testGoogleEmail),
      ),
    );
  });

  testWidgets('Cancel stops waiting for the browser', (tester) async {
    final flow = FakeGoogleAuthFlow()..signInGate = Completer<void>();
    await pumpApp(tester, await buildTestDependencies(tester, googleFlow: flow));
    await openAddProject(tester);
    await tester.tap(find.byKey(AddProjectDialog.googleKey));
    await tester.pump();
    expect(find.text('Finish signing in in your browser…'), findsOneWidget);

    await tester.tap(find.byKey(AddProjectDialog.cancelGoogleKey));
    await settleAsync(tester);
    expect(flow.cancels, 1);
    expect(find.text('Finish signing in in your browser…'), findsNothing);
    expect(find.text('Choose key file…'), findsOneWidget);
    expect(readCubit<ProjectsCubit>(tester).state.projects, isEmpty);
  });

  testWidgets('closing the dialog while waiting stops the sign-in', (tester) async {
    final flow = FakeGoogleAuthFlow()..signInGate = Completer<void>();
    await pumpApp(tester, await buildTestDependencies(tester, googleFlow: flow));
    await openAddProject(tester);
    await tester.tap(find.byKey(AddProjectDialog.googleKey));
    await tester.pump();

    await tester.tapAt(const Offset(5, 5));
    await settleAsync(tester);
    expect(find.byType(AddProjectDialog), findsNothing);
    expect(flow.cancels, 1);
  });

  testWidgets('a failed sign-in shows what went wrong', (tester) async {
    final flow = FakeGoogleAuthFlow(
      signIns: const [AuthException('Google sign-in failed (invalid_client).')],
    );
    await pumpApp(tester, await buildTestDependencies(tester, googleFlow: flow));
    await openAddProject(tester);
    await tester.tap(find.byKey(AddProjectDialog.googleKey));
    await settleAsync(tester);
    expect(find.text('Google sign-in failed (invalid_client).'), findsOneWidget);
  });

  testWidgets('an account without Firebase projects says so', (tester) async {
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        googleFlow: FakeGoogleAuthFlow(),
        client: fakeGoogle(firebaseProjects: const []),
      ),
    );
    await openAddProject(tester);
    await tester.tap(find.byKey(AddProjectDialog.googleKey));
    await settleAsync(tester);
    expect(find.textContaining('has no Firebase projects'), findsOneWidget);
    final add = tester.widget<FilledButton>(find.byKey(GoogleProjectsDialog.addKey));
    expect(add.onPressed, isNull);
  });

  testWidgets('a project that is already added says it will switch accounts', (
    tester,
  ) async {
    await pumpApp(
      tester,
      await buildTestDependencies(tester, googleFlow: FakeGoogleAuthFlow()),
    );
    await addTestProject(tester);
    await openAddProject(tester);
    await tester.tap(find.byKey(AddProjectDialog.googleKey));
    await settleAsync(tester);
    expect(find.textContaining('already added'), findsOneWidget);
  });
}
```

- [ ] **Step 4: Run them and confirm they fail**

Run: `flutter test test/features/projects/add_project_google_test.dart`
Expected: FAIL, because `AddProjectDialog.googleKey` and `GoogleProjectsDialog` don't exist.

- [ ] **Step 5: Write** `lib/features/projects/view/google_projects_dialog.dart`

```dart
import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The checklist of an account's Firebase projects (spec §4.2).
class GoogleProjectsDialog extends StatefulWidget {
  const GoogleProjectsDialog({required this.found, super.key});

  final GoogleProjectsFound found;

  static const addKey = Key('google-projects-add');

  static Key projectKey(String projectId) =>
      ValueKey('google-project-$projectId');

  @override
  State<GoogleProjectsDialog> createState() => _GoogleProjectsDialogState();
}

class _GoogleProjectsDialogState extends State<GoogleProjectsDialog> {
  final Set<String> _picked = {};
  bool _saving = false;
  String? _error;

  Future<void> _add() async {
    final cubit = context.read<ProjectsCubit>();
    final picked = [
      for (final project in widget.found.projects)
        if (_picked.contains(project.projectId)) project,
    ];
    setState(() {
      _saving = true;
      _error = null;
    });
    final error = await cubit.addGoogleProjects(widget.found.session, picked);
    if (!mounted) {
      return;
    }
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _saving = false;
        _error = error;
      });
    }
  }

  void _toggle(String projectId, bool? picked) {
    setState(() {
      if (picked ?? false) {
        _picked.add(projectId);
      } else {
        _picked.remove(projectId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final found = widget.found;
    final existing = {
      for (final project in context.read<ProjectsCubit>().state.projects)
        project.id,
    };
    final error = _error;
    final count = _picked.length;
    return AlertDialog(
      title: Text('Projects for ${found.email}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (found.projects.isEmpty)
              Text(
                '${found.email} has no Firebase projects. Sign in with another '
                'account, or ask to be added to a project.',
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 360),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final project in found.projects)
                      CheckboxListTile(
                        key: GoogleProjectsDialog.projectKey(project.projectId),
                        value: _picked.contains(project.projectId),
                        onChanged: _saving
                            ? null
                            : (picked) => _toggle(project.projectId, picked),
                        title: Text(project.displayName),
                        subtitle: Text(
                          existing.contains(project.projectId)
                              ? '${project.projectId} · already added; it will '
                                    'use this account'
                              : project.projectId,
                        ),
                      ),
                  ],
                ),
              ),
            if (_saving) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: GoogleProjectsDialog.addKey,
          onPressed: count == 0 || _saving ? null : _add,
          child: Text(switch (count) {
            0 => 'Add projects',
            1 => 'Add 1 project',
            _ => 'Add $count projects',
          }),
        ),
      ],
    );
  }
}
```

- [ ] **Step 6: Replace** `lib/features/projects/view/add_project_dialog.dart` with:

```dart
import 'dart:async';

import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/view/google_projects_dialog.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> showAddProjectDialog(BuildContext context) {
  final cubit = context.read<ProjectsCubit>();
  return showDialog<void>(
    context: context,
    builder: (_) =>
        BlocProvider.value(value: cubit, child: const AddProjectDialog()),
  );
}

class AddProjectDialog extends StatefulWidget {
  const AddProjectDialog({super.key});

  static const googleKey = Key('add-project-google');
  static const cancelGoogleKey = Key('add-project-google-cancel');

  @override
  State<AddProjectDialog> createState() => _AddProjectDialogState();
}

class _AddProjectDialogState extends State<AddProjectDialog> {
  bool _remember = false;
  bool _busy = false;
  String? _error;
  String? _info;

  /// Set while Google's sign-in is open; completing it stops waiting.
  Completer<void>? _cancelGoogle;
  GoogleProjectsFound? _found;

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
    final result = await context.read<ProjectsCubit>().addFromServiceAccount(
      text,
      persistKey: !kIsWeb || _remember,
    );
    if (!mounted) {
      return;
    }
    switch (result) {
      case AddProjectSuccess(:final project, needsProjectNumber: true):
        setState(() {
          _busy = false;
          _info =
              'Added ${project.id}. This key cannot read the project number, so set it '
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

  Future<void> _signInWithGoogle() async {
    final cubit = context.read<ProjectsCubit>();
    final cancel = Completer<void>();
    setState(() {
      _cancelGoogle = cancel;
      _busy = true;
      _error = null;
      _info = null;
    });
    final result = await cubit.signInWithGoogle(cancel: cancel.future);
    if (!mounted) {
      return;
    }
    setState(() {
      _cancelGoogle = null;
      _busy = false;
      switch (result) {
        case GoogleProjectsFound():
          _found = result;
        case GoogleSignInFailed(:final message):
          _error = message;
        case GoogleSignInStopped():
          break;
      }
    });
  }

  void _stopGoogle() {
    final cancel = _cancelGoogle;
    if (cancel != null && !cancel.isCompleted) {
      cancel.complete();
    }
  }

  @override
  void dispose() {
    // Closing the dialog while Google's page is open stops the sign-in, so
    // the loopback server closes too.
    _stopGoogle();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final found = _found;
    if (found != null) {
      return GoogleProjectsDialog(found: found);
    }
    final theme = Theme.of(context);
    final error = _error;
    final info = _info;
    final googleAvailable = context.read<ProjectsCubit>().canSignInWithGoogle;
    final waitingForGoogle = _cancelGoogle != null;
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
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _remember = value ?? false),
                title: const Text('Remember on this browser'),
                subtitle: const Text(
                  'Otherwise the key is kept only until this tab is closed or reloaded. '
                  'Browser storage can be read by scripts on this site.',
                ),
              ),
            ],
            const Divider(height: 32),
            const Text(
              'Or sign in with Google to add the Firebase projects your account '
              'can see.',
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: AddProjectDialog.googleKey,
              onPressed: googleAvailable && !_busy ? _signInWithGoogle : null,
              icon: const Icon(Icons.login),
              label: const Text('Sign in with Google…'),
            ),
            if (!googleAvailable) ...[
              const SizedBox(height: 4),
              Text(
                "Google sign-in isn't set up in this copy of FCM Studio. "
                'See docs/oauth-setup.md.',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (waitingForGoogle) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
              const SizedBox(height: 8),
              const Text(
                kIsWeb
                    ? 'Finish signing in in the Google pop-up…'
                    : 'Finish signing in in your browser…',
              ),
            ] else if (_busy) ...[
              const SizedBox(height: 16),
              const LinearProgressIndicator(),
            ],
            if (error != null) ...[
              const SizedBox(height: 16),
              Text(error, style: TextStyle(color: theme.colorScheme.error)),
            ],
            if (info != null) ...[const SizedBox(height: 16), Text(info)],
          ],
        ),
      ),
      actions: [
        if (waitingForGoogle)
          TextButton(
            key: AddProjectDialog.cancelGoogleKey,
            onPressed: _stopGoogle,
            child: const Text('Cancel sign-in'),
          )
        else
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

- [ ] **Step 7: Run the tests and confirm they pass**

Run: `flutter test test/features/projects/add_project_google_test.dart`, then `flutter test`, then `flutter analyze`.
Expected: everything passes, and `No issues found!`. The full run matters because the app tests open this dialog too.

- [ ] **Step 8: Commit**

```bash
dart format lib test
git add lib/app/dependencies.dart lib/features/projects/view/add_project_dialog.dart lib/features/projects/view/google_projects_dialog.dart test/helpers/app_harness.dart test/features/projects/add_project_google_test.dart
git commit -m "feat: sign in with Google from the Add project dialog and pick projects"
```

---

### Task 10: The project menu for Google projects

**Files:**
- Create: `lib/features/projects/view/sign_in_again_dialog.dart`
- Modify: `lib/features/projects/view/project_switcher.dart`, `test/app/app_test.dart`
- Test: `test/features/projects/project_menu_google_test.dart`

**Interfaces:**
- Consumes: `ProjectsCubit.signInAgain` (Task 7); `GoogleAccountRef` (Task 5); harness `addGoogleTestProject` and `buildTestDependencies(googleFlow:, googleUserInfo:)` (Task 9).
- Produces:
  - `SignInAgainDialog({required GoogleAccountRef account})`, with `cancelKey` (`Key('sign-in-again-cancel')`). It pops with the cubit's result: null means success.
  - The project menu shows `Signed in as <email>` and **Sign in again…** for Google projects.
  - New empty-state copy.

- [ ] **Step 1: Write the failing tests** `test/features/projects/project_menu_google_test.dart`

```dart
import 'dart:async';

import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:fcm_studio/features/projects/view/sign_in_again_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/app_harness.dart';
import '../../helpers/fake_google_auth_flow.dart';

Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('project-menu')));
  await tester.pumpAndSettle();
}

void main() {
  const account = GoogleAccountRef(testGoogleEmail);

  testWidgets('a Google project shows its account and signs in again', (tester) async {
    final flow = FakeGoogleAuthFlow(
      signIns: [
        googleCredentials(),
        googleCredentials(token: 'ya29.google-2', refreshToken: '1//refresh-2'),
      ],
    );
    final dependencies = await buildTestDependencies(tester, googleFlow: flow);
    await pumpApp(tester, dependencies);
    await addGoogleTestProject(tester);

    await openMenu(tester);
    expect(find.text('Signed in as $testGoogleEmail'), findsOneWidget);
    await tester.tap(find.text('Sign in again…'));
    await settleAsync(tester);

    expect(find.text('Signed in again as $testGoogleEmail.'), findsOneWidget);
    expect(flow.calls.last, 'signIn $testGoogleEmail');
    expect(
      await tester.runAsync(
        () => dependencies.projectsRepository.readGoogleRefreshToken(account),
      ),
      '1//refresh-2',
    );
  });

  testWidgets('Cancel while signing in again keeps the old sign-in', (tester) async {
    final flow = FakeGoogleAuthFlow();
    final dependencies = await buildTestDependencies(tester, googleFlow: flow);
    await pumpApp(tester, dependencies);
    await addGoogleTestProject(tester);
    flow.signInGate = Completer<void>();

    await openMenu(tester);
    await tester.tap(find.text('Sign in again…'));
    // Not pumpAndSettle: the dialog's progress bar animates until it closes.
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(
      find.text('Finish signing in as $testGoogleEmail in your browser…'),
      findsOneWidget,
    );
    await tester.tap(find.byKey(SignInAgainDialog.cancelKey));
    await settleAsync(tester);

    expect(find.text('Sign-in was cancelled.'), findsOneWidget);
    expect(
      await tester.runAsync(
        () => dependencies.projectsRepository.readGoogleRefreshToken(account),
      ),
      '1//refresh-1',
    );
  });

  testWidgets('signing in again as another account is refused', (tester) async {
    await pumpApp(
      tester,
      await buildTestDependencies(
        tester,
        googleFlow: FakeGoogleAuthFlow(),
        googleUserInfo: FakeGoogleUserInfo([testGoogleEmail, 'other@example.com']),
      ),
    );
    await addGoogleTestProject(tester);
    await openMenu(tester);
    await tester.tap(find.text('Sign in again…'));
    await settleAsync(tester);
    expect(find.textContaining('You signed in as other@example.com'), findsOneWidget);
  });

  testWidgets('a service-account project has no Google items', (tester) async {
    await pumpAppWithProject(tester);
    await openMenu(tester);
    expect(find.text('Sign in again…'), findsNothing);
    expect(find.textContaining('Signed in as'), findsNothing);
  });

  testWidgets('removing a Google project says what happens to the sign-in', (
    tester,
  ) async {
    await pumpApp(
      tester,
      await buildTestDependencies(tester, googleFlow: FakeGoogleAuthFlow()),
    );
    await addGoogleTestProject(tester);
    await openMenu(tester);
    await tester.tap(find.text('Remove project…'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('sign-in for $testGoogleEmail is forgotten'),
      findsOneWidget,
    );
  });
}
```

  In `test/app/app_test.dart`, change both occurrences of `'No projects yet. Add one with a service account key.'` to `'No projects yet. Add one with a service account key or Google sign-in.'`.

- [ ] **Step 2: Run them and confirm they fail**

Run: `flutter test test/features/projects/project_menu_google_test.dart test/app/app_test.dart`
Expected: FAIL. `SignInAgainDialog` doesn't exist, the menu has no Google items, and the empty-state text is still the old one.

- [ ] **Step 3: Write** `lib/features/projects/view/sign_in_again_dialog.dart`

```dart
import 'dart:async';

import 'package:fcm_studio/features/projects/cubit/projects_cubit.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Runs "Sign in again…" for a Google account (plan Decision 6), with a
/// Cancel while Google's page is open. Pops with the cubit's result: null on
/// success, otherwise the message to show.
class SignInAgainDialog extends StatefulWidget {
  const SignInAgainDialog({required this.account, super.key});

  final GoogleAccountRef account;

  static const cancelKey = Key('sign-in-again-cancel');

  @override
  State<SignInAgainDialog> createState() => _SignInAgainDialogState();
}

class _SignInAgainDialogState extends State<SignInAgainDialog> {
  final _cancel = Completer<void>();

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    final message = await context.read<ProjectsCubit>().signInAgain(
      widget.account,
      cancel: _cancel.future,
    );
    if (mounted) {
      Navigator.of(context).pop(message);
    }
  }

  void _stop() {
    if (!_cancel.isCompleted) {
      _cancel.complete();
    }
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final email = widget.account.email;
    return AlertDialog(
      title: const Text('Sign in again'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            kIsWeb
                ? 'Finish signing in as $email in the Google pop-up…'
                : 'Finish signing in as $email in your browser…',
          ),
        ],
      ),
      actions: [
        TextButton(
          key: SignInAgainDialog.cancelKey,
          onPressed: _stop,
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Update** `lib/features/projects/view/project_switcher.dart`.
  - Add `import 'package:fcm_studio/features/projects/view/sign_in_again_dialog.dart';`.
  - The empty state becomes `const Text('No projects yet. Add one with a service account key or Google sign-in.')`.
  - The menu enum becomes `enum _MenuAction { dev, staging, prod, projectNumber, signInAgain, remove }`.
  - In `itemBuilder`, between the project-number item and the remove item, add:

```dart
        if (project.credential case GoogleAccountRef(:final email)) ...[
          PopupMenuItem<_MenuAction>(
            enabled: false,
            child: Text('Signed in as $email'),
          ),
          const PopupMenuItem(
            value: _MenuAction.signInAgain,
            child: Text('Sign in again…'),
          ),
        ],
```

  - In `_onSelected`, add this case before `_MenuAction.remove`:

```dart
      case _MenuAction.signInAgain:
        final credential = project.credential;
        if (credential is! GoogleAccountRef) {
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        final message = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (_) => BlocProvider.value(
            value: cubit,
            child: SignInAgainDialog(account: credential),
          ),
        );
        messenger.showSnackBar(
          SnackBar(
            content: Text(message ?? 'Signed in again as ${credential.email}.'),
          ),
        );
```

  - In the remove dialog, replace `content: const Text('The project and its stored key are removed from FCM Studio. ' 'Nothing changes in Firebase.')` with:

```dart
            content: Text(switch (project.credential) {
              ServiceAccountRef() =>
                'The project and its stored key are removed from FCM Studio. '
                    'Nothing changes in Firebase.',
              GoogleAccountRef(:final email) =>
                'The project is removed from FCM Studio. The sign-in for $email '
                    'is forgotten once no other project uses it. Nothing changes '
                    'in Firebase.',
            }),
```

- [ ] **Step 5: Run the tests and confirm they pass**

Run: `flutter test test/features/projects/project_menu_google_test.dart test/app/app_test.dart`, then `flutter test`, then `flutter analyze`.
Expected: everything passes, and `No issues found!`.

- [ ] **Step 6: Commit**

```bash
dart format lib test
git add lib/features/projects/view/sign_in_again_dialog.dart lib/features/projects/view/project_switcher.dart test/app/app_test.dart test/features/projects/project_menu_google_test.dart
git commit -m "feat: show the Google account in the project menu and sign in again from it"
```

---

### Task 11: The setup guide, builds, the M4 success test, and the spec

Steps 3 and 4 need the user. They need a Google Cloud console, OAuth clients, a phone, and ideally a teammate. An agent does Steps 1, 2 and 5–6, and records Steps 3–4 as pending.

**Files:**
- Create: `docs/oauth-setup.md`
- Modify: `docs/superpowers/specs/2026-10-03-fcm-studio-design.md` (§2, §3.2, §4.1, §4.2, §4.4, §8.2, §13, §14)

- [ ] **Step 1: Write** `docs/oauth-setup.md`

````markdown
# Google sign-in setup (one time)

FCM Studio signs in to Google with two OAuth clients: one for the desktop app and one for the web build. Someone with access to Google Cloud console creates them once for the team. Everyone else only needs to be added as a test user.

## 1. Choose the Google Cloud project that owns the clients

Use any project you control, for example a new one named `fcm-studio-oauth`. Sending is billed to each target Firebase project, not to this one. Listing your Firebase projects is billed to this one, which is free within Google's normal quota.

In that project, open **APIs & Services → Library** and enable **Firebase Management API**. FCM Studio uses it to list the projects you can see.

## 2. Configure the consent screen

1. Open **Google Auth Platform** (the "OAuth consent screen").
2. Under **Audience**, set the user type to **External** and the publishing status to **Testing**.
3. Add each teammate's Google account as a **test user**.

While the app is in Testing, Google ends each sign-in after 7 days. FCM Studio then asks you to use **Sign in again…** in the project menu.

## 3. Create the desktop client

**Clients → Create client → Desktop app**. Name it "FCM Studio desktop", then copy its **Client ID** and **Client secret**. Google does not treat a desktop client secret as confidential, but keep it out of git anyway.

## 4. Create the web client

**Clients → Create client → Web application**. Name it "FCM Studio web".

Under **Authorized JavaScript origins**, add:
- `http://localhost:5050`, for development;
- the URL where the team hosts the web build.

No redirect URI is needed. Copy its **Client ID**.

## 5. Put the IDs in `config/oauth.json`

```bash
cp config/oauth.example.json config/oauth.json
```

Fill in `desktopClientId`, `desktopClientSecret` and `webClientId`, then rebuild. `config/oauth.json` is git-ignored. The app bundles it, and the web build serves it publicly. That is expected, because client IDs are public.

To run the web build in development, use the port the web client allows:

```bash
flutter run -d chrome --web-port 5050
```

## 6. Permissions each teammate needs

To send from a Google account to a Firebase project, the account needs both of these on that project:
- **Firebase Cloud Messaging API Admin**, or Firebase Admin, Editor or Owner, to send;
- **Service Usage Consumer**, or Editor or Owner, because sends are billed to the target project (`x-goog-user-project`).

If either is missing, FCM Studio's error explanation names the role.
````

- [ ] **Step 2: Run the full checks and build every target that can be built here**

```bash
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter test
flutter build macos --debug
flutter build web
```

Expected:
- no formatting changes;
- `No issues found!`;
- both test runs pass (the second run catches flaky tests);
- both builds succeed.

- [ ] **Step 3 (the user): the M4 success test**
  1. Follow `docs/oauth-setup.md` and create `config/oauth.json`.
  2. **macOS**:
     1. `flutter run -d macos`.
     2. Choose **Add project → Sign in with Google…**. The browser opens.
     3. Choose your account and allow both permissions. The tab says you can close it.
     4. Tick the project(s), then press **Add**.
     5. Send **Simple notification** to the Redmi, with **From device…** or a pasted token. It must arrive. This also confirms `x-goog-user-project` with a user token (plan Decision 9).
  3. Quit, relaunch, and send again. It must work without signing in again, because of the stored refresh token.
  4. Start **Sign in with Google…**, close the browser tab, then press **Cancel sign-in**. The dialog returns to normal.
  5. In the project menu, check that **Signed in as …** shows. Then use **Sign in again…** and finish it. The snackbar says "Signed in again as …".
  6. **Web**:
     1. `flutter run -d chrome --web-port 5050`.
     2. Choose **Add project → Sign in with Google…**. Google's pop-up opens.
     3. Add a project and send.
     4. Reload the page and send again. The pop-up appears (possibly without the account picker), then the send works.
  7. **Done when** a teammate, with no key file, adds a project this way and sends to their phone.
- [ ] **Step 4 (the user, optional): Windows.** Do the same as Step 3.2 on a Windows machine with `flutter run -d windows`.

- [ ] **Step 5: Record the decisions and the status in the spec**
  - **§2**: append to the `googleapis_auth` bullet: ` M4 uses `auth_browser.dart` for the web popup; the desktop loopback sign-in is hand-written (see §4.1).`
  - **§3.2**: in the `auth/` line, replace `google_account_token_provider.dart (+ _io.dart / _web.dart)` with `google_auth_flow.dart (+ _io.dart / _web.dart / _platform.dart), google_account_token_provider.dart, google_user_info.dart, oauth_config.dart`.
  - **§4.1**, in the `GoogleAccountTokenProvider` bullet:
    - "requests the same two scopes." becomes "requests the same two scopes, plus `openid` and `userinfo.email` so the app can read which account signed in. A sign-in that lacks either Firebase scope is refused, and nothing is saved."
    - The *Desktop* sentence becomes: "*Desktop (`_io`):* a "Desktop app" OAuth client. The app opens the system browser and receives the result on a one-off `127.0.0.1` server (PKCE, a `state` check, `prompt=select_account consent`). Cancel, closing the dialog, or 5 minutes stop the wait and close the port. The code exchange and refreshes are plain POSTs to the token endpoint. The refresh token is kept in `SecretStore`, so the user stays signed in. When Google rejects it (`invalid_grant`: expired or revoked), the user is asked to use **Sign in again…** in the project menu, which must use the same account."
    - Append to the *Web* sentence: " Once the account is known the popup uses `prompt: ''`. If the user picks a different account there, the call is refused."
  - **§4.2**, "Adding projects with Google sign-in": add step 4: `A ticked project that is already added switches to the Google account and keeps its environment (and its project number when Google has none). If exactly one project is ticked, it is selected.`
  - **§4.4**: replace "The file is loaded at startup." with "`config/` is bundled as an asset directory (with the committed `config/oauth.example.json`), so `config/oauth.json` is read at startup when present. The web build serves it publicly, which is fine for client IDs." Replace "The README documents the one-time setup:" with "`docs/oauth-setup.md` documents the one-time setup (the README links to it). It covers enabling the Firebase Management API in the OAuth client's project, which the project list is billed to, and:".
  - **§8.2** table: after the `SERVICE_DISABLED` row, add:

```markdown
| `403 PERMISSION_DENIED`, reason `USER_PROJECT_DENIED` (Google account) | The account may not bill API quota to the project (`x-goog-user-project`) | Ask for the Service Usage Consumer role, or use a service account key |
| `403 PERMISSION_DENIED`, reason `ACCESS_TOKEN_SCOPE_INSUFFICIENT` | The Google sign-in did not allow sending | Sign in again and allow every permission |
```

  - **§13** M0 row: replace `*Moved to the start of M4:* `x-goog-user-project` with a user token, because `gcloud` isn't installed and the check only matters for Google sign-in` with `*Checked by the M4 success test:* `x-goog-user-project` with a user token`.
  - **§13**: add this under the M3 status:

```markdown
**M4 status (<date>):**
- *Done:* the M4 code with its automated tests passing and a clean `flutter analyze`; the macOS debug and web builds succeed. Google sign-in works with fakes in tests; `docs/oauth-setup.md` holds the one-time Google Cloud setup.
- *Manual, pending:* <every item of plan Task 11 Steps 3–4 that the user has not reported, as a plain list; nothing is claimed as done unless the user reported it>.
```

  - **§14**: add the risk `- **Pop-up blockers (web).** Google's popup must open from a click. If the browser blocks it, the app says to allow pop-ups for the site and try again.`

- [ ] **Step 6: Commit**

```bash
git add docs/oauth-setup.md docs/superpowers/specs/2026-10-03-fcm-studio-design.md
git commit -m "docs: add the Google sign-in setup guide and record M4 status"
```
