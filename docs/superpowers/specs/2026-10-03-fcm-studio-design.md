# FCM Studio — Design Spec

- **Date:** 2026-10-03
- **Status:** Draft, awaiting review
- **Location:** `/Users/mobarak/Documents/learn/fcm_studio`

## 1. Purpose

A developer tool for sending Firebase Cloud Messaging (FCM) push notifications while building and testing apps. It replaces the Postman workflow, where you generate an OAuth access token by hand, paste device tokens, and type JSON payloads from memory.

**Users:** a team of mobile developers on macOS and Windows, plus a web version for quick use without installing anything.

**Success test:** plug in an Android phone, pick an app, pick a preset, and see the notification on the phone in **under 30 seconds**, without copying a token or generating an access token by hand.

### Decisions already made

| Topic | Decision |
|---|---|
| Stack | One Flutter app, no backend. Targets macOS, Windows and web |
| State management | `flutter_bloc` (Cubits for simple screens, a Bloc for the device panel) |
| Sign-in | Service account JSON (built first) **and** Google sign-in, both in v1 |
| Preset sharing | Local only. Shared between people by exporting and importing files |
| v1 extras | History + saved targets, dry run + plain-language errors, copy as cURL, logcat fallback for release builds |

### Out of scope for v1

- Reading device tokens from iOS devices. The iOS SDK keeps the token in the Keychain, which can't be read from outside the app.
- Shared or cloud-synced presets.
- Scheduled or bulk sends, and analytics.
- Code signing and notarisation for the desktop builds.
- Linux builds. Nothing in the design prevents adding them later.

## 2. Verified facts this design relies on

These were checked on 2026-10-03:

- Browsers may call `oauth2.googleapis.com/token`, `fcm.googleapis.com/v1/.../messages:send` and `firebase.googleapis.com/v1beta1/projects` directly. Each one answers the CORS preflight with `Access-Control-Allow-Origin` and allows the headers `authorization`, `content-type` and `x-goog-user-project`. So the web build needs no proxy.
- `google_sign_in` 7.2.0 supports Android, iOS, macOS and web, but **not Windows**.
- `googleapis_auth` 2.3.x offers service-account and loopback sign-in only in `auth_io.dart`, which does not run in browsers. For the browser it offers a popup flow in `auth_browser.dart`.
- `dart_jsonwebtoken` 3.4.x signs RS256 in pure Dart, so it works on every platform including web.
- `sembast` 3.8.x is pure Dart. `sembast_web` adds web support through IndexedDB.
- `flutter_secure_storage` 10.3.x supports macOS, Windows and web.
- The test device, a Redmi 14C on Android 16, connects over adb. On it, `com.syldel.delivery` is a release build, and `run-as` fails with `package not debuggable`. On 2026-10-04 a debug build of com.syldel.delivery was installed, so run-as works for it.

## 3. Architecture

### 3.1 Overview

```
┌────────────────────────── Flutter app (macOS / Windows / web) ─────────────────────────┐
│  features/  projects · composer · presets · targets · history · devices* · settings     │
│     (Cubits/Bloc + views)                                                               │
│  core/      auth · fcm · firebase · storage · platform                                  │
└──────────────┬──────────────────────────────┬──────────────────────────┬───────────────┘
               │ HTTPS                         │ HTTPS                    │ Process (desktop only)
     oauth2.googleapis.com          fcm / firebase.googleapis.com          adb → Android device
```

`*` The device feature exists only on desktop. On web, the platform layer reports it as unsupported and the UI hides it.

### 3.2 Project structure

```
fcm_studio/
  lib/
    main.dart
    app/                      app.dart, theme.dart, dependencies.dart (RepositoryProviders), shell (NavigationRail)
    core/
      auth/                   access_token_provider.dart, service_account_key.dart,
                              service_account_token_provider.dart,
                              google_account_token_provider.dart (+ _io.dart / _web.dart)
      fcm/                    fcm_client.dart, fcm_send_result.dart, fcm_error_explainer.dart, curl_builder.dart
      firebase/               firebase_projects_api.dart
      storage/                app_database.dart (+ _io.dart / _web.dart), secret_store.dart
      platform/               platform_capabilities.dart
      utils/                  clock.dart, redact.dart
    features/
      projects/               data/, cubit/, view/
      composer/               domain/ (message_renderer.dart, target.dart, fcm_rules.dart), cubit/, view/
      presets/                domain/ (preset.dart, variable_def.dart, preset_codec.dart), data/, cubit/, view/
      targets/                domain/, data/, cubit/, view/
      history/                domain/, data/, cubit/, view/
      devices/                data/ (process_runner.dart, adb_locator.dart, adb_service.dart + _io/_stub,
                              parsers/), bloc/, view/
      settings/               cubit/, view/
  assets/presets/builtin.json
  config/oauth.example.json   (config/oauth.json is git-ignored)
  test/                       same layout as lib/; fixtures/ holds real adb and FCM outputs
```

### 3.3 Conventions

- **State:** `flutter_bloc`. Cubits for projects, composer, presets, targets, history and settings. A `DevicesBloc` for the device panel, because it consumes a stream of plug/unplug events. States extend `Equatable`.
- **Dependency injection:** services are created once in `app/dependencies.dart` (`AppDependencies`) and passed to Cubits through their constructors. Services are plain Dart classes, with abstract interfaces where a test needs a fake.
- **Models:** immutable classes with hand-written `fromJson`/`toJson` and `copyWith`. No code generation.
- **Navigation:** a `NavigationRail` with an `IndexedStack` (Composer, Presets, Targets, History, Devices, Settings). No router package, because the app has no deep links.
- **Platform-specific code:** conditional imports (`if (dart.library.io)` / `if (dart.library.js_interop)`) behind a single interface per concern.
- **Lints:** `flutter_lints`, plus the analyzer's `strict-casts`, `strict-inference` and `strict-raw-types`.
- **Time:** an injectable `Clock`, so token-expiry and history logic can be tested.
- **Logging:** a `redact()` helper removes `Authorization` headers, private keys and refresh tokens from every log line and error message.

## 4. Sign-in, credentials and projects

### 4.1 Access tokens

```dart
abstract interface class AccessTokenProvider {
  Future<AccessToken> getToken({bool forceRefresh = false}); // token, expiresAt
  Map<String, String> extraHeaders(String projectId);        // e.g. x-goog-user-project
}
```

- **`ServiceAccountTokenProvider`** (all platforms):
  1. Builds a JWT with `iss`/`sub` set to `client_email`, `aud` set to `https://oauth2.googleapis.com/token`, `scope` set to `https://www.googleapis.com/auth/firebase.messaging https://www.googleapis.com/auth/firebase.readonly`, and `iat`/`exp` 1 hour apart.
  2. Signs it RS256 with `private_key` using `dart_jsonwebtoken`.
  3. POSTs `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer` to the token endpoint.
  4. Adds no extra headers.
- **`GoogleAccountTokenProvider`**: requests the same two scopes.
  - *Desktop (`_io`):* `googleapis_auth` `obtainAccessCredentialsViaUserConsent` with a "Desktop app" OAuth client. It opens the system browser and receives the result on a loopback port. The refresh token is kept in `SecretStore`, so the user stays signed in.
  - *Web (`_web`):* `googleapis_auth` `requestAccessCredentials` (Google's popup flow) with a "Web" OAuth client. There is no refresh token, so when the token expires the popup is shown again, and Google skips the account picker when it can.
  - `extraHeaders` returns `x-goog-user-project: <projectId>`, so API quota is charged to the target project rather than the OAuth client's project.
- **Caching:** tokens are kept in memory per credential and refreshed when less than 5 minutes remain. Concurrent requests share one in-flight refresh. After a `401` from FCM, the token is refreshed once and the send is retried once.

### 4.2 Projects

```
Project { id (Firebase project ID), displayName, projectNumber?, environment: dev|staging|prod,
          credential: ServiceAccountRef(clientEmail) | GoogleAccountRef(email) }
```

**Adding a project with a service account JSON:**
1. Pick a file (`file_selector`).
2. Validate it: `type == "service_account"`, and `project_id`, `client_email` and `private_key` must be present. The key must parse as PKCS#8 PEM.
3. Fetch a token, so a bad key or disabled account fails immediately with a clear message.
4. Store the raw JSON in `SecretStore` under `sa:<client_email>`.
5. Call `GET firebase.googleapis.com/v1beta1/projects/{id}` to fill in `displayName` and `projectNumber`. On `403`, keep the project ID as the name and let the user type the project number (optional; it is used only for the sender-ID check).
6. Show a tip recommending a separate service account that has only the **Firebase Cloud Messaging API Admin** role.

**Adding projects with Google sign-in:**
1. Sign in.
2. `GET firebase.googleapis.com/v1beta1/projects`, following pages.
3. Show a checklist of projects. The ticked ones become `Project`s with their names and numbers filled in.

**Environment:** defaults to `dev`. The user can change it at any time, and the colour is shown in the project switcher.

### 4.3 Production safeguard

When the selected project is `prod`:
- A red banner appears above the composer.
- Every send opens a confirmation dialog.
- For topic or condition sends, the dialog names the audience, e.g. "every device subscribed to `all_zone_store`", and the confirm button is enabled only after the user types the project ID.
- Dry runs (validate only) skip the confirmation, because they deliver nothing.

### 4.4 OAuth client configuration

- `config/oauth.json` (git-ignored) holds `desktopClientId`, `desktopClientSecret` and `webClientId`. A desktop app's "client secret" is not confidential by Google's definition, but it still stays out of git.
- The file is loaded at startup. If it is missing, the Google sign-in button is disabled with a hint that points to the README setup section.
- The README documents the one-time setup:
  - create the two OAuth clients;
  - add the web origins (`http://localhost:5050` for development, plus the hosting URL);
  - choose consent screen type "External" + "Testing" and add teammates as test users.

## 5. Composer

### 5.1 Model

```
ComposerState {
  projectId, target: Target, template: Map<String, Object?> /* FCM `message` minus target */,
  variables: List<VariableDef>, values: Map<String, String>, validateOnly: bool,
  presetId?, isDirty, render: RenderResult, sendStatus
}
Target = TokenTarget(token, senderId?) | TopicTarget(name) | ConditionTarget(expression)
```

The **template is the single source of truth.** The Form tab and the JSON tab both edit the template, and the preview shows the result of rendering it.

### 5.2 Rendering pipeline (`MessageRenderer`, pure Dart)

`render(template, variables, values, target, validateOnly) → RenderResult { request, notes, errors }`

1. **Substitute variables** in every string, recursively.
   - `{{key}}` takes the user's value.
   - Built-in values need no definition: `{{now_iso}}`, `{{now_ms}}`, `{{uuid}}`.
   - Built-in values get one value per render, so `{{uuid}}` used twice gives the same id twice. The preview shows sample values, and every send renders again, so each send gets fresh values.
   - Placeholders are replaced in string values only, not in keys.
   - An optional number or boolean variable that is empty removes its field (for example no `badge`), with a note in the preview.
   - If a string is *exactly* one placeholder and the variable is `number` or `boolean`, the result has that type. This keeps `apns.payload.aps.badge` an integer. Otherwise the value is inserted as text.
2. **Turn `data` values into strings:**
   - numbers and booleans become text;
   - objects and arrays become JSON-encoded text;
   - `null` entries are removed.
   Each conversion adds a note, e.g. "`data.order_id` converted from number to string".
3. **Validate** (errors block sending; warnings don't):
   - **Errors:**
     - a placeholder that is unknown, or required but empty;
     - a `data` key that FCM v1 reserves: `from`, `message_type`, or any key starting with `google.` or `gcm.notification.`;
     - a `token`, `topic` or `condition` key inside the template (the target is set only in the Target field);
     - a topic that doesn't match `[a-zA-Z0-9-_.~%]+` (a leading `/topics/` is removed automatically);
     - an empty token or condition. Pasted tokens have all whitespace and any surrounding quotes removed first.
   - **Warnings:**
     - a `data` key that older SDKs treat as reserved: `notification`, or any other key starting with `google` or `gcm`;
     - payload larger than 4,096 bytes;
     - a data-only message without `android.priority: "high"`;
     - an iOS background push without `apns-priority: 5` and `content-available: 1`.
4. **Add the target and wrap:** `{ "validate_only": true, "message": { token|topic|condition, ...rendered } }`. The `validate_only` field is included only for dry runs.

### 5.3 Form tab

The form is a structured editor for common paths. **Fields it doesn't cover are kept unchanged** in the template.

- **Variables:** widgets generated from the preset's `VariableDef`s:
  - text → text field;
  - multiline → text area;
  - number → numeric field;
  - boolean → switch;
  - enum → dropdown.
- **Message type:** `Notification + data` or `Data only`. Switching to data-only:
  - removes `notification`;
  - sets `android.priority: high`;
  - sets `apns.headers.apns-priority: "5"` and `apns.headers.apns-push-type: "background"`;
  - sets `apns.payload.aps.content-available: 1`.
  - Switching back to `Notification + data` adds an empty `notification` and removes the three background settings that Data only added.
- **JSON rewrite:** form edits rewrite the JSON with 2-space indentation.
- **Notification:** title, body, image URL.
- **Data:** a key/value table where rows can be added, removed and reordered.
- **Android:**
  - priority (normal/high);
  - `ttl`, `collapse_key`;
  - `notification.channel_id`, `notification.sound`, `notification.click_action`.
- **APNs:**
  - `apns-priority` (5/10);
  - `aps.sound`, `aps.badge`;
  - `content-available`, `mutable-content`.

### 5.4 JSON tab

- A code editor (`re_editor` with JSON highlighting) on the template.
- Edits are parsed as you type (changed 2026-10-03 from a 300 ms pause), so Send or Cmd/Ctrl+Enter right after typing always sends what is on screen.
- While the JSON is invalid:
  - the error and its line are shown;
  - the Form tab is read-only;
  - Send is disabled.
- If `re_editor` doesn't work acceptably on web, the fallback is a monospace `TextField` with the same validation. *Status 2026-10-03:* the web build with `re_editor` 0.10.0 compiles and `re_editor` declares web support. Hands-on checks in Chrome (typing, selection, copy/paste, undo, scrolling) are still to be done by the user, and the fallback is applied only if they fail.

### 5.5 Layout

- **Left column:**
  - project switcher;
  - target picker: Token / Topic / Condition, an autocomplete from saved targets, and **From device…** on desktop;
  - preset picker.
- **Centre:** the Form and JSON tabs.
- **Right column:**
  - the **Preview** of the final request body;
  - the dry-run checkbox and the **Send** button;
  - the **Result** panel.
- Below 1,000 px wide, the three columns become tabs.
- Material 3, following the system light/dark setting.
- **Shortcuts:** Cmd/Ctrl+Enter sends (also from inside the JSON editor, whose own Cmd/Ctrl+Enter "new line" binding is removed; holding the keys sends once), Cmd/Ctrl+S saves the preset.

## 6. Presets

```
Preset { id (uuid), name, description, variables: List<VariableDef>, template, builtIn, createdAt, updatedAt }
VariableDef { key ([a-zA-Z_][a-zA-Z0-9_]*), label, type: text|multiline|number|boolean|enum,
              options (enum only), required, defaultValue }
```

- **Built-in presets** come from `assets/presets/builtin.json` and are read-only, but can be duplicated:
  - Simple notification;
  - Notification with image;
  - Notification + data;
  - Data only (silent / background).
- **Saving:** "Save as preset" creates a new one. "Update preset" overwrites the preset it came from. Unsaved changes show a dot on the preset name. The dot and the "Discard unsaved changes?" question apply only while a preset is loaded.
- **Variables editor:** when the template contains placeholders without a definition, a quick fix offers to add them.
- **Export** of one, several or all presets produces a `*.fcmpresets.json` file:
  ```json
  { "format": "fcm-studio.presets", "version": 1, "exportedAt": "…", "presets": [ … ] }
  ```
  On desktop the user chooses where to save the file. On web the file is downloaded.
  Built-in presets are not exported; every install has them.
- **Import:**
  - checks `format`, and rejects a `version` newer than the app supports;
  - checks each preset;
  - asks what to do when a name already exists: **Keep both** (adds " (2)"), **Replace**, or **Skip**.
  - One choice applies to every name clash in the file.
  - Built-in presets are never replaced.
- Exports never include credentials, targets or history.

## 7. Targets and history

### 7.1 Saved targets

```
SavedTarget { id, label, kind: token|topic|condition, value, projectId?, senderId?,
              source: manual | device(serial, model, package) | history, lastUsedAt }
```

- The star next to the target field saves the current target. A filled star means the target is saved, and tapping it removes the saved target.
- **Tokens read from a device** are saved automatically and labelled `"<model> · <package> (debug|release)"`.
  - They are keyed by `(serial, package)`, so reading the token again updates the saved value instead of adding a duplicate.
- The autocomplete puts targets for the current project first, then the rest, sorted by `lastUsedAt`.
- **Sender-ID check:** when a token's `senderId` and the project's `projectNumber` are both known and differ, a warning appears: "This token belongs to project number X, not <project>". It offers **Switch project** if a saved project matches.
- Tokens are shown shortened in lists, e.g. `fAbC12…9xYz`. The full value is copied on click.

### 7.2 History

```
HistoryEntry { id, sentAt, projectId, environment, target (kind, value, label), presetName?,
               request (final body), validateOnly, httpStatus, outcome: success(messageName) |
               error(code, explanation), responseBody, durationMs }
```

- An entry is written for every send attempt, including failures. **No access token is ever stored.**
- Only the newest 1,000 entries are kept; older ones are removed on insert. A "Clear history" action exists.
- **Filters:** project, success or failure, and dry run or real. A text search covers the target, preset and body.
- **Actions on an entry:**
  - **Resend** (with a new access token);
  - **Open in composer** (the stored message becomes the template, with no variables);
  - **Save as preset**;
  - **Copy as cURL**.

## 8. Sending, errors and cURL

### 8.1 `FcmClient`

```dart
Future<FcmSendResult> send({required String projectId, required Map<String, Object?> body,
                            required AccessTokenProvider auth});
```

- `POST https://fcm.googleapis.com/v1/projects/{projectId}/messages:send`
- Headers: `Authorization: Bearer …`, `Content-Type: application/json`, plus the provider's extra headers.
- Timeout: 20 s.
- The client **does not retry automatically**, except for the single `401` refresh, so a notification can never be sent twice. The result panel offers a **Retry** button instead.
- `FcmSendResult` holds:
  - the HTTP status and duration;
  - the parsed `name` (message ID) on success;
  - on failure, the `error.status`, `error.message`, `details[].errorCode` and `details[].fieldViolations`.

### 8.2 `FcmErrorExplainer`

Turns each failure into a **title, an explanation and a suggested action**. The raw response is always available in a collapsible section.

| Signal | Explanation | Suggested action |
|---|---|---|
| `UNREGISTERED` (404) | The token is no longer valid: the app was uninstalled, its data was cleared, or the token was refreshed | Read the token from the device again |
| `INVALID_ARGUMENT` (400) | Lists each `fieldViolations` entry (field + reason) | Highlights the field in the JSON tab |
| `SENDER_ID_MISMATCH` (403) | The token belongs to a different Firebase project | Switch project |
| `QUOTA_EXCEEDED` (429) | Sending too fast | Wait, then retry |
| `UNAVAILABLE` (503) / `INTERNAL` (500) | Temporary FCM problem | Retry |
| `THIRD_PARTY_AUTH_ERROR` (401) | The APNs key/certificate or web push credentials are missing or invalid in Firebase | Link to the project's Cloud Messaging settings |
| `401 UNAUTHENTICATED` with no FCM code, after the retry | The credential was revoked or the key was deleted | Re-import the key / sign in again |
| `403 PERMISSION_DENIED`, reason `SERVICE_DISABLED` | The FCM API is not enabled for the project | Link to `console.developers.google.com/apis/api/fcm.googleapis.com/overview?project=<id>` |
| `403 PERMISSION_DENIED` (other) | The account lacks permission | Name the role needed (Firebase Cloud Messaging API Admin) |
| Network error or timeout | Offline, DNS failure or timeout | Retry |

### 8.3 `CurlBuilder`

- Produces a bash-style command:
  ```bash
  curl -X POST '<url>' -H 'Authorization: Bearer …' -H 'Content-Type: application/json' -d '<json>'
  ```
  It adds `-H 'x-goog-user-project: …'` when needed, and escapes single quotes correctly.
- Two copy options:
  - **With access token:** a warning says it is valid for up to 1 hour and shouldn't be pasted into chats.
  - **With `$FCM_ACCESS_TOKEN` placeholder.**
- Only bash quoting is supported. On Windows this works in Git Bash or WSL; PowerShell is not supported in v1.

## 9. Device tokens over adb (desktop only)

### 9.1 Finding adb

`AdbLocator` checks these locations in order and uses the first one where `adb version` succeeds:
1. The path set by the user in Settings.
2. `$ANDROID_HOME` or `$ANDROID_SDK_ROOT` + `/platform-tools/adb[.exe]`.
3. The default SDK locations:
   - macOS: `~/Library/Android/sdk/platform-tools/adb`;
   - Windows: `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`.
4. `/opt/homebrew/bin/adb` and `/usr/local/bin/adb`.
5. A `PATH` lookup (`which` / `where`).

Apps launched from Finder don't inherit the shell's `PATH`, which is why the explicit list comes first. Settings shows the path that was found, with a **Change** button.

All adb calls go through an injectable **`ProcessRunner`**. Every call has a 10 s timeout, uses `exec-out` where output is binary-sensitive, and decodes output as UTF-8 with `allowMalformed`.

### 9.2 Devices and packages

- **`DevicesBloc`** runs `adb track-devices -l` as a long-lived process. The output is a sequence of messages, each a 4-hex-digit length followed by that many bytes of payload.
  - The bloc parses each message into a device list.
  - If the process exits, it restarts with backoff (1, 2, 4… up to 30 s).
- **Device states** shown:
  - `device` (ready);
  - `unauthorized` (with the hint "Accept the USB debugging prompt on the phone");
  - `offline`.
- **Device details:** `ro.product.marketname` (falling back to `ro.product.model`), `ro.product.brand` and `ro.build.version.release`.
- **Packages:** `pm list packages -3`, sorted, with a search box. The last 5 packages used on that device are listed first.

### 9.3 Getting the token (`AdbService.readFcmToken(serial, package)`)

**Step 1: `run-as` (debug builds).**

`adb -s <serial> exec-out run-as <package> cat shared_prefs/com.google.android.gms.appid.xml`

| Output | Meaning | UI |
|---|---|---|
| XML | Parse the file (below) | Show the token(s) |
| `run-as: package not debuggable: <package>` (seen on the Redmi 14C, Android 16, 2026-10-03) | Release build | Offer Step 2 |
| `cat: shared_prefs/com.google.android.gms.appid.xml: No such file or directory` | No token yet | "Open the app once so it gets a token", with a **Launch app** button, then **Retry** |
| `run-as: unknown package: <package>` (Android 16, seen 2026-10-04; older Android prints `Package '<p>' is unknown`, and both are handled) | Not installed | Error message |

**Parser (`AppIdPrefsParser`, pure Dart):**
- For each `<string name="…">` whose name matches `^(.*)\|T\|(\d+)\|(.*)$`, group 2 is the **sender ID**.
- The value is JSON `{"token","appVersion","timestamp"}` in current SDKs. Older SDKs store a raw token; the parser accepts it if it looks like an FCM token.
- If there are several sender IDs, all of them are listed, and the one matching the current project's number is preselected.
- *Not yet confirmed on a device: the capture was skipped on 2026-10-04. The parser follows the format above, and `test/fixtures/adb/appid_prefs_synthetic.xml` is written by hand in that format. The M3 success test on the Redmi confirms it.*

**Step 2: logcat (release builds).**

This step runs only after the user confirms, because it restarts the app.
1. `am force-stop <package>`
2. `monkey -p <package> -c android.intent.category.LAUNCHER 1`
3. Poll `pidof <package>` every 250 ms, for up to 10 s.
4. Stream `logcat --pid=<pid>`, which includes earlier lines from that process.
5. Match `[A-Za-z0-9_-]{20,}:APA91b[A-Za-z0-9_-]{50,}`.
6. Stop at the first match or after 20 s.

- The step **never runs `logcat -c`**, so other tools such as Android Studio keep their logs.
- If nothing matches, the message explains that this release build doesn't print its token. The alternatives are a debug build or a debug-only log line.

**Result:** the token, its sender ID, the method (`run-as` or `logcat`) and when it was read. It becomes the composer's target and is saved automatically as a device target (§7.1).

## 10. Storage and security

- **`AppDatabase` (sembast):**
  - one store each for projects, presets, targets, history and settings;
  - desktop: a file in `getApplicationSupportDirectory()`;
  - web: IndexedDB via `sembast_web`.
  - Each record carries a `schemaVersion`, and migrations run at startup.
- **`SecretStore` (flutter_secure_storage):**
  - holds service account JSONs (`sa:<client_email>`) and Google refresh tokens (`google:<email>`);
  - secrets never go into sembast, logs, history or exports.
  - *Windows (checked 2026-10-03):* `flutter_secure_storage_windows` 4.1.0 stores values in a DPAPI-encrypted file (`DpapiJsonFileMapStorage`), not in Credential Manager, so a 2.4 KB service account JSON fits. No fallback is needed.
  - *macOS:* use `MacOsOptions(usesDataProtectionKeychain: false)`. The default data-protection keychain needs the `keychain-access-groups` entitlement and a signing team, which unsigned internal builds don't have. The login keychain may ask "Always Allow" after a rebuild changes the app's signature.
- **Web:**
  - service account keys stay **in memory only** by default;
  - "Remember on this browser" saves them through `flutter_secure_storage`'s web backend, with a warning that browser storage can be read by scripts on the same site.
- **Removing a project** also deletes its secret, unless another project uses the same credential.
- **macOS:**
  - `com.apple.security.app-sandbox` is set to `false`, so the app can run adb;
  - `com.apple.security.network.client` is enabled.

## 11. Error handling principles

- Every failure the user can see includes **what happened, why, and what to do next**. Raw details are collapsible.
- Bad input (missing variables, invalid JSON, a reserved data key) is caught **before** sending and shown next to the field.
- adb failures name the command that failed. They never block the rest of the app, which works without adb.
- Unexpected exceptions are caught at the Cubit/Bloc level, redacted, and shown as a dismissible error. The app never crashes to a blank screen.

## 12. Testing

- **Unit tests** (pure Dart):
  - `MessageRenderer`: substitution, typed placeholders, data-to-string conversion, reserved keys, missing values, size warning.
  - Target validation and `PresetCodec`: version checks, name conflicts, invalid files.
  - `AppIdPrefsParser`, using fixtures from the real device.
  - The logcat regex and the adb output parsers (`devices -l`, `track-devices` framing, `pm list`, `run-as` errors).
  - `FcmErrorExplainer`, using fixtures of real FCM error responses.
  - `CurlBuilder`: quote escaping.
  - JWT claims, and token caching and expiry with a fake `Clock`.
  - A PKCS#8 key generated for the tests.
- **HTTP tests:** `FcmClient`, the token providers and `FirebaseProjectsApi` against `package:http/testing.dart` `MockClient`. Covers the single 401 retry and the absence of other retries.
- **Cubit/Bloc tests** (plain `test`s that drive the cubit and check its state):
  - composer (rendering, sending, the prod confirmation flow);
  - presets (import conflicts);
  - `DevicesBloc` with a fake `AdbService` (plug/unplug, restart backoff, run-as → logcat flow).
- **Widget tests:**
  - Form ↔ JSON sync, keeping unknown fields;
  - invalid JSON disables Send;
  - the prod confirmation that requires typing the project ID for topic and condition sends.
- **Manual checklist** (in the README):
  - On the Redmi 14C with a debug Flutter app that uses `firebase_messaging`: token via run-as, then send a notification, a data-only message and a dry run.
  - The `com.syldel.delivery` release build through the logcat path.
  - The web build in Chrome: service account import, then a topic send.
  - Google sign-in on desktop and on web.
  - A Windows smoke test on a teammate's machine.
- **Commands:** `flutter analyze` and `flutter test` must pass before every milestone is called done.

## 13. Milestones

| # | Milestone | Done when |
|---|---|---|
| M0 | **Checks.** Debug-build token file format on the Redmi (fixtures captured); `dart_jsonwebtoken` with a real service account PKCS#8 key; `re_editor` on web. *Already settled on 2026-10-03:* Windows secure-storage size (no limit, see §10). *Moved to the start of M4:* `x-goog-user-project` with a user token, because `gcloud` isn't installed and the check only matters for Google sign-in | Each check is recorded in the spec as confirmed, or as changed with the fallback applied |
| M1 | **Send from a service account.** Scaffold, storage, `SecretStore`, `ServiceAccountTokenProvider`, `FcmClient`, projects (service account), composer JSON tab + preview + Send + result, `FcmErrorExplainer` | A notification sent from the tool arrives on the Redmi |
| M2 | **Developer experience.** Form tab, presets (built-in, editor, variables, import/export), saved targets, history, dry run, cURL, prod safeguard | The success test works with a pasted token |
| M3 | **Devices.** `AdbLocator`, `DevicesBloc`, packages, run-as token, logcat fallback, sender-ID check | The success test works fully on the Redmi in under 30 s |
| M4 | **Google sign-in.** Desktop loopback, web popup, project list import | A teammate adds projects and sends without any key file |
| M5 | **Release builds.** macOS `.app` zip, Windows zip, static web build, README (setup, OAuth, manual checklist) | A teammate installs it from the README alone |

**M0 token-file capture (2026-10-03):** deferred to the start of M3. It needs a debug build that uses `firebase_messaging` on the Redmi, plus the user running the capture commands, and nothing in M1 depends on it.

**M0/M1 status (2026-10-03):**
- *Done:*
  - All M1 code, with 115 automated tests passing and a clean `flutter analyze`.
  - The macOS debug build and the web build both succeed.
  - The macOS app launches and creates its database with no errors.
  - `tool/check_sa_token.dart` reaches Google's token endpoint. A throwaway key gets `invalid_grant: account not found`, which means the signed assertion's format is accepted.
- *Pending, needs the user:*
  - The real service account key check (`dart run tool/check_sa_token.dart <key.json>`).
  - The M1 end-to-end send to the Redmi from the macOS app, including Keychain persistence after a relaunch.
  - The hands-on `re_editor` check in Chrome, and the web reload / "Remember" flow.
  - The M0 token-file capture: skipped on 2026-10-04; the M3 success test checks the format instead.

**M2 status (2026-10-03):**
- *Done:* the M2 code with its automated tests passing and a clean `flutter analyze`; the macOS debug and web builds succeed.
- *Manual:* Pending, needs the user:
  - the timed success test with a pasted token on a real phone;
  - a dry run;
  - a data-only send;
  - persistence after a relaunch;
  - the production safeguards;
  - History → Resend and Copy as cURL;
  - preset export and import;
  - the web check in Chrome.
- *Still pending from M1:*
  - The real service account key check (`dart run tool/check_sa_token.dart <key.json>`).
  - The M1 end-to-end send to the Redmi from the macOS app, including Keychain persistence after a relaunch.
  - The hands-on `re_editor` check in Chrome, and the web reload / "Remember" flow.
  - The M0 token-file capture: skipped on 2026-10-04; the M3 success test checks the format instead.

## 14. Open risks

- **Token file format.** The format is inferred from the Firebase SDK's code and has not been seen on a device yet. M0 confirms it, and the parser accepts both known formats. The capture was skipped on 2026-10-04, so the M3 success test on the Redmi confirms the format.
- **Google sign-in in "Testing" mode.** Refresh tokens expire after 7 days, so people sign in again weekly. This is acceptable for an internal tool. Publishing and verifying the app later would remove it.
- **Unsigned macOS build.** Gatekeeper blocks the first launch, and the user must right-click and choose Open. The README explains this. Notarisation is out of scope.
