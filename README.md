# FCM Studio

FCM Studio sends Firebase Cloud Messaging (FCM) push notifications while you build and test apps. It replaces the Postman routine of generating an OAuth access token by hand, copying a device token, and typing the JSON payload from memory.

To send one, pick a Firebase project and read the token straight from a USB-connected Android phone. Then choose a preset and press **Send**. The aim is a notification on the phone in under 30 seconds.

FCM Studio is one Flutter app with no backend. It runs on macOS, Windows and the web. The hosted web build is at **https://fcm-studio-oauth.web.app**.

## Contents

- [Features](#features)
- [Where it runs](#where-it-runs)
- [Your first notification](#your-first-notification)
- [Feature guide](#feature-guide)
  - [1. Projects](#1-projects)
  - [2. Composer](#2-composer)
  - [3. Reading a token from a phone](#3-reading-a-token-from-a-phone)
  - [4. Presets](#4-presets)
  - [5. Targets](#5-targets)
  - [6. History](#6-history)
  - [7. Settings](#7-settings-desktop-only)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Common FCM errors](#common-fcm-errors)
- [Where your data is kept](#where-your-data-is-kept)
- [Troubleshooting](#troubleshooting)
- [Build from source](#build-from-source)
- [Development](#development)

## Features

- **Two ways to sign in.**
  - With a service account key: choose the file, drop it on the dialog, or paste its JSON.
  - With Google sign-in, which lists every Firebase project your account can see.
- **Composer.** The Form and JSON editors change the same message. A live preview shows the exact request. Placeholders such as `{{order_id}}` are filled in from variables. Mistakes are caught before anything is sent.
- **Device tokens from the phone.** FCM Studio reads an app's FCM token from an Android phone over USB.
  - Debug builds use `run-as`.
  - Release builds can fall back to the app's log.
- **Presets.**
  - 4 generic presets and 23 presets that copy the 6amMart backend's real payloads.
  - Your own presets, which you can export to a file and import to share with others.
- **Saved targets, and a history of every send** with Resend and Copy as cURL.
- **Plain-language errors.** Every FCM error says what happened and what to do next.
- **Production safeguard.** Projects marked `prod` show a red banner and ask before every send.

## Where it runs

| | macOS / Windows app | Web in Chrome or Edge | Web in Firefox or Safari |
|---|---|---|---|
| Send, presets, targets, history | Yes | Yes | Yes |
| Service account key | Yes | Yes | Yes |
| Google sign-in | Yes | Yes | Yes |
| Read tokens from a phone | Through adb | Over USB, or through the bridge | Through the bridge |

- Reading tokens works for **Android only**. iOS keeps the token in the Keychain, where no outside tool can read it.
- "USB" on the web means WebUSB: the browser talks to the phone directly.
- "Bridge" is a small helper you run on your computer, which uses your adb. See [Web: two ways to connect](#web-two-ways-to-connect).

## Your first notification

1. **Open FCM Studio.** Use https://fcm-studio-oauth.web.app, or the desktop app (see [Build from source](#build-from-source)).
   - macOS: the build is unsigned. The first time, right-click the app and choose **Open**.
2. **Add a project.**
   - In the Composer, click **Add project** under the **Project** field.
   - Then add a service account key, or use **Sign in with Google…** ([details](#1-projects)).
3. **Connect the phone.**
   - Turn on USB debugging on the phone and plug it in.
   - On the web, also connect it on the Devices screen first ([details](#web-two-ways-to-connect)).
4. **Pick the target.**
   - Press **From device…** next to the target field. If only one phone is ready, it's selected for you.
   - Tap your app. The token goes into **Target**, and the Composer comes back.
5. **Pick a preset.** Type in the **Preset** search field, for example `simple`, and choose **Simple notification**.
6. **Send.** Fill in the variables, then press **Send** (or Cmd/Ctrl+Enter). The result panel shows the message ID, and the notification appears on the phone.

No phone at hand? Choose **Token** and paste a token, or send to a **Topic**.

## Feature guide

### 1. Projects

Every send goes to the project selected in the **Project** field at the top of the Composer.

#### Add a project with a service account key

**Get a key:** Firebase console → Project settings → Service accounts → **Generate new private key**.

> Tip: create a separate service account that only has the **Firebase Cloud Messaging API Admin** role, and use its key here.

Then, in **Add project**, use any of these three ways:

- **Choose key file…**: pick the `.json` file.
- **Drop the file** on the box that says "Drop the key .json file here". If you drop several files, the first `.json` is used.
- **Paste the JSON** into **Or paste the key JSON**, then click **Add pasted key**. The box is cleared once the key is added.

When you add a key, FCM Studio:
- checks the key, and asks Google for an access token, so a bad or disabled key fails straight away with a clear message;
- reads the project's name and project number.

**If the key can't read the project number,** the project is still added. You can set the number later with **Set project number…** in the project menu (Firebase console → Project settings → General → Project number). It's optional: FCM Studio uses it only to warn when a device token belongs to a different project.

**On the web,** the key stays only until the tab is closed or reloaded. To keep it, tick **Remember on this browser**. Browser storage can be read by scripts on the same site, so only do this on a browser you trust.

#### Add projects with Google sign-in

1. In **Add project**, click **Sign in with Google…**.
   - **Desktop:** your browser opens. Finish signing in there.
   - **Web:** a Google pop-up opens. If the browser blocks it, allow pop-ups for the site and try again.
   - **Cancel sign-in** stops waiting.
2. Allow **both** permissions Google asks for.
3. Tick the projects you want. You can search them by name or project ID.
4. Click **Add N projects**.
   - A project you already added switches to this Google account and keeps its environment.

**What it needs:**
- **One-time setup:** someone on the team creates the OAuth clients and fills in `config/oauth.json` ([docs/oauth-setup.md](docs/oauth-setup.md)). Without that file, the Google button is disabled.
- **Two roles for your account** on each project:
  - **Firebase Cloud Messaging API Admin** (or Firebase Admin, Editor, Owner), to send;
  - **Service Usage Consumer** (or Editor, Owner), because sends are billed to the target project.
- **Sign in again every 7 days.** While the Google app is in "Testing", Google ends each sign-in after 7 days. Use **Sign in again…** in the project menu.

#### The project menu

The menu next to the **Project** field has:

- **Environment:** `dev`, `staging` or `prod`. New projects start as `dev`. A coloured chip next to the project field shows it.
- **Set project number…**
- **Signed in as …** and **Sign in again…** (Google projects only). Sign in again with the same account.
- **Remove project…**
  - FCM Studio forgets the project and its stored key, unless another project uses the same key or sign-in.
  - Nothing changes in Firebase.

#### Production safeguard

When the selected project is `prod`:

- A red banner says **PRODUCTION · project-id · every send asks for confirmation**.
- Every send asks **Send to production?**
- A topic or condition send names its audience, for example "every device subscribed to `all_zone_store`". You must type the project ID before **Send** is enabled.
- Dry runs skip the question, because they deliver nothing.

### 2. Composer

The Composer has three columns:
- **Setup:** project, target and preset;
- **Message:** the Form and JSON tabs;
- **Preview & result.**

In a window narrower than 1,000 px, the columns become tabs.

#### Target

Choose **Token**, **Topic** or **Condition**:

- **Token:** paste the FCM registration token. Spaces, line breaks and surrounding quotes are removed for you.
- **Topic:** the topic name without `/topics/`, for example `news`.
- **Condition:** a topic expression, for example `'news' in topics && 'sports' in topics`.

Other target tools:
- **Suggestions:** typing in the field suggests saved targets, with the current project's first.
- **Star:** the star saves the current target, and tapping a filled star removes it.
- **From device…** opens the Devices screen to read a token from a phone ([section 3](#3-reading-a-token-from-a-phone)).
- **Wrong-project warning:** if a token belongs to a different Firebase project than the selected one, a warning says so. It offers **Switch to …** when that project is added.

#### Preset

The **Preset** field is a search.

- **Searching:** type words in any order, ignoring case. For example, `store chat` finds "Store app · Chat message".
- **Order:** your presets are listed before the built-in ones.
- **Unsaved changes:** a dot before the name means the loaded preset has unsaved changes. Switching to another preset then asks **Discard unsaved changes?**
- **Save as preset…** creates a new preset. **Update preset** overwrites the loaded one.
- **Cmd/Ctrl+S:** updates your loaded preset, or asks for a name (Save as preset…) when the message isn't from one of your presets.

#### Variables

Write `{{name}}` anywhere in a string value, and FCM Studio fills it in from the **Variables** section.

- **Defining variables:** **Edit variables…** lets you set each variable's key, label, type, default value, and whether it's required.
  - The types are: Text, Multi-line text, Number, On/off, and Choice list.
- **Placeholders without a variable:** the Composer offers **Add as variables**.
- **Built-in values:** `{{now_iso}}`, `{{now_ms}}` and `{{uuid}}` need no definition, and get new values on every send.
- **Numbers and on/off values:** a value that is exactly one Number or On/off placeholder keeps its type, so `"{{badge}}"` becomes the number `3`, not the text `"3"`. An empty optional Number or On/off variable removes its field.

#### Form and JSON tabs

Both tabs edit the same message: the FCM `message` object, without the target.

**Form tab:**
- **Message type:**
  - **Notification + data**;
  - **Data only** (silent). It removes `notification` and sets the high-priority and background settings Android and iOS need.
- **Notification:** title, body, image URL.
- **Data:** key/value rows that you can add, remove and reorder.
- **Android:** priority, TTL, collapse key, channel ID, sound, click action.
- **APNs (iOS):**
  - priority, sound, badge;
  - **Wake the app in the background** (`content-available`);
  - **Let a notification service extension change it** (`mutable-content`).
- Fields the form doesn't show are kept as they are.

**JSON tab:**
- A code editor for the whole message.
- While the JSON is invalid:
  - the error and its line are shown;
  - the Form tab is read-only;
  - Send is disabled.

#### Checks before sending

**Errors stop the send:**
- a placeholder with no variable, or a required variable left empty;
- a `data` key that FCM reserves: `from`, `message_type`, or anything starting with `google.` or `gcm.notification.`;
- `token`, `topic` or `condition` inside the message. Set the target in the Target field instead;
- an invalid topic name, or an empty token or condition.

**Warnings don't stop it:**
- a message larger than 4,096 bytes;
- a data-only message without Android high priority;
- an iOS background push without `apns-priority: 5` and `content-available: 1`.

FCM needs every `data` value to be a string. Numbers, booleans and objects are converted for you, and the preview notes each change.

#### Preview and cURL

**Request preview** shows the exact body that will be sent. Its buttons:
- **Copy request body**;
- **Copy as cURL**, with two choices:
  - **with access token.** The token works for up to 1 hour, so don't paste the command into chats;
  - **with $FCM_ACCESS_TOKEN**, which leaves a placeholder you fill in yourself.

The cURL commands use bash quoting. On Windows, run them in Git Bash or WSL.

#### Send

- **Dry run (validate only):** FCM checks the message but delivers nothing.
- **Send**, or Cmd/Ctrl+Enter, even from inside the JSON editor.
- **On success:** **Sent** (or **Valid** for a dry run), with the message ID and how long it took.
- **On failure:**
  - a title, what went wrong, and what to do;
  - buttons such as **Show `field` in JSON**, **Open in console** or **Retry**;
  - the raw response.
- **No automatic resend:** FCM Studio never sends a message twice by itself, so a notification is never delivered twice by mistake. The one exception: when Google rejects an expired access token (401), the token is refreshed and the send is tried once more. Use **Retry** after any other failure.

### 3. Reading a token from a phone

**Before you start:**
1. On the phone, turn on **Developer options**, then **USB debugging**.
2. Plug the phone in with USB.
3. Accept **Allow USB debugging?** on the phone. Tick "Always allow from this computer".

**Which builds work:**

| App build | How FCM Studio gets the token |
|---|---|
| **Debug** | `run-as` reads the token file of the Firebase SDK directly. Fast and reliable. |
| **Release** | `run-as` isn't allowed. FCM Studio can restart the app and watch its log, but this only works if the app prints its token to the log. |

#### Reading a token

1. In the Composer, press **From device…**, or open **Devices**.
2. **Choose the phone:**
   - If only one phone is ready, it's selected for you.
   - Phones that aren't ready show a hint, such as **Accept the USB debugging prompt on the phone**.
3. **Find the app:**
   - Search with **Search apps**. The last 5 apps you used on that phone are at the top.
   - **Refresh the app list** after you install an app.
4. **Tap the app.** One of these happens:
   - **The token is found.** It goes into Target, and you're back in the Composer. The token is also saved as a target named like `Redmi 14C · com.example.app (debug)`. Reading it again updates the same saved target.
   - **The app has tokens for several Firebase projects.** Pick one. The one matching the selected project is already selected.
   - **"Open the app once so it gets a token."** Press **Launch app**, wait a moment, then **Retry**.
   - **The app is a release build.** Press **Restart the app and read its log…**, then **Restart and read**.
     - The app is closed and opened again, and its log is watched for up to 20 seconds.
     - Nothing is cleared from the log, so Android Studio keeps its logs.
     - If no token shows up, the app doesn't print it. Use a debug build, or add a debug-only log line that prints the token.

#### Desktop (adb)

The desktop app uses adb from the Android SDK Platform-Tools. It looks for adb in this order:
1. the path set in Settings;
2. `$ANDROID_HOME` or `$ANDROID_SDK_ROOT`;
3. the default SDK folder (`~/Library/Android/sdk` on macOS, `%LOCALAPPDATA%\Android\Sdk` on Windows);
4. Homebrew (`/opt/homebrew/bin`, `/usr/local/bin`);
5. `PATH`.

If adb isn't found, set its path in [Settings](#7-settings-desktop-only). The phone stays shared, so Android Studio and other IDEs keep working at the same time.

#### Web: two ways to connect

The web Devices screen has two buttons: **Connect a phone (USB)** and **Bridge**. Phones from both appear in one list, each with a **USB** or **Bridge** label.

| | Connect a phone (USB) | Bridge |
|---|---|---|
| Needs | Chrome or Edge, a page on https or localhost, Android 7 or newer | adb and the Dart SDK on your computer (Flutter includes Dart) |
| Browsers | Chrome, Edge, Opera | Any browser. Safari may block an https page from reaching your computer |
| Shared with Android Studio and other IDEs | No: a phone has one USB owner at a time | Yes, as with the desktop app |
| Best for | Teammates without adb | Android and Flutter developers |

##### Connect a phone (USB)

1. Click **Connect a phone (USB)** and choose the phone in the browser's list.
2. Accept **Allow USB debugging?** on the phone. Tick "Always allow" so it doesn't ask again.
3. The row becomes **Ready**.

Things to know:
- **Later visits:** the phone connects by itself.
- **Row menu:**
  - **Retry** reconnects a phone that is offline or stuck connecting.
  - **Forget** removes this site's access to the phone.
- **"This phone is in use by another program":** adb or Android Studio holds the phone. Quit Android Studio or run `adb kill-server`, then click **Retry**. Or use the bridge instead.
- **The browser's key:** the browser keeps a USB debugging key for this site, so the phone doesn't ask again on every visit.

##### Bridge

The bridge is one file, `fcm_bridge.dart`. It lets the page use your computer's adb, so the phone stays shared with your IDE.

1. **Get the file.** On the Devices screen, open **Bridge** and choose **Download fcm_bridge.dart**. It's also in this repository at [web/fcm_bridge.dart](web/fcm_bridge.dart).
2. **Start it** in the folder where you saved it:
   ```bash
   dart fcm_bridge.dart
   ```
   It prints `FCM Studio bridge ready on 127.0.0.1:15037 (adb: …). Keep this window open.`
3. **Connect.** Open **Bridge** and choose **Connect through bridge**.
   - Chrome may ask once whether this site may reach apps on your device. Allow it.
4. **Use it.** Phones appear with the **Bridge** label.
   - After the first connection, the page connects by itself on later visits.
   - If the bridge isn't running yet, the page keeps trying, and connects as soon as you start it.
   - On `localhost` it connects from the start.

**To stop using it,** choose **Bridge → Disconnect**. The page stops reconnecting. The bridge keeps running until you close its window (Ctrl+C).

**Options:**

```text
dart fcm_bridge.dart [--adb <path>] [--allow-origin <origin>]... [--help]

  --adb <path>             the adb to use (default: PATH, ANDROID_HOME,
                           ANDROID_SDK_ROOT, then the Android SDK's folder)
  --allow-origin <origin>  also accept FCM Studio from this address,
                           e.g. https://fcm-studio.example.com
```

The bridge accepts `http://localhost:<any port>`, `http://127.0.0.1:<any port>` and `https://fcm-studio-oauth.web.app` without any options. Hosting FCM Studio somewhere else? Start the bridge with `--allow-origin <that address>`.

**Why it's safe to run:**
- It listens only on `127.0.0.1:15037`, so nothing on your network can reach it.
- It accepts only FCM Studio's own addresses.
- It runs only the read-only adb commands FCM Studio needs:
  - phone details and the app list;
  - launching the app, stopping it, and finding its process;
  - reading the token file and the app's log.
- It refuses anything else, such as extra commands joined with `;` or `&&`.
- It never prints what the commands return, so tokens don't end up in your terminal.

**What the bridge line says:**

| Line | What to do |
|---|---|
| Bridge: connected · adb: `<path>` | Nothing. You're connected. |
| The bridge isn't running… | Start it with `dart fcm_bridge.dart`. If it's already running, its window says why it refused the page (usually a missing `--allow-origin`). |
| This fcm_bridge.dart doesn't match this page… | Download the file again, restart it, then click **Try again**. |
| adb wasn't found… | Restart the bridge with `--adb <path to adb>`. |
| The browser is blocking this site… | Allow the site to reach apps on this device in the site settings (the icon left of the address), then **Try again**. |

### 4. Presets

#### Built-in presets

Built-in presets are read-only. Use **Duplicate** to make an editable copy.

- **Generic:** Simple notification, Notification with image, Notification + data, Data only (silent / background).
- **6amMart (23 presets):** named "User app · …", "Delivery app · …", "Store app · …" and "6amMart · …".
  - They copy the real payloads of the 6amMart backend, including every key it sends (empty where it sends nothing), `channel_id: "6ammart"` and the sound `notification.wav`.
  - Together they cover all 35 `data.type` values the backend sends. A preset that covers several types has a **Type** choice list.

#### The Presets screen

The screen lists **My presets** first, then **Built-in**. Each preset's menu has:
- **Open in composer**
- **Duplicate**
- **Rename…**
- **Export…**
- **Delete…**

#### Export and import

**Export:**
- Tick presets, then click **Export N**. With nothing ticked, **Export all** exports everything, built-in presets included.
- The file is `*.fcmpresets.json`. On desktop you choose where to save it; on the web it's downloaded.
- Exports never include keys, targets or history.

**Import…:**
- Choose a `.fcmpresets.json` file.
- If names are already used, choose **Keep both** (adds " (2)"), **Replace** or **Skip**. The choice applies to every clash in the file.
- Built-in presets are never replaced. A clash with one is kept as a copy.

### 5. Targets

**Saved targets** lists every target you starred or read from a phone.

- Click a target to copy its full value. Tokens are shown shortened, for example `fAbC12…9xYz`.
- Each target's menu has **Use in composer**, **Rename…** and **Delete**.

### 6. History

Every send attempt is saved, including dry runs and failures.

- **What's kept:** the newest 1,000 entries.
- **What's never kept:** access tokens.
- **Filters:**
  - a project, or **All projects**;
  - **All / Succeeded / Failed**;
  - **Real + dry run / Real / Dry run**;
  - a search over target, preset and body.

Each entry shows the request and the response, and has these actions:
- **Resend:** sends the same message again, with a current access token.
- **Open in composer:** the sent message becomes the Composer's message.
- **Save as preset…**
- **Copy as cURL:** with the access token, or with `$FCM_ACCESS_TOKEN`.

**Clear history** deletes every entry.

### 7. Settings (desktop only)

**Android Debug Bridge (adb)** shows the adb in use, its version, and where it was found.
- **Change…** → type the full path in **Path to adb** → **Use**.
- **Find automatically** forgets your path and searches again.

## Keyboard shortcuts

| Keys | Action |
|---|---|
| Cmd/Ctrl + Enter | Send (also inside the JSON editor) |
| Cmd/Ctrl + S | Update your loaded preset, or save the message as a new preset |

## Common FCM errors

FCM Studio explains every error in the result panel. The ones you'll meet most:

| Error | Meaning | What to do |
|---|---|---|
| `UNREGISTERED` (404) | The token is no longer valid: the app was uninstalled, its data was cleared, or the token changed | Read the token from the phone again |
| `INVALID_ARGUMENT` (400) | A field is wrong. The panel lists each one | Click **Show `field` in JSON** |
| `SENDER_ID_MISMATCH` (403) | The token belongs to another Firebase project | Switch to that project |
| `THIRD_PARTY_AUTH_ERROR` (401) | The iOS APNs key or certificate is missing in Firebase | Add it in the project's Cloud Messaging settings |
| `PERMISSION_DENIED` · `SERVICE_DISABLED` (403) | The FCM API is off for the project | **Open in console** and enable it |
| `PERMISSION_DENIED` · `USER_PROJECT_DENIED` (403) | Your Google account may not bill the project | Ask for **Service Usage Consumer**, or use a service account key |
| `PERMISSION_DENIED` (403), other | The account can't send | Ask for **Firebase Cloud Messaging API Admin** |
| `QUOTA_EXCEEDED` (429) | Sending too fast | Wait, then **Retry** |
| `UNAVAILABLE` (503), `INTERNAL` (500), network error | A temporary problem | **Retry** |

## Where your data is kept

Everything stays on your computer or in your browser. There is no server, and nothing is synced.

| What | Desktop | Web |
|---|---|---|
| Projects, presets, targets, history, settings | `fcm_studio.db` in the app's support folder | The browser's IndexedDB |
| Service account keys, Google sign-ins | macOS login keychain; on Windows, a file encrypted for your user | Memory only, unless you tick **Remember on this browser** |
| The browser's USB debugging key | — | Kept for the site, so phones don't ask again |

**Never stored or logged:**
- access tokens: not in history or logs;
- device tokens: not in logs;
- error messages are cleaned of keys and tokens.

## Troubleshooting

**Starting the app and signing in**

| Problem | Fix |
|---|---|
| macOS says the app can't be opened | The build is unsigned. Right-click the app and choose **Open**. |
| macOS asks for the keychain after a rebuild | Choose **Always Allow**. A rebuild changes the app's signature. |
| **Sign in with Google…** is disabled | `config/oauth.json` is missing. See [docs/oauth-setup.md](docs/oauth-setup.md). |
| The Google pop-up doesn't open (web) | Allow pop-ups for the site, then try again. |
| "Sign in again" after about a week | Normal while the Google app is in Testing. Use **Sign in again…** in the project menu. |
| The key is gone after reloading the page | Add it again and tick **Remember on this browser**. |

**Phones and tokens**

| Problem | Fix |
|---|---|
| **adb was not found** | Install Android SDK Platform-Tools, or set the path in Settings. |
| The phone shows **Accept the USB debugging prompt on the phone** | Unlock the phone and accept the prompt. |
| The phone shows **Offline** | Unplug the phone and plug it in again. |
| USB on the web says "in use by another program" | Quit Android Studio or run `adb kill-server`, then **Retry**. Or use the bridge. |
| **Connect a phone (USB)** is disabled | USB needs Chrome or Edge, over https or localhost. Use the bridge in other browsers. |
| The bridge line says it isn't running | Start `dart fcm_bridge.dart` and keep its window open. If it's running, read its window: it names the address it refused. |
| A release build's token isn't found in the log | The app doesn't print its token. Use a debug build. |

## Build from source

**Requirements:**
- Flutter 3.44 or newer (stable channel, Dart 3.12).
- macOS app: Xcode.
- Windows app: Visual Studio with "Desktop development with C++".
- Reading tokens on desktop or through the bridge: Android SDK Platform-Tools (adb).

**Run it:**

```bash
git clone git@github.com:Mobarak6/fcm_studio.git
cd fcm_studio
flutter pub get

flutter run -d macos                     # macOS app
flutter run -d windows                   # Windows app
flutter run -d chrome --web-port 5050    # web; port 5050 is the one Google sign-in allows
```

**Google sign-in (optional):** create `config/oauth.json` from `config/oauth.example.json`, as described in [docs/oauth-setup.md](docs/oauth-setup.md). The file is git-ignored. Without it, everything except Google sign-in works.

**Release builds:**

| Platform | Command | Output |
|---|---|---|
| macOS | `flutter build macos` | `build/macos/Build/Products/Release/FCM Studio.app`. Zip it to share. It's unsigned, so users right-click → **Open** the first time. |
| Windows | `flutter build windows` | `build/windows/x64/runner/Release/`. Share the whole folder; the app is `fcm_studio.exe`. |
| Web | `flutter build web` | `build/web/`, which includes `fcm_bridge.dart` for download |

**Deploy the web build** to Firebase Hosting (project `fcm-studio-oauth`, set in `.firebaserc`):

```bash
flutter build web
firebase deploy --only hosting
```

Two addresses must list the hosting URL:
- the web OAuth client's authorized JavaScript origins, for Google sign-in;
- `hostedOrigins` in `web/fcm_bridge.dart`, for the bridge.

`https://fcm-studio-oauth.web.app` is already in `hostedOrigins`.

## Development

**Checks:** both must pass before a change is done.

```bash
flutter analyze   # strict lints
flutter test      # the whole suite
```

**Layout:**

```
lib/
  app/        app start, dependencies, navigation rail, theme
  core/       auth (service account, Google), fcm (client, errors, cURL),
              firebase (project list), storage (database, secret store), platform
  features/   projects · composer · presets · targets · history · devices · settings
              each with domain/, data/, cubit/ (or bloc/) and view/
web/
  fcm_bridge.dart   the bridge; imports only dart: libraries
assets/presets/builtin.json   built-in presets
test/         mirrors lib/; fixtures/ holds real adb and FCM outputs
```

**Conventions:**
- State lives in `flutter_bloc` Cubits, with a Bloc for the device list.
- Services are created once in `lib/app/dependencies.dart` and passed in through constructors.
- Platform-specific code sits behind conditional imports.

**Check a service account key from the command line.** This prints whether Google issues a token for the key, never the token itself:

```bash
dart run tool/check_sa_token.dart path/to/key.json
```

**Design documents:**
- [Main design](docs/superpowers/specs/2026-10-03-fcm-studio-design.md)
- [Phones on the web over USB](docs/superpowers/specs/2026-10-04-webusb-devices-design.md)
- [Phones on the web through the bridge](docs/superpowers/specs/2026-10-05-web-bridge-design.md)
- [Google sign-in setup](docs/oauth-setup.md)

## License

MIT. See [LICENSE](LICENSE).
