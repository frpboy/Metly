import 'package:flutter_test/flutter_test.dart';
import 'package:metly/models/price_model.dart';
import 'package:metly/services/price_service.dart';

void main() {
  group('PriceLogic.validatePrice', () {
    test('accepts finite positive numbers', () {
      expect(PriceLogic.validatePrice(383243.66), 383243.66);
      expect(PriceLogic.validatePrice(1), 1.0);
    });
    test('rejects null, strings, NaN, infinity, zero and negatives', () {
      for (final bad in [null, '383243.66', double.nan, double.infinity, 0, -1, -0.5]) {
        expect(() => PriceLogic.validatePrice(bad), throwsException,
            reason: 'should reject $bad');
      }
    });
  });

  group('PriceLogic.validateUpdatedAt', () {
    final now = DateTime.utc(2026, 11, 8, 12, 0);
    test('accepts a fresh timestamp', () {
      expect(
          PriceLogic.validateUpdatedAt('2026-11-08T11:59:00Z', now: now),
          DateTime.utc(2026, 11, 8, 11, 59));
    });
    test('rejects unparseable and non-string values', () {
      expect(() => PriceLogic.validateUpdatedAt(null, now: now), throwsException);
      expect(() => PriceLogic.validateUpdatedAt(12345, now: now), throwsException);
      expect(() => PriceLogic.validateUpdatedAt('not-a-date', now: now), throwsException);
    });
    test('rejects stale timestamps (>15 min old)', () {
      expect(() => PriceLogic.validateUpdatedAt('2026-11-08T11:44:59Z', now: now),
          throwsException);
    });
    test('rejects future timestamps (>5 min skew)', () {
      expect(() => PriceLogic.validateUpdatedAt('2026-11-08T12:05:01Z', now: now),
          throwsException);
    });
    test('requires an explicit zone designator', () {
      expect(() => PriceLogic.validateUpdatedAt('2026-11-08T11:59:00', now: now),
          throwsException);
      expect(PriceLogic.validateUpdatedAt('2026-11-08T17:29:00+05:30', now: now),
          DateTime.utc(2026, 11, 8, 11, 59));
    });
    test('rejects out-of-range components instead of normalizing them', () {
      for (final bad in [
        '2026-02-30T10:00:00Z',
        '2026-13-01T10:00:00Z',
        '2026-11-08T25:00:00Z',
        '2026-11-08T10:61:00Z',
        '2026-04-31T10:00:00Z',
      ]) {
        expect(() => PriceLogic.validateUpdatedAt(bad, now: now),
            throwsException,
            reason: '$bad must be rejected');
      }
    });
    test('accepts small clock skew', () {
      expect(PriceLogic.validateUpdatedAt('2026-11-08T12:04:00Z', now: now),
          DateTime.utc(2026, 11, 8, 12, 4));
    });
  });

  group('PriceLogic.nextObservedHigh', () {
    final t0 = DateTime.utc(2026, 11, 8, 10, 0);
    final t1 = DateTime.utc(2026, 11, 8, 11, 0);
    test('starts the window on first observation', () {
      final r = PriceLogic.nextObservedHigh(
          storedHigh: null, storedSince: null, price: 100, now: t0);
      expect(r.$1, 100);
      expect(r.$2, t0);
    });
    test('raises the high but keeps the window start', () {
      final r = PriceLogic.nextObservedHigh(
          storedHigh: 100, storedSince: t0, price: 150, now: t1);
      expect(r.$1, 150);
      expect(r.$2, t0);
    });
    test('keeps both on a lower price', () {
      final r = PriceLogic.nextObservedHigh(
          storedHigh: 100, storedSince: t0, price: 90, now: t1);
      expect(r.$1, 100);
      expect(r.$2, t0);
    });
    test('corrupt stored state (missing since) restarts cleanly', () {
      final r = PriceLogic.nextObservedHigh(
          storedHigh: 100, storedSince: null, price: 80, now: t1);
      expect(r.$1, 80);
      expect(r.$2, t1);
    });
    test('NaN/infinity/nonpositive stored highs restart the window', () {
      for (final bad in [double.nan, double.infinity, 0.0, -50.0]) {
        final r = PriceLogic.nextObservedHigh(
            storedHigh: bad, storedSince: t0, price: 80, now: t1);
        expect(r.$1, 80, reason: 'stored $bad must restart');
        expect(r.$2, t1);
      }
    });
    test('future stored window start restarts the window', () {
      final r = PriceLogic.nextObservedHigh(
          storedHigh: 100,
          storedSince: t1.add(const Duration(hours: 1)),
          price: 80,
          now: t1);
      expect(r.$1, 80);
      expect(r.$2, t1);
    });
  });

  group('PriceLogic.ozToDisplay', () {
    test('gold converts per-oz to per-10g', () {
      expect(PriceLogic.ozToDisplay(31.1035 * 1000, Metal.gold),
          closeTo(10000, 1e-6));
    });
    test('silver converts per-oz to per-kg', () {
      expect(PriceLogic.ozToDisplay(31.1035, Metal.silver), closeTo(1000, 1e-6));
    });
  });

  group('evaluateSignal provenance guard', () {
    test('observed-high snapshots always get a paused result', () {
      final s = PriceSnapshot(
        metal: Metal.gold,
        price: 100,
        recentHigh: 200, // 50% drawdown would scream BUY without the guard
        updatedAt: DateTime.utc(2026, 11, 8, 12, 0),
        highIsObserved: true,
        highObservedSince: DateTime.utc(2026, 11, 8, 10, 0),
      );
      final r = evaluateSignal(s, now: DateTime.utc(2026, 11, 8, 12, 0));
      expect(r.signal, Signal.paused);
      expect(r.reason, contains('paused'));
    });
    test('isStale is inclusive of the exact freshness deadline', () {
      final updated = DateTime.utc(2026, 11, 8, 12, 0);
      final s = PriceSnapshot(
          metal: Metal.gold, price: 1, recentHigh: 2, updatedAt: updated);
      expect(s.isStale(updated.add(const Duration(minutes: 14, seconds: 59))),
          isFalse);
      expect(s.isStale(updated.add(const Duration(minutes: 15))), isTrue);
    });
    test('stale snapshot gets a paused result even with a genuine high', () {
      final s = PriceSnapshot(
        metal: Metal.gold,
        price: 95,
        recentHigh: 100,
        updatedAt: DateTime.utc(2026, 11, 8, 11, 30), // 30 min old
      );
      final r = evaluateSignal(s, now: DateTime.utc(2026, 11, 8, 12, 0));
      expect(r.signal, Signal.paused);
      expect(r.reason, contains('stale'));
    });
    test('genuine historical high still evaluates normally', () {
      final s = PriceSnapshot(
        metal: Metal.gold,
        price: 95,
        recentHigh: 100, // 5% drawdown >= 2% threshold
        updatedAt: DateTime.utc(2026, 11, 8, 12, 0),
      );
      final r = evaluateSignal(s, now: DateTime.utc(2026, 11, 8, 12, 0));
      expect(r.signal, Signal.buy);
    });
  });
}
