import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:metly/screens/about_screen.dart';
import 'package:metly/screens/settings_screen.dart';

void main() {
  setUp(() { GoogleFonts.config.allowRuntimeFetching = false; });
  testWidgets('settings golden', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(prefs: prefs),
      routes: {'/about': (_) => const Scaffold()},
    ));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(SettingsScreen), matchesGoldenFile('tmp_settings.png'));
  });
  testWidgets('about golden', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
    await expectLater(
        find.byType(AboutScreen), matchesGoldenFile('tmp_about.png'));
  });
}
