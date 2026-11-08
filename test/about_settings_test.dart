import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:metly/screens/about_screen.dart';
import 'package:metly/screens/settings_screen.dart';

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });
  testWidgets('Settings opens the shared About route', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefs: prefs),
      routes: {'/about': (_) => const Scaffold(body: Text('ABOUT-ROUTE'))},
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('About Metly'));
    await tester.pumpAndSettle();
    expect(find.text('ABOUT-ROUTE'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('About keeps Metly identity and one sponsor choice',
      (tester) async {
    final opened = <Uri>[];
    await tester.pumpWidget(MaterialApp(home: AboutScreen(
      openLinkOverride: (uri) async {
        opened.add(uri);
        return true;
      },
    )));
    await tester.pumpAndSettle();
    expect(find.text('Metly'), findsOneWidget);
    expect(find.text('Rahul Muraleedharan · FrpBoy'), findsOneWidget);
    await tester.tap(find.text('Developer'));
    await tester.pumpAndSettle();
    expect(opened.single.toString(), 'https://www.frpboy.in/');
    await tester.scrollUntilVisible(find.text('Sponsor'), 300);
    expect(find.text('Sponsor'), findsOneWidget);
    await tester.tap(find.text('Sponsor'));
    await tester.pumpAndSettle();
    expect(find.text('Buy Me a Coffee'), findsOneWidget);
    expect(find.text('Patreon'), findsOneWidget);
    await tester.tap(find.text('Patreon'));
    await tester.pumpAndSettle();
    expect(opened.last.toString(), 'https://www.patreon.com/c/FrpBoy');
    await tester.pumpWidget(const SizedBox());
  });
}
