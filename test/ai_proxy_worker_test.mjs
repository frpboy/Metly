// Unit tests for ai-proxy worker v2. Run: node test/ai_proxy_worker_test.mjs
// Mocks: Google JWKS endpoint, Gemini generateContent, and the BUDGET
// Durable Object binding (backed by the real BudgetCounter class).
import assert from "node:assert/strict";
import worker, { BudgetCounter } from "../backend/ai-proxy/worker.js";

const PROJECT_ID = "metly-62916";

// --- RSA keypair + JWT helpers ---
const keyPair = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
);
const jwk = await crypto.subtle.exportKey("jwk", keyPair.publicKey);
jwk.kid = "test-kid";
jwk.alg = "RS256";
jwk.use = "sig";

const b64url = (bytes) =>
    Buffer.from(bytes).toString("base64").replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

async function makeJwt(payloadOverrides = {}) {
    const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", kid: "test-kid" })));
    const payload = b64url(
        new TextEncoder().encode(
            JSON.stringify({
                iss: `https://securetoken.google.com/${PROJECT_ID}`,
                aud: PROJECT_ID,
                exp: Math.floor(Date.now() / 1000) + 600,
                iat: Math.floor(Date.now() / 1000),
                sub: "user-abc-123",
                ...payloadOverrides,
            }),
        ),
    );
    const data = new TextEncoder().encode(`${header}.${payload}`);
    const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", keyPair.privateKey, data);
    return `${header}.${payload}.${b64url(new Uint8Array(sig))}`;
}

// --- Mock fetch: JWKS + Gemini ---
let geminiStatus = 200;
let geminiTokens = 700;
globalThis.fetch = async (url, options) => {
    if (String(url).includes("service_accounts/v1/jwk")) {
        return new Response(JSON.stringify({ keys: [jwk] }), {
            status: 200,
            headers: { "content-type": "application/json", "cache-control": "public, max-age=3600" },
        });
    }
    if (String(url).includes("generativelanguage.googleapis.com")) {
        assert.ok(String(url).includes("gemini-2.5-flash-lite"), "model is pinned");
        if (geminiStatus !== 200) {
            return new Response(JSON.stringify({ error: "quota" }), { status: geminiStatus });
        }
        return new Response(
            JSON.stringify({
                candidates: [{ content: { parts: [{ text: "AI test response" }] } }],
                usageMetadata: { totalTokenCount: geminiTokens },
            }),
            { status: 200, headers: { "content-type": "application/json" } },
        );
    }
    throw new Error("unexpected fetch: " + url);
};

// --- Mock BUDGET binding using the real BudgetCounter class ---
function makeBudgetEnv(overrides = {}) {
    const instances = new Map();
    return {
        GOOGLE_AI_API_KEY: "dummy-gemini-key",
        ...overrides,
        BUDGET: {
            idFromName: (name) => name,
            get: (id) => {
                if (!instances.has(id)) {
                    const store = new Map();
                    const state = {
                        storage: {
                            get: async (k) => store.get(k),
                            put: async (k, v) => void store.set(k, v),
                        },
                    };
                    const counter = new BudgetCounter(state);
                    instances.set(id, {
                        fetch: (urlOrReq, init) =>
                            counter.fetch(urlOrReq instanceof Request ? urlOrReq : new Request(urlOrReq, init)),
                    });
                }
                return instances.get(id);
            },
        },
    };
}

const ctx = { waitUntil: (p) => p };

function chatReq(body, token) {
    const headers = { "content-type": "application/json" };
    if (token) headers.authorization = `Bearer ${token}`;
    return new Request("http://localhost/v1/chat/completions", {
        method: "POST",
        headers,
        body: JSON.stringify(body),
    });
}

const goodBody = {
    model: "ignored-by-server",
    messages: [
        { role: "system", content: "You are helpful." },
        { role: "user", content: "Explain gold signals." },
    ],
    max_tokens: 300,
};

async function run() {
    // 1. OPTIONS preflight
    {
        const res = await worker.fetch(
            new Request("http://localhost/v1/chat/completions", { method: "OPTIONS" }),
            makeBudgetEnv(), ctx,
        );
        assert.equal(res.status, 200);
        assert.equal(res.headers.get("x-content-type-options"), "nosniff");
    }

    // 2. Unknown route -> 404
    {
        const res = await worker.fetch(
            new Request("http://localhost/nope", { method: "POST" }),
            makeBudgetEnv(), ctx,
        );
        assert.equal(res.status, 404);
    }

    // 3. Missing API key -> 500 fail closed
    {
        const env = makeBudgetEnv();
        delete env.GOOGLE_AI_API_KEY;
        const res = await worker.fetch(env.BUDGET && chatReq(goodBody, "x"), env, ctx);
        assert.equal(res.status, 500);
    }

    // 4. No token -> 401
    {
        const res = await worker.fetch(chatReq(goodBody), makeBudgetEnv(), ctx);
        assert.equal(res.status, 401);
    }

    // 5. Wrong audience -> 401
    {
        const bad = await makeJwt({ aud: "other-project" });
        const res = await worker.fetch(chatReq(goodBody, bad), makeBudgetEnv(), ctx);
        assert.equal(res.status, 401);
    }

    // 6. Expired token -> 401
    {
        const bad = await makeJwt({ exp: Math.floor(Date.now() / 1000) - 10 });
        const res = await worker.fetch(chatReq(goodBody, bad), makeBudgetEnv(), ctx);
        assert.equal(res.status, 401);
    }

    // 7. Valid token -> 200, OpenAI-shaped response
    {
        const token = await makeJwt();
        const res = await worker.fetch(chatReq(goodBody, token), makeBudgetEnv(), ctx);
        assert.equal(res.status, 200);
        const json = await res.json();
        assert.equal(json.choices[0].message.content, "AI test response");
    }

    // 8. Oversized payload -> 400
    {
        const token = await makeJwt();
        const big = { messages: [{ role: "user", content: "x".repeat(9000) }] };
        const res = await worker.fetch(chatReq(big, token), makeBudgetEnv(), ctx);
        assert.equal(res.status, 400);
    }

    // 9. Per-user daily request budget -> second request 429
    {
        const token = await makeJwt({ sub: "user-limited" });
        const env = makeBudgetEnv({ PER_USER_DAILY_REQUESTS: 1 });
        const r1 = await worker.fetch(chatReq(goodBody, token), env, ctx);
        assert.equal(r1.status, 200);
        const r2 = await worker.fetch(chatReq(goodBody, token), env, ctx);
        assert.equal(r2.status, 429);
    }

    // 10. Global daily request budget -> 429
    {
        const t1 = await makeJwt({ sub: "user-a" });
        const t2 = await makeJwt({ sub: "user-b" });
        const env = makeBudgetEnv({ GLOBAL_DAILY_REQUESTS: 1 });
        assert.equal((await worker.fetch(chatReq(goodBody, t1), env, ctx)).status, 200);
        assert.equal((await worker.fetch(chatReq(goodBody, t2), env, ctx)).status, 429);
    }

    // 11. Provider 429 -> fail closed 429, no fallback
    {
        geminiStatus = 429;
        const token = await makeJwt({ sub: "user-provider-429" });
        const res = await worker.fetch(chatReq(goodBody, token), makeBudgetEnv(), ctx);
        assert.equal(res.status, 429);
        geminiStatus = 200;
    }

    // 12. Provider 500 -> 502
    {
        geminiStatus = 500;
        const token = await makeJwt({ sub: "user-provider-500" });
        const res = await worker.fetch(chatReq(goodBody, token), makeBudgetEnv(), ctx);
        assert.equal(res.status, 502);
        geminiStatus = 200;
    }

    console.log("All ai-proxy worker v2 tests passed!");
}

run().catch((err) => {
    console.error(err);
    process.exit(1);
});
