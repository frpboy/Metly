import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../widgets/common_widgets.dart';

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
