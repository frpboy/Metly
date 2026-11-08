import 'dart:async';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/price_model.dart';

abstract class PriceProvider {
  Future<PriceSnapshot> latest(Metal metal);
}

class RealPriceProvider implements PriceProvider {
  final Dio _dio;
  final SharedPreferences prefs;
  final DateTime Function() _now;

  RealPriceProvider(this.prefs, {Dio? dio, DateTime Function()? clock})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
            )),
        _now = clock ?? DateTime.now;

  /// Custom price-worker endpoints are DISABLED for this release: an
  /// arbitrary configured URL cannot prove schema, currency/unit semantics
  /// or historical-high provenance, and the repo's own worker was a jitter
  /// simulator (now quarantined). A legacy saved URL is simply never read.
  /// All prices come from gold-api.com. Cache, in-flight requests and
  /// persisted observed highs are scoped to the source identity captured at
  /// request start, so a mid-flight settings change can never contaminate
  /// history.
  static const String _sourceKey = 'gold-api';

  static const String _goldApiBase = 'https://api.gold-api.com/price';
  static const Duration _cacheTtl = Duration(seconds: 30);

  // Short in-memory cache: providers ask clients not to poll faster than
  // ~30s, and a refresh tap should not fan out duplicate requests. A longer
  // provider Cache-Control max-age wins, but every entry is capped at the
  // snapshot's own freshness deadline so a cached value can never outlive
  // the age the UI considers live. In-flight requests are coalesced.
  final Map<String, (PriceSnapshot, DateTime)> _cache = {};
  final Map<String, Future<PriceSnapshot>> _inflight = {};

  @override
  Future<PriceSnapshot> latest(Metal metal) {
    const src = _sourceKey;
    final key = '$src:${metal.id}';
    final cached = _cache[key];
    if (cached != null && _now().isBefore(cached.$2)) {
      return Future.value(cached.$1);
    }
    final running = _inflight[key];
    if (running != null) return running;
    final future = _fetch(metal, src);
    _inflight[key] = future;
    unawaited(future.then((_) {
      _inflight.remove(key);
    }).catchError((_) {
      _inflight.remove(key);
    }));
    return future;
  }

  Future<PriceSnapshot> _fetch(Metal metal, String src) async {
    final res = await _dio.get(
        '$_goldApiBase/${metal == Metal.gold ? 'XAU' : 'XAG'}/INR');
    final snap = _parseGoldApi(metal, res.data, src);
    _cache['$src:${metal.id}'] = (
      snap,
      _earliest([
        _now().add(_ttlFromHeaders(res.headers)),
        snap.freshUntil,
      ])
    );
    return snap;
  }

  static DateTime _earliest(List<DateTime> times) =>
      times.reduce((a, b) => a.isBefore(b) ? a : b);

  static Duration _ttlFromHeaders(Headers headers) {
    final cc = headers.value('cache-control') ?? '';
    final m = RegExp(r'max-age=(\d+)').firstMatch(cc);
    if (m != null) {
      final secs = int.tryParse(m.group(1)!) ?? 0;
      if (secs > _cacheTtl.inSeconds) return Duration(seconds: secs);
    }
    return _cacheTtl;
  }

  PriceSnapshot _parseGoldApi(Metal metal, dynamic data, String src) {
    if (data is! Map) throw Exception('Unexpected response shape');
    final expectedSymbol = metal == Metal.gold ? 'XAU' : 'XAG';
    // Source metadata is required, not optional: a response that cannot
    // prove it is the requested metal in INR is rejected.
    if (data['symbol'] != expectedSymbol) {
      throw Exception('Missing or unexpected symbol in response');
    }
    if (data['currency'] != 'INR') {
      throw Exception('Missing or unexpected currency in response');
    }
    // Validate everything before touching the persisted observed high, so a
    // bad payload can never poison history.
    final pricePerOz = PriceLogic.validatePrice(data['price']);
    final updatedAt =
        PriceLogic.validateUpdatedAt(data['updatedAt'], now: _now());
    final price = PriceLogic.ozToDisplay(pricePerOz, metal);
    final high = _rollingHigh(metal, price, src);
    return PriceSnapshot(
      metal: metal,
      price: price,
      recentHigh: high.$1,
      highIsObserved: true,
      highObservedSince: high.$2,
      updatedAt: updatedAt,
      source: 'gold-api.com',
    );
  }

  (double, DateTime) _rollingHigh(Metal metal, double price, String src) {
    final keyV = '${src}_${metal.id}_observed_high';
    final keyS = '${src}_${metal.id}_observed_high_since';
    // Pre-source-scoped keys are of unknown provenance: never read, never
    // migrated; the window simply starts fresh under the scoped key.
    final storedV = prefs.getDouble(keyV);
    final storedS = prefs.getString(keyS);
    final result = PriceLogic.nextObservedHigh(
      storedHigh: storedV,
      storedSince: storedS != null ? DateTime.tryParse(storedS) : null,
      price: price,
      now: _now(),
    );
    // Persistence is best-effort: a failed write must not break pricing.
    unawaited(prefs.setDouble(keyV, result.$1).catchError((_) => false));
    unawaited(
        prefs.setString(keyS, result.$2.toIso8601String()).catchError((_) => false));
    return result;
  }
}

/// Pure helpers kept separate for unit testing.
class PriceLogic {
  static const double troyOzGrams = 31.1035;
  static const Duration maxPriceAge = Duration(minutes: 15);
  static const Duration maxFutureSkew = Duration(minutes: 5);

  /// Convert an INR-per-troy-ounce spot price to the app's display units
  /// (gold: INR/10g, silver: INR/kg).
  static double ozToDisplay(double pricePerOz, Metal metal) =>
      metal == Metal.gold
          ? pricePerOz / troyOzGrams * 10
          : pricePerOz / troyOzGrams * 1000;

  /// Validate a raw price field: must be a finite, positive number.
  static double validatePrice(dynamic raw) {
    if (raw is! num) throw Exception('Missing or non-numeric price');
    final v = raw.toDouble();
    if (!v.isFinite || v <= 0) throw Exception('Invalid price value');
    return v;
  }

  // ISO-8601 with an explicit zone designator (Z or ±hh:mm); offsets are
  // required so a naive local-looking string can never be misread as UTC.
  static final RegExp _tsPattern = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})(?::(\d{2}))?(?:\.\d+)?(Z|[+-]\d{2}:?\d{2})$');

  /// Parse and sanity-check a provider timestamp: explicit zone required,
  /// out-of-range components rejected (never normalized into a different
  /// valid date), not stale, not in the future beyond small clock skew.
  static DateTime validateUpdatedAt(dynamic raw, {DateTime? now}) {
    if (raw is! String) throw Exception('Missing updatedAt');
    final text = raw.trim();
    final m = _tsPattern.firstMatch(text);
    if (m == null) {
      throw Exception('updatedAt must be ISO-8601 with an explicit zone');
    }
    final year = int.parse(m.group(1)!);
    final month = int.parse(m.group(2)!);
    final day = int.parse(m.group(3)!);
    final hour = int.parse(m.group(4)!);
    final minute = int.parse(m.group(5)!);
    final second = m.group(6) != null ? int.parse(m.group(6)!) : 0;
    if (month < 1 || month > 12) throw Exception('Invalid month');
    if (hour > 23 || minute > 59 || second > 59) {
      throw Exception('Invalid time');
    }
    // Day must exist in the given month (DateTime(y, m+1, 0) = last day).
    final daysInMonth = DateTime(year, month + 1, 0).day;
    if (day < 1 || day > daysInMonth) throw Exception('Invalid day');
    final ts = DateTime.tryParse(text);
    if (ts == null) throw Exception('Unparseable updatedAt');
    final ref = now ?? DateTime.now();
    if (ts.isAfter(ref.add(maxFutureSkew))) {
      throw Exception('Price timestamp in the future');
    }
    if (ts.isBefore(ref.subtract(maxPriceAge))) {
      throw Exception('Price data stale');
    }
    return ts;
  }

  /// Rolling high of observed prices. The window start ([storedSince]) is
  /// kept once set; a higher price only raises the high, never resets the
  /// observation window. Corrupt persisted state (non-finite, non-positive
  /// or future-dated) restarts the window instead of poisoning it.
  static (double, DateTime) nextObservedHigh({
    required double? storedHigh,
    required DateTime? storedSince,
    required double price,
    required DateTime now,
  }) {
    final highOk =
        storedHigh != null && storedHigh.isFinite && storedHigh > 0;
    final sinceOk = storedSince != null &&
        !storedSince.isAfter(now.add(maxFutureSkew));
    if (!highOk || !sinceOk) return (price, now);
    if (price > storedHigh) return (price, storedSince);
    return (storedHigh, storedSince);
  }
}
