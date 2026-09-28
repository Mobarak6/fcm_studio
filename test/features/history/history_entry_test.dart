import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/history/domain/history_filter.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/history_fixture.dart';

void main() {
  test('round-trips success and failure entries through JSON', () {
    for (final entry in [
      historyEntry('a'),
      historyEntry('b', ok: false, dryRun: true, presetName: 'Promo'),
    ]) {
      expect(HistoryEntry.fromJson(entry.toJson()), entry);
    }
  });

  test('a failure before FCM answered has no status and still round-trips', () {
    final entry = HistoryEntry(
      id: 'n',
      sentAt: DateTime.utc(2026, 10, 3),
      projectId: 'demo-project',
      environment: ProjectEnvironment.prod,
      target: const HistoryTarget(kind: TargetKind.topic, value: 'news'),
      request: const {
        'message': {'topic': 'news'},
      },
      validateOnly: false,
      outcome: const HistoryFailure(
        code: 'NETWORK',
        explanation: 'Network error',
      ),
      duration: Duration.zero,
    );
    expect(HistoryEntry.fromJson(entry.toJson()), entry);
    expect(entry.succeeded, isFalse);
  });

  test('template is the stored message without its target', () {
    expect(historyEntry('a').template, {
      'notification': {'title': 'Order shipped'},
    });
  });

  group('filter', () {
    final entries = [
      historyEntry('ok', presetName: 'Promo'),
      historyEntry('failed', ok: false),
      historyEntry('dry', dryRun: true),
      historyEntry('other', projectId: 'other-project'),
    ];

    List<String> ids(HistoryFilter filter) => [
      for (final e in entries)
        if (filter.matches(e)) e.id,
    ];

    test('by project', () {
      expect(ids(const HistoryFilter(projectId: 'other-project')), ['other']);
    });

    test('by outcome', () {
      expect(ids(const HistoryFilter(outcome: OutcomeFilter.failure)), [
        'failed',
      ]);
      expect(ids(const HistoryFilter(outcome: OutcomeFilter.success)), [
        'ok',
        'dry',
        'other',
      ]);
    });

    test('by dry run or real', () {
      expect(ids(const HistoryFilter(mode: ModeFilter.dryRun)), ['dry']);
      expect(ids(const HistoryFilter(mode: ModeFilter.real)), [
        'ok',
        'failed',
        'other',
      ]);
    });

    test('text search covers the target, the preset and the body', () {
      expect(ids(const HistoryFilter(query: 'promo')), ['ok']);
      expect(ids(const HistoryFilter(query: 'REDMI')), hasLength(4));
      expect(ids(const HistoryFilter(query: 'shipped')), hasLength(4));
      expect(ids(const HistoryFilter(query: 'nothing like this')), isEmpty);
    });
  });
}
