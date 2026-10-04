/// How this platform reaches phones (WebUSB design §4.9).
enum DeviceAccess {
  /// Desktop: the adb program.
  adb,

  /// Chrome, Edge or Opera on https or localhost: WebUSB.
  webUsb,

  /// A browser without WebUSB, e.g. Firefox or Safari.
  noWebUsb,

  /// A web page not opened over https (or localhost).
  notSecure,
}
