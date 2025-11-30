import 'package:flutter/material.dart';

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
  static const String prefsProxyUrl = 'proxy_url';
  static const String prefsProxyTok = 'proxy_token';

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
