import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metly/models/price_model.dart';
import 'package:metly/widgets/signal_card.dart';

void main() {
  testWidgets('SignalCard renders buy state with icon and semantics',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final goldSnapshot = PriceSnapshot(
      metal: Metal.gold,
      price: 75000,
      recentHigh: 76000,
      updatedAt: now,
    );
    const buyResult = SignalResult(
      Signal.buy,
      'Gold is trading near key support.',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignalCard(snapshot: goldSnapshot, result: buyResult),
        ),
      ),
    );

    expect(find.text('BUY GOLD NOW!'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up_rounded), findsOneWidget);
    expect(find.text('Gold is trading near key support.'), findsOneWidget);

    final semanticsFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label?.contains('Buy recommendation for Gold') ==
              true,
    );
    expect(semanticsFinder, findsOneWidget);
  });

  testWidgets('SignalCard renders wait state with icon and semantics',
      (WidgetTester tester) async {
    final now = DateTime.now();
    final silverSnapshot = PriceSnapshot(
      metal: Metal.silver,
      price: 92000,
      recentHigh: 92500,
      updatedAt: now,
    );
    const waitResult = SignalResult(
      Signal.wait,
      'Silver is close to recent peak.',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SignalCard(snapshot: silverSnapshot, result: waitResult),
        ),
      ),
    );

    expect(find.text('WAIT SILVER '), findsOneWidget);
    expect(find.byIcon(Icons.pause_circle_outline_rounded), findsOneWidget);
    expect(find.text('Silver is close to recent peak.'), findsOneWidget);

    final semanticsFinder = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          widget.properties.label?.contains('Wait recommendation for Silver') ==
              true,
    );
    expect(semanticsFinder, findsOneWidget);
  });
}
