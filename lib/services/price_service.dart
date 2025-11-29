import 'dart:math';
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
  // TODO: Add API Key in Cfg or Settings
  final String _apiKey = 'YOUR_API_KEY'; 

  @override
  Future<PriceSnapshot> latest(Metal metal) async {
    // TODO: Implement real API call
    // Example: final res = await _dio.get('https://api.metalpriceapi.com/v1/latest?api_key=$_apiKey&base=INR&currencies=${metal.id.toUpperCase()}');
    throw UnimplementedError('Real API not integrated yet');
  }
}
