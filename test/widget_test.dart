import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metly/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setupFirebaseCoreMocks();

  setUpAll(() async {
    await Firebase.initializeApp();
  });
  testWidgets('App loads and displays Home screen', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MetlyApp(prefs: prefs));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Metly'), findsOneWidget);
    expect(find.text('Enter Dashboard'), findsOneWidget);
  });

  testWidgets('Feedback screen shows hints and submits feedback', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MetlyApp(prefs: prefs));
    await tester.pumpAndSettle();

    // Open drawer and navigate to feedback
    final menuButton = find.byTooltip('Menu');
    expect(menuButton, findsOneWidget);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Feedback'));
    await tester.pumpAndSettle();

    expect(find.text('Feedback'), findsWidgets);
    expect(find.text('name@example.com'), findsOneWidget);
    expect(find.text('Share ideas, issues, or suggestions…'), findsOneWidget);

    // Enter message and submit
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Your message'), 'Great app!');
    await tester.tap(find.text('Submit'));
    await tester.pump();

    expect(find.text('Thank you! Feedback submitted.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });

  testWidgets('Dashboard loads and displays prices for both metals', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MetlyApp(prefs: prefs));
    await tester.pumpAndSettle();

    // Tap "Enter Dashboard" button from HomeScreen
    await tester.tap(find.text('Enter Dashboard'));
    await tester.pump();
    // Allow Future.wait to complete (mock delay is 120ms)
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Refresh Prices'), findsOneWidget);
    // Gold and Silver signal cards are rendered
    expect(find.textContaining('GOLD'), findsWidgets);
    expect(find.textContaining('SILVER'), findsWidgets);

    // Tap Refresh Prices to verify concurrent refresh completes successfully
    await tester.tap(find.text('Refresh Prices'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();

    expect(find.textContaining('GOLD'), findsWidgets);
    expect(find.textContaining('SILVER'), findsWidgets);
  });
}
