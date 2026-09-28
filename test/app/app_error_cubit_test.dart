import 'package:fcm_studio/app/app_error_cubit.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'reports an error redacted, with what was being done, until dismissed',
    () {
      final cubit = AppErrorCubit()
        ..report(
          Exception('Authorization: Bearer ya29.secret'),
          context: 'Could not save',
        );
      expect(
        cubit.state,
        'Could not save: Exception: Authorization: Bearer [REDACTED]',
      );
      cubit.dismiss();
      expect(cubit.state, isNull);
    },
  );

  test(
    'routeUncaughtErrors shows framework errors and keeps the old handler',
    () {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      final previousFlutter = FlutterError.onError;
      addTearDown(() {
        FlutterError.onError = previousFlutter;
      });
      final seen = <FlutterErrorDetails>[];
      FlutterError.onError = seen.add;
      final cubit = AppErrorCubit();

      routeUncaughtErrors(binding, cubit);
      final details = FlutterErrorDetails(
        exception: StateError('build failed'),
      );
      FlutterError.onError!(details);

      expect(cubit.state, 'Bad state: build failed');
      expect(seen, [details]);
    },
  );
}
