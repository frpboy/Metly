import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../widgets/common_widgets.dart';

class HomeScreen extends StatelessWidget {
  final SharedPreferences prefs;
  const HomeScreen({super.key, required this.prefs});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MetlyDrawer(),
      appBar: const MetlyAppBar(titleTop: 'Metly', titleBottom: Cfg.brandLine),
      backgroundColor: const Color(0xFF0E0E0E),
      body: Center(
          child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/logo/icon.png', width: 120),
                    const SizedBox(height: 24),
                    Text('Welcome to Metly',
                        style: GoogleFonts.poppins(
                            color: Cfg.gold,
                            fontSize: 26,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(
                        'AI-driven insights for Gold, Silver & other precious metals.\nMade with pride, built for smart investors.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 36),
                    ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                            backgroundColor: Cfg.gold,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 32, vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(30))),
                        icon: const Icon(Icons.trending_up),
                        label: Text('Enter Dashboard',
                            style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w600, fontSize: 16)),
                        onPressed: () =>
                            Navigator.pushNamed(context, '/dashboard')),
                  ]))),
    );
  }
}
