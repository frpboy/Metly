import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import 'config/app_config.dart';
import 'screens/home_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/about_screen.dart';
import 'screens/feedback_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/paywall_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final prefs = await SharedPreferences.getInstance();
  runApp(MetlyApp(prefs: prefs));
}

class MetlyApp extends StatelessWidget {
  final SharedPreferences prefs;
  const MetlyApp({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    final theme = ThemeData(
      brightness: Brightness.dark,
      colorSchemeSeed: Cfg.gold,
      useMaterial3: true,
      textTheme: GoogleFonts.poppinsTextTheme(ThemeData.dark().textTheme),
    );
    return MaterialApp(
      title: Cfg.appTitle,
      debugShowCheckedModeBanner: false,
      theme: theme,
      routes: {
        '/': (_) => HomeScreen(prefs: prefs),
        '/dashboard': (_) => DashboardScreen(prefs: prefs),
        '/about': (_) => const AboutScreen(),
        '/feedback': (_) => const FeedbackScreen(),
        '/settings': (_) => SettingsScreen(prefs: prefs),
        '/paywall': (_) => PaywallScreen(prefs: prefs),
      },
      initialRoute: '/',
    );
  }
}
