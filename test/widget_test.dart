// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:driver_app/main.dart';

void main() {
  testWidgets('App boots smoke test', (WidgetTester tester) async {
    // Build the app and verify it renders without throwing.
    await tester.pumpWidget(const DriverApp());
    // Splash screen schedules a short timer; advance fake time to flush it.
    await tester.pump(const Duration(seconds: 3));
    expect(find.byType(DriverApp), findsOneWidget);

    // Dispose app tree so periodic/background timers are canceled in dispose.
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
