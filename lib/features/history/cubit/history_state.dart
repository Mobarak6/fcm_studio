import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/history/domain/history_filter.dart';

enum HistoryStatus { initial, loading, ready }

class HistoryState extends Equatable {
  const HistoryState({
    this.status = HistoryStatus.initial,
    this.entries = const [],
    this.filter = const HistoryFilter(),
  });

  final HistoryStatus status;

  /// Every entry, newest first.
  final List<HistoryEntry> entries;
  final HistoryFilter filter;

  /// The entries that match [filter].
  List<HistoryEntry> get visible => entries.where(filter.matches).toList();

  /// The projects that appear in history, for the project filter.
  List<String> get projectIds =>
      {for (final e in entries) e.projectId}.toList()..sort();

  HistoryState copyWith({
    HistoryStatus? status,
    List<HistoryEntry>? entries,
    HistoryFilter? filter,
  }) => HistoryState(
    status: status ?? this.status,
    entries: entries ?? this.entries,
    filter: filter ?? this.filter,
  );

  @override
  List<Object?> get props => [status, entries, filter];
}
