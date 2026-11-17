import 'package:flutter_test/flutter_test.dart';

import 'package:tenter/main.dart';

void main() {
  testWidgets('shows the Tenter app name', (WidgetTester tester) async {
    await tester.pumpWidget(const TenterApp());

    expect(find.text('Tenter'), findsOneWidget);
  });
}
