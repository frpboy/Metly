import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metly/models/price_model.dart';
import 'package:metly/widgets/signal_card.dart';

Widget wrap(Widget child) =>
    MaterialApp(home: Scaffold(body: SingleChildScrollView(child: child)));

void main() {
  final snapshot = PriceSnapshot(
    metal: Metal.gold,
    price: 100000,
    recentHigh: 102000,
    updatedAt: DateTime.now(),
    highIsObserved: true,
    highObservedSince: DateTime.utc(2026, 11, 1),
    source: 'gold-api.com',
  );

  testWidgets('LiveSpotCard shows neutral spot info, no buy/wait verdict',
      (tester) async {
    await tester.pumpWidget(wrap(LiveSpotCard(snapshot: snapshot)));
    expect(find.text('GOLD - LIVE SPOT'), findsOneWidget);
    expect(find.textContaining('signals are paused'), findsOneWidget);
    expect(find.textContaining('not Indian retail rates'), findsOneWidget);
    expect(find.textContaining('highest price observed by this app since'),
        findsOneWidget);
    // Attribution is visible.
    expect(find.textContaining('gold-api.com', findRichText: true), findsOneWidget);
    // No trading verdict anywhere on the card.
    expect(find.textContaining('BUY'), findsNothing);
    expect(find.textContaining('WAIT'), findsNothing);
  });

  testWidgets('SignalCard carries source attribution too', (tester) async {
    final sig = evaluateSignal(
        PriceSnapshot(
          metal: Metal.gold,
          price: 95,
          recentHigh: 100,
          updatedAt: DateTime.now(),
          source: 'configured price worker',
        ),
        now: DateTime.now());
    await tester
        .pumpWidget(wrap(SignalCard(snapshot: PriceSnapshot(
          metal: Metal.gold,
          price: 95,
          recentHigh: 100,
          updatedAt: DateTime.now(),
          source: 'configured price worker',
        ), result: sig)));
    expect(find.textContaining('configured price worker', findRichText: true), findsOneWidget);
  });

  testWidgets('LiveSpotCard golden: neutral card layout', (tester) async {
    await tester.pumpWidget(wrap(SizedBox(
        width: 420, child: LiveSpotCard(snapshot: snapshot))));
    await expectLater(find.byType(LiveSpotCard),
        matchesGoldenFile('live_spot_card.png'));
  });
}
