import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../services/price_service.dart';
import '../services/ai_service.dart';
import '../models/price_model.dart';
import '../models/watchlist_item.dart';
import '../models/portfolio_item.dart';
import '../services/auth_service.dart';
import '../services/firestore_service.dart';
import '../widgets/common_widgets.dart';
import '../widgets/signal_card.dart';

class DashboardScreen extends StatefulWidget {
  final SharedPreferences prefs;

  /// Test/seam overrides; production uses the real implementations.
  final PriceProvider? providerOverride;
  final FirestoreService? firestoreOverride;
  final AiClient? aiOverride;
  final AuthService? authOverride;

  /// Clock seam for aging tests.
  final DateTime Function()? clockOverride;
  const DashboardScreen(
      {super.key,
      required this.prefs,
      this.providerOverride,
      this.firestoreOverride,
      this.aiOverride,
      this.authOverride,
      this.clockOverride});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  Timer? _stalenessTimer;
  Timer? _staleDeadlineTimer;
  late final DateTime Function() _clock = widget.clockOverride ?? DateTime.now;
  late final PriceProvider provider =
      widget.providerOverride ?? RealPriceProvider(widget.prefs);
  late final AuthService _auth = widget.authOverride ?? metlyDefaultAuth();
  int _refreshGen = 0;
  int _aiGen = 0;
  PriceSnapshot? gold;
  PriceSnapshot? silver;
  bool loading = false;
  String? loadError;
  bool aiBusy = false;
  String? aiText;
  bool sipEnabled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Time-passage revalidation: a displayed snapshot must not sit on screen
    // as live past its freshness window.
    _stalenessTimer = Timer.periodic(
        const Duration(minutes: 1), (_) => _revalidateIfStale());
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stalenessTimer?.cancel();
    _staleDeadlineTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _revalidateIfStale();
  }

  void _revalidateIfStale() {
    if (loading) return;
    final now = _clock();
    final stale = (gold?.isStale(now) ?? false) || (silver?.isStale(now) ?? false);
    if (stale) _refresh();
  }

  /// Relabel cards as stale the moment the first snapshot crosses its
  /// freshness deadline, and refresh. A 60s backstop timer covers clock
  /// jumps; this deadline timer is exact, so a card never sits looking live
  /// past its freshness window.
  void _scheduleStaleDeadline() {
    _staleDeadlineTimer?.cancel();
    final now = _clock();
    final deadlines = [
      if (gold != null) gold!.freshUntil,
      if (silver != null) silver!.freshUntil,
    ];
    if (deadlines.isEmpty) return;
    final first = deadlines.reduce((a, b) => a.isBefore(b) ? a : b);
    final wait = first.difference(now);
    _staleDeadlineTimer = Timer(wait <= Duration.zero ? Duration.zero : wait,
        () {
      if (!mounted) return;
      setState(() {}); // stale warnings appear immediately
      _revalidateIfStale();
    });
  }

  Future<void> _refresh() async {
    if (loading) return; // one refresh at a time
    final gen = ++_refreshGen;
    _aiGen++; // any in-flight AI answer now belongs to old data
    setState(() {
      loading = true;
      loadError = null;
      aiText = null;
      aiBusy = false; // in-flight AI is invalidated below; button recovers
    });
    try {
      final g = await provider.latest(Metal.gold);
      final s = await provider.latest(Metal.silver);
      if (!mounted || gen != _refreshGen) return;
      setState(() {
        gold = g;
        silver = s;
      });
      _scheduleStaleDeadline();
    } catch (e) {
      if (!mounted || gen != _refreshGen) return;
      // Never leave stale data on screen looking live after a failed load.
      setState(() {
        loadError =
            'Live prices unavailable right now. Pull to refresh to retry.';
        gold = null;
        silver = null;
        aiText = null;
      });
    } finally {
      if (mounted && gen == _refreshGen) setState(() => loading = false);
    }
  }

  Future<void> _askAI() async {
    if (gold == null || silver == null) return;
    final now = _clock();
    if (gold!.isStale(now) || silver!.isStale(now)) {
      setState(() => aiText =
          'Price data is stale. Refresh before asking for an explanation.');
      return;
    }
    if (gold!.highIsObserved || silver!.highIsObserved) {
      setState(() => aiText =
          'Signals are paused while only rolling observed highs are available. '
          'They resume once a price source with a verified historical-high contract is configured.');
      return;
    }
    if (loading) return; // never explain while fresh data is loading
    final g = gold!;
    final s = silver!;
    final client = widget.aiOverride ?? OpenRouterClient(widget.prefs);
    final gSig = evaluateSignal(g, now: _clock());
    final sSig = evaluateSignal(s, now: _clock());
    final gen = ++_aiGen;
    setState(() => aiBusy = true);
    try {
      final text = await client.explainSignals(
          gold: g, goldSig: gSig, silver: s, silverSig: sSig);
      // A late answer must not land on top of newer or failed data.
      if (!mounted || gen != _aiGen || !identical(gold, g) || !identical(silver, s)) {
        return;
      }
      setState(() => aiText = text);
    } catch (e) {
      if (!mounted || gen != _aiGen) return;
      setState(() => aiText = 'AI error: $e');
    } finally {
      if (mounted && gen == _aiGen) setState(() => aiBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = _clock();
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
                onPressed: (aiBusy || loading) ? null : _askAI,
                style: FilledButton.styleFrom(
                    backgroundColor: Colors.black, foregroundColor: Colors.white),
                icon: Icon(aiBusy ? Icons.hourglass_top : Icons.auto_awesome),
                label: Text(aiBusy ? 'Thinking…' : 'Ask AI')),
          ]),
          const SizedBox(height: 12),
          if (loadError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(loadError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 13)),
            ),
          if (gold != null)
            gold!.highIsObserved
                ? LiveSpotCard(snapshot: gold!, now: _clock)
                : SignalCard(
                    snapshot: gold!,
                    result: evaluateSignal(gold!, now: now),
                    now: _clock),
          if (silver != null)
            silver!.highIsObserved
                ? LiveSpotCard(snapshot: silver!, now: _clock)
                : SignalCard(
                    snapshot: silver!,
                    result: evaluateSignal(silver!, now: now),
                    now: _clock),
          const SizedBox(height: 12),
          if (sipEnabled)
            const Text('SIP tip: Invest regularly to average risk and returns.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          // Watchlist & Portfolio, scoped to the signed-in account.
          StreamBuilder<MetlyUser?>(
            stream: _auth.authChanges(),
            builder: (context, authSnap) {
              if (authSnap.connectionState == ConnectionState.waiting &&
                  !authSnap.hasData) {
                return const Center(
                    child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2.5)));
              }
              final user = authSnap.data;
              if (user == null) return const _SignedOutSavingsCard();
              final firestore =
                  widget.firestoreOverride ?? FirestoreService(uid: user.uid);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _WatchlistSection(firestore: firestore),
                  const SizedBox(height: 24),
                  _PortfolioSection(firestore: firestore),
                ],
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

/* ══════════════════════════════════════════════════════════════════════════
   ACCOUNT-GATED WATCHLIST & PORTFOLIO
══════════════════════════════════════════════════════════════════════════ */

class _SignedOutSavingsCard extends StatelessWidget {
  const _SignedOutSavingsCard();
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white24)),
      child: Column(children: [
        const Icon(Icons.bookmark_add_outlined, color: Cfg.gold, size: 30),
        const SizedBox(height: 8),
        Text('Save your watchlist & portfolio',
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text('Create a free account and your metals, targets and holdings '
            'stay saved to you on every device.',
            textAlign: TextAlign.center,
            style:
                GoogleFonts.poppins(color: Colors.white70, fontSize: 12.5)),
        const SizedBox(height: 12),
        FilledButton(
          style: FilledButton.styleFrom(
              backgroundColor: Cfg.gold, foregroundColor: Colors.black),
          onPressed: () => Navigator.pushNamed(context, '/auth'),
          child: const Text('Sign in / Create account',
              style: TextStyle(fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

class _WatchlistSection extends StatelessWidget {
  final FirestoreService firestore;
  const _WatchlistSection({required this.firestore});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Watchlist',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: Cfg.gold)),
        const Spacer(),
        IconButton(
          tooltip: 'Add watchlist target',
          icon: const Icon(Icons.add_circle_outline, color: Cfg.gold),
          onPressed: () => _showAddWatchlist(context, firestore),
        ),
      ]),
      const SizedBox(height: 4),
      StreamBuilder<List<WatchlistItem>>(
        stream: firestore.watchlistStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Watchlist unavailable',
                style: TextStyle(color: Colors.redAccent, fontSize: 13));
          }
          if (!snapshot.hasData) {
            return const Center(
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5)));
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Text('No watchlist items yet. Tap + to add one.',
                style: TextStyle(color: Colors.white70));
          }
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (c, i) {
              final it = items[i];
              return ListTile(
                title: Text(
                    '${it.metal.toUpperCase()} @ ₹${it.targetPrice.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                    'Added: ${it.addedAt.toLocal().toString().split('.').first}',
                    style: const TextStyle(color: Colors.white54)),
                trailing: IconButton(
                  tooltip: 'Remove from watchlist',
                  icon: const Icon(Icons.delete_outline, color: Colors.white54),
                  onPressed: () async {
                    try {
                      await firestore.removeWatchlistItem(it.id);
                    } catch (_) {
                      if (context.mounted) _showSaveError(context);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    ]);
  }
}

class _PortfolioSection extends StatelessWidget {
  final FirestoreService firestore;
  const _PortfolioSection({required this.firestore});
  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Text('Portfolio',
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: Cfg.gold)),
        const Spacer(),
        IconButton(
          tooltip: 'Add portfolio holding',
          icon: const Icon(Icons.add_circle_outline, color: Cfg.gold),
          onPressed: () => _showAddPortfolio(context, firestore),
        ),
      ]),
      const SizedBox(height: 4),
      StreamBuilder<List<PortfolioItem>>(
        stream: firestore.portfolioStream(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text('Portfolio unavailable',
                style: TextStyle(color: Colors.redAccent, fontSize: 13));
          }
          if (!snapshot.hasData) {
            return const Center(
                child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5)));
          }
          final items = snapshot.data!;
          if (items.isEmpty) {
            return const Text('No holdings yet. Tap + to add one.',
                style: TextStyle(color: Colors.white70));
          }
          return ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            itemBuilder: (c, i) {
              final it = items[i];
              return ListTile(
                title: Text(
                    '${it.metal.toUpperCase()} holdings: ${it.amount.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white)),
                subtitle: Text(
                    'Avg price: ₹${it.avgPrice.toStringAsFixed(2)}',
                    style: const TextStyle(color: Colors.white54)),
                trailing: IconButton(
                  tooltip: 'Remove holding',
                  icon: const Icon(Icons.delete_outline, color: Colors.white54),
                  onPressed: () async {
                    try {
                      await firestore.removePortfolioItem(it.id);
                    } catch (_) {
                      if (context.mounted) _showSaveError(context);
                    }
                  },
                ),
              );
            },
          );
        },
      ),
    ]);
  }
}

void _showSaveError(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Could not save right now. Please try again.')));
}

String _newId() => DateTime.now().microsecondsSinceEpoch.toString();

Widget _metalDropdown(String value, ValueChanged<String> onChanged) {
  return DropdownButtonFormField<String>(
    initialValue: value,
    dropdownColor: const Color(0xFF1C1C1C),
    style: const TextStyle(color: Colors.white),
    decoration: InputDecoration(
      labelText: 'Metal',
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24)),
    ),
    items: const [
      DropdownMenuItem(value: 'gold', child: Text('Gold')),
      DropdownMenuItem(value: 'silver', child: Text('Silver')),
    ],
    onChanged: (v) => onChanged(v ?? 'gold'),
  );
}

InputDecoration _numDeco(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Colors.white70),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.white24)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Cfg.gold)),
    );

Future<void> _showAddWatchlist(
    BuildContext context, FirestoreService firestore) async {
  final priceCtrl = TextEditingController();
  String metal = 'gold';
  String? error;
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setDlg) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text('Add watchlist target',
            style: TextStyle(color: Cfg.gold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _metalDropdown(metal, (v) => setDlg(() => metal = v)),
          const SizedBox(height: 12),
          TextField(
            controller: priceCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: _numDeco('Target price (₹)'),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
          ],
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white70))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Cfg.gold, foregroundColor: Colors.black),
            onPressed: () {
              final price = double.tryParse(priceCtrl.text.trim());
              // NaN slips past <= 0 checks; require a real finite number.
              if (price == null || !price.isFinite || price <= 0) {
                setDlg(() => error = 'Enter a target price above zero.');
                return;
              }
              Navigator.pop(dialogCtx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;
  final price = double.parse(priceCtrl.text.trim());
  try {
    await firestore.addWatchlistItem(WatchlistItem(
        id: _newId(), metal: metal, targetPrice: price, addedAt: DateTime.now()));
  } catch (_) {
    if (context.mounted) _showSaveError(context);
  }
}

Future<void> _showAddPortfolio(
    BuildContext context, FirestoreService firestore) async {
  final amountCtrl = TextEditingController();
  final avgCtrl = TextEditingController();
  String metal = 'gold';
  String? error;
  final saved = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (dialogCtx, setDlg) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title:
            const Text('Add holding', style: TextStyle(color: Cfg.gold)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          _metalDropdown(metal, (v) => setDlg(() => metal = v)),
          const SizedBox(height: 12),
          TextField(
            controller: amountCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: _numDeco('Quantity'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: avgCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: _numDeco('Average buy price (₹ per unit)'),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(error!,
                style:
                    const TextStyle(color: Colors.redAccent, fontSize: 12.5)),
          ],
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child:
                  const Text('Cancel', style: TextStyle(color: Colors.white70))),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Cfg.gold, foregroundColor: Colors.black),
            onPressed: () {
              final amount = double.tryParse(amountCtrl.text.trim());
              final avg = double.tryParse(avgCtrl.text.trim());
              // NaN slips past <= 0 checks; require real finite numbers.
              if (amount == null || !amount.isFinite || amount <= 0) {
                setDlg(() => error = 'Enter a quantity above zero.');
                return;
              }
              if (avg == null || !avg.isFinite || avg <= 0) {
                setDlg(() => error = 'Enter an average price above zero.');
                return;
              }
              Navigator.pop(dialogCtx, true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (saved != true) return;
  final amount = double.parse(amountCtrl.text.trim());
  final avg = double.parse(avgCtrl.text.trim());
  try {
    await firestore.addPortfolioItem(PortfolioItem(
        id: _newId(),
        metal: metal,
        amount: amount,
        avgPrice: avg,
        addedAt: DateTime.now()));
  } catch (_) {
    if (context.mounted) _showSaveError(context);
  }
}
