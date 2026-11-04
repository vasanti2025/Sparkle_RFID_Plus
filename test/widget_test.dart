import 'package:flutter_test/flutter_test.dart';
import 'package:sparkle_rfid_plus/app.dart';
import 'package:sparkle_rfid_plus/core/constants/app_strings.dart';

void main() {
  testWidgets('Splash opens', (tester) async {
    await tester.pumpWidget(const SparkleRfidPlusApp());
    expect(find.text(AppStrings.everyPieceMatters), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
  });
}
