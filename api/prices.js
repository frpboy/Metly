/* Vercel serverless function: bounded server-side cache in front of the
 * OroPocket free public prices endpoint, per the provider's own guidance
 * ("poll from your server, cache it; do not call directly from a browser
 * for every visitor"). Free tier compatible, zero dependencies (Node 18+
 * global fetch).
 *
 * Contract (200):
 *   {
 *     source: 'oropocket',
 *     gold:   { buyPerGram, sellPerGram, gstPerGram },
 *     silver: { buyPerGram, sellPerGram, gstPerGram },
 *     asOf: '<upstream ISO-8601 UTC timestamp>',
 *     fetchedAt: '<server ISO-8601 UTC timestamp>',
 *     stale: false
 *   }
 * On upstream failure with a cached value: same shape with stale: true and
 * the original asOf, so clients can apply their own freshness rules.
 * On upstream failure with no cache: 502 { error }.
 *
 * Semantics preserved from the provider (verified against their docs and
 * live responses): buy/sell are INR per gram for 24K 99.9% gold and 99.9%
 * silver; buy EXCLUDES GST; gstPerGram is exactly 3% of buy.
 */

const UPSTREAM = 'https://api.oropocket.com/public/prices';
const TTL_MS = 60_000;          // provider refreshes ~2-2.5 min; never poll faster
const TIMEOUT_MS = 8_000;
const MAX_CACHE_AGE_MS = 30 * 60_000; // never serve a QUOTE older than 30 min (by its asOf)
// Browsers revalidate quickly; the Vercel edge cache absorbs concurrent
// visitors across instances so upstream quota (10 req/min/IP) is preserved.
const EDGE_CACHE = 'public, max-age=30, s-maxage=60, stale-while-revalidate=180';

let cache = null; // { payload, fetchedAtMs }
let inflight = null; // coalesces concurrent cold misses to ONE upstream call

// Contract enforcement: the provider documents currency/unit as "always INR
// and gram today - do not hardcode the assumption", so anything else (or a
// missing field) is rejected rather than silently mislabelled.
function isValidQuote(d) {
  const ok = (m) =>
    m && Number.isFinite(m.buy) && m.buy > 0 &&
    Number.isFinite(m.sell) && m.sell > 0 &&
    Number.isFinite(m.gst) && m.gst >= 0 &&
    m.currency === 'INR' && m.unit === 'gram';
  return d && d.data && ok(d.data.gold) && ok(d.data.silver) &&
    typeof d.data.timestamp === 'string' &&
    !Number.isNaN(Date.parse(d.data.timestamp));
}

async function fetchUpstream() {
  const res = await fetch(UPSTREAM, {
    signal: AbortSignal.timeout(TIMEOUT_MS),
    headers: { accept: 'application/json' },
  });
  if (res.status === 429) throw new Error('upstream rate limited (429)');
  if (!res.ok) throw new Error('upstream HTTP ' + res.status);
  const body = await res.json();
  if (!isValidQuote(body)) throw new Error('unexpected upstream shape');
  const now = new Date();
  return {
    source: 'oropocket',
    gold: {
      buyPerGram: body.data.gold.buy,
      sellPerGram: body.data.gold.sell,
      gstPerGram: body.data.gold.gst,
    },
    silver: {
      buyPerGram: body.data.silver.buy,
      sellPerGram: body.data.silver.sell,
      gstPerGram: body.data.silver.gst,
    },
    asOf: body.data.timestamp,
    fetchedAt: now.toISOString(),
    stale: false,
  };
}

module.exports = async (req, res) => {
  // Defensive security headers preventing MIME sniffing, framing, and referrer leakage
  res.setHeader('access-control-allow-origin', '*');
  res.setHeader('access-control-allow-methods', 'GET,OPTIONS');
  res.setHeader('content-type', 'application/json; charset=utf-8');
  res.setHeader('x-content-type-options', 'nosniff');
  res.setHeader('x-frame-options', 'DENY');
  res.setHeader('referrer-policy', 'no-referrer');
  if (req.method === 'OPTIONS') {
    res.status(204).end();
    return;
  }
  if (req.method !== 'GET') {
    res.status(405).json({ error: 'method not allowed' });
    return;
  }
  const now = Date.now();
  if (cache && now - cache.fetchedAtMs < TTL_MS) {
    res.setHeader('cache-control', EDGE_CACHE);
    res.status(200).json(cache.payload);
    return;
  }
  try {
    if (!inflight) {
      inflight = fetchUpstream().then((payload) => {
        cache = { payload, fetchedAtMs: Date.now() };
        return payload;
      }).finally(() => {
        inflight = null;
      });
    }
    const payload = await inflight;
    res.setHeader('cache-control', EDGE_CACHE);
    res.status(200).json(payload);
  } catch (e) {
    // Stale-serving is bounded by the QUOTE's own age (asOf), not by when we
    // happened to fetch it: an already-old quote never gets a fresh 30 min.
    const quoteAge = cache ? now - Date.parse(cache.payload.asOf) : Infinity;
    if (cache && quoteAge < MAX_CACHE_AGE_MS) {
      res.setHeader('cache-control', 'no-store');
      res.status(200).json({ ...cache.payload, stale: true });
      return;
    }
    res.setHeader('cache-control', 'no-store');
    res.status(502).json({ error: String(e && e.message ? e.message : e) });
  }
};
