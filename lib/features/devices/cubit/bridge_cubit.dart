import 'dart:async';

import 'package:fcm_studio/features/devices/data/bridge/bridge_client.dart';
import 'package:fcm_studio/features/devices/data/bridge/bridge_status.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The bridge's status for the Devices screen, and its buttons (bridge
/// design §4.6).
class BridgeCubit extends Cubit<BridgeStatus> {
  BridgeCubit({required BridgeControl control})
    : _control = control,
      super(control.status) {
    _subscription = _control.statuses.listen(emit);
  }

  final BridgeControl _control;
  late final StreamSubscription<BridgeStatus> _subscription;

  Future<void> start() => _control.start();

  void connect() => _control.connect();

  Future<void> disconnect() => _control.disconnect();

  void download() => _control.download();

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
