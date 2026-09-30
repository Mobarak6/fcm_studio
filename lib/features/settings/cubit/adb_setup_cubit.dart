import 'package:fcm_studio/features/devices/data/adb_locator.dart';
import 'package:fcm_studio/features/settings/cubit/adb_setup_state.dart';
import 'package:fcm_studio/features/settings/data/settings_repository.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/settings/cubit/adb_setup_state.dart';

/// Finds adb at startup and when the user changes its path (spec §9.1).
class AdbSetupCubit extends Cubit<AdbSetupState> {
  AdbSetupCubit({required this._locator, required this._settings})
    : super(const AdbSetupState());

  final AdbLocator _locator;
  final SettingsRepository _settings;

  Future<void> locate() async {
    emit(state.copyWith(status: AdbStatus.locating));
    final userPath = await _settings.readAdbPath();
    final search = await _locator.locate(userPath: userPath);
    if (isClosed) {
      return;
    }
    emit(
      AdbSetupState(
        status: search.found == null ? AdbStatus.notFound : AdbStatus.found,
        location: search.found,
        userPath: userPath,
        tried: search.tried,
      ),
    );
  }

  /// Stores the path typed in Settings (null clears it) and looks again.
  Future<void> setUserPath(String? path) async {
    await _settings.writeAdbPath(path);
    await locate();
  }
}
