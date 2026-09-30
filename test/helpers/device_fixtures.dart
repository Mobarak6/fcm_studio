import 'dart:convert';

/// The fake token in the hand-written fixture test/fixtures/adb/appid_prefs_synthetic.xml.
final fakeDeviceToken =
    'fakeInstanceId0000000:APA91bFAKE_TOKEN_FOR_TESTS_ONLY_${'a' * 49}';

final otherDeviceToken =
    'otherInstanceId000000:APA91bOTHER_TOKEN_FOR_TESTS_ONLY_${'b' * 49}';

const redmiSerial = 'DETWFUOZZHZ5SWFQ';

/// What `adb track-devices -l` printed for the Redmi 14C on 2026-10-04.
const redmiTrackLine =
    'DETWFUOZZHZ5SWFQ       device usb:34603008X product:pond_global '
    'model:2409BRN2CA device:pond transport_id:1\n';

/// One `track-devices` message: a 4-hex-digit byte length, then the payload.
String trackFrame(String payload) =>
    '${utf8.encode(payload).length.toRadixString(16).padLeft(4, '0')}$payload';

/// A token file in the current SDK's format (spec §9.3).
String appIdPrefsXml(Map<String, String> tokensBySender) =>
    "<?xml version='1.0' encoding='utf-8' standalone='yes' ?>\n"
    '<map>\n'
    '    <string name="|S||P|">REDACTED_LONG_VALUE</string>\n'
    '    <string name="|S|id">REDACTED_FID</string>\n'
    '${[for (final entry in tokensBySender.entries) '    <string name="[DEFAULT]|T|${entry.key}|*">{&quot;token&quot;:&quot;${entry.value}&quot;,&quot;appVersion&quot;:&quot;1&quot;,&quot;timestamp&quot;:1759550000000}</string>\n'].join()}'
    '    <string name="|S|cre">1759550000</string>\n'
    '</map>\n';
