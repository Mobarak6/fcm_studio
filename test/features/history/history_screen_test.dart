import 'package:fcm_studio/app/navigation_cubit.dart';
import 'package:fcm_studio/features/composer/cubit/composer_cubit.dart';
import 'package:fcm_studio/features/history/cubit/history_cubit.dart';
import 'package:fcm_studio/features/history/domain/history_entry.dart';
import 'package:fcm_studio/features/history/view/history_screen.dart';
import 'package:fcm_studio/features/presets/cubit/presets_cubit.dart';
import 'package:fcm_studio/features/presets/view/preset_details_dialog.dart';
import 'package:fcm_studio/features/projects/domain/project.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import '../../helpers/app_harness.dart';
import '../../helpers/fake_google.dart';
import '../../helpers/history_fixture.dart';
import '../../helpers/service_account_fixture.dart';

void main() {
  Future<(ComposerCubit, List<http.Request>)> openHistory(
    WidgetTester tester, {
    List<HistoryEntry> entries = const [],
    ProjectEnvironment environment = ProjectEnvironment.dev,
  }) async {
    final requests = <http.Request>[];
    final dependencies = await buildTestDependencies(
      tester,
      client: fakeGoogle(onFcmRequest: requests.add),
    );
    await tester.runAsync(() async {
      for (final entry in entries) {
        await dependencies.historyRepository.add(entry);
      }
    });
    await pumpApp(tester, dependencies);
    final projects = await addTestProject(tester);
    await tester.runAsync(
      () => projects.setEnvironment(testProjectId, environment),
    );
    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pumpAndSettle();
    return (readCubit<ComposerCubit>(tester), requests);
  }

  Future<void> expand(WidgetTester tester, String id) async {
    await tester.tap(find.byKey(ValueKey('history-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('a send from the composer shows up in History', (tester) async {
    final (projects, composer) = await pumpAppWithProject(tester);
    composer.setTargetValue('abc:APA91bxyz');
    await tester.runAsync(() => composer.send(projects.state.selected!));
    await tester.runAsync(readCubit<HistoryCubit>(tester).load);
    await tester.tap(find.byKey(const Key('nav-history')));
    await tester.pumpAndSettle();
    expect(find.textContaining('demo-project · Sent'), findsOneWidget);
  });

  testWidgets('filters by outcome and searches', (tester) async {
    await openHistory(
      tester,
      entries: [
        historyEntry(
          'ok',
          presetName: 'Promo',
          sentAt: DateTime.utc(2026, 10, 3, 9),
        ),
        historyEntry('bad', ok: false, sentAt: DateTime.utc(2026, 10, 3, 10)),
      ],
    );
    expect(find.byType(HistoryTile), findsNWidgets(2));

    await tester.tap(find.text('Failed'));
    await tester.pump();
    expect(find.byType(HistoryTile), findsOneWidget);
    expect(find.textContaining('UNREGISTERED'), findsOneWidget);

    await tester.tap(find.text('All'));
    await tester.enterText(find.byKey(HistoryScreen.searchKey), 'promo');
    await tester.pump();
    expect(find.byType(HistoryTile), findsOneWidget);
    expect(find.textContaining('Promo'), findsOneWidget);
  });

  testWidgets('Resend sends the stored request again', (tester) async {
    final (_, requests) = await openHistory(
      tester,
      entries: [historyEntry('e1')],
    );
    await expand(tester, 'e1');
    await tester.tap(find.byKey(const ValueKey('history-resend-e1')));
    await settleAsync(tester);
    expect(requests, hasLength(1));
    expect(
      find.text('Resent: projects/demo-project/messages/0:1'),
      findsOneWidget,
    );
  });

  testWidgets('Resend asks first for a production project', (tester) async {
    final (_, requests) = await openHistory(
      tester,
      entries: [historyEntry('e1')],
      environment: ProjectEnvironment.prod,
    );
    await expand(tester, 'e1');
    await tester.tap(find.byKey(const ValueKey('history-resend-e1')));
    await tester.pumpAndSettle();
    expect(find.text('Send to production?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await settleAsync(tester);
    expect(requests, isEmpty);
  });

  testWidgets('Resend is off when the project was removed', (tester) async {
    await openHistory(
      tester,
      entries: [historyEntry('gone', projectId: 'gone-project')],
    );
    await expand(tester, 'gone');
    final resend = tester.widget<ButtonStyleButton>(
      find.byKey(const ValueKey('history-resend-gone')),
    );
    expect(resend.onPressed, isNull);
    expect(
      find.byTooltip('The project gone-project was removed.'),
      findsOneWidget,
    );
  });

  testWidgets('Open in composer loads the message and its target', (
    tester,
  ) async {
    final (composer, _) = await openHistory(
      tester,
      entries: [historyEntry('e1')],
    );
    await expand(tester, 'e1');
    await tester.tap(find.byKey(const ValueKey('history-open-e1')));
    await tester.pumpAndSettle();
    expect(composer.state.template, {
      'notification': {'title': 'Order shipped'},
    });
    expect(composer.state.targetValue, 'abc:APA91bxyz');
    expect(readCubit<NavigationCubit>(tester).state, AppSection.composer);
  });

  testWidgets('Save as preset stores the message without variables', (
    tester,
  ) async {
    await openHistory(tester, entries: [historyEntry('e1')]);
    await expand(tester, 'e1');
    await tester.tap(find.byKey(const ValueKey('history-save-e1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(PresetDetailsDialog.nameKey),
      'From history',
    );
    await tester.enterText(find.byKey(PresetDetailsDialog.groupKey), 'Ops');
    await tester.tap(find.byKey(PresetDetailsDialog.saveKey));
    await settleAsync(tester);
    final saved = readCubit<PresetsCubit>(tester).state.userPresets.single;
    expect(saved.name, 'From history');
    expect(saved.variables, isEmpty);
    expect(saved.group, 'Ops');
    expect(saved.template, {
      'notification': {'title': 'Order shipped'},
    });
  });

  testWidgets('Clear history with a project filter set leaves a valid filter', (
    tester,
  ) async {
    await openHistory(
      tester,
      entries: [
        historyEntry('a', sentAt: DateTime.utc(2026, 10, 3, 9)),
        historyEntry('b', sentAt: DateTime.utc(2026, 10, 3, 10)),
      ],
    );
    await tester.tap(find.byType(DropdownButton<String?>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('demo-project').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(HistoryScreen.clearKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-clear-confirm')));
    await settleAsync(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Nothing sent yet.'), findsOneWidget);
  });

  testWidgets('Clear history asks, then empties the list', (tester) async {
    await openHistory(tester, entries: [historyEntry('e1')]);
    await tester.tap(find.byKey(HistoryScreen.clearKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('history-clear-confirm')));
    await settleAsync(tester);
    expect(find.text('Nothing sent yet.'), findsOneWidget);
  });
}
