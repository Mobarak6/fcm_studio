import 'dart:async';

import 'package:fcm_studio/features/devices/cubit/token_reader_state.dart';
import 'package:fcm_studio/features/devices/data/adb_service.dart';
import 'package:fcm_studio/features/devices/data/recent_packages_repository.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/devices/domain/token_read_results.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/devices/cubit/token_reader_state.dart';

/// Reads an app's FCM token from the selected phone (spec §9.3): `run-as`
/// for debug builds, then logcat for release builds once the user agrees.
class TokenReaderCubit extends Cubit<TokenReaderState> {
  TokenReaderCubit({required this._serviceFor, required this._recent})
    : super(const TokenReaderState());

  final AdbService Function(String adbPath) _serviceFor;
  final RecentPackagesRepository _recent;
  AdbService? _service;
  String? _adbPath;
  StreamSubscription<LogcatProgress>? _logcat;
  Completer<void>? _logcatDone;

  /// Bumped by every new read, dismiss and device change, so an answer that
  /// arrives after the user moved on is dropped.
  int _generation = 0;
  int _packagesEpoch = 0;

  /// The adb the reader was last opened with.
  String? get adbPath => _adbPath;

  Future<void> openDevice(String adbPath, String serial) async {
    _adbPath = adbPath;
    _generation++;
    final epoch = ++_packagesEpoch;
    final old = _takeLogcat();
    _service = _serviceFor(adbPath);
    emit(TokenReaderState(serial: serial));
    await old();
    if (isClosed || epoch != _packagesEpoch) {
      return;
    }
    await refreshPackages();
  }

  Future<void> refreshPackages() async {
    final service = _service;
    final serial = state.serial;
    if (service == null || serial == null) {
      return;
    }
    final epoch = ++_packagesEpoch;
    emit(
      state.copyWith(
        packagesStatus: PackagesStatus.loading,
        packagesError: () => null,
      ),
    );
    try {
      final installed = await service.listPackages(serial);
      final recent = await _recent.recent(serial);
      if (isClosed || state.serial != serial || epoch != _packagesEpoch) {
        return;
      }
      emit(
        state.copyWith(
          packagesStatus: PackagesStatus.ready,
          installed: installed,
          recent: recent,
        ),
      );
    } on AdbException catch (e) {
      if (isClosed || state.serial != serial || epoch != _packagesEpoch) {
        return;
      }
      emit(
        state.copyWith(
          packagesStatus: PackagesStatus.failed,
          packagesError: () => e.message,
        ),
      );
    }
  }

  void search(String query) => emit(state.copyWith(query: query));

  /// Step 1: `run-as` (debug builds).
  Future<void> readToken(String package, {String? projectNumber}) async {
    final service = _service;
    final serial = state.serial;
    if (service == null || serial == null || state.isBusy) {
      return;
    }
    final generation = ++_generation;
    emit(state.copyWith(read: TokenReading(package)));
    final result = await service.readTokenWithRunAs(serial, package);
    if (!_isCurrent(generation, serial)) {
      return;
    }
    final read = switch (result) {
      RunAsTokens(:final tokens) => TokenReadFound(
        package,
        tokens: tokens,
        method: TokenReadMethod.runAs,
        preselectedSenderId: _preselect(tokens, projectNumber),
      ),
      RunAsReleaseBuild() => TokenReadReleaseBuild(package),
      RunAsNoTokenYet() => TokenReadNoTokenYet(package),
      RunAsNotInstalled() => TokenReadNotInstalled(package),
      RunAsFailed(:final message) => TokenReadFailed(package, message),
    };
    emit(state.copyWith(read: read));
    if (read is TokenReadFound) {
      await _remember(serial, package);
    }
  }

  /// Step 2 (release builds). Restarts the app, so only after the user
  /// confirmed. Completes when the step ends.
  Future<void> readTokenFromLogcat(String package) async {
    final service = _service;
    final serial = state.serial;
    if (service == null || serial == null || state.isBusy) {
      return;
    }
    // Claim the busy state before the first await.
    final generation = ++_generation;
    final old = _takeLogcat();
    final done = _logcatDone = Completer<void>();
    emit(
      state.copyWith(
        read: TokenReadWatchingLogcat(package, const LogcatRestartingApp()),
      ),
    );
    await old();
    if (!_isCurrent(generation, serial)) {
      _finish(done);
      return;
    }
    _logcat = service
        .readTokenFromLogcat(serial, package)
        .listen(
          (progress) {
            if (!_isCurrent(generation, serial)) {
              return;
            }
            final read = switch (progress) {
              LogcatFound(:final token) => TokenReadFound(
                package,
                tokens: [FoundToken(token: token)],
                method: TokenReadMethod.logcat,
              ),
              LogcatNoToken() => TokenReadLogcatNoToken(package),
              LogcatAppDidNotStart() => TokenReadAppDidNotStart(package),
              LogcatFailed(:final message) => TokenReadFailed(package, message),
              LogcatRestartingApp() ||
              LogcatWaitingForApp() ||
              LogcatWatching() => TokenReadWatchingLogcat(package, progress),
            };
            emit(state.copyWith(read: read));
            if (read is TokenReadFound) {
              unawaited(_remember(serial, package));
            }
          },
          onError: (Object _) {
            if (_isCurrent(generation, serial)) {
              emit(
                state.copyWith(
                  read: TokenReadFailed(package, 'Reading logcat stopped.'),
                ),
              );
            }
            _finish(done);
          },
          onDone: () {
            if (_isCurrent(generation, serial) &&
                state.read is TokenReadWatchingLogcat) {
              emit(state.copyWith(read: TokenReadLogcatNoToken(package)));
            }
            _finish(done);
          },
        );
    await done.future;
  }

  Future<void> launchApp(String package) async {
    final service = _service;
    final serial = state.serial;
    if (service == null || serial == null || state.isBusy) {
      return;
    }
    final generation = _generation;
    try {
      await service.launchApp(serial, package);
    } on AdbException catch (e) {
      if (_isCurrent(generation, serial) && !state.isBusy) {
        emit(state.copyWith(read: TokenReadFailed(package, e.message)));
      }
    }
  }

  /// Back to the package list.
  void dismiss() {
    _generation++;
    unawaited(_takeLogcat()());
    emit(state.copyWith(read: const TokenReadIdle()));
  }

  bool _isCurrent(int generation, String serial) =>
      !isClosed && generation == _generation && state.serial == serial;

  void _finish(Completer<void> done) {
    if (!done.isCompleted) {
      done.complete();
    }
    if (identical(_logcatDone, done)) {
      _logcatDone = null;
    }
  }

  static String? _preselect(List<FoundToken> tokens, String? projectNumber) {
    for (final token in tokens) {
      if (projectNumber != null && token.senderId == projectNumber) {
        return token.senderId;
      }
    }
    return tokens.length == 1 ? tokens.single.senderId : null;
  }

  /// Best-effort: the recent list is a convenience, so errors are dropped.
  Future<void> _remember(String serial, String package) async {
    try {
      await _recent.remember(serial, package);
      final recent = await _recent.recent(serial);
      if (!isClosed && state.serial == serial) {
        emit(state.copyWith(recent: recent));
      }
    } on Object {
      // Ignored on purpose.
    }
  }

  /// Detaches the running logcat step now; the returned function cancels it
  /// and completes its waiting future.
  Future<void> Function() _takeLogcat() {
    final subscription = _logcat;
    final done = _logcatDone;
    _logcat = null;
    _logcatDone = null;
    return () async {
      try {
        await subscription?.cancel();
      } finally {
        if (done != null && !done.isCompleted) {
          done.complete();
        }
      }
    };
  }

  @override
  Future<void> close() async {
    _generation++;
    _packagesEpoch++;
    await _takeLogcat()();
    return super.close();
  }
}
