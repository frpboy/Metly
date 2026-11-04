// Constant-time string comparison preventing timing side-channel attacks on tokens
function timingSafeEqual(a, b) {
    if (typeof a !== "string" || typeof b !== "string") return false;
    const enc = new TextEncoder();
    const bufA = enc.encode(a), bufB = enc.encode(b);
    if (bufA.byteLength !== bufB.byteLength) return false;
    if (typeof crypto !== "undefined" && typeof crypto.timingSafeEqual === "function") {
        return crypto.timingSafeEqual(bufA, bufB);
    }
    let mismatch = 0;
    for (let i = 0; i < bufA.byteLength; i++) mismatch |= bufA[i] ^ bufB[i];
    return mismatch === 0;
}

export default {
    async fetch(req, env, ctx) {
        // CORS and security headers
        const cors = {
            "access-control-allow-origin": env.CORS_ALLOW_ORIGIN || "*",
            "access-control-allow-headers": "authorization,content-type",
            "access-control-allow-methods": "GET,POST,OPTIONS",
            "x-content-type-options": "nosniff",
        };
        if (req.method === "OPTIONS") {
            return new Response(null, { headers: cors });
        }

        // only allow our single endpoint
        const url = new URL(req.url);
        if (url.pathname !== "/v1/chat/completions") {
            return new Response(JSON.stringify({ error: "Not found" }), {
                status: 404,
                headers: { "content-type": "application/json", ...cors },
            });
        }

        // auth: require proxy token header using timing-safe comparison
        const incomingToken = req.headers.get("authorization") || "";
        const bearer = incomingToken.startsWith("Bearer ") ? incomingToken.slice(7) : incomingToken;
        if (!env.METLY_PROXY_TOKEN) {
            return new Response(JSON.stringify({ error: "Proxy not configured" }), {
                status: 500,
                headers: { "content-type": "application/json", ...cors },
            });
        }
        if (!timingSafeEqual(bearer, env.METLY_PROXY_TOKEN)) {
            return new Response(JSON.stringify({ error: "Unauthorized" }), {
                status: 401,
                headers: { "content-type": "application/json", ...cors },
            });
        }

        // forward to OpenRouter
        const body = await req.json().catch(() => null);
        if (!body) {
            return new Response(JSON.stringify({ error: "Invalid JSON" }), {
                status: 400,
                headers: { "content-type": "application/json", ...cors },
            });
        }

        const resp = await fetch("https://openrouter.ai/api/v1/chat/completions", {
            method: "POST",
            headers: {
                "content-type": "application/json",
                "authorization": `Bearer ${env.OPENROUTER_API_KEY}`,
                "x-title": "Metly",
                "http-referer": "https://metly.app",
            },
            body: JSON.stringify(body),
        });

        const text = await resp.text();
        return new Response(text, {
            status: resp.status,
            headers: {
                "content-type": resp.headers.get("content-type") || "application/json",
                ...cors,
            },
        });
    },
};
