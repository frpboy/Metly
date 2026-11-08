import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metly/models/portfolio_item.dart';
import 'package:metly/models/price_model.dart';
import 'package:metly/models/watchlist_item.dart';
import 'package:metly/screens/auth_screen.dart';
import 'package:metly/screens/dashboard_screen.dart';
import 'package:metly/services/ai_service.dart';
import 'package:metly/services/auth_service.dart';
import 'package:metly/services/firestore_service.dart';
import 'package:metly/services/price_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Controllable fake auth: starts at [user] and can be flipped mid-test.
class FakeAuth implements AuthService {
  MetlyUser? user;
  final _ctrl = StreamController<MetlyUser?>.broadcast();
  FakeAuth([this.user = const MetlyUser(uid: 'u1', email: 'a@b.co')]);

  void emit(MetlyUser? u) {
    user = u;
    _ctrl.add(u);
  }

  @override
  Stream<MetlyUser?> authChanges() {
    // Replay current state to every new listener, then live changes.
    late StreamController<MetlyUser?> c;
    c = StreamController<MetlyUser?>(onListen: () {
      c.add(user);
      c.addStream(_ctrl.stream).whenComplete(() => c.close());
    });
    return c.stream;
  }

  @override
  MetlyUser? get current => user;
  @override
  Future<MetlyUser> signIn(String email, String password) async {
    emit(const MetlyUser(uid: 'u1', email: 'a@b.co'));
    return user!;
  }

  @override
  Future<MetlyUser> signUp(String email, String password) => signIn(email, password);
  @override
  Future<void> resetPassword(String email) async {}
  @override
  Future<void> signOut() async => emit(null);
}

/// Records writes instead of touching Firebase.
class RecordingFirestore extends FirestoreService {
  final addedWatchlist = <WatchlistItem>[];
  final addedPortfolio = <PortfolioItem>[];
  final removedWatchlist = <String>[];
  final removedPortfolio = <String>[];
  List<WatchlistItem> watchlistItems;
  List<PortfolioItem> portfolioItems;

  RecordingFirestore(
      {this.watchlistItems = const [], this.portfolioItems = const []});

  @override
  Future<void> addWatchlistItem(WatchlistItem item) async =>
      addedWatchlist.add(item);
  @override
  Future<void> removeWatchlistItem(String id) async =>
      removedWatchlist.add(id);
  @override
  Stream<List<WatchlistItem>> watchlistStream() => Stream.value(watchlistItems);
  @override
  Future<void> addPortfolioItem(PortfolioItem item) async =>
      addedPortfolio.add(item);
  @override
  Future<void> removePortfolioItem(String id) async => removedPortfolio.add(id);
  @override
  Stream<List<PortfolioItem>> portfolioStream() => Stream.value(portfolioItems);
}

class FakeProvider implements PriceProvider {
  @override
  Future<PriceSnapshot> latest(Metal metal) async => PriceSnapshot(
        metal: metal,
        price: 100000,
        recentHigh: 102000,
        updatedAt: DateTime.now(),
        highIsObserved: true,
        highObservedSince: DateTime.now(),
        source: 'test',
      );
}

Future<void> pumpApp(WidgetTester tester,
    {required AuthService auth, required FirestoreService firestore}) async {
  tester.view.physicalSize = const Size(800, 3600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(MaterialApp(
    routes: {'/auth': (_) => AuthScreen(authOverride: auth)},
    home: DashboardScreen(
      prefs: prefs,
      providerOverride: FakeProvider(),
      firestoreOverride: firestore,
      authOverride: auth,
      aiOverride: _NeverAi(),
    ),
  ));
  await tester.pumpAndSettle();
}

class _NeverAi implements AiClient {
  @override
  Future<String> explainSignals(
          {required PriceSnapshot gold,
          required SignalResult goldSig,
          required PriceSnapshot silver,
          required SignalResult silverSig}) =>
      Completer<String>().future;
}

void main() {
  testWidgets('signed-out dashboard shows account CTA, no watchlist streams',
      (tester) async {
    await pumpApp(tester,
        auth: FakeAuth(null), firestore: RecordingFirestore());
    expect(find.text('Save your watchlist & portfolio'), findsOneWidget);
    expect(find.text('Sign in / Create account'), findsOneWidget);
    expect(find.text('Watchlist'), findsNothing);
    expect(find.text('Portfolio'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('CTA navigates to the auth screen', (tester) async {
    await pumpApp(tester,
        auth: FakeAuth(null), firestore: RecordingFirestore());
    await tester.tap(find.text('Sign in / Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('New to Metly? Create an account'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('signed-in dashboard shows sections with add buttons',
      (tester) async {
    await pumpApp(tester, auth: FakeAuth(), firestore: RecordingFirestore());
    expect(find.text('Watchlist'), findsOneWidget);
    expect(find.text('Portfolio'), findsOneWidget);
    expect(find.byTooltip('Add watchlist target'), findsOneWidget);
    expect(find.byTooltip('Add portfolio holding'), findsOneWidget);
    expect(find.text('No watchlist items yet. Tap + to add one.'),
        findsOneWidget);
    expect(find.text('No holdings yet. Tap + to add one.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('watchlist add validates input then records the item',
      (tester) async {
    final fs = RecordingFirestore();
    await pumpApp(tester, auth: FakeAuth(), firestore: fs);

    await tester.tap(find.byTooltip('Add watchlist target'));
    await tester.pumpAndSettle();

    // Invalid: empty price.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a target price above zero.'), findsOneWidget);
    expect(fs.addedWatchlist, isEmpty);

    // Valid: dialog closes and the write is recorded.
    await tester.enterText(
        find.widgetWithText(TextField, 'Target price (₹)'), '7000');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fs.addedWatchlist.length, 1);
    expect(fs.addedWatchlist.single.metal, 'gold');
    expect(fs.addedWatchlist.single.targetPrice, 7000);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('portfolio add validates both numbers then records the holding',
      (tester) async {
    final fs = RecordingFirestore();
    await pumpApp(tester, auth: FakeAuth(), firestore: fs);

    await tester.tap(find.byTooltip('Add portfolio holding'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a quantity above zero.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '2.5');
    await tester.enterText(
        find.widgetWithText(TextField, 'Average buy price (₹ per unit)'),
        '6500');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(fs.addedPortfolio.length, 1);
    expect(fs.addedPortfolio.single.amount, 2.5);
    expect(fs.addedPortfolio.single.avgPrice, 6500);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('delete buttons call remove on the service', (tester) async {
    final fs = RecordingFirestore(watchlistItems: [
      WatchlistItem(
          id: 'w1', metal: 'silver', targetPrice: 90, addedAt: DateTime.now())
    ], portfolioItems: [
      PortfolioItem(
          id: 'p1',
          metal: 'gold',
          amount: 1,
          avgPrice: 6000,
          addedAt: DateTime.now())
    ]);
    await pumpApp(tester, auth: FakeAuth(), firestore: fs);
    await tester.tap(find.byTooltip('Remove from watchlist'));
    await tester.tap(find.byTooltip('Remove holding'));
    await tester.pumpAndSettle();
    expect(fs.removedWatchlist, ['w1']);
    expect(fs.removedPortfolio, ['p1']);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('auth screen validates email and password before submit',
      (tester) async {
    var submitted = false;
    final auth = _SubmitSpyAuth(onSubmit: () => submitted = true);
    await tester.pumpWidget(
        MaterialApp(home: AuthScreen(authOverride: auth)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(submitted, isFalse);

    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'rahul@example.com');
    await tester.enterText(find.widgetWithText(TextField, 'Password'), '123');
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
    expect(
        find.text('Password must be at least 6 characters.'), findsOneWidget);
    expect(submitted, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('create-account toggle flips the auth screen mode',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: AuthScreen(authOverride: FakeAuth(null))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New to Metly? Create an account'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
    expect(find.text('Create account'), findsOneWidget);
    expect(find.text('Already have an account? Sign in'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('signed-out FirestoreService emits empty lists and refuses writes',
      () async {
    final fs = FirestoreService(); // no uid
    expect(await fs.watchlistStream().first, isEmpty);
    expect(await fs.portfolioStream().first, isEmpty);
    expect(
        () => fs.addWatchlistItem(WatchlistItem(
            id: 'x', metal: 'gold', targetPrice: 1, addedAt: DateTime.now())),
        throwsStateError);
    expect(
        () => fs.addPortfolioItem(PortfolioItem(
            id: 'x',
            metal: 'gold',
            amount: 1,
            avgPrice: 1,
            addedAt: DateTime.now())),
        throwsStateError);
  });

  testWidgets('watchlist add rejects NaN and Infinity', (tester) async {
    final fs = RecordingFirestore();
    await pumpApp(tester, auth: FakeAuth(), firestore: fs);
    await tester.tap(find.byTooltip('Add watchlist target'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Target price (₹)'), 'nan');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a target price above zero.'), findsOneWidget);
    expect(fs.addedWatchlist, isEmpty);

    await tester.enterText(
        find.widgetWithText(TextField, 'Target price (₹)'), 'Infinity');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a target price above zero.'), findsOneWidget);
    expect(fs.addedWatchlist, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('portfolio add rejects NaN quantity and Infinity price',
      (tester) async {
    final fs = RecordingFirestore();
    await pumpApp(tester, auth: FakeAuth(), firestore: fs);
    await tester.tap(find.byTooltip('Add portfolio holding'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Quantity'), 'nan');
    await tester.enterText(
        find.widgetWithText(TextField, 'Average buy price (₹ per unit)'),
        '100');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a quantity above zero.'), findsOneWidget);
    expect(fs.addedPortfolio, isEmpty);

    await tester.enterText(find.widgetWithText(TextField, 'Quantity'), '1');
    await tester.enterText(
        find.widgetWithText(TextField, 'Average buy price (₹ per unit)'),
        'Infinity');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(find.text('Enter an average price above zero.'), findsOneWidget);
    expect(fs.addedPortfolio, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('forgot password sends a reset and confirms without leaking',
      (tester) async {
    final resets = <String>[];
    final auth = _ResetSpyAuth(resets);
    await tester.pumpWidget(MaterialApp(home: AuthScreen(authOverride: auth)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(resets, isEmpty);
    expect(
        find.text('Enter your email above, then tap "Forgot password".'),
        findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'rahul@example.com');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(resets, ['rahul@example.com']);
    expect(
        find.text(
            'If an account exists for that email, a reset link is on its way.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('successful sign-in on initial /auth route goes home, no crash',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      initialRoute: '/auth',
      routes: {
        '/': (_) => const Scaffold(body: Text('HOME-ROUTE')),
        '/auth': (_) => AuthScreen(authOverride: FakeAuth(null)),
      },
    ));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextField, 'Email'), 'a@b.co');
    await tester.enterText(
        find.widgetWithText(TextField, 'Password'), 'secret1');
    await tester.tap(find.text('Sign in').last);
    await tester.pumpAndSettle();
    expect(find.text('HOME-ROUTE'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  test('tryFromMap returns null for malformed documents', () {
    expect(WatchlistItem.tryFromMap('x', {'metal': 'gold'}), isNull);
    expect(
        WatchlistItem.tryFromMap('x', {
          'metal': 'gold',
          'targetPrice': 'oops',
          'addedAt': '2026-11-08T00:00:00.000'
        }),
        isNull);
    expect(
        WatchlistItem.tryFromMap('x', {
          'metal': 'gold',
          'targetPrice': 7000,
          'addedAt': '2026-11-08T00:00:00.000'
        })!
            .targetPrice,
        7000);
    expect(PortfolioItem.tryFromMap('y', {'metal': 'silver'}), isNull);
    expect(
        PortfolioItem.tryFromMap('y', {
          'metal': 'silver',
          'amount': 2,
          'avgPrice': 90,
          'addedAt': '2026-11-08T00:00:00.000'
        })!
            .amount,
        2);
  });
}

class _SubmitSpyAuth implements AuthService {
  final void Function() onSubmit;
  _SubmitSpyAuth({required this.onSubmit});
  @override
  Stream<MetlyUser?> authChanges() => Stream.value(null);
  @override
  MetlyUser? get current => null;
  @override
  Future<MetlyUser> signIn(String email, String password) async {
    onSubmit();
    return const MetlyUser(uid: 'u1');
  }

  @override
  Future<MetlyUser> signUp(String email, String password) async {
    onSubmit();
    return const MetlyUser(uid: 'u1');
  }

  @override
  Future<void> resetPassword(String email) async {}

  @override
  Future<void> signOut() async {}
}


class _ResetSpyAuth implements AuthService {
  final List<String> resets;
  _ResetSpyAuth(this.resets);
  @override
  Stream<MetlyUser?> authChanges() => Stream.value(null);
  @override
  MetlyUser? get current => null;
  @override
  Future<MetlyUser> signIn(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<MetlyUser> signUp(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<void> resetPassword(String email) async => resets.add(email);
  @override
  Future<void> signOut() async {}
}
