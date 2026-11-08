import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
  /// All prices come from the app's own same-origin `/api/prices` route, a
  /// bounded server-side cache in front of OroPocket's free public endpoint
  /// (Indian retail: 24K 99.9% gold and 99.9% silver, INR per gram, buy and
  /// sell, 3% GST broken out). Cache, in-flight requests and persisted
  /// observed highs are scoped to the source identity captured at request
  /// start, so a mid-flight settings change can never contaminate history.
  static const String _sourceKey = 'oropocket';

  /// Same-origin server cache (Vercel serverless function) on web, where the
  /// app is served from the same deployment as the function. Non-web builds
  /// (Android etc.) have no same origin - Uri.base is file:/// there - so
  /// they call the production deployment's function explicitly.
  static final String _endpoint = kIsWeb
      ? Uri.base.resolve('/api/prices').toString()
      : 'https://metly-gold.vercel.app/api/prices';
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

  // One request serves BOTH metals; the combined in-flight future is shared
  // so a gold+silver dashboard refresh fans out to a single /api/prices hit.
  Future<void>? _combinedInflight;

  Future<PriceSnapshot> _fetch(Metal metal, String src) async {
    _combinedInflight ??= _fetchCombined(src).whenComplete(() {
      _combinedInflight = null;
    });
    await _combinedInflight;
    final cached = _cache['$src:${metal.id}'];
    if (cached == null) {
      throw Exception('Combined price payload missing ${metal.id}');
    }
    return cached.$1;
  }

  Future<void> _fetchCombined(String src) async {
    final res = await _dio.get(_endpoint);
    final data = res.data;
    if (data is! Map) throw Exception('Unexpected response shape');
    final serverStale = data['stale'] == true;
    for (final metal in Metal.values) {
      final snap = _parseOroPocket(metal, data, src, serverStale: serverStale);
      _cache['$src:${metal.id}'] = (
        snap,
        _earliest([
          _now().add(_ttlFromHeaders(res.headers)),
          snap.freshUntil,
        ])
      );
    }
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

  PriceSnapshot _parseOroPocket(Metal metal, Map data, String src,
      {bool serverStale = false}) {
    // Source metadata is required, not optional: a response that cannot
    // prove it is the OroPocket payload for the requested metal is rejected.
    if (data['source'] != 'oropocket') {
      throw Exception('Missing or unexpected source in response');
    }
    final section = data[metal.id];
    if (section is! Map) {
      throw Exception('Missing ${metal.id} section in response');
    }
    // Validate everything before touching the persisted observed high, so a
    // bad payload can never poison history.
    final buyPerGram = PriceLogic.validatePrice(section['buyPerGram']);
    final sellPerGram = PriceLogic.validatePrice(section['sellPerGram']);
    final gstPerGram = section['gstPerGram'] is num
        ? (section['gstPerGram'] as num).toDouble()
        : throw Exception('Missing or non-numeric gstPerGram');
    if (!gstPerGram.isFinite || gstPerGram < 0) {
      throw Exception('Invalid gstPerGram value');
    }
    // A quote the server flags as stale may be older than the normal 15-min
    // window; accept its real age and let the UI staleness machinery label
    // it, rather than rejecting last-known data outright.
    final updatedAt = PriceLogic.validateUpdatedAt(data['asOf'],
        now: _now(), allowStale: serverStale);
    final price = PriceLogic.gramToDisplay(buyPerGram, metal);
    final high = _rollingHigh(metal, price, src);
    return PriceSnapshot(
      metal: metal,
      price: price,
      sellPrice: PriceLogic.gramToDisplay(sellPerGram, metal),
      gstAmount: PriceLogic.gramToDisplay(gstPerGram, metal),
      purity: metal == Metal.gold ? '24K 99.9%' : '99.9%',
      recentHigh: high.$1,
      highIsObserved: true,
      highObservedSince: high.$2,
      updatedAt: updatedAt,
      source: 'OroPocket',
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

  /// Cap for server-flagged stale quotes, aligned with the server's own
  /// 30-minute stale-serving bound: a quote older than this is rejected
  /// outright even when the server (or a future misbehaving proxy) flags
  /// it as merely stale.
  static const Duration maxStaleAge = Duration(minutes: 30);

  /// Convert an INR-per-troy-ounce spot price to the app's display units
  /// (gold: INR/10g, silver: INR/kg).
  static double ozToDisplay(double pricePerOz, Metal metal) =>
      metal == Metal.gold
          ? pricePerOz / troyOzGrams * 10
          : pricePerOz / troyOzGrams * 1000;

  /// Convert an INR-per-gram retail price to the app's display units
  /// (gold: INR/10g, silver: INR/kg). Plain unit arithmetic, not a rate
  /// conversion.
  static double gramToDisplay(double pricePerGram, Metal metal) =>
      metal == Metal.gold ? pricePerGram * 10 : pricePerGram * 1000;

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
  static DateTime validateUpdatedAt(dynamic raw,
      {DateTime? now, bool allowStale = false}) {
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
    if (!allowStale && ts.isBefore(ref.subtract(maxPriceAge))) {
      throw Exception('Price data stale');
    }
    if (allowStale && ts.isBefore(ref.subtract(maxStaleAge))) {
      throw Exception('Stale quote beyond 30-minute cap rejected');
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
