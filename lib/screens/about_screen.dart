import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_config.dart';
import '../widgets/common_widgets.dart';

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MetlyDrawer(),
      appBar: const MetlyAppBar(
          titleTop: 'About Metly', titleBottom: Cfg.brandLine),
      backgroundColor: const Color(0xFF0E0E0E),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Row(children: [
          Image.asset('assets/logo/icon.png', width: 72),
          const SizedBox(width: 16),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Metly',
                style: GoogleFonts.poppins(
                    color: Cfg.gold,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
            Text(Cfg.brandLine,
                style: GoogleFonts.poppins(color: Colors.white70)),
            Text('Version ${Cfg.version}',
                style: GoogleFonts.poppins(color: Colors.white54)),
          ]),
        ]),
        const SizedBox(height: 24),
        Text(
            'Metly is an open-source app that provides clear, actionable signals for gold, silver, and other precious metals. Built for India.',
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70)),
        const SizedBox(height: 24),
        const Divider(color: Colors.white12),
        const SizedBox(height: 12),
        Text('Credits',
            style: GoogleFonts.poppins(
                fontSize: 16, color: Cfg.gold, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text('Design & Development: K4NN4N\nBrand: Metly',
            style: GoogleFonts.poppins(fontSize: 13, color: Colors.white70)),
        const SizedBox(height: 24),
        Center(
            child: Text('© 2025 K4NN4N',
                style:
                    GoogleFonts.poppins(color: Colors.white54, fontSize: 12))),
      ]),
    );
  }
}
