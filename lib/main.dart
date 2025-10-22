import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

/* =============================================================================
   METLY — AI MODES + PAYWALL STUBS
   - AI modes:
       Off (free)
       Metly AI (₹99/month)  -> needs subscription entitlement
       Use My API (₹999 one-time) -> needs lifetime entitlement + user API key
   - Non-subscribed users can use the whole app minus AI. No lock on signals.
============================================================================= */

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(MetlyApp(prefs: prefs));
}

/* ──────────────────────────────────────────────────────────────────────────────
   CONFIG
────────────────────────────────────────────────────────────────────────────── */
class Cfg {
  static const Color gold = Color(0xFFFFD700);
  static const String brandLine = 'Made in India with ❤ Gold';
  static const String appTitle = 'Metly — $brandLine';
  static const String version = 'v1.0.0';

  // Festival dates for post-festive guard (extend later)
  static final DateTime dhanteras2025 = DateTime(2025, 10, 18);
  static final DateTime diwali2025 = DateTime(2025, 10, 20);

  // OpenRouter defaults
  static const String defaultModel = 'openai/gpt-4o-mini';

  // Pref keys
  static const String prefsKeyApi = 'openrouter_api_key';
  static const String prefsKeyModel = 'openrouter_model';

  // Entitlements (stubs now; real billing later)
  static const String entSubActive = 'ent_sub_active'; // Metly AI ₹99/mo
  static const String entLifetime = 'ent_lifetime_active'; // Use My API ₹999

  // AI Mode selection
  static const String prefsAiMode = 'ai_mode'; // 0=Off, 1=Metly AI, 2=My API

  // Pricing labels (UI only; billing later)
  static const String priceMonthly = '₹99/month';
  static const String priceLifetime = '₹999 (lifetime)';
}

/* ──────────────────────────────────────────────────────────────────────────────
   AI MODES
────────────────────────────────────────────────────────────────────────────── */
enum AiMode { off, metlyCloud, userApi }

extension AiModeX on AiMode {
  String get label => switch (this) {
        AiMode.off => 'Off',
        AiMode.metlyCloud => 'Metly AI (${Cfg.priceMonthly})',
        AiMode.userApi => 'Use My API (${Cfg.priceLifetime})',
      };
  int get idx => switch (this) {
        AiMode.off => 0,
        AiMode.metlyCloud => 1,
        AiMode.userApi => 2
      };
  static AiMode fromIdx(int i) => switch (i) {
        1 => AiMode.metlyCloud,
        2 => AiMode.userApi,
        _ => AiMode.off
      };
}

/* ──────────────────────────────────────────────────────────────────────────────
   ROOT APP
────────────────────────────────────────────────────────────────────────────── */
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

/* ──────────────────────────────────────────────────────────────────────────────
   MARKET MODELS + SIGNAL ENGINE
────────────────────────────────────────────────────────────────────────────── */
enum Metal { gold, silver }

extension MetalX on Metal {
  String get id => this == Metal.gold ? 'gold' : 'silver';
  String get label => this == Metal.gold ? 'Gold' : 'Silver';
  String get unit => this == Metal.gold ? 'INR / 10g' : 'INR / kg';
}

class PriceSnapshot {
  final Metal metal;
  final double price;
  final double recentHigh;
  final DateTime updatedAt;
  PriceSnapshot({
    required this.metal,
    required this.price,
    required this.recentHigh,
    required this.updatedAt,
  });
  double get drawdownPct => ((recentHigh - price) / recentHigh * 100);
  String get unit => metal.unit;
}

enum Signal { buy, wait }

class SignalResult {
  final Signal signal;
  final String reason;
  const SignalResult(this.signal, this.reason);
}

bool _isPostFestiveWindow(DateTime now) {
  final end1 = Cfg.dhanteras2025.add(const Duration(days: 14));
  final end2 = Cfg.diwali2025.add(const Duration(days: 14));
  return (now.isAfter(Cfg.dhanteras2025) && now.isBefore(end1)) ||
      (now.isAfter(Cfg.diwali2025) && now.isBefore(end2));
}

SignalResult evaluateSignal(PriceSnapshot s, {required DateTime now}) {
  final dd = s.drawdownPct;
  final postFestive = _isPostFestiveWindow(now);

  if (s.metal == Metal.gold) {
    if (dd >= 2) {
      return SignalResult(
        Signal.buy,
        postFestive
            ? 'Post-festive correction ≥2% detected'
            : 'Price is ${dd.toStringAsFixed(2)}% below recent high',
      );
    }
    return const SignalResult(Signal.wait, 'Drop < 2% vs recent high');
  } else {
    if (dd >= 5) {
      return SignalResult(
        Signal.buy,
        postFestive
            ? 'Post-festive correction ≥5% detected'
            : 'Price is ≥5% below recent high',
      );
    }
    return const SignalResult(Signal.wait, 'Drop < 5% vs recent high');
  }
}

/* ──────────────────────────────────────────────────────────────────────────────
   PRICE PROVIDER (Mock for now)
────────────────────────────────────────────────────────────────────────────── */
abstract class PriceProvider {
  Future<PriceSnapshot> latest(Metal metal);
}

class MockPriceProvider implements PriceProvider {
  final Random _rng = Random();
  double _goldPrice = 132760; // per 10g
  double _goldHigh = 136500; // 30d high
  double _silverPrice = 170000; // per kg
  double _silverHigh = 190000; // 30d high

  double _jitter(double base) {
    final pct = (_rng.nextDouble() - 0.5) * 0.008; // ±0.8%
    return (base * (1 + pct)).clamp(1, double.infinity);
  }

  @override
  Future<PriceSnapshot> latest(Metal metal) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (metal == Metal.gold) {
      _goldPrice = _jitter(_goldPrice);
      return PriceSnapshot(
        metal: metal,
        price: _goldPrice,
        recentHigh: _goldHigh,
        updatedAt: DateTime.now(),
      );
    } else {
      _silverPrice = _jitter(_silverPrice);
      return PriceSnapshot(
        metal: metal,
        price: _silverPrice,
        recentHigh: _silverHigh,
        updatedAt: DateTime.now(),
      );
    }
  }
}

/* ──────────────────────────────────────────────────────────────────────────────
   OPENROUTER AI CLIENT
────────────────────────────────────────────────────────────────────────────── */
class OpenRouterClient {
  final Dio _dio;
  final SharedPreferences prefs;
  OpenRouterClient(this.prefs)
      : _dio = Dio(BaseOptions(
          baseUrl: 'https://openrouter.ai/api',
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Content-Type': 'application/json',
            'X-Title': 'Metly',
            if (!kIsWeb) 'HTTP-Referer': 'metly.app',
          },
        ));

  String? get apiKey => prefs.getString(Cfg.prefsKeyApi);
  String get model => prefs.getString(Cfg.prefsKeyModel) ?? Cfg.defaultModel;

  Future<String> explainSignals({
    required PriceSnapshot gold,
    required SignalResult goldSig,
    required PriceSnapshot silver,
    required SignalResult silverSig,
  }) async {
    final key = apiKey;
    if (key == null || key.trim().isEmpty) {
      throw Exception('OpenRouter API key not set. Add it in Settings.');
    }

    final ddG = gold.drawdownPct.toStringAsFixed(2);
    final ddS = silver.drawdownPct.toStringAsFixed(2);

    final sys = '''
You are a financial assistant focused on Indian digital gold and silver investing. 
Summarize signals clearly in <150 words, bullet style>. 
Rules:
- Gold BUY if price is 2–5% below recent high (or more).
- Silver BUY if price is ≥5% below recent high.
- After Dhanteras/Diwali spikes, confirm drop threshold before BUY.
Be factual and concise. End with a one-line takeaway.''';

    final usr = '''
Today:
- Gold price: ₹${_fmt(gold.price)} / ${gold.unit}; high: ₹${_fmt(gold.recentHigh)}; drawdown: $ddG%; signal: ${goldSig.signal.name.toUpperCase()} (${goldSig.reason})
- Silver price: ₹${_fmt(silver.price)} / ${silver.unit}; high: ₹${_fmt(silver.recentHigh)}; drawdown: $ddS%; signal: ${silverSig.signal.name.toUpperCase()} (${silverSig.reason})
Explain rationale for both and comment on SIP suitability.''';

    final body = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': sys},
        {'role': 'user', 'content': usr},
      ],
      'temperature': 0.3,
      'max_tokens': 300,
    };

    final res = await _dio.post(
      '/v1/chat/completions',
      data: body,
      options: Options(headers: {'Authorization': 'Bearer $key'}),
    );

    final content = res.data?['choices']?[0]?['message']?['content'];
    if (content is String && content.trim().isNotEmpty) {
      return content.trim();
    }
    throw Exception('Empty AI response');
  }
}

/* ──────────────────────────────────────────────────────────────────────────────
   SHARED UI
────────────────────────────────────────────────────────────────────────────── */
class MetlyAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String titleTop;
  final String titleBottom;
  final bool showMenu;
  const MetlyAppBar({
    super.key,
    required this.titleTop,
    required this.titleBottom,
    this.showMenu = true,
  });

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
              ),
            )
          : null,
      title: Column(
        children: [
          Text(
            titleTop,
            style: GoogleFonts.poppins(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              color: Cfg.gold,
            ),
          ),
          Text(
            titleBottom,
            style: GoogleFonts.poppins(
              fontSize: 11,
              color: Colors.white70,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: 'Settings',
          onPressed: () => Navigator.pushNamed(context, '/settings'),
          icon: const Icon(Icons.settings_outlined),
        ),
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
        child: Column(
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.home_outlined, color: Colors.white70),
              title: const Text('Home'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamedAndRemoveUntil(context, '/', (_) => false);
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.trending_up_outlined, color: Colors.white70),
              title: const Text('Dashboard'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/dashboard');
              },
            ),
            ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white70),
              title: const Text('About'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/about');
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.feedback_outlined, color: Colors.white70),
              title: const Text('Feedback'),
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/feedback');
              },
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                '© 2025 K4NN4N',
                style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/* ──────────────────────────────────────────────────────────────────────────────
   HOME
────────────────────────────────────────────────────────────────────────────── */
class HomeScreen extends StatelessWidget {
  final SharedPreferences prefs;
  const HomeScreen({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MetlyDrawer(),
      appBar: const MetlyAppBar(
        titleTop: 'Metly',
        titleBottom: Cfg.brandLine,
      ),
      backgroundColor: const Color(0xFF0E0E0E),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset('assets/logo/icon.png', width: 120),
              const SizedBox(height: 24),
              Text(
                'Welcome to Metly',
                style: GoogleFonts.poppins(
                  color: Cfg.gold,
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'AI-driven insights for Gold, Silver & other precious metals.\n'
                'Made with pride, built for smart investors.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 36),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Cfg.gold,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 14,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30),
                  ),
                ),
                icon: const Icon(Icons.trending_up),
                label: Text(
                  'Enter Dashboard',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                onPressed: () => Navigator.pushNamed(context, '/dashboard'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/* ──────────────────────────────────────────────────────────────────────────────
   DASHBOARD (Signals + AI gating)
────────────────────────────────────────────────────────────────────────────── */
class DashboardScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const DashboardScreen({super.key, required this.prefs});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final PriceProvider provider = MockPriceProvider();
  PriceSnapshot? gold;
  PriceSnapshot? silver;
  bool sipEnabled = false;
  bool loading = false;

  String? aiText;
  bool aiBusy = false;

  AiMode get aiMode =>
      AiModeX.fromIdx(widget.prefs.getInt(Cfg.prefsAiMode) ?? 0);
  bool get hasSub => widget.prefs.getBool(Cfg.entSubActive) ?? false;
  bool get hasLife => widget.prefs.getBool(Cfg.entLifetime) ?? false;
  String? get userKey => widget.prefs.getString(Cfg.prefsKeyApi);

  bool get canUseAI {
    return switch (aiMode) {
      AiMode.off => false,
      AiMode.metlyCloud => hasSub,
      AiMode.userApi =>
        (hasLife && (userKey != null && userKey!.trim().isNotEmpty)),
    };
  }

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
    if (!canUseAI) {
      if (!mounted) return;
      Navigator.pushNamed(context, '/paywall');
      return;
    }
    if (gold == null || silver == null) return;
    final client = OpenRouterClient(widget.prefs);
    try {
      setState(() {
        aiBusy = true;
        aiText = null;
      });
      final gSig = evaluateSignal(gold!, now: DateTime.now());
      final sSig = evaluateSignal(silver!, now: DateTime.now());
      final text = await client.explainSignals(
        gold: gold!,
        goldSig: gSig,
        silver: silver!,
        silverSig: sSig,
      );
      setState(() => aiText = text);
    } catch (e) {
      setState(() => aiText = 'AI error: ${e.toString()}');
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
        titleTop: 'Dashboard',
        titleBottom: 'Signals • Gold • Silver',
      ),
      backgroundColor: const Color(0xFF0E0E0E),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Cfg.gold,
                    foregroundColor: Colors.black,
                  ),
                  onPressed: loading ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Prices'),
                ),
                const SizedBox(width: 12),
                FilterChip(
                  selected: sipEnabled,
                  onSelected: (v) => setState(() => sipEnabled = v),
                  label: const Text('SIP Tip'),
                  selectedColor: Cfg.gold.withOpacity(0.25),
                  side: BorderSide(color: Cfg.gold.withOpacity(0.35)),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: aiBusy ? null : _askAI,
                  style: FilledButton.styleFrom(
                    backgroundColor: canUseAI ? Colors.black : Colors.black12,
                    side: BorderSide(
                      color: (canUseAI ? Cfg.gold : Colors.white24)
                          .withOpacity(0.6),
                    ),
                    foregroundColor: Colors.white,
                  ),
                  icon: Icon(aiBusy ? Icons.hourglass_top : Icons.auto_awesome),
                  label: Text(aiBusy
                      ? 'Thinking…'
                      : (canUseAI ? 'Ask AI' : 'Unlock AI')),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (gold != null)
              SignalCard(
                  snapshot: gold!, result: evaluateSignal(gold!, now: now)),
            if (silver != null)
              SignalCard(
                  snapshot: silver!, result: evaluateSignal(silver!, now: now)),
            const SizedBox(height: 12),
            if (sipEnabled)
              Text(
                'SIP tip: Invest regularly to average risk and returns.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: Colors.white70, fontSize: 13),
              ),
            const SizedBox(height: 16),
            _PlatformLinksRow(),
            const SizedBox(height: 16),
            if (aiText != null) _AiInsight(text: aiText!),
          ],
        ),
      ),
    );
  }
}

/* ── Signal Card UI ─────────────────────────────────────────────────────────── */
class SignalCard extends StatelessWidget {
  final PriceSnapshot snapshot;
  final SignalResult result;
  const SignalCard({super.key, required this.snapshot, required this.result});

  @override
  Widget build(BuildContext context) {
    final isBuy = result.signal == Signal.buy;
    final bg = isBuy ? const Color(0xFF073B2A) : const Color(0xFF3B0707);
    final border = isBuy ? const Color(0xFF17A36B) : const Color(0xFFB34A4A);
    final title =
        '${isBuy ? "BUY" : "WAIT"} ${snapshot.metal.label.toUpperCase()} ${isBuy ? "NOW!" : ""}';

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border.withOpacity(0.6), width: 1.4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              )),
          const SizedBox(height: 8),
          Wrap(
            spacing: 16,
            runSpacing: 6,
            children: [
              _Fact('Price', '₹${_fmt(snapshot.price)} / ${snapshot.unit}'),
              _Fact('Recent high', '₹${_fmt(snapshot.recentHigh)}'),
              _Fact(
                  'Below high', '${snapshot.drawdownPct.toStringAsFixed(2)}%'),
              _Fact('Updated', _timeFmt(snapshot.updatedAt)),
            ],
          ),
          const SizedBox(height: 10),
          Text(result.reason,
              style: GoogleFonts.poppins(
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500,
              )),
        ],
      ),
    );
  }
}

/* ── Reusable bits ─────────────────────────────────────────────────────────── */
class _Fact extends StatelessWidget {
  final String k, v;
  const _Fact(this.k, this.v);
  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text.rich(
        TextSpan(children: [
          TextSpan(
            text: '$k: ',
            style: GoogleFonts.poppins(
              color: Colors.white70,
              fontWeight: FontWeight.w600,
            ),
          ),
          TextSpan(
            text: v,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ]),
      ),
      backgroundColor: Colors.white.withOpacity(0.06),
      side: const BorderSide(color: Colors.white24),
    );
  }
}

class _PlatformLinksRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget btn(String label) => OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: Cfg.gold.withOpacity(0.5)),
            foregroundColor: Colors.white,
          ),
          onPressed: () {},
          child: Text(label),
        );
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        btn('MMTC-PAMP'),
        btn('DigiGold'),
        btn('Tanishq Digital'),
      ],
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
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('AI Insight',
              style: GoogleFonts.poppins(
                color: Cfg.gold,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              )),
          const SizedBox(height: 8),
          SelectableText(
            text,
            style: GoogleFonts.poppins(color: Colors.white.withOpacity(0.92)),
          ),
        ],
      ),
    );
  }
}

/* ──────────────────────────────────────────────────────────────────────────────
   ABOUT
────────────────────────────────────────────────────────────────────────────── */
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MetlyDrawer(),
      appBar: const MetlyAppBar(
        titleTop: 'About Metly',
        titleBottom: Cfg.brandLine,
      ),
      backgroundColor: const Color(0xFF0E0E0E),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            children: [
              Image.asset('assets/logo/icon.png', width: 72),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Metly',
                      style: GoogleFonts.poppins(
                          color: Cfg.gold,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  Text(Cfg.brandLine,
                      style: GoogleFonts.poppins(color: Colors.white70)),
                  Text('Version ${Cfg.version}',
                      style: GoogleFonts.poppins(color: Colors.white54)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'Metly is an open-source app that provides clear, actionable signals '
            'for gold, silver, and other precious metals. It’s built for India, '
            'focused on transparency, speed, and simplicity.',
            style: GoogleFonts.poppins(fontSize: 14, color: Colors.white70),
          ),
          const SizedBox(height: 24),
          Divider(color: Colors.white12),
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
                    GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

/* ──────────────────────────────────────────────────────────────────────────────
   FEEDBACK
────────────────────────────────────────────────────────────────────────────── */
class FeedbackScreen extends StatefulWidget {
  const FeedbackScreen({super.key});
  @override
  State<FeedbackScreen> createState() => _FeedbackScreenState();
}

class _FeedbackScreenState extends State<FeedbackScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _message = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Thank you! Feedback submitted.'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    _message.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: const MetlyDrawer(),
      appBar: const MetlyAppBar(
        titleTop: 'Feedback',
        titleBottom: 'Tell us what to improve',
      ),
      backgroundColor: const Color(0xFF0E0E0E),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _email,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Email (optional)',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Cfg.gold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _message,
                    style: const TextStyle(color: Colors.white),
                    minLines: 4,
                    maxLines: 6,
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Message required'
                        : null,
                    decoration: const InputDecoration(
                      labelText: 'Your message',
                      labelStyle: TextStyle(color: Colors.white70),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Cfg.gold),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Cfg.gold,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 14),
                      ),
                      onPressed: _submit,
                      icon: const Icon(Icons.send),
                      label: const Text('Submit'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/* ──────────────────────────────────────────────────────────────────────────────
   SETTINGS (AI Mode + API key + stub entitlements)
────────────────────────────────────────────────────────────────────────────── */
class SettingsScreen extends StatefulWidget {
  final SharedPreferences prefs;
  const SettingsScreen({super.key, required this.prefs});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late AiMode _mode;
  late final TextEditingController _keyCtrl;
  late final TextEditingController _modelCtrl;
  bool _subActive = false;
  bool _lifeActive = false;

  @override
  void initState() {
    super.initState();
    _mode = AiModeX.fromIdx(widget.prefs.getInt(Cfg.prefsAiMode) ?? 0);
    _keyCtrl =
        TextEditingController(widget.prefs.getString(Cfg.prefsKeyApi) ?? '');
    _modelCtrl = TextEditingController(
        widget.prefs.getString(Cfg.prefsKeyModel) ?? Cfg.defaultModel);
    _subActive = widget.prefs.getBool(Cfg.entSubActive) ?? false;
    _lifeActive = widget.prefs.getBool(Cfg.entLifetime) ?? false;
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.prefs.setInt(Cfg.prefsAiMode, _mode.idx);
    await widget.prefs.setString(Cfg.prefsKeyApi, _keyCtrl.text.trim());
    await widget.prefs.setString(Cfg.prefsKeyModel, _modelCtrl.text.trim());
    await widget.prefs.setBool(Cfg.entSubActive, _subActive);
    await widget.prefs.setBool(Cfg.entLifetime, _lifeActive);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Settings saved')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MetlyAppBar(
        titleTop: 'Settings',
        titleBottom: 'AI & Entitlements',
        showMenu: false,
      ),
      backgroundColor: const Color(0xFF0E0E0E),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('AI Mode',
              style: GoogleFonts.poppins(
                  fontSize: 16, color: Cfg.gold, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          DropdownButtonFormField<AiMode>(
            value: _mode,
            dropdownColor: const Color(0xFF1A1A1A),
            decoration: const InputDecoration(
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder:
                  OutlineInputBorder(borderSide: BorderSide(color: Cfg.gold)),
            ),
            items: AiMode.values
                .map((m) => DropdownMenuItem(value: m, child: Text(m.label)))
                .toList(),
            onChanged: (m) => setState(() => _mode = m ?? AiMode.off),
          ),
          const SizedBox(height: 16),
          if (_mode == AiMode.userApi) ...[
            Text('OpenRouter API',
                style:
                    GoogleFonts.poppins(fontSize: 16, color: Colors.white70)),
            const SizedBox(height: 8),
            TextFormField(
              controller: _keyCtrl,
              obscureText: true,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'API Key',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder:
                    OutlineInputBorder(borderSide: BorderSide(color: Cfg.gold)),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _modelCtrl,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Model (e.g., openai/gpt-4o-mini)',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder:
                    OutlineInputBorder(borderSide: BorderSide(color: Cfg.gold)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Divider(color: Colors.white12),
          const SizedBox(height: 12),
          Text('Entitlements (stub for now)',
              style: GoogleFonts.poppins(
                  fontSize: 16, color: Cfg.gold, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          SwitchListTile(
            value: _subActive,
            activeColor: Cfg.gold,
            title: Text('Metly AI subscription • ${Cfg.priceMonthly}'),
            subtitle: const Text('Enables Metly AI mode'),
            onChanged: (v) => setState(() => _subActive = v),
          ),
          SwitchListTile(
            value: _lifeActive,
            activeColor: Cfg.gold,
            title: Text('Lifetime unlock for user API • ${Cfg.priceLifetime}'),
            subtitle: const Text('Enables “Use My API” mode'),
            onChanged: (v) => setState(() => _lifeActive = v),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: Cfg.gold,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
            ),
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save'),
          ),
          const SizedBox(height: 10),
          Text(
            'Note: These are local toggles for development. '
            'We will wire real Google Play Billing (subscriptions + one-time purchase) later. '
            'App remains fully usable without AI.',
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/* ──────────────────────────────────────────────────────────────────────────────
   PAYWALL SCREEN (stub; shows options & routes to Settings)
────────────────────────────────────────────────────────────────────────────── */
class PaywallScreen extends StatelessWidget {
  final SharedPreferences prefs;
  const PaywallScreen({super.key, required this.prefs});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MetlyAppBar(
        titleTop: 'Unlock AI',
        titleBottom: 'Metly AI • Use My API',
        showMenu: false,
      ),
      backgroundColor: const Color(0xFF0E0E0E),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _PayTile(
              title: 'Metly AI',
              subtitle: 'On-demand explanations • ${Cfg.priceMonthly}',
              icon: Icons.auto_awesome,
              onTap: () {
                prefs.setInt(Cfg.prefsAiMode, AiMode.metlyCloud.idx);
                Navigator.pushReplacementNamed(context, '/settings');
              },
            ),
            const SizedBox(height: 12),
            _PayTile(
              title: 'Use My API',
              subtitle: 'Bring your own key • ${Cfg.priceLifetime}',
              icon: Icons.vpn_key_outlined,
              onTap: () {
                prefs.setInt(Cfg.prefsAiMode, AiMode.userApi.idx);
                Navigator.pushReplacementNamed(context, '/settings');
              },
            ),
            const Spacer(),
            Text(
              'You can continue using Metly without AI.',
              style: GoogleFonts.poppins(color: Colors.white70),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: Cfg.gold.withOpacity(0.6)),
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PayTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  const _PayTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    return ListTile(
      tileColor: const Color(0xFF141414),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Icon(icon, color: Cfg.gold, size: 28),
      title:
          Text(title, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
      subtitle:
          Text(subtitle, style: GoogleFonts.poppins(color: Colors.white70)),
      trailing: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: Cfg.gold,
          foregroundColor: Colors.black,
        ),
        onPressed: onTap,
        child: const Text('Select'),
      ),
    );
  }
}

/* ──────────────────────────────────────────────────────────────────────────────
   HELPERS
────────────────────────────────────────────────────────────────────────────── */
String _timeFmt(DateTime t) {
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '$hh:$mm IST';
}

String _fmt(double v) {
  final s = v.toStringAsFixed(0);
  if (s.length <= 3) return s;
  final last3 = s.substring(s.length - 3);
  String rest = s.substring(0, s.length - 3);
  final parts = <String>[];
  while (rest.length > 2) {
    parts.insert(0, rest.substring(rest.length - 2));
    rest = rest.substring(0, rest.length - 2);
  }
  if (rest.isNotEmpty) parts.insert(0, rest);
  return '${parts.join(',')},$last3';
}
