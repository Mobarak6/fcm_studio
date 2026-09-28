import 'package:fcm_studio/app/startup_error_app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('explains a startup failure without leaking secrets', (
    tester,
  ) async {
    await tester.pumpWidget(
      StartupErrorApp(error: Exception('Bearer ya29.secret')),
    );
    expect(find.text('FCM Studio could not start'), findsOneWidget);
    expect(find.textContaining('[REDACTED]'), findsOneWidget);
    expect(find.textContaining('ya29.secret'), findsNothing);
    expect(
      find.textContaining('local database may be damaged'),
      findsOneWidget,
    );
  });
}
