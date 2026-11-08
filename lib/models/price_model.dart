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

  /// True when [recentHigh] is a rolling high of prices observed by this
  /// device since [highObservedSince], not a genuine market historical high.
  final bool highIsObserved;
  final DateTime? highObservedSince;

  /// Human-readable name of the data source, shown in the UI.
  final String source;
  PriceSnapshot(
      {required this.metal,
      required this.price,
      required this.recentHigh,
      required this.updatedAt,
      this.highIsObserved = false,
      this.highObservedSince,
      this.source = 'gold-api.com'});
  double get drawdownPct => ((recentHigh - price) / recentHigh * 100);
  String get unit => metal.unit;

  /// Newest instant at which this snapshot may still be shown as live.
  DateTime get freshUntil => updatedAt.add(const Duration(minutes: 15));

  /// True once the snapshot reaches the end of the freshness window
  /// (inclusive: at the exact deadline the data is already stale).
  bool isStale(DateTime now) => !now.isBefore(freshUntil);
}

enum Signal { buy, wait, paused }

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
  // Provenance guard: a rolling observed high is not a genuine historical
  // high, so trading signals stay paused no matter who calls this.
  if (s.highIsObserved) {
    return const SignalResult(Signal.paused,
        'Signals paused: only an observed rolling high is available');
  }
  if (s.isStale(now)) {
    return const SignalResult(
        Signal.paused, 'Signals paused: price data is stale - refresh');
  }
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
