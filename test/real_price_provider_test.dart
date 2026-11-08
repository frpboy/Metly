import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:metly/models/price_model.dart';
import 'package:metly/services/price_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal hand-rolled adapter: records requests, serves canned responses.
class FakeAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;
  int calls = 0;
  final List<String> paths = [];
  FakeAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<Uint8List>? requestStream, Future<void>? cancelToken) async {
    calls++;
    paths.add(options.path);
    return handler(options);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonBody(Map<String, dynamic> body,
        {Map<String, List<String>> headers = const {}}) =>
    ResponseBody.fromString(jsonEncode(body), 200,
        headers: {
          'content-type': ['application/json'],
          ...headers,
        },
        statusMessage: 'OK');

/// Clock shared by the provider and payload builders in a test.
class FakeClock {
  DateTime now;
  FakeClock(this.now);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

/// OroPocket-shaped combined payload: INR per gram, buy/sell + 3% GST.
/// Gold buy 10000/g -> 100000 per 10g; silver buy 100/g -> 100000 per kg.
Map<String, dynamic> goldPayload(FakeClock clock,
        {num? price = 10000, String? source = 'oropocket'}) =>
    {
      if (source != null) 'source': source,
      'gold': {
        'buyPerGram': price,
        'sellPerGram': 9600,
        'gstPerGram': 300,
      },
      'silver': {
        'buyPerGram': 100,
        'sellPerGram': 95,
        'gstPerGram': 3,
      },
      'asOf': clock.now.toUtc().toIso8601String(),
      'fetchedAt': clock.now.toUtc().toIso8601String(),
      'stale': false,
    };

Future<(RealPriceProvider, FakeAdapter, FakeClock)> makeProvider(
  Future<ResponseBody> Function(RequestOptions) handler, {
  Map<String, Object> prefs = const {},
  DateTime? start,
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final sp = await SharedPreferences.getInstance();
  final adapter = FakeAdapter(handler);
  final dio = Dio()..httpClientAdapter = adapter;
  final clock = FakeClock(start ?? DateTime.now());
  return (RealPriceProvider(sp, dio: dio, clock: clock.call), adapter, clock);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('oropocket path', () {
    test('happy path: converts, marks observed, attributes source', () async {
      final (provider, _, clock) = await makeProvider((_) async => jsonBody(goldPayload(FakeClock(DateTime.now()))));
      final snap = await provider.latest(Metal.gold);
      expect(snap.price, closeTo(100000, 1));
      expect(snap.highIsObserved, isTrue);
      expect(snap.highObservedSince, isNotNull);
      expect(snap.source, 'OroPocket');
      expect(clock, isNotNull);
    });

    test('missing or wrong source/section/price rejected, nothing persisted', () async {
      for (final mutate in [
        (Map<String, dynamic> b) => b..['source'] = 'somewhere-else',
        (Map<String, dynamic> b) => b..remove('source'),
        (Map<String, dynamic> b) => b..remove('gold'),
        (Map<String, dynamic> b) =>
            (b['gold'] as Map).remove('buyPerGram'),
      ]) {
        SharedPreferences.setMockInitialValues({});
        final sp = await SharedPreferences.getInstance();
        final clock = FakeClock(DateTime.now());
        final adapter = FakeAdapter((_) async {
          final body = goldPayload(clock);
          mutate(body);
          return jsonBody(body);
        });
        final provider = RealPriceProvider(sp,
            dio: Dio()..httpClientAdapter = adapter, clock: clock.call);
        await expectLater(provider.latest(Metal.gold), throwsException);
        expect(sp.getDouble('oropocket_gold_observed_high'), isNull,
            reason: 'mutation must not persist');
      }
    });

    test('zero/negative/null/string price rejected, nothing persisted', () async {
      for (final bad in [0, -5, null, 'oops']) {
        SharedPreferences.setMockInitialValues({});
        final sp = await SharedPreferences.getInstance();
        final clock = FakeClock(DateTime.now());
        final adapter = FakeAdapter((_) async => jsonBody({
              ...goldPayload(clock),
              'gold': {
                'buyPerGram': bad,
                'sellPerGram': 9600,
                'gstPerGram': 300,
              },
            }));
        final provider = RealPriceProvider(sp,
            dio: Dio()..httpClientAdapter = adapter, clock: clock.call);
        await expectLater(provider.latest(Metal.gold), throwsException);
        expect(sp.getDouble('oropocket_gold_observed_high'), isNull,
            reason: 'price $bad must not persist');
      }
    });

    test('stale and future timestamps rejected, nothing persisted', () async {
      for (final offset in [
        const Duration(hours: -2),
        const Duration(hours: 1)
      ]) {
        SharedPreferences.setMockInitialValues({});
        final sp = await SharedPreferences.getInstance();
        final clock = FakeClock(DateTime.now());
        final ts = clock.now.toUtc().add(offset);
        final adapter = FakeAdapter((_) async =>
            jsonBody({...goldPayload(clock), 'asOf': ts.toIso8601String()}));
        final provider = RealPriceProvider(sp,
            dio: Dio()..httpClientAdapter = adapter, clock: clock.call);
        await expectLater(provider.latest(Metal.gold), throwsException);
        expect(sp.getDouble('oropocket_gold_observed_high'), isNull);
      }
    });

    test('non-map body rejected', () async {
      final (provider, _, _) = await makeProvider((_) async =>
          ResponseBody.fromString('[1,2,3]', 200,
              headers: {
                'content-type': ['application/json']
              },
              statusMessage: 'OK'));
      await expectLater(provider.latest(Metal.gold), throwsException);
    });

    test('30s cache: second call within TTL does not hit the network', () async {
      final (provider, adapter, clock) =
          await makeProvider((_) async => jsonBody(goldPayload(FakeClock(DateTime.now()))));
      await provider.latest(Metal.gold);
      clock.advance(const Duration(seconds: 10));
      await provider.latest(Metal.gold);
      expect(adapter.calls, 1);
    });

    test('cache expires after TTL when the clock advances', () async {
      final (provider, adapter, clock) = await makeProvider(
          (_) async => jsonBody(goldPayload(FakeClock(DateTime.now()))));
      await provider.latest(Metal.gold);
      clock.advance(const Duration(seconds: 31));
      // payload timestamp is built from real time in the handler, so it
      // stays fresh; only the cache TTL (driven by the injected clock) ages.
      await provider.latest(Metal.gold);
      expect(adapter.calls, 2);
    });

    test('provider max-age is capped at the snapshot freshness deadline',
        () async {
      final clock = FakeClock(DateTime.now());
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final adapter = FakeAdapter((_) async => jsonBody(goldPayload(clock),
          headers: {
            'cache-control': ['public, max-age=3600']
          }));
      final provider = RealPriceProvider(sp,
          dio: Dio()..httpClientAdapter = adapter, clock: clock.call);
      await provider.latest(Metal.gold);
      // 10 minutes in: within max-age, still cached.
      clock.advance(const Duration(minutes: 10));
      await provider.latest(Metal.gold);
      expect(adapter.calls, 1);
      // 16 minutes in: past the 15-minute freshness deadline; even though
      // max-age says an hour, the cache must have expired.
      clock.advance(const Duration(minutes: 6));
      await provider.latest(Metal.gold);
      expect(adapter.calls, 2);
    });

    test('in-flight requests are coalesced', () async {
      final completer = Completer<ResponseBody>();
      final (provider, adapter, _) =
          await makeProvider((_) => completer.future);
      final f1 = provider.latest(Metal.gold);
      final f2 = provider.latest(Metal.gold);
      completer.complete(jsonBody(goldPayload(FakeClock(DateTime.now()))));
      final results = await Future.wait([f1, f2]);
      expect(adapter.calls, 1);
      expect(results[0].price, results[1].price);
    });

    test('network error propagates and clears the in-flight slot', () async {
      var fail = true;
      final (provider, adapter, _) = await makeProvider((_) async {
        if (fail) {
          throw DioException(
              requestOptions: RequestOptions(),
              type: DioExceptionType.receiveTimeout);
        }
        return jsonBody(goldPayload(FakeClock(DateTime.now())));
      });
      await expectLater(provider.latest(Metal.gold), throwsException);
      fail = false;
      final snap = await provider.latest(Metal.gold);
      expect(adapter.calls, 2); // retried, not stuck on the dead future
      expect(snap.price, closeTo(100000, 1));
    });

    test('observed high window start is preserved across refreshes', () async {
      SharedPreferences.setMockInitialValues({
        'oropocket_gold_observed_high': 90000.0,
        'oropocket_gold_observed_high_since': '2026-11-01T00:00:00.000Z',
      });
      final sp = await SharedPreferences.getInstance();
      final adapter =
          FakeAdapter((_) async => jsonBody(goldPayload(FakeClock(DateTime.now()))));
      final provider =
          RealPriceProvider(sp, dio: Dio()..httpClientAdapter = adapter);
      final snap = await provider.latest(Metal.gold);
      expect(snap.recentHigh, closeTo(100000, 1));
      expect(snap.highObservedSince, DateTime.utc(2026, 11, 1));
    });

    test('legacy pre-source-scoped prefs keys are never read or migrated',
        () async {
      SharedPreferences.setMockInitialValues({
        'gold_observed_high': 999999.0,
        'gold_observed_high_since': '2020-01-01T00:00:00.000Z',
      });
      final sp = await SharedPreferences.getInstance();
      final adapter =
          FakeAdapter((_) async => jsonBody(goldPayload(FakeClock(DateTime.now()))));
      final provider =
          RealPriceProvider(sp, dio: Dio()..httpClientAdapter = adapter);
      final snap = await provider.latest(Metal.gold);
      // Unknown-provenance history is discarded: window starts fresh.
      expect(snap.recentHigh, closeTo(100000, 1));
      expect(snap.highObservedSince!.isAfter(DateTime(2021)), isTrue);
      // Legacy keys untouched (not migrated into the scoped namespace).
      expect(sp.getDouble('gold_observed_high'), 999999.0);
    });

    test('a configured worker URL is ignored: /api/prices is always used',
        () async {
      final (provider, adapter, _) = await makeProvider(
          (_) async => jsonBody(goldPayload(FakeClock(DateTime.now()))),
          prefs: {'price_worker_url': 'https://worker.example/prices'});
      final snap = await provider.latest(Metal.gold);
      expect(snap.source, 'OroPocket');
      expect(adapter.paths.single, contains('/api/prices'));
    });

    test('sell rate, GST breakout and purity surface on the snapshot',
        () async {
      final (provider, _, _) = await makeProvider(
          (_) async => jsonBody(goldPayload(FakeClock(DateTime.now()))));
      final snap = await provider.latest(Metal.gold);
      expect(snap.price, closeTo(100000, 1)); // 10000/g x10, ex-GST
      expect(snap.sellPrice, closeTo(96000, 1)); // 9600/g x10
      expect(snap.gstAmount, closeTo(3000, 1)); // 300/g x10, separate
      expect(snap.purity, '24K 99.9%');
      final silver = await provider.latest(Metal.silver);
      expect(silver.price, closeTo(100000, 1)); // 100/g x1000
      expect(silver.purity, '99.9%');
    });

    test('one combined request serves both metals', () async {
      final (provider, adapter, _) = await makeProvider(
          (_) async => jsonBody(goldPayload(FakeClock(DateTime.now()))));
      await provider.latest(Metal.gold);
      await provider.latest(Metal.silver);
      expect(adapter.calls, 1);
    });

    test('server-flagged stale quote at 29min accepted, 31min rejected',
        () async {
      final clock = FakeClock(DateTime.now());
      final at = clock.now.toUtc().subtract(const Duration(minutes: 29));
      final (p1, _, _) = await makeProvider((_) async => jsonBody({
            ...goldPayload(clock),
            'asOf': at.toIso8601String(),
            'stale': true,
          }));
      final snap = await p1.latest(Metal.gold);
      expect(snap.updatedAt, at);
      // 31 minutes: beyond the 30-minute client cap -> rejected even flagged
      SharedPreferences.setMockInitialValues({});
      final sp = await SharedPreferences.getInstance();
      final clock2 = FakeClock(DateTime.now());
      final old31 = clock2.now.toUtc().subtract(const Duration(minutes: 31));
      final adapter = FakeAdapter((_) async => jsonBody({
            ...goldPayload(clock2),
            'asOf': old31.toIso8601String(),
            'stale': true,
          }));
      final p2 = RealPriceProvider(sp,
          dio: Dio()..httpClientAdapter = adapter, clock: clock2.call);
      await expectLater(p2.latest(Metal.gold), throwsException);
      expect(sp.getDouble('oropocket_gold_observed_high'), isNull,
          reason: 'over-cap quote must not persist');
    });

    test('server-flagged stale quote is accepted with its real age',
        () async {
      final clock = FakeClock(DateTime.now());
      final staleTs = clock.now.toUtc().subtract(const Duration(minutes: 20));
      final (provider, _, _) = await makeProvider((_) async => jsonBody({
            ...goldPayload(clock),
            'asOf': staleTs.toIso8601String(),
            'stale': true,
          }));
      final snap = await provider.latest(Metal.gold);
      expect(snap.updatedAt, staleTs);
      expect(snap.isStale(clock.now), isTrue);
    });
  });

}
