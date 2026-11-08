// Dev-only pixel harness. Not referenced by the app; used to capture
// readable fixture screenshots of dashboard states. Run:
//   flutter build web -t tool/dev_preview.dart
// States via query param: ?state=stale-pending | stream-error | pending | live
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:metly/config/app_config.dart';
import 'package:metly/models/portfolio_item.dart';
import 'package:metly/models/price_model.dart';
import 'package:metly/models/watchlist_item.dart';
import 'package:metly/screens/dashboard_screen.dart';
import 'package:metly/services/firestore_service.dart';
import 'package:metly/services/price_service.dart';

class _FakeFirestoreError extends FirestoreService {
  @override
  Stream<List<WatchlistItem>> watchlistStream() =>
      Stream.error(Exception('denied'));
  @override
  Stream<List<PortfolioItem>> portfolioStream() =>
      Stream.error(Exception('denied'));
}

class _FakeFirestorePending extends FirestoreService {
  @override
  Stream<List<WatchlistItem>> watchlistStream() =>
      Stream.fromFuture(Completer<List<WatchlistItem>>().future);
  @override
  Stream<List<PortfolioItem>> portfolioStream() =>
      Stream.fromFuture(Completer<List<PortfolioItem>>().future);
}

class _FixtureProvider implements PriceProvider {
  _FixtureProvider({this.hangFromStart = false, this.fresh = false});
  final bool hangFromStart;

  /// ?state=live: fresh (non-stale) snapshots so the LIVE RATE title and
  /// current-quote rendering are capturable.
  final bool fresh;
  int _calls = 0;
  @override
  Future<PriceSnapshot> latest(Metal metal) {
    _calls++;
    if (hangFromStart || _calls > 2) {
      return Completer<PriceSnapshot>().future; // fetch hangs
    }
    // 20 minutes old: past the 15-minute client freshness window but inside
    // the 30-minute stale cap - a state the real server path can produce.
    final updated = fresh
        ? DateTime.now()
        : DateTime.now().subtract(const Duration(minutes: 20));
    return Future.value(PriceSnapshot(
      metal: metal,
      price: 123216,
      sellPrice: 119518,
      gstAmount: 3696,
      purity: metal == Metal.gold ? '24K 99.9%' : '99.9%',
      recentHigh: 123216,
      updatedAt: updated,
      highIsObserved: true,
      highObservedSince: updated,
      source: 'OroPocket',
    ));
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // ignore: invalid_use_of_visible_for_testing_member -- dev-only pixel harness
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final state = Uri.base.queryParameters['state'] ?? 'stale-pending';
  runApp(MaterialApp(
    // Same theme as the production app (see lib/main.dart) so harness pixels
    // prove the real appearance.
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: Cfg.gold,
      useMaterial3: true,
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
    ),
    home: DashboardScreen(
      prefs: prefs,
      providerOverride: _FixtureProvider(
          hangFromStart: state == 'pending', fresh: state == 'live'),
      firestoreOverride:
          state == 'stream-error' ? _FakeFirestoreError() : _FakeFirestorePending(),
    ),
  ));
}
