import 'package:fcm_studio/features/composer/domain/target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('token: removes whitespace, line breaks and surrounding quotes', () {
    expect(const TokenTarget('  "abc:APA91b\n  xyz"  ').token, 'abc:APA91bxyz');
    expect(const TokenTarget("'abc'").token, 'abc');
  });

  test('token: empty is an error', () {
    expect(
      const TokenTarget('  ').validate().single.message,
      'Enter a device token.',
    );
    expect(const TokenTarget('abc').validate(), isEmpty);
  });

  test('topic: removes /topics/ and checks the characters', () {
    expect(const TopicTarget(' /topics/news ').name, 'news');
    expect(const TopicTarget('news').validate(), isEmpty);
    expect(const TopicTarget('news feed').validate().single.path, 'target');
    expect(
      const TopicTarget('').validate().single.message,
      'Enter a topic name.',
    );
  });

  test('condition: trims and requires a value', () {
    expect(
      const ConditionTarget("  'a' in topics ").expression,
      "'a' in topics",
    );
    expect(const ConditionTarget(' ').validate(), hasLength(1));
  });

  test('toMessageField uses the matching FCM field', () {
    expect(const TokenTarget(' a ').toMessageField(), {'token': 'a'});
    expect(const TopicTarget('/topics/b').toMessageField(), {'topic': 'b'});
    expect(const ConditionTarget("'b' in topics").toMessageField(), {
      'condition': "'b' in topics",
    });
  });

  test('Target.of builds the matching type', () {
    expect(Target.of(TargetKind.token, 'a'), const TokenTarget('a'));
    expect(Target.of(TargetKind.topic, 'a'), const TopicTarget('a'));
    expect(Target.of(TargetKind.condition, 'a'), const ConditionTarget('a'));
  });

  test('normalized is the value that goes to FCM', () {
    expect(const TokenTarget(' "abc def" ').normalized, 'abcdef');
    expect(const TopicTarget('/topics/news').normalized, 'news');
    expect(
      const ConditionTarget("  'a' in topics ").normalized,
      "'a' in topics",
    );
  });
}
