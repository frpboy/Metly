import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metly/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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

    // Enter message and verify clear button works
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Your message'), 'Typo message');
    await tester.pumpAndSettle();

    final clearBtn = find.byTooltip('Clear message');
    expect(clearBtn, findsOneWidget);
    await tester.tap(clearBtn);
    await tester.pumpAndSettle();
    expect(find.byTooltip('Clear message'), findsNothing);

    // Enter message and submit
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Your message'), 'Great app!');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Submit'));
    await tester.pump();

    expect(find.text('Thank you! Feedback submitted.'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
  });
}
