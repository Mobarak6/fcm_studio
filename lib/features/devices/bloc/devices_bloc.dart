import 'dart:async';
import 'dart:math';

import 'package:fcm_studio/features/devices/bloc/devices_event.dart';
import 'package:fcm_studio/features/devices/bloc/devices_state.dart';
import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/domain/adb_device.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/devices/bloc/devices_event.dart';
export 'package:fcm_studio/features/devices/bloc/devices_state.dart';

/// Tracks plugged-in phones with `adb track-devices -l` and restarts it with
/// backoff when it exits (spec §9.2).
class DevicesBloc extends Bloc<DevicesEvent, DevicesState> {
  DevicesBloc({required this._serviceFor, this._backoff = defaultBackoff})
    : super(const DevicesState()) {
    on<DevicesAdbChanged>(_onAdbChanged);
    on<DeviceSelected>(_onSelected);
    on<_TrackerUpdated>(_onUpdated);
    on<_TrackerEnded>(_onEnded);
    on<_TrackerRestart>(_onRestart);
    on<_DetailsLoaded>(_onDetailsLoaded);
  }

  /// 1, 2, 4, 8, 16, then 30 seconds.
  static Duration defaultBackoff(int attempt) =>
      Duration(seconds: min(30, 1 << (attempt - 1).clamp(0, 5)));

  final AdbService Function(String adbPath) _serviceFor;
  final Duration Function(int attempt) _backoff;
  AdbService? _service;
  StreamSubscription<List<AdbDevice>>? _subscription;
  Timer? _restartTimer;
  int _failures = 0;
  final Set<String> _loadingDetails = {};

  Future<void> _onAdbChanged(
    DevicesAdbChanged event,
    Emitter<DevicesState> emit,
  ) async {
    await _stop();
    _failures = 0;
    final path = event.adbPath;
    if (path == null) {
      _service = null;
      emit(DevicesState(selectedSerial: state.selectedSerial));
      return;
    }
    _service = _serviceFor(path);
    emit(
      state.copyWith(
        status: TrackerStatus.starting,
        adbPath: () => path,
        devices: const [],
        retryIn: () => null,
      ),
    );
    _listen();
  }

  void _listen() {
    final service = _service;
    if (service == null) {
      return;
    }
    _subscription = service.trackDevices().listen(
      (devices) {
        if (!isClosed) {
          add(_TrackerUpdated(devices));
        }
      },
      onError: (Object error) {
        if (!isClosed) {
          add(_TrackerEnded(error));
        }
      },
      onDone: () {
        if (!isClosed) {
          add(const _TrackerEnded());
        }
      },
      cancelOnError: true,
    );
  }

  void _onUpdated(_TrackerUpdated event, Emitter<DevicesState> emit) {
    _failures = 0;
    final devices = event.devices;
    final ready = devices.where((device) => device.isReady).toList();
    var selected = state.selectedSerial;
    final selectedPresent = devices.any((device) => device.serial == selected);
    if ((selected == null || !selectedPresent) && ready.length == 1) {
      selected = ready.single.serial;
    }
    emit(
      state.copyWith(
        status: TrackerStatus.running,
        devices: devices,
        selectedSerial: () => selected,
        retryIn: () => null,
        lastError: () => null,
      ),
    );
    for (final device in ready) {
      _loadDetails(device.serial);
    }
  }

  void _onSelected(DeviceSelected event, Emitter<DevicesState> emit) {
    emit(state.copyWith(selectedSerial: () => event.serial));
    final device = state.selected;
    if (device != null && device.isReady) {
      _loadDetails(device.serial);
    }
  }

  void _loadDetails(String serial) {
    final service = _service;
    if (service == null ||
        state.details.containsKey(serial) ||
        !_loadingDetails.add(serial)) {
      return;
    }
    unawaited(
      service
          .deviceDetails(serial)
          .then<void>(
            (details) {
              if (!isClosed) {
                add(_DetailsLoaded(serial, details));
              }
            },
            onError: (Object _) {
              if (!isClosed) {
                add(_DetailsLoaded(serial, null));
              }
            },
          ),
    );
  }

  void _onDetailsLoaded(_DetailsLoaded event, Emitter<DevicesState> emit) {
    _loadingDetails.remove(event.serial);
    final details = event.details;
    if (details != null) {
      emit(state.copyWith(details: {...state.details, event.serial: details}));
    }
  }

  void _onEnded(_TrackerEnded event, Emitter<DevicesState> emit) {
    _subscription = null;
    if (_service == null) {
      return;
    }
    _failures++;
    final delay = _backoff(_failures);
    final error = event.error;
    emit(
      state.copyWith(
        status: TrackerStatus.restarting,
        devices: const [],
        retryIn: () => delay,
        lastError: () => error == null ? null : _describe(error),
      ),
    );
    _restartTimer = Timer(delay, () {
      if (!isClosed) {
        add(const _TrackerRestart());
      }
    });
  }

  void _onRestart(_TrackerRestart event, Emitter<DevicesState> emit) {
    if (_service == null || _subscription != null) {
      return;
    }
    emit(state.copyWith(status: TrackerStatus.starting, retryIn: () => null));
    _listen();
  }

  static String _describe(Object error) => switch (error) {
    AdbException(:final message) => message,
    _ => '$error',
  };

  Future<void> _stop() async {
    _restartTimer?.cancel();
    _restartTimer = null;
    final subscription = _subscription;
    _subscription = null;
    await subscription?.cancel();
  }

  @override
  Future<void> close() async {
    await _stop();
    return super.close();
  }
}

class _TrackerUpdated extends DevicesEvent {
  const _TrackerUpdated(this.devices);

  final List<AdbDevice> devices;
}

class _TrackerEnded extends DevicesEvent {
  const _TrackerEnded([this.error]);

  final Object? error;
}

class _TrackerRestart extends DevicesEvent {
  const _TrackerRestart();
}

class _DetailsLoaded extends DevicesEvent {
  const _DetailsLoaded(this.serial, this.details);

  final String serial;
  final DeviceDetails? details;
}
