# FCM Studio: phones on the web (WebUSB)

**Status:**
- **Implemented:** 2026-10-04 (M5 code with tests).
- **Pending:** the manual success test in §10, on the Redmi in Chrome.

**Milestone:** M5. It comes before release builds, which move to M6.

**Main spec:** [2026-10-03-fcm-studio-design.md](2026-10-03-fcm-studio-design.md). This document adds to its §9 (device tokens) and does not repeat it.

## 1. Purpose

Teammates use the hosted web build (an HTTPS URL) and won't install the desktop app. In the web build today, the Devices screen and **From device…** are hidden, because a browser can't run adb.

This milestone gives the web build the same device feature as the desktop app:
- list a USB-connected Android phone;
- pick an app;
- read its FCM token, with `run-as` for debug builds and logcat after confirmation for release builds;
- put the token in Target and save it as a device target.

The browser talks to the phone directly over **WebUSB**, so no adb has to be installed.

**Success test:** see §10.

## 2. Decisions

- **The adb protocol is implemented in Dart** on top of a thin WebUSB interop layer (approach A). We don't wrap a JavaScript library: no npm or bundler, and everything except the interop runs in `flutter test`.
- **The web implements the existing `AdbService` interface.**
  - The Devices screen, `DevicesBloc`, `TokenReaderCubit`, the parsers and the `run-as` classification are shared with desktop.
  - The device commands move into shared code (§4.7).
- **Supported:** Chromium browsers only (Chrome, Edge, Opera), over HTTPS or localhost. USB only.
- **Android 7 or newer** (the `shell_v2` feature). Older phones get a clear message.
- **The browser's adb key** is a 2048-bit RSA key, created once per browser profile and site. It is stored through `SecretStore`.
- **Desktop is unchanged:** it keeps using adb.

## 3. Facts this design relies on

| Fact | Status |
|---|---|
| `package:web` 1.1.1 (in our lock file) has no WebUSB bindings, so we write our own js_interop types | Checked 2026-10-04 |
| WebCrypto's RSASSA-PKCS1-v1_5 `sign` hashes its input. adb signs the 20-byte token as an already-hashed SHA-1 value, so signing is done in Dart with `BigInt.modPow`, and WebCrypto is used only to create the key | Known API behaviour |
| `classifyRunAs` reads `output.combined`. On the web, `run-as` errors arrive on stderr (shell v2), so classification works unchanged | Checked in `run_as_outcome.dart` 2026-10-04 |
| `run-as` errors name the outcome the same way over shell v2 as over `exec-out` | To check in the M5 success test |
| While the adb server (or Android Studio) holds the phone, `claimInterface` fails in the browser | To check in the M5 success test (record the exact error) |
| The Redmi 14C announces `shell_v2` in its `CNXN` banner | To check in the M5 success test |
| On Windows, the phone's adb interface must use the WinUSB driver (Google USB Driver) | To check on Windows if a Windows PC is available |
| Signing in the browser takes about 160 ms with CRT (about 510 ms without), once per connection | Measured 2026-10-04 with the dart2js build in Node 22 |

## 4. Architecture

```
Devices screen / TokenReaderCubit / DevicesBloc          (shared, unchanged UI logic)
        │ AdbService
        ├── ProcessAdbService (desktop)  ── DeviceShell: `adb -s <serial> shell|exec-out …`
        └── WebUsbAdbService  (web)      ── DeviceShell: shell v2 over AdbConnection
                 both delegate phone commands to AdbCommands (shared)
        AdbConnection ── AdbMessage codec, ShellV2 codec, AdbKey
        UsbTransport  ── WebUsbTransport (js_interop, web only) | FakeUsbTransport (tests)
```

New code goes in `lib/features/devices/data/webusb/`. Everything is pure Dart except `usb_interop.dart` and `web_usb_transport.dart`, which are reached through a conditional export, the same pattern as `process_runner_platform.dart`.

### 4.1 `usb_interop.dart` (web only)

js_interop extension types for the calls we use:
- **`navigator.usb`:** `getDevices()`, `requestDevice({filters})`, and the `connect` and `disconnect` events.
- **`USBDevice`:** `open()`, `close()`, `selectConfiguration()`, `claimInterface()`, `releaseInterface()`, `transferIn()`, `transferOut()`, `forget()`, `serialNumber`, `productName`, `manufacturerName`, and `configuration` (interfaces, alternates, endpoints).
- **`USBInTransferResult` and `USBOutTransferResult`:** `data`, `status`.
- No other code imports this file.

### 4.2 `UsbTransport`

```dart
abstract interface class UsbTransport {
  Future<Uint8List> read(int length);   // one bulk IN transfer of up to [length] bytes
  Future<void> write(Uint8List bytes);  // one bulk OUT transfer
  Future<void> close();
}
```

**`WebUsbTransport`:**
- finds the interface with class `0xFF`, subclass `0x42`, protocol `0x01`, and its bulk IN and OUT endpoints;
- opens the device, selects configuration 1 if none is selected, and claims that interface.
- Claim failures surface as `UsbClaimException`, and transfer failures as `UsbDisconnectedException`.

**`FakeUsbTransport`** (tests) plays a scripted phone: it queues the bytes the phone sends and records the bytes the host writes.

### 4.3 `AdbMessage` codec

The header is six little-endian `uint32` values: `command`, `arg0`, `arg1`, `data_length`, `data_check` (the sum of the payload's bytes) and `magic` (`command ^ 0xFFFFFFFF`).

**Commands:**

| Command | Value |
|---|---|
| `CNXN` | `0x4E584E43` |
| `AUTH` | `0x48545541` |
| `OPEN` | `0x4E45504F` |
| `OKAY` | `0x59414B4F` |
| `WRTE` | `0x45545257` |
| `CLSE` | `0x45534C43` |

**Rules:**
- The header and the payload are sent as **separate** USB transfers. Reading works the same way: 24 bytes of header, then exactly `data_length` bytes, possibly over several transfers.
- We announce version `0x01000001`, so the phone doesn't check checksums. We still write a correct `data_check`, and we don't verify incoming ones.
- A bad `magic` is a protocol error, and the connection closes.

### 4.4 `AdbConnection`

**Handshake:**
1. Send `CNXN(0x01000001, 1048576, "host::features=shell_v2,cmd")`.
2. The phone answers with either:
   - `CNXN`, carrying a banner such as `device::ro.product.model=…;…;features=…`. The connection is ready.
   - `AUTH(1 = TOKEN, 0, 20 bytes)`. Reply `AUTH(2 = SIGNATURE, 0, sign(token))`.
3. After the signature, the phone answers with either:
   - `CNXN`: ready.
   - Another `AUTH TOKEN`: the phone doesn't know our key. Reply `AUTH(3 = RSAPUBLICKEY, 0, base64(androidPublicKey) + " fcm-studio@<site host>" + "\0")`. The phone shows "Allow USB debugging?". The connection reports **waiting for approval**, with no timeout, until the phone sends `CNXN`.
4. A banner whose features lack `shell_v2` means the phone is too old (§7).

**Streams:**
- `open(service)` sends `OPEN(localId, 0, service + "\0")` and returns an `AdbStream`. `OKAY` confirms it; `CLSE` means the phone refused it.
- Each received `WRTE` is acknowledged with `OKAY`.
- Streams only receive. No command sends stdin, so the host never writes `WRTE`, and the design has no flow control for host writes (no `delayed_ack` either).
- `close()` sends `CLSE`.
- One reader loop dispatches messages by local ID, and writes are serialized.

**Failure:** the phone's maximum payload size comes from its `CNXN` `arg1`. A transport failure fails every open stream and the connection with `UsbDisconnectedException`.

### 4.5 `AdbKey` and storage

- **Creation:** made once with WebCrypto (`RSASSA-PKCS1-v1_5`, 2048-bit, exponent 65537, exportable). The key is exported as JWK and stored through `SecretStore` under the key `adb:browser-key`.
- **`sign(token)`:**
  - builds an EMSA-PKCS1-v1_5 block for a SHA-1 hash: `00 01 FF…FF 00`, then the DigestInfo `30 21 30 09 06 05 2B 0E 03 02 1A 05 00 04 14`, then the 20-byte token;
  - computes `m^d mod n` with `BigInt.modPow`, using the CRT values from the JWK for speed;
  - returns 256 bytes, big-endian.
- **`androidPublicKey()`:** Android's 524-byte layout, all values little-endian:
  - `uint32` number of 32-bit words in the modulus (64);
  - `uint32 n0inv` = `-1 / n mod 2^32`;
  - the 256-byte modulus;
  - the 256-byte `rr` = `(2^2048)^2 mod n`;
  - `uint32` exponent.
- **Signing is pure Dart and testable.** Tests use a throwaway key made once with `adb keygen` and committed as a fixture. The fixture's `.pub` file is the expected output of `androidPublicKey()`. That key is trusted by no phone.

### 4.6 `ShellV2` codec

- **Service string:** `shell,v2,raw:<command>` (no terminal).
- **Packet layout:** a 1-byte ID, then a 4-byte little-endian length, then the data.

| Packet ID | Meaning |
|---|---|
| 0 | stdin |
| 1 | stdout |
| 2 | stderr |
| 3 | exit (1 byte: the exit code) |
| 4 | close stdin |

- The decoder copes with packets split across, or packed into, `WRTE` payloads.
- **`run(command)`** collects stdout, stderr and the exit code into the existing `ProcessOutput`.
- **`start(command)`** gives a `RunningProcess`: stdout as a stream, an exit-code future, and `kill()`. `kill()` closes the stream (`CLSE`), which makes the phone stop the command.

### 4.7 `DeviceShell` and `AdbCommands` (refactor)

```dart
abstract interface class DeviceShell {
  Future<ProcessOutput> run(String serial, String command);
  Future<RunningProcess> start(String serial, String command);
  String describe(String serial, String command); // used in error messages
}
```

**`AdbCommands`** holds the phone-side logic that is in `ProcessAdbService` today, unchanged in behaviour:
- `deviceDetails`, `listPackages`, `readTokenWithRunAs`, `launchApp`, `readTokenFromLogcat`, plus `_waitForPid` and `_watchLogcat`;
- the timeouts, the token redaction and the "never `logcat -c`" rule.

**The two shells:**
- **Desktop:** `ProcessDeviceShell` runs `adb -s <serial> shell <command>`, or `exec-out` for `run-as … cat`, as today. Its error messages still name the full adb command.
- **Web:** `WebUsbDeviceShell` runs shell v2 on that phone's connection. Error messages name the command and the phone, for example "`pm list packages -3` on Redmi 14C failed: …".

`ProcessAdbService` = `trackDevices` (adb) + `AdbCommands(ProcessDeviceShell)`. All M3 tests must pass unchanged, except for moved imports.

### 4.8 `WebUsbAdbService implements AdbService`

**Phone list:**
- Phones come from `navigator.usb.getDevices()`, filtered to those with an adb interface, kept up to date by the `connect` and `disconnect` events.
- Each phone gets one `AdbConnection`, opened automatically when it is listed.
- **`trackDevices()`** emits `List<AdbDevice>` whenever a phone is added, removed or changes state. It doesn't end while the app is open, so `DevicesBloc`'s restart logic never fires.

**Phone identity:**
- `serial` = `USBDevice.serialNumber`. When that is empty or already taken, use `usb:<vendorId>:<productId>#<n>` (4-digit hex IDs; `n` counts from 1 in the order the phones were listed this session).
- `model` = `productName`.

**Extra methods (web only):**
- `connectPhone()`: calls `requestDevice` with the adb filter. It must be called from a button press. Closing the chooser returns nothing and isn't an error.
- `retry(serial)`: reconnects a phone that is offline or waiting for approval.
- `forget(serial)`: calls `USBDevice.forget()` and removes the phone.

**Commands:** `AdbCommands(WebUsbDeviceShell)`.

### 4.9 Platform and UI

**`PlatformFeatures.canRunAdb`** becomes `deviceAccess`:
- `adb` on desktop;
- `webUsb` on web when `navigator.usb` exists and the page is a secure context;
- `none(reason)` otherwise, where the reason is `noWebUsb` or `notSecure`.

**Navigation:**
- **Devices** is in the rail for all three values; for `none` it shows the explanation from §7.
- **From device…** appears for `adb` and `webUsb`.
- **Settings** (the adb path) appears for `adb` only.

**Wiring on web:**
- `DevicesBloc` and `TokenReaderCubit` get the single `WebUsbAdbService`, and tracking starts at app start.
- There is no adb path and no `AdbSetupCubit.locate()`. The adb exit guard stays desktop-only: when the tab closes, the browser releases the phones.

**Devices screen on web:**
- a **Connect a phone…** button;
- empty state: "No phones yet. Turn on USB debugging on the phone, plug it in, then click **Connect a phone…**";
- each row's menu has **Forget**, and offline or unauthorized rows also have **Retry**;
- the hints come from §6 and §7.

## 5. Flows

### First connection

1. The user clicks **Connect a phone…**. The browser's chooser lists phones with an adb interface, and the user picks one.
2. The row shows **Connecting…**.
3. The app claims the interface and runs the handshake from §4.4.
   - If the phone doesn't know our key, it shows "Allow USB debugging?". The row shows the unauthorized hint until the user accepts.
4. The row becomes ready.
5. From then on it behaves like desktop: details, package list with search, the last 5 packages, `run-as` and the logcat fallback, and the result goes to Target and is saved as a device target.

### Later visits

- The browser remembers phones this site was allowed to use. They connect as soon as they're listed or plugged in.
- If "Always allow from this computer" was ticked, the phone doesn't ask again.

### Cancelling and unplugging

- **Cancelling a read, or leaving the screen,** closes that read's streams, which ends the command on the phone.
- **Unplugging:**
  - The `disconnect` event removes the row.
  - Any running read fails with "The phone was disconnected", with **Retry**.
  - The selection is kept, so the phone is picked up again when it returns (existing `DevicesBloc` behaviour).

## 6. Device states

| Browser situation | `DeviceState` | Shown |
|---|---|---|
| Connected and authorised | `device` | ready |
| Waiting for "Allow USB debugging?" | `unauthorized` | "Accept the USB debugging prompt on the phone" (existing hint) |
| Claim failed, transport lost, or protocol error | `offline` | the reason (§7) + **Retry** |
| Opening or handshaking | `other` (raw state `connecting`) | "Connecting…" |

## 7. Errors

Every message says what happened and what to do (main spec §11). Tokens are never logged, and errors pass through `redact()`.

| Situation | Message |
|---|---|
| No WebUSB (Firefox, Safari) | Devices screen: "Reading tokens from a phone needs Chrome or Edge. You can still paste a token in Target." |
| Not a secure context | "Open FCM Studio over https to connect a phone." |
| Chooser closed | Nothing |
| Claim failed | "This phone is in use by another program. Close Android Studio or run `adb kill-server`, then click Retry." On Windows, add: "If it still fails, install the Google USB Driver for this phone." |
| Phone too old (no `shell_v2`) | "This phone runs Android 6 or older. Use the desktop app for it." |
| Phone refused the key, or the prompt was dismissed | Stays unauthorized; **Retry** sends the key again |
| Disconnected during a command | "The phone was disconnected. Plug it in and click Retry." |
| A command failed | "`<command>` on <phone> failed: <output>" (tokens replaced by `<token>`) |
| Protocol error (bad magic, unexpected message) | Offline: "The connection to the phone failed. Unplug it, plug it in again, and click Retry." |

## 8. Security and storage

- **The private key** is stored through `SecretStore` (on web, `flutter_secure_storage`'s browser backend). It's the browser's equivalent of `~/.android/adbkey`.
  - Anyone using that browser profile on that site can use phones that trusted this key. That's the same trust as desktop adb.
  - The key never goes into sembast, logs, history, exports or error messages.
- **Unlike service account keys,** the adb key is kept by default. Otherwise every visit would make the phone ask again.
  - The Devices screen notes this under **Forget**: "This browser keeps a USB debugging key for this site."
- **Revoking access:** **Forget** removes the browser's access to a phone. On the phone, Developer options › Revoke USB debugging authorisations removes the phone's trust in every key.

## 9. Testing

**Unit tests (`flutter test`; no browser):**
- **`AdbMessage`:** golden bytes for each command, the magic, the checksum, and payload lengths of 0 and above 64 KiB.
- **`AdbConnection` against `FakeUsbTransport`:**
  - handshake straight to `CNXN`;
  - token, then signature accepted;
  - token, signature refused, public key, then accepted;
  - refused for good: the connection stays waiting;
  - banner without `shell_v2`;
  - several streams at once with interleaved `WRTE`s;
  - `CLSE` from the phone;
  - a transport failure fails all streams.
- **`ShellV2`:** split and packed packets, stdout and stderr, the exit code, and an empty output.
- **`AdbKey`:** the signature and the Android public key against the `adb keygen` fixture.
- **`AdbCommands`:**
  - the existing M3 command tests, run through `ProcessDeviceShell`;
  - the shared logic run against a fake `DeviceShell` (run-as outcomes, logcat found, timeout, app didn't start, cancel).
- **`WebUsbAdbService`,** with a fake device source and fake transports:
  - list updates on connect and disconnect;
  - the state mapping from §6;
  - `retry` and `forget`;
  - "phone disconnected" during a read.
- **Platform:** `deviceAccess` decides what the rail and target picker show, for all three values.

**Not unit-tested:** `usb_interop.dart` and `WebUsbTransport` stay thin. `flutter build web` must succeed, and the success test covers them.

## 10. M5 success test

Run it on the hosted HTTPS build (or `flutter run -d chrome`) in Chrome on macOS, with the Redmi:
1. **In use:** with Android Studio running, **Connect a phone…** leads to the "in use" message. Quit it, click **Retry**: the phone asks "Allow USB debugging?". Accept, and the row is ready.
2. **Debug build:** pick a 6amMart debug build. `run-as` puts the token in Target in under 60 s from plugging in.
3. **Release build:** confirm the logcat fallback; the token is found (or the "doesn't print its token" message appears).
4. **Reload:** reload the page with "Always allow" ticked. The phone connects without the chooser or the prompt.
5. **Unplug:** unplugging during a logcat read shows "The phone was disconnected".
6. **Other browsers:** Firefox shows the Chrome-or-Edge message, and the rest of the app works.
7. **Windows (optional):** repeat steps 1–2 on Windows.
8. **Record the results** in §3 ("to check" rows), as confirmed or changed.

## 11. Out of scope

- Wireless debugging: browsers can't open TCP connections or pair over Wi-Fi.
- Firefox and Safari: no WebUSB.
- Android 6 and older.
- Two tabs using the same phone at once.
- File transfer (`sync:`), screen mirroring and `delayed_ack`.

## 12. Open risks

- **Large transfers:** some phones need a zero-length packet after a transfer whose size is an exact multiple of the endpoint's packet size. We only send small payloads, but `WebUsbTransport` sends a zero-length packet in that case.
- **Slow signing:** measured at about 160 ms per connection (§3), so it isn't a problem.
- **Two USB devices with the same serial** (rare, e.g. cheap phones): the fallback identity keeps them apart within one session.

## 13. Changes to the main spec (made with this design)

- **§3.1:** devices on desktop through adb, and on Chromium web browsers through WebUSB (this document).
- **§9:** retitle to "Device tokens (desktop: adb; web: WebUSB)" and point here.
- **§10:** add the adb browser key (`adb:browser-key` in `SecretStore`, kept by default).
- **§13:** insert M5 "Phones on the web (WebUSB)", with the success test in §10 here. "Release builds" becomes M6.
