import 'package:flutter_test/flutter_test.dart';
import 'package:metly/models/price_model.dart';
import 'package:metly/services/price_service.dart';

class TestPriceProvider implements PriceProvider {
  int calls = 0;
  @override
  Future<PriceSnapshot> latest(Metal metal) async {
    calls++;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    return PriceSnapshot(
      metal: metal,
      price: metal == Metal.gold ? 130000 : 170000,
      recentHigh: metal == Metal.gold ? 135000 : 180000,
      updatedAt: DateTime.now(),
    );
  }
}

void main() {
  test(
      'Future.wait fetches gold and silver concurrently in ~50ms instead of ~100ms',
      () async {
    final provider = TestPriceProvider();
    final stopwatch = Stopwatch()..start();

    final results = await Future.wait([
      provider.latest(Metal.gold),
      provider.latest(Metal.silver),
    ]);

    stopwatch.stop();

    expect(results.length, 2);
    expect(results[0].metal, Metal.gold);
    expect(results[1].metal, Metal.silver);
    expect(provider.calls, 2);
    // Since calls run concurrently, elapsed time should be close to 50ms (well under 95ms)
    expect(stopwatch.elapsedMilliseconds, lessThan(95));
  });
}
