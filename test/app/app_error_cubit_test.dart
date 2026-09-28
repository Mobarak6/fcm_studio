import 'package:fcm_studio/app/app_error_cubit.dart';
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
}
