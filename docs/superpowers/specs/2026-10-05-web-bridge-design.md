# FCM Studio: phones on the web through a local bridge

**Status:**
- **Implemented:** 2026-10-05 (M5.1 code with tests).
- **Pending:** the manual success test in §9, on the Redmi in Chrome, Firefox and Safari.

**Milestone:** M5.1. It follows M5 (WebUSB). M6 (release builds) is unchanged.

**Builds on:**
- [2026-10-03-fcm-studio-design.md](2026-10-03-fcm-studio-design.md) (main spec, §9 device tokens);
- [2026-10-04-webusb-devices-design.md](2026-10-04-webusb-devices-design.md) (WebUSB, §4.7 `DeviceShell` and `AdbCommands`).

This document does not repeat them.

## 1. Purpose

With WebUSB the browser claims the phone's USB interface itself. A USB device has one owner at a time, so while the web holds the phone, adb and every IDE (Antigravity, Android Studio) lose it. And while adb holds it, the web shows "in use by another program". The desktop app has no such conflict because it asks the adb server, which shares the phone with every client. A browser can't reach the adb server: it listens on raw TCP port 5037, and pages can't open raw TCP connections.

This milestone gives the web build a second way to reach phones: a small **bridge** program on the user's own computer. The page talks to the bridge over a WebSocket on `127.0.0.1`; the bridge runs the `adb` program. The phone stays with the adb server, so it's shared with the IDEs exactly as with the desktop app.

**Who it's for:**
- **Teammates with adb** (Android or Flutter developers): they use the web build, and the IDE keeps working at the same time.
- **Teammates without adb:** they keep using USB (WebUSB), unchanged.

**Success test:** see §9.

## 2. Decisions

These were made in chat on 2026-10-05.

- **Keep WebUSB and add the bridge.** The web Devices screen offers both.
- **The bridge is one Dart file, `fcm_bridge.dart`, run with `dart fcm_bridge.dart`.** It imports only `dart:` libraries, so it runs without a package or `pub get`. It needs the Dart or Flutter SDK, which adb users normally have. The web build serves it for download.
- **The bridge runs phone commands, not the token logic** (approach A).
  - The web keeps `AdbCommands`, so the desktop, WebUSB and bridge paths all share the same token code.
  - The bridge runs only the commands `AdbCommands` uses (§4.3).
  - Rejected:
    - (B) the bridge does the whole token read: it would need FCM Studio's packages, so a checkout and `pub get`;
    - (C) a raw relay to adb port 5037: it would allow any adb command, and would need the adb server protocol written in the browser.
- **Two buttons; the bridge connects by itself after the first use.**
  - **Connect a phone (USB)** and **Bridge** are always shown.
  - Once the bridge has connected in a browser, the page connects to it automatically on later visits, and keeps trying while it's not running.
  - On a page served from localhost, it connects automatically from the start.
- **Only FCM Studio may use the bridge:** an Origin allow-list of localhost, `--allow-origin` values, and a hosted-origins list in the file. That list is empty until the hosting URL is decided.
- **The bridge listens on `127.0.0.1:15037` only.** It's easy to remember: adb uses 5037.
- **Desktop is unchanged.**

## 3. Facts this design relies on

| Fact | Status |
|---|---|
| `dart <file>` runs a script outside any package when it imports only `dart:` libraries | Known (Dart tooling) |
| `flutter build web` copies the files in `web/` to the build output unchanged; it compiles only `lib/main.dart` | Known (Flutter tooling) |
| `package:web` 1.1.1 has `WebSocket` bindings | Checked 2026-10-05 |
| Chrome treats `ws://127.0.0.1` as potentially trustworthy, so an https page may open it (no mixed-content block) | Known for Chrome |
| Firefox and Safari allow the same from an https page | To check (§9 step 3) |
| Chrome's Local Network Access asks the user once before a public https site reaches loopback (WebSockets included) | To check (§9 step 2) |
| A denied Local Network Access permission can be read with the Permissions API, so the page can say "blocked" instead of "not running" | To check; if not, the "not running" text mentions site settings (§7) |
| Over USB, the serial adb reports equals the USB serial number WebUSB reports, so the same phone can be matched in both lists | To check (§9 step 1); a mismatch only shows the phone twice |

## 4. Architecture

```
Browser (FCM Studio web)                       User's computer
┌──────────────────────────────────────┐       ┌──────────────────────────┐
│ DevicesBloc / TokenReaderCubit       │       │ fcm_bridge.dart          │
│        │ AdbService                  │       │  127.0.0.1:15037         │
│   WebPhones ──┬── WebUsbAdbService ──┼─USB─┐ │  Origin + Host check     │
│               └── BridgeAdbService   │     │ │  command allow-list      │
│                     AdbCommands      │     │ │        │ Process.start   │
│                     BridgeDeviceShell│     │ │      adb ── adb server ──┼─USB─ phone
│                     BridgeClient ────┼─ws──┼─┘                          │
└──────────────────────────────────────┘     └──── (one owner per phone) ─┘
```

### 4.1 `web/fcm_bridge.dart` (the bridge)

**Where it lives:** in `web/`, so every web build serves it at `fcm_bridge.dart` next to `index.html`. Tests import it by relative path.

**Language level:** it starts with `// @dart=3.0`, so the analyzer rejects language features newer than Dart 3.0. It also uses only `dart:io` APIs that exist in Dart 3.0. That way teammates with an older Flutter can run it.

**Command line:**
```
dart fcm_bridge.dart [--adb <path>] [--allow-origin <origin>]... [--help]
```

**At start:**
1. **Find adb**, in this order:
   - `--adb`;
   - `adb` on `PATH`;
   - `$ANDROID_HOME/platform-tools`, then `$ANDROID_SDK_ROOT/platform-tools`;
   - the default SDK folder: `~/Library/Android/sdk` on macOS, `%LOCALAPPDATA%\Android\Sdk` on Windows, `~/Android/Sdk` on Linux.

   If adb isn't found, the bridge still starts. It reports the problem in `hello` (§4.2), and the terminal shows the same hint.
2. **Bind** `InternetAddress.loopbackIPv4` port 15037. If the port is taken, it prints "Port 15037 is in use; is another bridge already running?" and exits with code 1.
3. **Print** `FCM Studio bridge ready on 127.0.0.1:15037 (adb: <path>). Keep this window open.`

**Each WebSocket connection** is handled on its own:
- its requests run at the same time;
- when it closes, the bridge kills every process it started, so no `adb logcat` is left running.

**Requests that aren't WebSocket upgrades** get `400` with the text "FCM Studio bridge: open FCM Studio to use it."

**What it prints:** start-up, each connection opened or closed (with its origin), refused connections and refused commands. It never prints command output: device tokens are never logged.

### 4.2 Protocol

The bridge and the page send JSON text frames. `id` is a number the page picks for each request.

**Bridge → page, first message on every connection:**
```json
{"type": "hello", "protocol": 1, "adb": "/Users/x/Library/Android/sdk/platform-tools/adb"}
{"type": "hello", "protocol": 1, "adb": null, "problem": "adb wasn't found. Start the bridge with --adb <path to adb>."}
```

**Page → bridge:**

| Message | Meaning |
|---|---|
| `{"type": "track", "id": 1}` | Run `adb track-devices -l` and stream its output |
| `{"type": "run", "id": 2, "serial": "…", "kind": "shell" \| "execOut" \| "logcat", "text": "…"}` | Run one phone command (`PhoneCommand`) |
| `{"type": "kill", "id": 2}` | Stop request 2 |

**Bridge → page, for a request:**

| Message | Meaning |
|---|---|
| `{"type": "stdout", "id": 2, "data": "<base64>"}` | A chunk of standard output, as bytes |
| `{"type": "stderr", "id": 2, "data": "<base64>"}` | A chunk of standard error |
| `{"type": "exit", "id": 2, "code": 0}` | The process ended; last message for this id |
| `{"type": "error", "id": 2, "message": "…"}` | It couldn't run (refused, adb missing, spawn failed); last message for this id |

**Arguments:** the bridge builds adb's arguments exactly as `ProcessDeviceShell` does:
- `shell` → `-s <serial> shell <text>`;
- `execOut` → `-s <serial> exec-out <text split on spaces>`;
- `logcat` → `-s <serial> logcat <text split on spaces>`.

It starts the process with an argument list, never through a shell on the computer.

**Versions:** `protocol` is an integer, the same constant in the bridge and the page. A test checks that both are equal. The page refuses a bridge whose number differs (§7), and the number goes up whenever the allow-list or the messages change.

### 4.3 Security

1. **Loopback only:** it binds `127.0.0.1`, so nothing on the network can connect.
2. **Origin allow-list:** the WebSocket upgrade must carry an `Origin` header that is one of:
   - `http://localhost:<any port>` or `http://127.0.0.1:<any port>`;
   - an origin given with `--allow-origin`;
   - an entry in the file's `hostedOrigins` constant (empty until the hosting URL is decided).

   Any other origin, or a missing `Origin`, gets `403`, and the terminal prints:
   ```
   Refused a connection from <origin>. To allow it: --allow-origin <origin>
   ```
3. **Host check (DNS rebinding):** the `Host` header must be `127.0.0.1:15037` or `localhost:15037`.
4. **Command allow-list:** `track`, plus exactly these `run` requests:

   | kind | text |
   |---|---|
   | shell | `getprop ro.product.marketname; getprop ro.product.model; getprop ro.product.brand; getprop ro.build.version.release` |
   | shell | `pm list packages -3` |
   | shell | `monkey -p <package> -c android.intent.category.LAUNCHER 1` |
   | shell | `am force-stop <package>` |
   | shell | `pidof <package>` |
   | execOut | `run-as <package> cat shared_prefs/com.google.android.gms.appid.xml` |
   | logcat | `--pid=<digits>` |

   The patterns:
   - `<package>`: `^[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z][A-Za-z0-9_]*)+$`;
   - the serial: `^[A-Za-z0-9._:-]+$`, and it must not start with `-`;
   - `<digits>`: `^[0-9]{1,10}$`.

   Anything else gets `error` with "fcm_bridge refused this command", and the terminal prints the refused text. So `;`, `&&`, quotes or spaces can't sneak a second command onto the phone.
5. **The page's allow-list test:** a test runs every `AdbCommands` method through a recording `DeviceShell` and checks that the bridge accepts each command. A new command in `AdbCommands` fails that test until the bridge allows it (and `protocol` goes up).

### 4.4 Web client

All files are in `lib/features/devices/data/bridge/`.

**`BridgeChannel`** is a WebSocket behind an interface (`Stream<String> messages`, which ends when the connection closes, plus `send` and `close`).
- `browser/bridge_platform_web.dart` uses `package:web`'s `WebSocket`. It also checks Local Network Access, tells whether the page is local, and downloads the bridge file. It's chosen by a conditional export (`bridge_platform.dart`), as with `webusb_platform.dart`; the VM gets a stub.
- Tests use an in-memory fake, and a `dart:io` WebSocket for the end-to-end test.

**`BridgeClient`** owns the connection.
- It opens `ws://127.0.0.1:15037`, waits for `hello` (5 s), checks `protocol`, and then reports `Connected(adbPath)`.
- It hands out request ids and routes each reply by id.
- **Status stream** (`BridgeStatus`): `off`, `connecting`, `connected(adbPath)`, `notRunning`, `wrongVersion(bridgeProtocol)`, `noAdb(problem)`, `blocked`.
- **Reconnects:** while it's wanted (auto-connect is on, or the user pressed **Connect through bridge**) and not connected, it retries on the same schedule as `DevicesBloc.defaultBackoff` (1, 2, 4, 8, 16, then 30 s). The exception is `wrongVersion`, which waits for **Try again**.
- **`noAdb`:** the client stays connected and lists no phones. Restarting the bridge with `--adb` drops the connection, and the retry then gets a `hello` with adb.
- **`connect()`** starts it; **`disconnect()`** closes the connection and stops retrying.
- **Losing the connection:**
  - every pending `run` fails with `AdbException('The bridge stopped.')`;
  - every started process's stdout ends with that error, and its `exitCode` completes with -1.

**Auto-connect flag:** `SettingsRepository` gets `readBridgeAutoConnect` and `writeBridgeAutoConnect`.
- It's set to true after the first `hello` with a matching `protocol`, and to false on **Disconnect**.
- At app start, the client connects if the flag is true or the page's host is `localhost` or `127.0.0.1`.

**`BridgeDeviceShell implements DeviceShell`:**
- `run` sends `run`, collects stdout and stderr until `exit`, and returns `ProcessOutput`. It decodes UTF-8 the same way `ProcessRunner` does.
- Like desktop, `run` gives up after 10 s (`ProcessRunner.defaultTimeout`): it sends `kill` and throws `` `adb -s <serial> …` (through the bridge) did not finish within 10 seconds ``.
- `start` returns a `RunningProcess` whose stdout is the decoded byte chunks; `kill()` sends `kill`.
- `describe` gives `` `adb -s <serial> shell …` (through the bridge) ``.
- An `error` reply becomes `AdbException(message)`.

**`BridgeAdbService implements AdbService`:**
- `trackDevices` sends `track` and runs the decoded stdout through the existing `TrackDevicesDecoder`.
- Everything else goes to `AdbCommands(shell: BridgeDeviceShell(...))`, with the same timeouts as desktop.

### 4.5 `WebPhones implements AdbService`

This is the web's single `AdbService` (source key `'web'`). It joins the WebUSB phones (when the browser has WebUSB) and the bridge phones.
- **`trackDevices`** combines the latest list from each side:
  - each device gets `link: PhoneLink.usb` or `PhoneLink.bridge`;
  - when the same serial is in both lists, only the bridge entry is kept. That way, while the bridge runs, the "in use" WebUSB row never shows.
- **The bridge side:**
  - it follows `BridgeClient`: an empty list unless connected;
  - if `adb track-devices` ends while connected, it tracks again after the same back-off;
  - bridge failures never end the combined stream, so `DevicesBloc` doesn't restart the WebUSB side.
- **The other methods** go to the bridge if its latest list has the serial, otherwise to WebUSB if its latest list has it. Any other serial throws `AdbException('That phone is no longer connected.')`.
- **`PhoneAccess`** (Connect, Retry, Forget) stays WebUSB-only.

**`AdbDevice`** gets `final PhoneLink? link`, part of `props`. It's null on desktop.

### 4.6 Platform and UI

**Platform:**
- `PlatformFeatures.canReadPhones` becomes true on every web value. `deviceAccess` now only says whether USB (WebUSB) works.
- Desktop is unchanged.

**Wiring:**
- On web, `AppDependencies` creates a `BridgeClient` and a `WebPhones`. `WebPhones` gets the `WebUsbAdbService` only when `deviceAccess == webUsb`.
- `DevicesBloc` is kicked with `DevicesAdbChanged(WebPhones.source)` on every web value.
- The UI gets a `BridgeCubit` (a thin wrapper over `BridgeClient`, with state `BridgeStatus`), provided like `PhoneAccess`.
- The bridge is closed with the tab; desktop's exit guard stays desktop-only.

**Devices screen on web:**
```
[Connect a phone (USB)]   [Bridge ▾]
Bridge: ● Connected · adb: ~/Library/Android/sdk/platform-tools/adb
────────────────────────────────────────────────────────────────
Redmi Note 12        Ready      Bridge
Pixel 7              Ready      USB      ⋮  (Retry / Forget)
```
- **Connect a phone (USB):**
  - same as M5 when `deviceAccess == webUsb`;
  - otherwise disabled, with the reason from WebUSB design §7, ending "Use the bridge instead."
- **Bridge status line and menu:** the line follows the bridge states in §6. The menu has **Connect through bridge** / **Disconnect**.
- **Rows:**
  - each row has a small **USB** or **Bridge** label;
  - bridge rows have no menu (adb manages them);
  - unauthorized or offline bridge rows show the desktop hints from the main spec §9.2.
- **Empty state:** "No phones yet. Start the bridge (if you have adb), or turn on USB debugging, plug the phone in, and click **Connect a phone (USB)**."
- **Download fcm_bridge.dart** saves `Uri.base.resolve('fcm_bridge.dart')` as a file (an anchor with `download`).
- **Copy** puts `dart fcm_bridge.dart` on the clipboard.
- **From device…** in the composer works with bridge phones unchanged.

## 5. Flows

### First use on the hosted site
1. Devices → **Connect through bridge**. The bridge isn't running yet, so the line says how to start it.
2. The user clicks **Download fcm_bridge.dart**, then in that folder runs `dart fcm_bridge.dart`.
3. Within the back-off, the page connects. Chrome may ask once to let the site reach apps on this device; the user allows it.
4. `hello` arrives: **Connected**. Phones appear with the **Bridge** label, and the auto-connect flag is saved.

### Later visits
The page connects at start. When the bridge isn't running, the line says so, and the page keeps retrying. Starting the bridge brings the phones in by itself.

### Bridge stops during a read
The read fails with "The bridge stopped." The bridge rows disappear, and the line shows **not running**. After a restart, the page reconnects, and **Retry** on the read works.

### Disconnect
**Disconnect** closes the connection, clears the flag and stops retrying. The bridge rows disappear. The bridge itself keeps running for other tabs.

## 6. Bridge states

| `BridgeStatus` | Line | Actions |
|---|---|---|
| `off` | Bridge: off | **Connect through bridge** |
| `connecting` | Bridge: connecting… | — |
| `connected(adb)` | Bridge: connected · adb: `<path>` | **Disconnect** |
| `notRunning` | The bridge isn't running. In the folder where you saved it, run `dart fcm_bridge.dart`. If it's running, its window says why it refused this page. | **Copy**, **Download fcm_bridge.dart**, **Try again** |
| `wrongVersion(n)` | This fcm_bridge.dart doesn't match this page (bridge protocol n, page 1). Download it again and restart it. | **Download fcm_bridge.dart**, **Try again** |
| `noAdb(problem)` | `problem` from `hello` | **Try again** |
| `blocked` | The browser is blocking this site from reaching apps on this computer. Allow it in the site settings (the icon left of the address), then try again. | **Try again** |

**Try again** reconnects at once and resets the back-off.

## 7. Errors

| Situation | What the user sees |
|---|---|
| WebSocket can't open (bridge not running, origin refused, port blocked) | `notRunning` (§6) |
| Permissions API reports Local Network Access denied | `blocked` |
| No `hello` within 5 s, or a malformed one | `notRunning`, and the retries continue |
| `protocol` differs | `wrongVersion`; no retries until **Try again** |
| `hello` has `adb: null` | `noAdb(problem)` |
| A command is refused (only possible with a mismatched file) | The read's error: "`adb -s <serial> shell …` (through the bridge) failed: fcm_bridge refused this command." |
| The connection drops mid-command | "The bridge stopped." on the read; `notRunning` on the line |
| adb's own failures (device offline, `run-as` denied, …) | Unchanged: exit code and stderr reach `AdbCommands` exactly as on desktop |
| A command doesn't finish within 10 s | The read's error: "`adb -s <serial> …` (through the bridge) did not finish within 10 seconds"; the bridge kills it |
| Port 15037 taken when the bridge starts | Terminal only: "Port 15037 is in use; is another bridge already running?" |

## 8. Testing

**The bridge** (VM tests that import `web/fcm_bridge.dart`, with a fake process starter in place of adb):
- **The allow-list as a table:** each of the seven commands is accepted. Refused:
  - `pm uninstall x.y`, `rm -rf /sdcard`;
  - `pidof a.b; reboot`, `pidof a.b && reboot`, `pidof 'a.b'`, `pidof a`;
  - `--pid=1 -c`, `--pid=x`;
  - a serial starting with `-`;
  - an unknown kind.
- **Origin and Host:** localhost on any port; `--allow-origin`; a `hostedOrigins` entry; an unknown origin; a missing Origin; a wrong Host.
- **Protocol:** `hello` with and without adb; `run` streams stdout and stderr, then `exit`; `track` streams; `kill` stops the process; closing the connection kills its processes; a spawn failure gives `error`.
- **adb discovery:** a fake environment for the `--adb`, `PATH`, `ANDROID_HOME` and default-folder cases on macOS, Windows and Linux.
- **End to end:** the real bridge server on a free port, a `dart:io` WebSocket `BridgeChannel` and the real `BridgeAdbService`, with a fake adb behind the bridge. A whole `readTokenWithRunAs`, plus a logcat read with a `kill`.

**Sync tests:**
- every command `AdbCommands` sends is accepted by the bridge's allow-list;
- the bridge's and the page's `protocol` and port constants are equal.

**Web client:**
- `BridgeClient` against a fake channel: hello and version check, reply routing by id, the 5 s hello timeout, back-off retries, connection loss failing pending runs, disconnect stopping retries, and the auto-connect flag rules.
- `BridgeDeviceShell` and `BridgeAdbService`: outputs, errors, `describe`.
- `WebPhones`:
  - merging, the `link` labels, and deduping by serial (the bridge wins);
  - routing each call to the right side, and an unknown serial;
  - a bridge failure doesn't end the stream;
  - with no WebUSB side.

**Widgets:** the Devices screen for every bridge state:
- **Copy** and **Download**;
- the USB and Bridge labels;
- no menu on bridge rows;
- Firefox (`noWebUsb`): the USB button disabled with its reason, and the bridge usable;
- the empty state.

## 9. M5.1 success test

On macOS, with the Redmi, in Chrome:
1. **Sharing:** with `dart fcm_bridge.dart` running, read a token on the web while running an app from Antigravity on the same phone. Both work; no "in use".
2. **Permission:** from the hosted https build (or an https tunnel to it), the first connect asks the Local Network Access question once; after a reload, it connects without asking.
3. **Other browsers:** Firefox and Safari connect to the bridge and read a token. Record the result in §3.
4. **Stopping:** stopping the bridge mid-read shows "The bridge stopped."; restarting it brings the phone back by itself.
5. **Version:** a bridge file with `protocol` changed to 2 shows the "doesn't match" line.

Each result is recorded in §3 and in the main spec's M5.1 status.

## 10. Out of scope

- **The hosting URL:** it goes into `hostedOrigins` (one line) once it's decided; until then, use `--allow-origin`.
- Compiled bridge programs, signing, a tray app or auto-start.
- Reaching phones on another computer.
- Wireless debugging pairing.
- Manual tests on Windows and Linux: their adb discovery is unit-tested only.

## 11. Open risks

- **Local Network Access is still changing in Chrome** (prompt text, permission name, WebSocket coverage). The `notRunning` text covers the case where the page can't tell.
- **Safari may block loopback from https.** Then Safari users keep the explanation, and Chrome or Firefox work.
- **Version skew** between the site and a downloaded file: the protocol check turns it into a clear message.
- **Console noise:** each failed retry logs a WebSocket error in the browser console. The back-off caps it at one every 30 s.

## 12. Changes to the main spec (made with this design)

- **§3.1:** the web also reaches phones through the local bridge (this document).
- **§9:** retitle to "Device tokens (desktop: adb; web: WebUSB or the local bridge)".
- **§13:** insert M5.1 "Phones on the web through a local bridge", with the success test in §9 here.

**Change to the WebUSB design:** in §11, Firefox and Safari now point to the bridge.
