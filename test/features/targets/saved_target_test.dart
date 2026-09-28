import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:fcm_studio/features/targets/domain/saved_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 10, 3, 9);

  SavedTarget saved(
    String id, {
    TargetKind kind = TargetKind.token,
    String value = 'tok',
    String? projectId,
    Duration age = Duration.zero,
  }) => SavedTarget(
    id: id,
    label: 'Label $id',
    kind: kind,
    value: value,
    projectId: projectId,
    lastUsedAt: t0.subtract(age),
  );

  test('round-trips every field, including a device source', () {
    final target = SavedTarget(
      id: 'a',
      label: 'Redmi · com.example (debug)',
      kind: TargetKind.token,
      value: 'tok',
      projectId: 'demo-project',
      senderId: '123456789012',
      source: const TargetSource(
        kind: TargetSourceKind.device,
        serial: 'SER',
        model: 'Redmi',
        package: 'com.example',
      ),
      lastUsedAt: t0,
    );
    expect(SavedTarget.fromJson(target.toJson()), target);
  });

  test('matches a target by its normalised value', () {
    final target = saved('a', value: 'abc:APA91b');
    expect(target.matches(const TokenTarget(' "abc:APA91b" ')), isTrue);
    expect(target.matches(const TopicTarget('abc:APA91b')), isFalse);
  });

  test('orderFor puts the current project first, each group newest first', () {
    final ordered = SavedTarget.orderFor([
      saved('other-new', projectId: 'other'),
      saved(
        'mine-old',
        projectId: 'demo-project',
        age: const Duration(days: 2),
      ),
      saved('mine-new', projectId: 'demo-project'),
      saved('none', age: const Duration(days: 1)),
    ], 'demo-project');
    expect(ordered.map((t) => t.id), [
      'mine-new',
      'mine-old',
      'other-new',
      'none',
    ]);
  });

  test('tokens are shortened for display; topics are shown in full', () {
    expect(saved('a', value: 'fAbC12345678909xYz').displayValue, 'fAbC12…9xYz');
    expect(
      saved('b', kind: TargetKind.topic, value: 'news').displayValue,
      'news',
    );
  });

  test('default labels', () {
    expect(
      SavedTarget.defaultLabel(const TokenTarget('fAbC12345678909xYz')),
      'Token fAbC12…9xYz',
    );
    expect(SavedTarget.defaultLabel(const TopicTarget('news')), 'Topic news');
    expect(
      SavedTarget.defaultLabel(const ConditionTarget("'a' in topics")),
      "'a' in topics",
    );
  });
}
