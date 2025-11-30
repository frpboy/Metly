import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../config/app_config.dart';
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
          baseUrl: prefs.getString(Cfg.prefsProxyUrl)?.trim().isNotEmpty == true
              ? prefs
                  .getString(Cfg.prefsProxyUrl)!
                  .replaceAll(RegExp(r'/+$'), '') // strip trailing slash
              : 'https://openrouter.ai/api/v1',
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 30),
          headers: {
            'Content-Type': 'application/json',
            'X-Title': 'Metly',
            if (!kIsWeb) 'HTTP-Referer': 'metly.app',
          },
        ));

  String? get _proxyTok => prefs.getString(Cfg.prefsProxyTok);
  String? get _apiKey => prefs.getString(Cfg.prefsKeyApi);
  String get model => prefs.getString(Cfg.prefsKeyModel) ?? Cfg.defaultModel;

  bool get _useProxy =>
      (prefs.getString(Cfg.prefsProxyUrl)?.trim().isNotEmpty ?? false);

  @override
  Future<String> explainSignals({
    required PriceSnapshot gold,
    required SignalResult goldSig,
    required PriceSnapshot silver,
    required SignalResult silverSig,
  }) async {
    final ddG = gold.drawdownPct.toStringAsFixed(2);
    final ddS = silver.drawdownPct.toStringAsFixed(2);

    final sys = 'You are a financial assistant for Indian gold/silver…';
    final usr = '''
Today:
- Gold price: ₹${fmt(gold.price)} / ${gold.unit}; high: ₹${fmt(gold.recentHigh)}; drawdown: $ddG%; signal: ${goldSig.signal.name.toUpperCase()} (${goldSig.reason})
- Silver price: ₹${fmt(silver.price)} / ${silver.unit}; high: ₹${fmt(silver.recentHigh)}; drawdown: $ddS%; signal: ${silverSig.signal.name.toUpperCase()} (${silverSig.reason})
Explain briefly with bullets.''';

    final body = {
      'model': model,
      'messages': [
        {'role': 'system', 'content': sys},
        {'role': 'user', 'content': usr},
      ],
      'temperature': 0.3,
      'max_tokens': 300,
    };

    final headers = <String, String>{
      if (_useProxy) 'Authorization': 'Bearer ${_proxyTok ?? ''}',
      if (!_useProxy) 'Authorization': 'Bearer ${_apiKey ?? ''}',
    };

    final path = _useProxy ? '' : '/chat/completions';

    final res =
        await _dio.post(path, data: body, options: Options(headers: headers));
    final content = res.data?['choices']?[0]?['message']?['content'];
    if (content is String && content.trim().isNotEmpty) return content.trim();
    throw Exception('Empty AI response');
  }
}
