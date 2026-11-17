import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tenter/main.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows the empty local sample library', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TenterApp());
    await tester.pumpAndSettle();

    expect(find.text('TENTER'), findsOneWidget);
    expect(find.text('Catch a sound.'), findsOneWidget);
    expect(find.text('RECORD'), findsOneWidget);
  });

  testWidgets('shows the LOOM-8 connection status', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const TenterApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('LOOM-8').last);
    await tester.pumpAndSettle();

    expect(find.text('No device connected'), findsOneWidget);
    expect(find.text('CONNECT LOOM-8'), findsOneWidget);
  });
}
