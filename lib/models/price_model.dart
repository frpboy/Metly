import '../config/app_config.dart';

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
