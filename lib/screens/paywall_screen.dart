import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../widgets/common_widgets.dart';

class PaywallScreen extends StatelessWidget {
  final SharedPreferences prefs;
  const PaywallScreen({super.key, required this.prefs});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MetlyAppBar(
          titleTop: 'Unlock AI',
          titleBottom: 'Choose your plan',
          showMenu: false),
      backgroundColor: const Color(0xFF0E0E0E),
      body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            _PlanCard(
                title: 'Metly AI',
                price: Cfg.priceMonthly,
                desc: 'Use Metly cloud (creator’s API via secure proxy).',
                onTap: () async {
                  await prefs.setBool(Cfg.entSubActive, true);
                  if (context.mounted) Navigator.pop(context);
                }),
            const SizedBox(height: 12),
            _PlanCard(
                title: 'Use My API',
                price: Cfg.priceLifetime,
                desc: 'Lifetime unlock to use your own OpenRouter key.',
                onTap: () async {
                  await prefs.setBool(Cfg.entLifetime, true);
                  if (context.mounted) Navigator.pop(context);
                }),
          ])),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String title, price, desc;
  final VoidCallback onTap;
  const _PlanCard(
      {required this.title,
      required this.price,
      required this.desc,
      required this.onTap});
  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: const Color(0xFF161616),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24)),
        child: Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('$title • $price',
                    style: GoogleFonts.poppins(
                        color: Cfg.gold,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 6),
                Text(desc, style: GoogleFonts.poppins(color: Colors.white70)),
              ])),
          FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                  backgroundColor: Cfg.gold, foregroundColor: Colors.black),
              child: const Text('Unlock')),
        ]));
  }
}
