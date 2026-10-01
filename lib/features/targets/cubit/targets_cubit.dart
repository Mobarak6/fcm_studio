import 'dart:async';

import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/core/utils/ids.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/devices/domain/device_token.dart';
import 'package:fcm_studio/features/targets/cubit/targets_state.dart';
import 'package:fcm_studio/features/targets/data/targets_repository.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/targets/cubit/targets_state.dart';

class TargetsCubit extends Cubit<TargetsState> {
  TargetsCubit({
    required this._repository,
    this._clock = const SystemClock(),
    this._newId = newUuid,
  }) : super(const TargetsState()) {
    // Sends change lastUsedAt, so follow every change to the store.
    _subscription = _repository.changes.listen((_) => load());
  }

  final TargetsRepository _repository;
  final Clock _clock;
  final IdGenerator _newId;
  late final StreamSubscription<void> _subscription;

  Future<void> load() async {
    final targets = await _repository.loadAll();
    if (!isClosed) {
      emit(TargetsState(targets: targets));
    }
  }

  /// Saves [target] (the star next to the target field). A blank [label]
  /// becomes [SavedTarget.defaultLabel].
  Future<SavedTarget> save(
    Target target, {
    required String label,
    String? projectId,
  }) async {
    final trimmed = label.trim();
    final saved = SavedTarget(
      id: _newId(),
      label: trimmed.isEmpty ? SavedTarget.defaultLabel(target) : trimmed,
      kind: target.kind,
      value: target.normalized,
      projectId: projectId,
      lastUsedAt: _clock.now(),
    );
    await _repository.save(saved);
    await load();
    return saved;
  }

  /// Saves a token read from a phone (spec §7.1). Keyed by phone and app, so
  /// reading the same app's token again updates the saved target.
  Future<SavedTarget> saveDeviceToken(
    DeviceToken token, {
    String? projectId,
  }) async {
    final existing = (await _repository.loadAll())
        .where(
          (t) =>
              t.source.kind == TargetSourceKind.device &&
              t.source.serial == token.serial &&
              t.source.package == token.package,
        )
        .firstOrNull;
    final saved = SavedTarget(
      id: existing?.id ?? _newId(),
      label: token.label,
      kind: TargetKind.token,
      value: TokenTarget(token.token).normalized,
      projectId: projectId ?? existing?.projectId,
      senderId: token.senderId,
      source: TargetSource(
        kind: TargetSourceKind.device,
        serial: token.serial,
        model: token.deviceName,
        package: token.package,
      ),
      lastUsedAt: _clock.now(),
    );
    await _repository.save(saved);
    await load();
    return saved;
  }

  Future<void> rename(SavedTarget target, String label) async {
    await _repository.save(target.copyWith(label: label.trim()));
    await load();
  }

  Future<void> remove(SavedTarget target) async {
    await _repository.remove(target.id);
    await load();
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
