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
 * On upstream failure with no cache: 502 with a generic error.
 *
 * Semantics preserved from the provider: buy/sell are INR per gram for 24K
 * 99.9% gold and 99.9% silver; buy EXCLUDES GST; gstPerGram is exactly 3% of buy.
 */

const UPSTREAM = 'https://api.oropocket.com/public/prices';
const TTL_MS = 60_000;
const TIMEOUT_MS = 8_000;
const MAX_CACHE_AGE_MS = 30 * 60_000;
const EDGE_CACHE = 'public, max-age=30, s-maxage=60, stale-while-revalidate=180';

let cache = null;
let inflight = null;

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
  res.setHeader('access-control-allow-origin', '*');
  res.setHeader('access-control-allow-methods', 'GET, OPTIONS');
  res.setHeader('content-type', 'application/json; charset=utf-8');
  res.setHeader('x-content-type-options', 'nosniff');
  res.setHeader('x-frame-options', 'DENY');

  if (req.method === 'OPTIONS') {
    res.setHeader('access-control-allow-headers', 'content-type');
    res.status(204).end?.() || res.status(204).json({});
    return;
  }

  if (req.method !== 'GET') {
    res.setHeader('allow', 'GET, OPTIONS');
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
    const quoteAge = cache ? now - Date.parse(cache.payload.asOf) : Infinity;
    if (cache && quoteAge < MAX_CACHE_AGE_MS) {
      res.setHeader('cache-control', 'no-store');
      res.status(200).json({ ...cache.payload, stale: true });
      return;
    }
    res.setHeader('cache-control', 'no-store');
    console.error('Price upstream fetch error:', e);
    res.status(502).json({ error: 'Upstream price service temporarily unavailable' });
  }
};
