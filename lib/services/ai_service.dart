import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
import '../models/price_model.dart';
import '../models/price_model.dart';
import '../utils/formatters.dart';

/* ════════════════════════════════════════════════════════════════════════════
   AI CLIENTS
════════════════════════════════════════════════════════════════════════════ */
abstract class AiClient {
  Future<String> explainSignals({
    required PriceSnapshot gold,
    required SignalResult goldSig,
    required PriceSnapshot silver,
    required SignalResult silverSig,
  });
}

class OpenRouterClient implements AiClient {
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
        'Today:\n- Gold: ₹${fmt(gold.price)} / ${gold.unit}; high ₹${fmt(gold.recentHigh)}; drawdown $ddG%; signal: ${goldSig.signal.name.toUpperCase()} (${goldSig.reason})\n- Silver: ₹${fmt(silver.price)} / ${silver.unit}; high ₹${fmt(silver.recentHigh)}; drawdown $ddS%; signal: ${silverSig.signal.name.toUpperCase()} (${silverSig.reason})\nExplain rationale for both and comment on SIP suitability.';
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
class ProxyAiClient implements AiClient {
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
        'Today:\n- Gold: ₹${fmt(gold.price)} / ${gold.unit}; high ₹${fmt(gold.recentHigh)}; drawdown $ddG%; signal: ${goldSig.signal.name.toUpperCase()} (${goldSig.reason})\n- Silver: ₹${fmt(silver.price)} / ${silver.unit}; high ₹${fmt(silver.recentHigh)}; drawdown $ddS%; signal: ${silverSig.signal.name.toUpperCase()} (${silverSig.reason})\nExplain rationale for both and comment on SIP suitability.';
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
