import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../config/app_config.dart';

/* ════════════════════════════════════════════════════════════════════════════
   NAV + HOME
════════════════════════════════════════════════════════════════════════════ */
class MetlyAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String titleTop;
  final String titleBottom;
  final bool showMenu;
  const MetlyAppBar(
      {super.key,
      required this.titleTop,
      required this.titleBottom,
      this.showMenu = true});
  @override
  Size get preferredSize => const Size.fromHeight(64);
  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.black,
      centerTitle: true,
      leading: showMenu
          ? Builder(
              builder: (ctx) => IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                    tooltip: 'Menu',
                  ))
          : null,
      title: Column(children: [
        Text(titleTop,
            style: GoogleFonts.poppins(
                fontWeight: FontWeight.w700, fontSize: 20, color: Cfg.gold)),
        Text(titleBottom,
            style: GoogleFonts.poppins(
                fontSize: 11, color: Colors.white70, letterSpacing: 0.3)),
      ]),
      actions: [
        IconButton(
            tooltip: 'Settings',
            onPressed: () => Navigator.pushNamed(context, '/settings'),
            icon: const Icon(Icons.settings_outlined)),
      ],
    );
  }
}

class MetlyDrawer extends StatelessWidget {
  const MetlyDrawer({super.key});
  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: const Color(0xFF121212),
      child: SafeArea(
          child: Column(children: [
        const SizedBox(height: 8),
        ListTile(
            leading: const Icon(Icons.home_outlined, color: Colors.white70),
            title: const Text('Home'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
            }),
        ListTile(
            leading:
                const Icon(Icons.trending_up_outlined, color: Colors.white70),
            title: const Text('Dashboard'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/dashboard');
            }),
        ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.white70),
            title: const Text('About'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/about');
            }),
        ListTile(
            leading: const Icon(Icons.feedback_outlined, color: Colors.white70),
            title: const Text('Feedback'),
            onTap: () {
              Navigator.pop(context);
              Navigator.pushNamed(context, '/feedback');
            }),
        const Spacer(),
        Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('© 2025 K4NN4N',
                style:
                    GoogleFonts.poppins(color: Colors.white54, fontSize: 12))),
      ])),
    );
  }
}

class PlatformLinksRow extends StatelessWidget {
  const PlatformLinksRow({super.key});
  @override
  Widget build(BuildContext context) {
    Widget btn(String label) => OutlinedButton(
        style: OutlinedButton.styleFrom(
            side: BorderSide(color: Cfg.gold.withValues(alpha: 0.5)),
            foregroundColor: Colors.white),
        onPressed: () {},
        child: Text(label));
    return Wrap(
        spacing: 10,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [btn('MMTC-PAMP'), btn('DigiGold'), btn('Tanishq Digital')]);
  }
}
