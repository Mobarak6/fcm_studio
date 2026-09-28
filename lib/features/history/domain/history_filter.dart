import 'dart:convert';

import 'package:equatable/equatable.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';

enum OutcomeFilter { all, success, failure }

enum ModeFilter { all, real, dryRun }

/// The History screen's filters (spec §7.2).
class HistoryFilter extends Equatable {
  const HistoryFilter({
    this.projectId,
    this.outcome = OutcomeFilter.all,
    this.mode = ModeFilter.all,
    this.query = '',
  });

  /// Null shows every project.
  final String? projectId;
  final OutcomeFilter outcome;
  final ModeFilter mode;

  /// Searches the target, the preset name and the request body.
  final String query;

  bool matches(HistoryEntry entry) {
    if (projectId != null && entry.projectId != projectId) {
      return false;
    }
    final outcomeMatches = switch (outcome) {
      OutcomeFilter.all => true,
      OutcomeFilter.success => entry.succeeded,
      OutcomeFilter.failure => !entry.succeeded,
    };
    final modeMatches = switch (mode) {
      ModeFilter.all => true,
      ModeFilter.real => !entry.validateOnly,
      ModeFilter.dryRun => entry.validateOnly,
    };
    if (!outcomeMatches || !modeMatches) {
      return false;
    }
    final text = query.trim().toLowerCase();
    if (text.isEmpty) {
      return true;
    }
    return [
      entry.target.value,
      entry.target.label ?? '',
      entry.presetName ?? '',
      jsonEncode(entry.request),
    ].join('\n').toLowerCase().contains(text);
  }

  HistoryFilter copyWith({
    String? Function()? projectId,
    OutcomeFilter? outcome,
    ModeFilter? mode,
    String? query,
  }) => HistoryFilter(
    projectId: projectId != null ? projectId() : this.projectId,
    outcome: outcome ?? this.outcome,
    mode: mode ?? this.mode,
    query: query ?? this.query,
  );

  @override
  List<Object?> get props => [projectId, outcome, mode, query];
}
