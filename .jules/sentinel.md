# Sentinel's Security Journal

## 2026-10-28 - Timing-safe Proxy Token Verification in Edge Workers
**Vulnerability:** In `backend/ai-proxy/worker.js`, bearer token authentication was checked using standard JavaScript equality (`bearer !== env.METLY_PROXY_TOKEN`). Because string comparison short-circuits on the first mismatched byte/character, attackers could perform statistical timing measurements over many HTTP requests to iteratively guess the secret `METLY_PROXY_TOKEN`.
**Learning:** Cloudflare Workers and Node runtimes support Web Cryptography APIs and constant-time operations (`crypto.timingSafeEqual`). When comparing sensitive secrets, raw string equality should never be used; fixed-length byte buffer XOR comparisons or `crypto.timingSafeEqual` prevent side-channel timing leaks.
**Prevention:** Always compare secrets, tokens, signatures, and hashes using constant-time algorithms (`timingSafeEqual`) and verify buffer lengths carefully before comparisons.
