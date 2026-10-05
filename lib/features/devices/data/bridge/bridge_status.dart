import 'package:equatable/equatable.dart';

/// Where the page's connection to the bridge stands (bridge design §6).
sealed class BridgeStatus extends Equatable {
  const BridgeStatus();

  @override
  List<Object?> get props => const [];
}

/// Not wanted: never connected in this browser, or disconnected.
final class BridgeOff extends BridgeStatus {
  const BridgeOff();
}

final class BridgeConnecting extends BridgeStatus {
  const BridgeConnecting();
}

/// Ready: phones come from [adbPath] on the user's computer.
final class BridgeConnected extends BridgeStatus {
  const BridgeConnected(this.adbPath);

  final String adbPath;

  @override
  List<Object?> get props => [adbPath];
}

/// Nothing answered, or the bridge refused this page. Retrying.
final class BridgeNotRunning extends BridgeStatus {
  const BridgeNotRunning();
}

/// The bridge file is from another version; waits for Try again.
final class BridgeWrongVersion extends BridgeStatus {
  const BridgeWrongVersion(this.bridgeProtocol);

  final int bridgeProtocol;

  @override
  List<Object?> get props => [bridgeProtocol];
}

/// Connected, but the bridge found no adb.
final class BridgeNoAdb extends BridgeStatus {
  const BridgeNoAdb(this.problem);

  final String problem;

  @override
  List<Object?> get props => [problem];
}

/// The browser denied this site access to apps on this computer.
final class BridgeBlocked extends BridgeStatus {
  const BridgeBlocked();
}
