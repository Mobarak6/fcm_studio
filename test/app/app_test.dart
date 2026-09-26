import 'package:fcm_studio/app/app.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the app title', (tester) async {
    await tester.pumpWidget(const FcmStudioApp());
    expect(find.text('FCM Studio'), findsOneWidget);
  });
}
