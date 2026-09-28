import 'dart:async';

import 'package:fcm_studio/core/utils/clock.dart';
import 'package:fcm_studio/core/utils/ids.dart';
import 'package:fcm_studio/features/composer/domain/target.dart';
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
