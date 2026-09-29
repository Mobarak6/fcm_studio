import 'dart:async';

import 'package:sembast/sembast.dart';

/// Sembast's cooperator pauses with a short `Future.delayed`, which creates
/// timers inside the widget tests' fake-async zone and makes them flaky.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  disableSembastCooperator();
  await testMain();
}
