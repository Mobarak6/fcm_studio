import 'dart:async';

import 'package:fcm_studio/features/composer/data/message_sender.dart';
import 'package:fcm_studio/features/history/cubit/history_state.dart';
import 'package:fcm_studio/features/history/data/history_repository.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/history/domain/history_filter.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

export 'package:fcm_studio/features/history/cubit/history_state.dart';

class HistoryCubit extends Cubit<HistoryState> {
  HistoryCubit({required this._repository, required this._sender})
    : super(const HistoryState()) {
    // The composer records sends in the same store.
    _subscription = _repository.changes.listen((_) => load());
  }

  final HistoryRepository _repository;
  final MessageSender _sender;
  late final StreamSubscription<void> _subscription;

  Future<void> load() async {
    final entries = await _repository.loadAll();
    if (!isClosed) {
      emit(state.copyWith(status: HistoryStatus.ready, entries: entries));
    }
  }

  void setFilter(HistoryFilter filter) => emit(state.copyWith(filter: filter));

  Future<void> clear() async {
    await _repository.clear();
    await load();
  }

  /// Sends [entry]'s stored request again, with a current access token
  /// (spec §7.2). The resend gets its own history entry.
  Future<SendOutcome> resend(HistoryEntry entry, Project project) =>
      _sender.send(
        project: project,
        request: entry.request,
        target: entry.target.toTarget(),
        presetName: entry.presetName,
      );

  Future<String> curl(
    HistoryEntry entry,
    Project project, {
    required bool includeAccessToken,
  }) => _sender.curl(
    project: project,
    request: entry.request,
    includeAccessToken: includeAccessToken,
  );

  @override
  Future<void> close() async {
    await _subscription.cancel();
    return super.close();
  }
}
