import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:metly/screens/about_screen.dart';
import 'package:metly/screens/settings_screen.dart';
import 'package:metly/config/app_config.dart';

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
    expect(find.text('Entitlements (dev stubs)'), findsNothing);
    expect(find.textContaining('₹99'), findsNothing);
    expect(find.textContaining('₹999'), findsNothing);
    expect(find.textContaining('subscription'), findsNothing);
    expect(find.textContaining('Lifetime unlock'), findsNothing);
    expect(find.text('Data Source'), findsOneWidget);
    expect(find.textContaining('billing'), findsNothing);
    expect(find.textContaining('development only'), findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<AiMode>));
    await tester.pumpAndSettle();
    expect(find.text('Metly AI'), findsOneWidget);
    expect(find.text('Use My API'), findsOneWidget);
    expect(find.textContaining('₹'), findsNothing);
  });
  testWidgets('about golden', (tester) async {
    tester.view.physicalSize = const Size(390, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();
    expect(find.textContaining('Proprietary'), findsNothing);
    expect(find.textContaining('Apache License 2.0.'), findsOneWidget);
    expect(find.text('© 2026 K4NN4N'), findsOneWidget);
  });
}
