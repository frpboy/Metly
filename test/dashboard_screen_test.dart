import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metly/models/portfolio_item.dart';
import 'package:metly/models/price_model.dart';
import 'package:metly/models/watchlist_item.dart';
import 'package:metly/screens/dashboard_screen.dart';
import 'package:metly/services/ai_service.dart';
import 'package:metly/services/firestore_service.dart';
import 'package:metly/services/price_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeFirestore extends FirestoreService {
  @override
  Stream<List<WatchlistItem>> watchlistStream() => Stream.value(const []);
  @override
  Stream<List<PortfolioItem>> portfolioStream() => Stream.value(const []);
}

class FakeFirestorePending extends FirestoreService {
  @override
  Stream<List<WatchlistItem>> watchlistStream() =>
      Stream.fromFuture(Completer<List<WatchlistItem>>().future);
  @override
  Stream<List<PortfolioItem>> portfolioStream() =>
      Stream.fromFuture(Completer<List<PortfolioItem>>().future);
}

class FakeFirestoreError extends FirestoreService {
  @override
  Stream<List<WatchlistItem>> watchlistStream() =>
      Stream.error(Exception('denied'));
  @override
  Stream<List<PortfolioItem>> portfolioStream() =>
      Stream.error(Exception('denied'));
}

class FakeProvider implements PriceProvider {
  Future<PriceSnapshot> Function(Metal) handler;
  FakeProvider(this.handler);
  @override
  Future<PriceSnapshot> latest(Metal metal) => handler(metal);
}

class FakeAi implements AiClient {
  final completer = Completer<String>();
  int calls = 0;
  @override
  Future<String> explainSignals(
      {required PriceSnapshot gold,
      required SignalResult goldSig,
      required PriceSnapshot silver,
      required SignalResult silverSig}) {
    calls++;
    return completer.future;
  }
}

PriceSnapshot snap(Metal m,
        {bool observed = true, bool stale = false, DateTime? at}) =>
    PriceSnapshot(
      metal: m,
      price: 100000,
      recentHigh: 102000,
      updatedAt: stale
          ? (at ?? DateTime.now()).subtract(const Duration(hours: 1))
          : (at ?? DateTime.now()),
      highIsObserved: observed,
      highObservedSince: observed ? (at ?? DateTime.now()) : null,
    );

Future<void> pumpDashboard(
  WidgetTester tester, {
  required FakeProvider provider,
  AiClient? ai,
  FirestoreService? firestore,
  DateTime Function()? clock,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(MaterialApp(
      home: DashboardScreen(
    prefs: prefs,
    providerOverride: provider,
    firestoreOverride: firestore ?? FakeFirestore(),
    aiOverride: ai,
    clockOverride: clock,
  )));
}

class DashClock {
  DateTime now;
  DashClock(this.now);
  DateTime call() => now;
}

void main() {
  testWidgets('refresh failure shows error and no live cards', (tester) async {
    final provider =
        FakeProvider((m) async => throw Exception('network down'));
    await pumpDashboard(tester, provider: provider);
    await tester.pumpAndSettle();
    expect(find.textContaining('Live prices unavailable'), findsOneWidget);
    expect(find.textContaining('LIVE SPOT'), findsNothing);
    expect(find.textContaining('BUY'), findsNothing);
    await tester.pumpWidget(const SizedBox()); // dispose, cancels timer
  });

  testWidgets('success shows neutral live spot cards, no verdicts',
      (tester) async {
    final provider = FakeProvider((m) async => snap(m));
    await pumpDashboard(tester, provider: provider);
    await tester.pumpAndSettle();
    expect(find.text('GOLD - LIVE SPOT'), findsOneWidget);
    expect(find.text('SILVER - LIVE SPOT'), findsOneWidget);
    expect(find.textContaining('signals are paused'), findsWidgets);
    expect(find.textContaining('BUY'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('dispose during an in-flight refresh does not crash',
      (tester) async {
    final completer = Completer<PriceSnapshot>();
    final provider = FakeProvider((m) => completer.future);
    await pumpDashboard(tester, provider: provider);
    await tester.pump();
    await tester.pumpWidget(const SizedBox()); // dispose mid-flight
    completer.complete(snap(Metal.gold));
    await tester.pump();
    // reaching here without a framework exception is the assertion
  });

  testWidgets('late AI answer cannot restore text after a failed refresh',
      (tester) async {
    var fail = false;
    final provider = FakeProvider((m) async {
      if (fail) throw Exception('network down');
      return snap(m, observed: false);
    });
    final ai = FakeAi();
    await pumpDashboard(tester, provider: provider, ai: ai);
    await tester.pumpAndSettle();

    // Genuine-high fresh snapshots: signal cards visible, AI allowed.
    expect(find.textContaining('LIVE SPOT'), findsNothing);

    await tester.tap(find.text('Ask AI'));
    await tester.pump();
    expect(ai.calls, 1);

    // Now the refresh fails; AI answer is still in flight.
    fail = true;
    await tester.tap(find.text('Refresh Prices'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Live prices unavailable'), findsOneWidget);

    // The late AI answer lands and must be discarded.
    ai.completer.complete('some old AI explanation');
    await tester.pumpAndSettle();
    expect(find.textContaining('some old AI explanation'), findsNothing);
    expect(find.textContaining('Live prices unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pending Firestore streams show a bounded 24px spinner',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final provider = FakeProvider((m) async => snap(m));
    await pumpDashboard(tester,
        provider: provider, firestore: FakeFirestorePending());
    // pumpAndSettle would hang on the infinite spinner animation; pump a few
    // frames instead so the waiting-state StreamBuilders build.
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    final spinners = find.byType(CircularProgressIndicator);
    expect(spinners, findsNWidgets(2));
    for (var i = 0; i < 2; i++) {
      expect(tester.getSize(spinners.at(i)), const Size(24, 24));
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Firestore stream errors show unavailable text, not a spinner',
      (tester) async {
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final provider = FakeProvider((m) async => snap(m));
    await pumpDashboard(tester,
        provider: provider, firestore: FakeFirestoreError());
    await tester.pumpAndSettle();
    expect(find.text('Watchlist unavailable'), findsOneWidget);
    expect(find.text('Portfolio unavailable'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a stale snapshot is labeled immediately, never shown as live',
      (tester) async {
    final t0 = DateTime.now();
    final clock = DashClock(t0);
    var hang = false;
    final provider = FakeProvider((m) {
      if (hang) return Completer<PriceSnapshot>().future;
      return Future.value(snap(m, at: clock.now));
    });
    await pumpDashboard(tester, provider: provider, clock: clock.call);
    await tester.pumpAndSettle();
    expect(find.textContaining('This price is stale'), findsNothing);

    // Jump past the freshness window with the network now hanging: the
    // deadline timer fires as fake time crosses it, the old cards relabel
    // as stale immediately, and the pending refresh cannot clear them.
    hang = true;
    clock.now = t0.add(const Duration(minutes: 16));
    await tester.pump(const Duration(minutes: 15, milliseconds: 50));
    expect(find.textContaining('This price is stale'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('crossing the freshness deadline triggers a re-fetch',
      (tester) async {
    final t0 = DateTime.now();
    final clock = DashClock(t0);
    var calls = 0;
    final provider = FakeProvider((m) async {
      calls++;
      return snap(m, at: clock.now);
    });
    await pumpDashboard(tester, provider: provider, clock: clock.call);
    await tester.pumpAndSettle();
    expect(calls, 2); // gold + silver

    clock.now = t0.add(const Duration(minutes: 16));
    await tester.pump(
        const Duration(minutes: 15, milliseconds: 50)); // deadline timer fires
    await tester.pump(const Duration(milliseconds: 50)); // refresh completes
    expect(calls, greaterThan(2)); // revalidation refreshed
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('refresh during in-flight AI resets the Thinking button',
      (tester) async {
    final provider = FakeProvider((m) async => snap(m, observed: false));
    final ai = FakeAi();
    await pumpDashboard(tester, provider: provider, ai: ai);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ask AI'));
    await tester.pump();
    expect(find.text('Thinking…'), findsOneWidget);

    await tester.tap(find.text('Refresh Prices'));
    await tester.pumpAndSettle();
    // Button recovered: label back, enabled again.
    expect(find.text('Thinking…'), findsNothing);
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Ask AI'));
    expect(button.onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('lifecycle resume with stale data revalidates', (tester) async {
    final t0 = DateTime.now();
    final clock = DashClock(t0);
    var calls = 0;
    final provider = FakeProvider((m) async {
      calls++;
      return snap(m, at: clock.now);
    });
    await pumpDashboard(tester, provider: provider, clock: clock.call);
    await tester.pumpAndSettle();
    expect(calls, 2);

    clock.now = t0.add(const Duration(minutes: 20));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pumpAndSettle();
    expect(calls, greaterThan(2));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('stale cards show LAST KNOWN, never LIVE SPOT, during a pending refresh',
      (tester) async {
    final t0 = DateTime.now();
    final clock = DashClock(t0);
    var hang = false;
    final provider = FakeProvider((m) {
      if (hang) return Completer<PriceSnapshot>().future;
      return Future.value(snap(m, at: clock.now));
    });
    await pumpDashboard(tester, provider: provider, clock: clock.call);
    await tester.pumpAndSettle();
    expect(find.text('GOLD - LIVE SPOT'), findsOneWidget);

    hang = true;
    clock.now = t0.add(const Duration(minutes: 16));
    await tester.pump(const Duration(minutes: 15, milliseconds: 50));
    expect(find.text('GOLD - LAST KNOWN (STALE)'), findsOneWidget);
    expect(find.text('SILVER - LAST KNOWN (STALE)'), findsOneWidget);
    expect(find.textContaining('LIVE SPOT'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Ask AI is disabled while a refresh is loading', (tester) async {
    final completer = Completer<PriceSnapshot>();
    final provider = FakeProvider((m) => completer.future);
    final ai = FakeAi();
    await pumpDashboard(tester, provider: provider, ai: ai);
    await tester.pump();
    final button = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Ask AI'));
    expect(button.onPressed, isNull);
    completer.complete(snap(Metal.gold));
    await tester.pumpWidget(const SizedBox());
  });
}
