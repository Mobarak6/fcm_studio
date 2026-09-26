import 'package:fcm_studio/core/utils/clock.dart';

class FixedClock implements Clock {
  FixedClock(this.current);

  DateTime current;

  @override
  DateTime now() => current;

  void advance(Duration duration) => current = current.add(duration);
}
