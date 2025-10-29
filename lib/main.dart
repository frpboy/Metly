// lib/main.dart
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final prefs = await SharedPreferences.getInstance();
  runApp(MetlyApp(prefs: prefs));
}

/* ════════════════════════════════════════════════════════════════════════════
   CONFIG + PRICING
════════════════════════════════════════════════════════════════════════════ */
class Cfg {
  static const Color gold = Color(0xFFFFD700);
  static const String brandLine = 'Made in India with ❤ Gold';
  static const String appTitle = 'Metly — $brandLine';
  static const String version = 'v1.0.1';

  // Festival dates for post-festive guard (example 2025)
  static final DateTime dhanteras2025 = DateTime(2025, 10, 18);
  static final DateTime diwali2025 = DateTime(2025, 10, 20);

  // Models
  static const String defaultModel = 'openai/gpt-4o-mini';

  // Pref keys
  static const String prefsKeyApi = 'openrouter_api_key'; // user's own key
  static const String prefsKeyModel = 'openrouter_model';

  // NEW: proxy prefs (Metly AI)
  static const String prefsProxyUrl = 'metly_proxy_url';
  static const String prefsProxyTok = 'metly_proxy_token';

  // Entitlements (dev stubs for pricing)
  // ₹99/mo for Metly AI (creator’s API)
  static const String entSubActive = 'ent_sub_active';
  // ₹999 lifetime for using customer’s own API
  static const String entLifetime = 'ent_lifetime_active';

  // AI Mode selection
  static const String prefsAiMode =
      'ai_mode'; // 0=Off, 1=Metly AI, 2=Use My API

  // UI labels
  static const String priceMonthly = '₹99/month';
  static const String priceLifetime = '₹999 (lifetime)';
}

/* ════════════════════════════════════════════════════════════════════════════
   AI MODES
════════════════════════════════════════════════════════════════════════════ */
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

/* ════════════════════════════════════════════════════════════════════════════
   MARKET SIM + SIGNALS (mock prices for now)
════════════════════════════════════════════════════════════════════════════ */
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
  PriceSnapshot(
      {required this.metal,
      required this.price,
      required this.recentHigh,
      required this.updatedAt});
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
              : 'Price is ${dd.toStringAsFixed(2)}% below recent high');
    }
    return const SignalResult(Signal.wait, 'Drop < 2% vs recent high');
  } else {
    if (dd >= 5) {
      return SignalResult(
          Signal.buy,
          postFestive
              ? 'Post-festive correction ≥5% detected'
              : 'Price is ≥5% below recent high');
    }
    return const SignalResult(Signal.wait, 'Drop < 5% vs recent high');
  }
}

abstract class PriceProvider {
  Future<PriceSnapshot> latest(Metal metal);
}

class MockPriceProvider implements PriceProvider {
  final Random _rng = Random();
  double _goldPrice = 132760;
  final double _goldHigh = 136500;
  double _silverPrice = 170000;
  final double _silverHigh = 190000;
  double _jitter(double base) {
    final pct = (_rng.nextDouble() - 0.5) * 0.008;
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
          updatedAt: DateTime.now());
    }
    _silverPrice = _jitter(_silverPrice);
    return PriceSnapshot(
        metal: metal,
        price: _silverPrice,
        recentHigh: _silverHigh,
        updatedAt: DateTime.now());
  }
}

/* ════════════════════════════════════════════════════════════════════════════
   AI CLIENTS
════════════════════════════════════════════════════════════════════════════ */
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
    const sys =
        'You are a financial assistant for Indian digital gold & silver investors. Summarize signals in <150 words, bullets. Rules: Gold BUY if ≥2% below recent high; Silver BUY if ≥5% below. After Dhanteras/Diwali spikes, confirm threshold before BUY. End with a one-line takeaway.';
    final usr =
        'Today:\n- Gold: ₹${_fmt(gold.price)} / ${gold.unit}; high ₹${_fmt(gold.recentHigh)}; drawdown $ddG%; signal: ${goldSig.signal.name.toUpperCase()} (${goldSig.reason})\n- Silver: ₹${_fmt(silver.price)} / ${silver.unit}; high ₹${_fmt(silver.recentHigh)}; drawdown $ddS%; signal: ${silverSig.signal.name.toUpperCase()} (${silverSig.reason})\nExplain rationale for both and comment on SIP suitability.';
    final body = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': sys},
        {'role': 'user', 'content': usr}
      ],
      'temperature': 0.3,
      'max_tokens': 300
    };
    final res = await _dio.post('/v1/chat/completions',
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $key'}));
    final content = res.data?['choices']?[0]?['message']?['content'];
    if (content is String && content.trim().isNotEmpty) return content.trim();
    throw Exception('Empty AI response');
  }
}

/// Cloudflare Worker proxy -> OpenRouter (Metly AI mode)
class ProxyAiClient {
  final Dio _dio;
  final SharedPreferences prefs;
  ProxyAiClient(this.prefs)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          headers: {'Content-Type': 'application/json'},
        ));
  String? get _url => prefs.getString(Cfg.prefsProxyUrl);
  String? get _tok => prefs.getString(Cfg.prefsProxyTok);
  String get model => prefs.getString(Cfg.prefsKeyModel) ?? Cfg.defaultModel;

  Future<String> explainSignals({
    required PriceSnapshot gold,
    required SignalResult goldSig,
    required PriceSnapshot silver,
    required SignalResult silverSig,
  }) async {
    final url = _url?.trim();
    final tok = _tok?.trim();
    if (url == null || url.isEmpty) {
      throw Exception('Proxy URL not set. Add it in Settings.');
    }
    if (tok == null || tok.isEmpty) {
      throw Exception('Proxy token not set. Add it in Settings.');
    }
    final ddG = gold.drawdownPct.toStringAsFixed(2);
    final ddS = silver.drawdownPct.toStringAsFixed(2);
    const sys =
        'You are a financial assistant for Indian digital gold & silver investors. Summarize signals in <150 words, bullets. Rules: Gold BUY if ≥2% below recent high; Silver BUY if ≥5% below. After Dhanteras/Diwali spikes, confirm threshold before BUY. End with a one-line takeaway.';
    final usr =
        'Today:\n- Gold: ₹${_fmt(gold.price)} / ${gold.unit}; high ₹${_fmt(gold.recentHigh)}; drawdown $ddG%; signal: ${goldSig.signal.name.toUpperCase()} (${goldSig.reason})\n- Silver: ₹${_fmt(silver.price)} / ${silver.unit}; high ₹${_fmt(silver.recentHigh)}; drawdown $ddS%; signal: ${silverSig.signal.name.toUpperCase()} (${silverSig.reason})\nExplain rationale for both and comment on SIP suitability.';
    final body = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': sys},
        {'role': 'user', 'content': usr}
      ],
      'temperature': 0.3,
      'max_tokens': 300
    };
    final res = await _dio.post(url,
        data: body,
        options: Options(headers: {'Authorization': 'Bearer $tok'}));
    final data = res.data;
    final content = data?['choices']?[0]?['message']?['content'];
    if (content is String && content.trim().isNotEmpty) return content.trim();
    throw Exception('Empty AI response from proxy');
  }
}

/* ════════════════════════════════════════════════════════════════════════════
   SHARED UI BITS
════════════════════════════════════════════════════════════════════════════ */
String _fmt(num v) {
  final s = v.toStringAsFixed(0);
  final buf = StringBuffer();
  int c = 0;
  for (int i = s.length - 1; i >= 0; i--) {
    buf.write(s[i]);
    c++;
    if (c == 3 && i != 0) {
      buf.write(',');
      c = 0;
    }
  }
  return String.fromCharCodes(buf.toString().codeUnits.reversed);
}

String _timeFmt(DateTime t) {
  final h = t.hour.toString().padLeft(2, '0');
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m IST';
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

/* ════════════════════════════════════════════════════════════════════════════
   DASHBOARD
════════════════════════════════════════════════════════════════════════════ */
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

  bool get canUseAI => switch (aiMode) {
        AiMode.off => false,
        AiMode.metlyCloud => hasSub,
        AiMode.userApi =>
          (hasLife && (userKey != null && userKey!.trim().isNotEmpty)),
      };

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

    final AiMode mode = aiMode;
    final ai = (mode == AiMode.metlyCloud)
        ? ProxyAiClient(widget.prefs)
        : OpenRouterClient(widget.prefs);

    try {
      setState(() {
        aiBusy = true;
        aiText = null;
      });
      final gSig = evaluateSignal(gold!, now: DateTime.now());
      final sSig = evaluateSignal(silver!, now: DateTime.now());
      final text = await ai.explainSignals(
          gold: gold!, goldSig: gSig, silver: silver!, silverSig: sSig);
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
                selectedColor: Cfg.gold.withOpacity(0.25),
                side: BorderSide(color: Cfg.gold.withOpacity(0.35))),
            const Spacer(),
            FilledButton.icon(
                onPressed: aiBusy ? null : _askAI,
                style: FilledButton.styleFrom(
                    backgroundColor: canUseAI ? Colors.black : Colors.black12,
                    side: BorderSide(
                        color: (canUseAI ? Cfg.gold : Colors.white24)
                            .withOpacity(0.6)),
                    foregroundColor: Colors.white),
                icon: Icon(aiBusy ? Icons.hourglass_top : Icons.auto_awesome),
                label: Text(aiBusy
                    ? 'Thinking…'
                    : (canUseAI ? 'Ask AI' : 'Unlock AI'))),
          ]),
          const SizedBox(height: 12),
          if (gold != null)
            SignalCard(
                snapshot: gold!, result: evaluateSignal(gold!, now: now)),
          if (silver != null)
            SignalCard(
                snapshot: silver!, result: evaluateSignal(silver!, now: now)),
          const SizedBox(height: 12),
          if (sipEnabled)
            Text('SIP tip: Invest regularly to average risk and returns.',
                textAlign: TextAlign.center,
                style:
                    GoogleFonts.poppins(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 16),
          _PlatformLinksRow(),
          const SizedBox(height: 16),
          if (aiText != null) _AiInsight(text: aiText!),
        ]),
      ),
    );
  }
}

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
          border: Border.all(color: border.withOpacity(0.6), width: 1.4)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: GoogleFonts.poppins(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Colors.white)),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 6, children: [
          _Fact('Price', '₹${_fmt(snapshot.price)} / ${snapshot.unit}'),
          _Fact('Recent high', '₹${_fmt(snapshot.recentHigh)}'),
          _Fact('Below high', '${snapshot.drawdownPct.toStringAsFixed(2)}%'),
          _Fact('Updated', _timeFmt(snapshot.updatedAt)),
        ]),
        const SizedBox(height: 10),
        Text(result.reason,
            style: GoogleFonts.poppins(
                color: Colors.white.withOpacity(0.9),
                fontWeight: FontWeight.w500)),
      ]),
    );
  }
}

class _Fact extends StatelessWidget {
  final String k, v;
  const _Fact(this.k, this.v);
  @override
  Widget build(BuildContext context) {
    return Chip(
        label: Text.rich(TextSpan(children: [
          TextSpan(
              text: '$k: ',
              style: GoogleFonts.poppins(
                  color: Colors.white70, fontWeight: FontWeight.w600)),
          TextSpan(
              text: v,
              style: GoogleFonts.poppins(
                  color: Colors.white, fontWeight: FontWeight.w600)),
        ])),
        backgroundColor: Colors.white.withOpacity(0.06),
        side: const BorderSide(color: Colors.white24));
  }
}

class _PlatformLinksRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    Widget btn(String label) => OutlinedButton(
        style: OutlinedButton.styleFrom(
            side: BorderSide(color: Cfg.gold.withOpacity(0.5)),
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
              style:
                  GoogleFonts.poppins(color: Colors.white.withOpacity(0.92))),
        ]));
  }
}

/* ════════════════════════════════════════════════════════════════════════════
   ABOUT + FEEDBACK
════════════════════════════════════════════════════════════════════════════ */
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
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Thank you! Feedback submitted.'),
        behavior: SnackBarBehavior.floating));
    _message.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        drawer: const MetlyDrawer(),
        appBar: const MetlyAppBar(
            titleTop: 'Feedback', titleBottom: 'Tell us what to improve'),
        backgroundColor: const Color(0xFF0E0E0E),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Form(
                        key: _formKey,
                        child: Column(children: [
                          TextFormField(
                            controller: _email,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              labelText: 'Email (optional)',
                              labelStyle: TextStyle(color: Colors.white70),
                              enabledBorder: OutlineInputBorder(
                                  borderSide:
                                      BorderSide(color: Colors.white24)),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Cfg.gold)),
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
                                  borderSide:
                                      BorderSide(color: Colors.white24)),
                              focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: Cfg.gold)),
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
                                          horizontal: 22, vertical: 14)),
                                  onPressed: _submit,
                                  icon: const Icon(Icons.send),
                                  label: const Text('Submit'))),
                        ]))))));
  }
}

/* ════════════════════════════════════════════════════════════════════════════
   PAYWALL (stub)
════════════════════════════════════════════════════════════════════════════ */
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

/* ════════════════════════════════════════════════════════════════════════════
   SETTINGS (AI mode + grouped model dropdown + proxy + entitlements)
════════════════════════════════════════════════════════════════════════════ */
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
  late final TextEditingController _proxyUrlCtrl;
  late final TextEditingController _proxyTokCtrl;
  bool _subActive = false;
  bool _lifeActive = false;

  // Grouped model options
  final Map<String, Map<String, String>> modelGroups = {
    'Recommended': {
      'openai/gpt-4o-mini': 'GPT-4o Mini (Fast & Smart)',
      'openai/gpt-4o': 'GPT-4o (Full Model)',
      'anthropic/claude-3.5-sonnet': 'Claude 3.5 Sonnet',
    },
    'Open-Source': {
      'mistralai/mistral-nemo': 'Mistral Nemo (Open)',
      'meta-llama/llama-3.1-70b': 'LLaMA 3.1 70B (Meta)',
      'gryphe/mythomax-l2-13b': 'MythoMax L2 13B (Open)',
    },
    'Experimental': {
      'google/gemini-flash-1.5': 'Gemini 1.5 Flash (Google)',
      'perplexity/sonar-small-online': 'Perplexity Sonar (Web + Search)',
    },
  };

  @override
  void initState() {
    super.initState();
    _mode = AiModeX.fromIdx(widget.prefs.getInt(Cfg.prefsAiMode) ?? 0);
    _keyCtrl = TextEditingController(
        text: widget.prefs.getString(Cfg.prefsKeyApi) ?? '');
    _modelCtrl = TextEditingController(
        text: widget.prefs.getString(Cfg.prefsKeyModel) ?? Cfg.defaultModel);
    _proxyUrlCtrl = TextEditingController(
        text: widget.prefs.getString(Cfg.prefsProxyUrl) ?? '');
    _proxyTokCtrl = TextEditingController(
        text: widget.prefs.getString(Cfg.prefsProxyTok) ?? '');
    _subActive = widget.prefs.getBool(Cfg.entSubActive) ?? false;
    _lifeActive = widget.prefs.getBool(Cfg.entLifetime) ?? false;
  }

  @override
  void dispose() {
    _keyCtrl.dispose();
    _modelCtrl.dispose();
    _proxyUrlCtrl.dispose();
    _proxyTokCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.prefs.setInt(Cfg.prefsAiMode, _mode.idx);
    await widget.prefs.setString(Cfg.prefsKeyApi, _keyCtrl.text.trim());
    await widget.prefs.setString(Cfg.prefsKeyModel, _modelCtrl.text.trim());
    await widget.prefs.setString(Cfg.prefsProxyUrl, _proxyUrlCtrl.text.trim());
    await widget.prefs.setString(Cfg.prefsProxyTok, _proxyTokCtrl.text.trim());
    await widget.prefs.setBool(Cfg.entSubActive, _subActive);
    await widget.prefs.setBool(Cfg.entLifetime, _lifeActive);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Settings saved')));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const MetlyAppBar(
          titleTop: 'Settings', titleBottom: 'AI & Proxy', showMenu: false),
      backgroundColor: const Color(0xFF0E0E0E),
      body: ListView(padding: const EdgeInsets.all(24), children: [
        Text('AI Mode',
            style: GoogleFonts.poppins(
                fontSize: 16, color: Cfg.gold, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        DropdownButtonFormField<AiMode>(
          initialValue: _mode,
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
        if (_mode == AiMode.metlyCloud) ...[
          const SizedBox(height: 16),
          Text('Metly AI Proxy (Cloudflare Worker)',
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.white70)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _proxyUrlCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                labelText: 'Proxy URL (…/v1/chat/completions)',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Cfg.gold))),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _proxyTokCtrl,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                labelText: 'Proxy Token (METLY_PROXY_TOKEN)',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Cfg.gold))),
          ),
        ],
        if (_mode == AiMode.userApi) ...[
          const SizedBox(height: 16),
          Text('OpenRouter API (Use My API)',
              style: GoogleFonts.poppins(fontSize: 16, color: Colors.white70)),
          const SizedBox(height: 8),
          TextFormField(
            controller: _keyCtrl,
            obscureText: true,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
                labelText: 'OpenRouter API Key',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Cfg.gold))),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue:
                _modelCtrl.text.isNotEmpty ? _modelCtrl.text : Cfg.defaultModel,
            items: [
              for (final group in modelGroups.entries) ...[
                DropdownMenuItem<String>(
                    enabled: false,
                    child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(group.key,
                            style: GoogleFonts.poppins(
                                color: Colors.amberAccent,
                                fontWeight: FontWeight.w600,
                                fontSize: 13)))),
                ...group.value.entries.map((e) => DropdownMenuItem<String>(
                    value: e.key,
                    child: Padding(
                        padding: const EdgeInsets.only(left: 12),
                        child: Text(e.value,
                            style: GoogleFonts.poppins(color: Colors.white))))),
              ],
            ],
            onChanged: (val) =>
                setState(() => _modelCtrl.text = val ?? Cfg.defaultModel),
            decoration: const InputDecoration(
                labelText: 'Model',
                labelStyle: TextStyle(color: Colors.white70),
                enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24)),
                focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Cfg.gold))),
            dropdownColor: const Color(0xFF1A1A1A),
          ),
        ],
        const SizedBox(height: 16),
        const Divider(color: Colors.white12),
        const SizedBox(height: 12),
        Text('Entitlements (dev stubs)',
            style: GoogleFonts.poppins(
                fontSize: 16, color: Cfg.gold, fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        SwitchListTile(
            value: _subActive,
            activeThumbColor: Cfg.gold,
            title: const Text('Metly AI subscription • ${Cfg.priceMonthly}'),
            subtitle: const Text('Enables Metly AI mode'),
            onChanged: (v) => setState(() => _subActive = v)),
        SwitchListTile(
            value: _lifeActive,
            activeThumbColor: Cfg.gold,
            title: const Text('Lifetime unlock • ${Cfg.priceLifetime}'),
            subtitle: const Text('Enables “Use My API” mode'),
            onChanged: (v) => setState(() => _lifeActive = v)),
        const SizedBox(height: 16),
        FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: Cfg.gold,
                foregroundColor: Colors.black,
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 14)),
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save')),
        const SizedBox(height: 10),
        Text(
            'Note: These toggles are for development only. We will wire real billing later.',
            style: GoogleFonts.poppins(color: Colors.white54, fontSize: 12)),
      ]),
    );
  }
}
