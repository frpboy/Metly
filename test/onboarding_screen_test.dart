import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metly/screens/onboarding_screen.dart';
import 'package:metly/services/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _SignedInStubAuth extends SignedOutStubAuth {
  const _SignedInStubAuth();
  @override
  MetlyUser? get current =>
      const MetlyUser(uid: 'test-uid', email: 'user@example.com');
}

Widget _wrap(SharedPreferences prefs, {Map<String, WidgetBuilder>? routes}) {
  return MaterialApp(
    theme: ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: const Color(0xFFFFD700),
      useMaterial3: true,
      fontFamily: 'Poppins',
    ),
    home: OnboardingScreen(prefs: prefs),
    routes: routes ?? {},
  );
}

void main() {
  GoogleFonts.config.allowRuntimeFetching = false;

  // Load real Poppins binaries so goldens render readable text instead of the
  // test placeholder font. Test-only assets; the app itself fetches Poppins
  // at runtime via google_fonts.
  setUpAll(() async {
    // Material Icons glyph font (committed copy from the Flutter SDK) so
    // icon areas are readable in goldens on any machine.
    const iconFontPath = 'test/fonts/MaterialIcons-Regular.otf';
    final iconBytes = await File(iconFontPath).readAsBytes();
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(iconBytes)));
    await iconLoader.load();
    for (final entry in const [
      ('test/fonts/Poppins-Regular.ttf', FontWeight.normal),
      ('test/fonts/Poppins-SemiBold.ttf', FontWeight.w600),
    ]) {
      final bytes = await File(entry.$1).readAsBytes();
      final loader = FontLoader('Poppins')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
  });

  testWidgets('step 1 renders welcome content', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_wrap(prefs));
    await tester.pumpAndSettle();

    expect(find.text('Welcome to Metly'), findsOneWidget);
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.byKey(const Key('onboard_begin')), findsOneWidget);
    await expectLater(find.byType(OnboardingScreen),
        matchesGoldenFile('goldens/onboarding_step1.png'));
  });

  testWidgets('full flow: begin -> skip account -> finish writes flag and exits',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var exited = false;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFFFD700),
        useMaterial3: true,
        fontFamily: 'Poppins',
      ),
      initialRoute: '/onboarding',
      routes: {
        '/onboarding': (_) => OnboardingScreen(prefs: prefs),
        '/': (_) {
          exited = true;
          return const Scaffold(body: Text('HOME'));
        },
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboard_begin')));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text('Save your watchlist'), findsOneWidget);
    await expectLater(find.byType(OnboardingScreen),
        matchesGoldenFile('goldens/onboarding_step2.png'));

    await tester.tap(find.byKey(const Key('onboard_skip_account')));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 3'), findsOneWidget);
    expect(find.text("You're all set"), findsOneWidget);
    await expectLater(find.byType(OnboardingScreen),
        matchesGoldenFile('goldens/onboarding_step3.png'));

    await tester.tap(find.byKey(const Key('onboard_finish')));
    await tester.pumpAndSettle();
    expect(prefs.getBool(OnboardingScreen.completeFlag), isTrue);
    expect(exited, isTrue);
  });

  testWidgets('back button returns to previous step', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_wrap(prefs));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboard_begin')));
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboard_back')));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.text('Welcome to Metly'), findsOneWidget);
  });

  testWidgets('sign-in button routes to /auth', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(_wrap(prefs, routes: {
      '/auth': (_) => const Scaffold(body: Text('AUTH')),
    }));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboard_begin')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboard_signin')));
    await tester.pumpAndSettle();
    expect(find.text('AUTH'), findsOneWidget);
    expect(prefs.getBool(OnboardingScreen.completeFlag), isNot(true));
  });

  testWidgets('phone-size 360x800 renders all steps without overflow',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(prefs));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'step 1 overflow');

    await tester.tap(find.byKey(const Key('onboard_begin')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'step 2 overflow');
    await expectLater(find.byType(OnboardingScreen),
        matchesGoldenFile('goldens/onboarding_step2_phone360.png'));

    await tester.tap(find.byKey(const Key('onboard_skip_account')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'step 3 overflow');
  });

  testWidgets('large text scale 2.0 renders all steps without overflow',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: _wrap(prefs),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'step 1 overflow @2x text');

    await tester.tap(find.byKey(const Key('onboard_begin')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'step 2 overflow @2x text');
    await expectLater(find.byType(OnboardingScreen),
        matchesGoldenFile('goldens/onboarding_step2_text2x.png'));

    await tester.tap(find.byKey(const Key('onboard_skip_account')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'step 3 overflow @2x text');
  });

  testWidgets('returning from /auth resumes step 2 and can finish',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var exited = false;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFFFD700),
        useMaterial3: true,
        fontFamily: 'Poppins',
      ),
      initialRoute: '/onboarding',
      routes: {
        '/onboarding': (_) => OnboardingScreen(prefs: prefs),
        '/auth': (_) => Scaffold(
            appBar: AppBar(title: const Text('AUTH APPBAR')),
            body: const Text('AUTH')),
        '/': (_) {
          exited = true;
          return const Scaffold(body: Text('HOME'));
        },
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboard_begin')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboard_signin')));
    await tester.pumpAndSettle();
    expect(find.text('AUTH'), findsOneWidget);

    // User backs out of auth: onboarding resumes on the account step.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Step 2 of 3'), findsOneWidget);

    await tester.tap(find.byKey(const Key('onboard_skip_account')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('onboard_finish')));
    await tester.pumpAndSettle();
    expect(prefs.getBool(OnboardingScreen.completeFlag), isTrue);
    expect(exited, isTrue);
  });

  testWidgets('signed-in account step shows sync confirmation and Continue',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    var exited = false;
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFFFFD700),
        useMaterial3: true,
        fontFamily: 'Poppins',
      ),
      initialRoute: '/onboarding',
      routes: {
        '/onboarding': (_) => OnboardingScreen(
            prefs: prefs, auth: const _SignedInStubAuth()),
        '/': (_) {
          exited = true;
          return const Scaffold(body: Text('HOME'));
        },
      },
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboard_begin')));
    await tester.pumpAndSettle();

    // Signed-in variant: no sign-in prompt, no misleading "without account".
    expect(find.text("You're signed in"), findsOneWidget);
    expect(find.byKey(const Key('onboard_signin')), findsNothing);
    expect(find.byKey(const Key('onboard_skip_account')), findsNothing);
    await expectLater(find.byType(OnboardingScreen),
        matchesGoldenFile('goldens/onboarding_step2_signedin.png'));

    await tester.tap(find.byKey(const Key('onboard_continue')));
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 3'), findsOneWidget);
    await tester.tap(find.byKey(const Key('onboard_finish')));
    await tester.pumpAndSettle();
    expect(prefs.getBool(OnboardingScreen.completeFlag), isTrue);
    expect(exited, isTrue);
  });

  testWidgets('large text scale 2.0: scroll reaches and taps every action',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: _wrap(prefs),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('onboard_begin')));
    await tester.pumpAndSettle();

    // The secondary action starts below the viewport at 2x: drag the
    // scrollable until it is visible, prove it is hit-testable, tap through.
    final skip = find.byKey(const Key('onboard_skip_account'));
    await tester.scrollUntilVisible(skip, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.getRect(skip).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(OnboardingScreen)).bottom));
    expect(tester.hitTestOnBinding(tester.getCenter(skip)).path, isNotEmpty);
    await tester.tap(skip);
    await tester.pumpAndSettle();
    expect(find.text('Step 3 of 3'), findsOneWidget);

    final finish = find.byKey(const Key('onboard_finish'));
    await tester.scrollUntilVisible(finish, 200,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    expect(tester.hitTestOnBinding(tester.getCenter(finish)).path, isNotEmpty);
  });

  testWidgets('phone 360x800 + text scale 2.0 combo completes with flag',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var exited = false;
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
      child: MaterialApp(
        theme: ThemeData(
          brightness: Brightness.dark,
          colorSchemeSeed: const Color(0xFFFFD700),
          useMaterial3: true,
          fontFamily: 'Poppins',
        ),
        initialRoute: '/onboarding',
        routes: {
          '/onboarding': (_) => OnboardingScreen(prefs: prefs),
          '/': (_) {
            exited = true;
            return const Scaffold(body: Text('HOME'));
          },
        },
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'combo step 1 overflow');

    await tester.scrollUntilVisible(find.byKey(const Key('onboard_begin')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('onboard_begin')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'combo step 2 overflow');

    await tester.scrollUntilVisible(
        find.byKey(const Key('onboard_skip_account')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('onboard_skip_account')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'combo step 3 overflow');

    await tester.scrollUntilVisible(find.byKey(const Key('onboard_finish')), 200,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(find.byKey(const Key('onboard_finish')));
    await tester.pumpAndSettle();
    expect(prefs.getBool(OnboardingScreen.completeFlag), isTrue);
    expect(exited, isTrue);
  });
}
