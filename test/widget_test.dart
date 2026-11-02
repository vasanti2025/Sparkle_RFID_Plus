import 'package:flutter_test/flutter_test.dart';
import 'package:sparkle_rfid_plus/main.dart';

void main() {
  testWidgets('Splash opens', (tester) async {
    await tester.pumpWidget(const SparkleRfidPlusApp());
    expect(find.text('Every piece matters.'), findsOneWidget);
  });
}
