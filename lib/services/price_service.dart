import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/price_model.dart';

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

class RealPriceProvider implements PriceProvider {
  final Dio _dio = Dio();
  final SharedPreferences prefs;

  RealPriceProvider(this.prefs);

  String? get _workerUrl => prefs.getString(Cfg.prefsPriceWorkerUrl);

  @override
  Future<PriceSnapshot> latest(Metal metal) async {
    final url = _workerUrl;
    if (url == null || url.isEmpty) {
      // Fallback to mock if no URL configured
      return MockPriceProvider().latest(metal);
    }

    try {
      final res = await _dio.get(url);
      final data = res.data;

      if (data == null) throw Exception('No data');

      final key = metal == Metal.gold ? 'gold' : 'silver';
      final item = data[key];

      if (item == null) throw Exception('Metal data not found');

      return PriceSnapshot(
        metal: metal,
        price: (item['price'] as num).toDouble(),
        recentHigh: (item['recentHigh'] as num).toDouble(),
        updatedAt: DateTime.parse(item['updatedAt']),
      );
    } catch (e) {
      debugPrint('Error fetching prices: $e');
      // Fallback on error
      return MockPriceProvider().latest(metal);
    }
  }
}
