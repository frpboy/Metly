import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../widgets/common_widgets.dart';

class AboutScreen extends StatelessWidget {
  final Future<bool> Function(Uri)? openLinkOverride;
  const AboutScreen({super.key, this.openLinkOverride});

  Future<void> _open(BuildContext context, String url) async {
    final uri = Uri.parse(url);
    bool opened;
    try {
      opened = await (openLinkOverride?.call(uri) ??
          launchUrl(uri, mode: LaunchMode.externalApplication));
    } catch (_) {
      opened = false;
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open this link.')));
    }
  }

  Widget _link(BuildContext context, String title, String detail, String url,
          IconData icon) =>
      ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: Cfg.gold),
        title: Text(title),
        subtitle: Text(detail, style: const TextStyle(color: Colors.white60)),
        trailing: const Icon(Icons.open_in_new, size: 18),
        onTap: () => _open(context, url),
      );

  void _sponsors(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF181818),
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Support Metly',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            const Text('Optional tips support Rahul\'s work. No donation is '
                'needed to use the account, watchlist or portfolio features.'),
            const SizedBox(height: 12),
            _link(sheetContext, 'Buy Me a Coffee', 'buymeacoffee.com/frpboy',
                'https://buymeacoffee.com/frpboy', Icons.coffee_outlined),
            _link(sheetContext, 'Patreon', 'patreon.com/c/FrpBoy',
                'https://www.patreon.com/c/FrpBoy', Icons.favorite_outline),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MetlyDrawer(),
      appBar: const MetlyAppBar(
          titleTop: 'About Metly', titleBottom: Cfg.brandLine),
      backgroundColor: const Color(0xFF0E0E0E),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Row(children: [
          Image.asset('assets/logo/icon.png', width: 64),
          const SizedBox(width: 16),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Metly',
                    style: GoogleFonts.poppins(
                        color: Cfg.gold,
                        fontSize: 22,
                        fontWeight: FontWeight.w700)),
                const Text(Cfg.brandLine,
                    style: TextStyle(color: Colors.white70)),
                const Text('Version ${Cfg.version}',
                    style: TextStyle(color: Colors.white54)),
              ])),
        ]),
        const SizedBox(height: 24),
        const Text(
            'Indian gold and silver rates, with a personal watchlist '
            'and portfolio. Prices are informational, not investment advice.',
            style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 16),
        const Divider(color: Colors.white12),
        _link(context, 'Developer', 'Rahul Muraleedharan · FrpBoy',
            'https://www.frpboy.in/', Icons.person_outline),
        _link(context, 'GitHub', 'github.com/frpboy',
            'https://github.com/frpboy', Icons.code),
        _link(context, 'LinkedIn', 'Rahul Muraleedharan',
            'https://www.linkedin.com/in/rahul-muraleedharan-it', Icons.link),
        _link(context, 'Support requests', 'FRPboy Projects on Telegram',
            'https://t.me/FRPboy_Projects', Icons.support_agent),
        _link(context, 'Source & documentation', 'frpboy/Metly',
            'https://github.com/frpboy/Metly', Icons.description_outlined),
        _link(
            context,
            'Releases',
            'Metly releases on GitHub',
            'https://github.com/frpboy/Metly/releases',
            Icons.new_releases_outlined),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading:
              const Icon(Icons.volunteer_activism_outlined, color: Cfg.gold),
          title: const Text('Sponsor'),
          subtitle: const Text('Optional support: Buy Me a Coffee or Patreon'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _sponsors(context),
        ),
        const Divider(color: Colors.white12),
        const SizedBox(height: 12),
        const Text('License & credits',
            style: TextStyle(
                fontSize: 16, color: Cfg.gold, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        const Text(
            'Apache License 2.0\n'
            'Design & development: K4NN4N (Rahul Muraleedharan)\n'
            'Brand: Metly\n'
            'Built with Flutter and Firebase. Price data: OroPocket.',
            style: TextStyle(fontSize: 13, color: Colors.white70)),
        _link(
            context,
            'License',
            'Read the Metly repository license',
            'https://github.com/frpboy/Metly/blob/main/LICENSE',
            Icons.gavel_outlined),
        const SizedBox(height: 16),
        const Center(
            child: Text('© 2025 K4NN4N',
                style: TextStyle(color: Colors.white54, fontSize: 12))),
      ]),
    );
  }
}
