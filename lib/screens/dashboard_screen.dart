```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../services/price_service.dart';
import '../services/ai_service.dart';
import '../models/price_snapshot.dart';
import '../models/watchlist_item.dart';
import '../models/portfolio_item.dart';
import '../services/firestore_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/signal_card.dart';

class DashboardScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const DashboardScreen({super.key, required this.prefs});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final PriceProvider provider = RealPriceProvider(widget.prefs);
  final FirestoreService _firestore = FirestoreService();
  PriceSnapshot? gold;
  PriceSnapshot? silver;
  bool loading = false;
  bool aiBusy = false;
  String? aiText;
  bool sipEnabled = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => loading = true);
    final g = await provider.latest(Metal.gold);
    final s = await provider.latest(Metal.silver);
    setState(() {
      gold = g;
      silver = s;
      loading = false;
      aiText = null;
    });
  }

  Future<void> _askAI() async {
    if (gold == null || silver == null) return;
    final client = OpenRouterClient(widget.prefs);
    final gSig = evaluateSignal(gold!, now: DateTime.now());
    final sSig = evaluateSignal(silver!, now: DateTime.now());
    setState(() => aiBusy = true);
    try {
      final text = await client.explainSignals(
          gold: gold!, goldSig: gSig, silver: silver!, silverSig: sSig);
      setState(() => aiText = text);
    } catch (e) {
      setState(() => aiText = 'AI error: $e');
    } finally {
      setState(() => aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Scaffold(
      drawer: const MetlyDrawer(),
      appBar: const MetlyAppBar(
          titleTop: 'Dashboard', titleBottom: 'Signals • Gold • Silver'),
      backgroundColor: const Color(0xFF0E0E0E),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Row(children: [
            FilledButton.icon(
                style: FilledButton.styleFrom(
                    backgroundColor: Cfg.gold, foregroundColor: Colors.black),
                onPressed: loading ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh Prices')),
            const SizedBox(width: 12),
            FilterChip(
                selected: sipEnabled,
                onSelected: (v) => setState(() => sipEnabled = v),
                label: const Text('SIP Tip'),
                selectedColor: Cfg.gold.withValues(alpha: 0.25),
                side: BorderSide(color: Cfg.gold.withValues(alpha: 0.35))),
            const Spacer(),
            FilledButton.icon(
                onPressed: aiBusy ? null : _askAI,
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.black, foregroundColor: Colors.white),
                icon: Icon(aiBusy ? Icons.hourglass_top : Icons.auto_awesome),
                label: Text(aiBusy ? 'Thinking…' : 'Ask AI')),
          ]),
          const SizedBox(height: 12),
          if (gold != null)
            SignalCard(snapshot: gold!, result: evaluateSignal(gold!, now: now)),
          if (silver != null)
            SignalCard(snapshot: silver!, result: evaluateSignal(silver!, now: now)),
          const SizedBox(height: 12),
          if (sipEnabled)
            const Text('SIP tip: Invest regularly to average risk and returns.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          // Watchlist Section
          const Text('Watchlist', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Cfg.gold)),
          const SizedBox(height: 8),
          StreamBuilder<List<WatchlistItem>>(
            stream: _firestore.watchlistStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();
              final items = snapshot.data!;
              if (items.isEmpty) return const Text('No watchlist items', style: TextStyle(color: Colors.white70));
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                itemBuilder: (c, i) {
                  final it = items[i];
                  return ListTile(
                    title: Text('${it.metal.toUpperCase()} @ ₹${it.targetPrice.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white)),
                    subtitle: Text('Added: ${it.addedAt.toLocal().toString().split('.').first}', style: const TextStyle(color: Colors.white54)),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 24),
          // Portfolio Section
          const Text('Portfolio', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Cfg.gold)),
          const SizedBox(height: 8),
          StreamBuilder<List<PortfolioItem>>(
            stream: _firestore.portfolioStream(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();
              final items = snapshot.data!;
              if (items.isEmpty) return const Text('No portfolio items', style: TextStyle(color: Colors.white70));
              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: items.length,
                itemBuilder: (c, i) {
                  final it = items[i];
                  return ListTile(
                    title: Text('${it.metal.toUpperCase()} holdings: ${it.amount.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white)),
                    subtitle: Text('Avg price: ₹${it.avgPrice.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white54)),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),
          const PlatformLinksRow(),
          const SizedBox(height: 16),
          if (aiText != null) _AiInsight(text: aiText!),
        ]),
      ),
    );
  }
}

class _AiInsight extends StatelessWidget {
  final String text;
  const _AiInsight({required this.text});
  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white24)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('AI Insight',
              style: GoogleFonts.poppins(
                  color: Cfg.gold, fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SelectableText(text,
              style: GoogleFonts.poppins(
                  color: Colors.white.withValues(alpha: 0.92))),
        ]));
  }
}
```
