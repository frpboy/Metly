// Metly AI proxy v2 (source prep; NOT deployed).
//
// Threat model this design addresses:
//   - The old static METLY_PROXY_TOKEN had to live in the APK/web build and was
//     extractable by anyone, after which the proxy was fully open.
//   - v2 authenticates every caller with a per-user Firebase ID token
//     (anonymous sign-in on the metly-62916 project), so abuse is attributable
//     and throttleable per user.
//   - Usage is bounded by a Durable Object counter (single-threaded per object,
//     so the read-modify-write below is atomic and concurrency-safe; state is
//     durable). Ceilings sit BELOW the Gemini free-tier daily quota so the
//     worker stops cleanly before the provider 429s.
//   - Spend: the API key lives on the billing-enabled Gemini project. The
//     request/token ceilings below are the enforceable boundary (atomic,
//     fail closed); they bound usage, and at pinned-model prices that bounds
//     worst-case cost, but they are NOT a guaranteed billed-dollar cap -
//     provider billing math is authoritative. No auto model switch.
//   - Model is pinned in code (gemini-2.5-flash-lite); the client cannot choose.

const FIREBASE_PROJECT_ID = "metly-62916";
const JWKS_URL =
    "https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com";
const MODEL = "gemini-2.5-flash-lite";

// Daily ceilings. Defaults are conservative placeholders; final values come
// from Rahul's approved monthly budget (pending) and are set via env vars at
// deploy time. All four are tunable without a code change.
const DEFAULTS = {
    PER_USER_DAILY_REQUESTS: 10,
    PER_USER_DAILY_TOKENS: 40_000,
    GLOBAL_DAILY_REQUESTS: 450,
    GLOBAL_DAILY_TOKENS: 900_000,
    MAX_MESSAGES: 10,
    MAX_TOTAL_CHARS: 8_000,
    MAX_OUTPUT_TOKENS: 512,
};

function json(body, status, cors) {
    return new Response(JSON.stringify(body), {
        status,
        headers: { "content-type": "application/json", ...cors },
    });
}

// ---- Firebase ID token verification (RS256 against Google's JWKS) ----

let jwksCache = { keys: [], expiresAt: 0 };

async function getJwks() {
    const now = Date.now();
    if (jwksCache.keys.length && now < jwksCache.expiresAt) return jwksCache.keys;
    const resp = await fetch(JWKS_URL);
    if (!resp.ok) throw new Error("jwks fetch failed");
    const maxAge = /max-age=(\d+)/.exec(resp.headers.get("cache-control") || "");
    const body = await resp.json();
    jwksCache = {
        keys: body.keys || [],
        expiresAt: now + (maxAge ? parseInt(maxAge[1], 10) : 3600) * 1000,
    };
    return jwksCache.keys;
}

function b64urlToBytes(s) {
    const b64 = s.replace(/-/g, "+").replace(/_/g, "/");
    const bin = atob(b64);
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
}

// Returns the decoded payload on success, null on any failure (fail closed).
async function verifyFirebaseIdToken(token) {
    try {
        const parts = token.split(".");
        if (parts.length !== 3) return null;
        const header = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[0])));
        if (header.alg !== "RS256" || !header.kid) return null;
        const keys = await getJwks();
        const jwk = keys.find((k) => k.kid === header.kid);
        if (!jwk) return null;
        const key = await crypto.subtle.importKey(
            "jwk",
            jwk,
            { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
            false,
            ["verify"],
        );
        const data = new TextEncoder().encode(`${parts[0]}.${parts[1]}`);
        const ok = await crypto.subtle.verify(
            "RSASSA-PKCS1-v1_5",
            key,
            b64urlToBytes(parts[2]),
            data,
        );
        if (!ok) return null;
        const payload = JSON.parse(new TextDecoder().decode(b64urlToBytes(parts[1])));
        const nowSec = Math.floor(Date.now() / 1000);
        if (payload.iss !== `https://securetoken.google.com/${FIREBASE_PROJECT_ID}`) return null;
        if (payload.aud !== FIREBASE_PROJECT_ID) return null;
        if (typeof payload.exp !== "number" || payload.exp <= nowSec) return null;
        if (typeof payload.iat !== "number" || payload.iat > nowSec + 300) return null;
        if (typeof payload.sub !== "string" || !payload.sub) return null;
        return payload;
    } catch {
        return null;
    }
}

// ---- Durable Object: atomic daily budget counters ----
// One object instance per (scope, UTC day) via idFromName; each instance is
// single-threaded, so check-and-increment cannot race.

export class BudgetCounter {
    constructor(state) {
        this.state = state;
    }

    async fetch(req) {
        const { key, addRequests = 0, addTokens = 0, maxRequests, maxTokens, enforce = true } =
            await req.json();
        const day = new Date().toISOString().slice(0, 10);
        let rec = (await this.state.storage.get(key)) || { day, requests: 0, tokens: 0 };
        if (rec.day !== day) rec = { day, requests: 0, tokens: 0 };
        const nextRequests = rec.requests + addRequests;
        const nextTokens = rec.tokens + addTokens;
        if (enforce && (nextRequests > maxRequests || nextTokens > maxTokens)) {
            return Response.json({ allowed: false, used: rec });
        }
        rec.requests = nextRequests;
        rec.tokens = nextTokens;
        await this.state.storage.put(key, rec);
        return Response.json({ allowed: true, used: rec });
    }
}

async function checkBudget(env, scope, addRequests, addTokens, maxRequests, maxTokens, enforce = true) {
    const day = new Date().toISOString().slice(0, 10);
    const id = env.BUDGET.idFromName(`${scope}:${day}`);
    const stub = env.BUDGET.get(id);
    const resp = await stub.fetch("https://budget.internal/check", {
        method: "POST",
        body: JSON.stringify({ key: scope, addRequests, addTokens, maxRequests, maxTokens, enforce }),
    });
    return resp.json();
}

// ---- Request shaping ----

function capMessages(messages) {
    if (!Array.isArray(messages) || messages.length === 0 || messages.length > DEFAULTS.MAX_MESSAGES) {
        return null;
    }
    let total = 0;
    for (const m of messages) {
        if (!m || typeof m.content !== "string" || !["system", "user", "assistant"].includes(m.role)) {
            return null;
        }
        total += m.content.length;
    }
    if (total === 0 || total > DEFAULTS.MAX_TOTAL_CHARS) return null;
    return { messages, totalChars: total };
}

export default {
    async fetch(req, env, ctx) {
        const cors = {
            "access-control-allow-origin": env.CORS_ALLOW_ORIGIN || "*",
            "access-control-allow-headers": "authorization,content-type",
            "access-control-allow-methods": "GET,POST,OPTIONS",
            "x-content-type-options": "nosniff",
        };
        if (req.method === "OPTIONS") {
            return new Response(null, { headers: cors });
        }

        const url = new URL(req.url);
        if (url.pathname !== "/v1/chat/completions") {
            return json({ error: "Not found" }, 404, cors);
        }

        // Fail closed if the worker is not fully configured.
        if (!env.GOOGLE_AI_API_KEY || !env.BUDGET) {
            return json({ error: "Proxy not configured" }, 500, cors);
        }

        // Per-user auth: Firebase ID token (anonymous sign-in in the app).
        const auth = req.headers.get("authorization") || "";
        const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
        const claims = token ? await verifyFirebaseIdToken(token) : null;
        if (!claims) {
            return json({ error: "Unauthorized" }, 401, cors);
        }
        const uid = claims.sub;

        const body = await req.json().catch(() => null);
        const shaped = body && capMessages(body.messages);
        if (!shaped) {
            return json({ error: "Invalid request" }, 400, cors);
        }
        const maxOutput = Math.min(
            typeof body.max_tokens === "number" ? body.max_tokens : DEFAULTS.MAX_OUTPUT_TOKENS,
            DEFAULTS.MAX_OUTPUT_TOKENS,
        );

        // Conservative pre-call reservation: ~4 chars/token input + full output.
        const reserved = Math.ceil(shaped.totalChars / 4) + maxOutput;
        const limits = {
            userReq: env.PER_USER_DAILY_REQUESTS ?? DEFAULTS.PER_USER_DAILY_REQUESTS,
            userTok: env.PER_USER_DAILY_TOKENS ?? DEFAULTS.PER_USER_DAILY_TOKENS,
            globReq: env.GLOBAL_DAILY_REQUESTS ?? DEFAULTS.GLOBAL_DAILY_REQUESTS,
            globTok: env.GLOBAL_DAILY_TOKENS ?? DEFAULTS.GLOBAL_DAILY_TOKENS,
        };
        try {
            const user = await checkBudget(env, `u:${uid}`, 1, reserved, limits.userReq, limits.userTok);
            if (!user.allowed) {
                return json({ error: "Daily AI limit reached for your account" }, 429, cors);
            }
            const global = await checkBudget(env, "global", 1, reserved, limits.globReq, limits.globTok);
            if (!global.allowed) {
                return json({ error: "Metly AI is at today's capacity, try again tomorrow" }, 429, cors);
            }
        } catch (e) {
            console.error("budget check failed:", e);
            return json({ error: "Service unavailable" }, 503, cors); // fail closed
        }

        // Translate OpenAI-style messages to Gemini generateContent.
        const systemParts = shaped.messages.filter((m) => m.role === "system");
        const contents = shaped.messages
            .filter((m) => m.role !== "system")
            .map((m) => ({
                role: m.role === "assistant" ? "model" : "user",
                parts: [{ text: m.content }],
            }));
        const geminiBody = {
            contents,
            generationConfig: { temperature: 0.3, maxOutputTokens: maxOutput },
        };
        if (systemParts.length) {
            geminiBody.systemInstruction = {
                parts: [{ text: systemParts.map((m) => m.content).join("\n") }],
            };
        }

        let resp;
        try {
            resp = await fetch(
                `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent`,
                {
                    method: "POST",
                    headers: {
                        "content-type": "application/json",
                        "x-goog-api-key": env.GOOGLE_AI_API_KEY,
                    },
                    body: JSON.stringify(geminiBody),
                },
            );
        } catch {
            return json({ error: "AI provider unreachable" }, 502, cors);
        }

        if (!resp.ok) {
            // Provider quota/budget exhaustion or provider error: fail closed,
            // no fallback model and no paid upgrade path.
            const status = resp.status === 429 ? 429 : 502;
            return json(
                { error: status === 429 ? "Metly AI quota exhausted, try again tomorrow" : "AI provider error" },
                status,
                cors,
            );
        }

        const data = await resp.json().catch(() => null);
        const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
        if (typeof text !== "string") {
            return json({ error: "AI provider error" }, 502, cors);
        }

        // Reconcile actual usage against the reservation (never negative).
        const actual = data?.usageMetadata?.totalTokenCount;
        if (typeof actual === "number" && actual > reserved) {
            const delta = actual - reserved;
            ctx?.waitUntil?.(Promise.all([
                checkBudget(env, `u:${uid}`, 0, delta, Infinity, Infinity, false),
                checkBudget(env, "global", 0, delta, Infinity, Infinity, false),
            ]).catch(() => {}));
        }

        return json({ choices: [{ message: { content: text } }] }, 200, cors);
    },
};
