import assert from "node:assert/strict";
import worker from "../backend/ai-proxy/worker.js";

async function runTests() {
  const env = {
    METLY_PROXY_TOKEN: "super-secret-token-12345",
    OPENROUTER_API_KEY: "openrouter-dummy-key",
  };

  // Mock global fetch for forward requests
  globalThis.fetch = async (url, options) => {
    return new Response(JSON.stringify({ choices: [{ message: { content: "AI test response" } }] }), {
      status: 200,
      headers: { "content-type": "application/json" },
    });
  };

  // Test 1: OPTIONS CORS preflight returns correct security & CORS headers
  {
    const req = new Request("http://localhost/v1/chat/completions", {
      method: "OPTIONS",
    });
    const res = await worker.fetch(req, env, {});
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("x-content-type-options"), "nosniff");
    assert.equal(res.headers.get("access-control-allow-methods"), "GET,POST,OPTIONS");
  }

  // Test 2: Invalid route returns 404
  {
    const req = new Request("http://localhost/v1/unknown", {
      method: "POST",
    });
    const res = await worker.fetch(req, env, {});
    assert.equal(res.status, 404);
    assert.equal(res.headers.get("x-content-type-options"), "nosniff");
  }

  // Test 3: Missing authorization header returns 401
  {
    const req = new Request("http://localhost/v1/chat/completions", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ model: "test" }),
    });
    const res = await worker.fetch(req, env, {});
    assert.equal(res.status, 401);
    const body = await res.json();
    assert.equal(body.error, "Unauthorized");
    assert.equal(res.headers.get("x-content-type-options"), "nosniff");
  }

  // Test 4: Mismatched token length returns 401
  {
    const req = new Request("http://localhost/v1/chat/completions", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "authorization": "Bearer short",
      },
      body: JSON.stringify({ model: "test" }),
    });
    const res = await worker.fetch(req, env, {});
    assert.equal(res.status, 401);
  }

  // Test 5: Same length but wrong token returns 401
  {
    const wrongToken = "x".repeat(env.METLY_PROXY_TOKEN.length);
    const req = new Request("http://localhost/v1/chat/completions", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "authorization": `Bearer ${wrongToken}`,
      },
      body: JSON.stringify({ model: "test" }),
    });
    const res = await worker.fetch(req, env, {});
    assert.equal(res.status, 401);
  }

  // Test 6: Valid token succeeds with 200 and security headers
  {
    const req = new Request("http://localhost/v1/chat/completions", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "authorization": `Bearer ${env.METLY_PROXY_TOKEN}`,
      },
      body: JSON.stringify({ model: "test", messages: [] }),
    });
    const res = await worker.fetch(req, env, {});
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("x-content-type-options"), "nosniff");
    const json = await res.json();
    assert.equal(json.choices[0].message.content, "AI test response");
  }

  // Test 7: Missing METLY_PROXY_TOKEN in env returns 500
  {
    const req = new Request("http://localhost/v1/chat/completions", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        "authorization": `Bearer any`,
      },
      body: JSON.stringify({ model: "test" }),
    });
    const res = await worker.fetch(req, {}, {});
    assert.equal(res.status, 500);
  }

  console.log("All ai-proxy worker security and auth tests passed!");
}

runTests().catch((err) => {
  console.error(err);
  process.exit(1);
});
