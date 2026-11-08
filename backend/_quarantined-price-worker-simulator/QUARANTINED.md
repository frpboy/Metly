# QUARANTINED: simulated price worker (not a real data source)

`worker.js` in this directory returns random jitter around hardcoded prices
with fixed "recent highs". It is a UI demo simulator, not a market data
source.

It must NOT be deployed or configured as the app's price worker. The app's
price layer (lib/services/price_service.dart) treats every custom worker as
unverified and shows observed-only prices with trading signals paused;
deploying this simulator as a "real" feed previously caused simulated prices
to be displayed as live market data.

Kept for historical reference only. Do not reference from docs, deploy
scripts, or settings.
