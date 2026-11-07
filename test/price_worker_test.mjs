import assert from "node:assert/strict";
import worker from "../backend/price-worker/worker.js";

async function runTests() {
  const env = {
    CORS_ALLOW_ORIGIN: "https://metly.app",
  };

  // Test 1: OPTIONS CORS preflight returns correct security & CORS headers
  {
    const req = new Request("http://localhost/", {
      method: "OPTIONS",
    });
    const res = await worker.fetch(req, env, {});
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("x-content-type-options"), "nosniff");
    assert.equal(res.headers.get("access-control-allow-origin"), "https://metly.app");
    assert.equal(res.headers.get("access-control-allow-methods"), "GET,OPTIONS");
  }

  // Test 2: Disallowed method (POST) returns 405 Method Not Allowed with Allow and security headers
  {
    const req = new Request("http://localhost/", {
      method: "POST",
    });
    const res = await worker.fetch(req, env, {});
    assert.equal(res.status, 405);
    assert.equal(res.headers.get("x-content-type-options"), "nosniff");
    assert.equal(res.headers.get("allow"), "GET, OPTIONS");
    const json = await res.json();
    assert.equal(json.error, "Method not allowed");
  }

  // Test 3: Disallowed method (DELETE) returns 405 Method Not Allowed
  {
    const req = new Request("http://localhost/", {
      method: "DELETE",
    });
    const res = await worker.fetch(req, env, {});
    assert.equal(res.status, 405);
  }

  // Test 4: GET request succeeds with 200, valid price data, and security headers
  {
    const req = new Request("http://localhost/", {
      method: "GET",
    });
    const res = await worker.fetch(req, env, {});
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("x-content-type-options"), "nosniff");
    assert.equal(res.headers.get("access-control-allow-origin"), "https://metly.app");
    const json = await res.json();
    assert.ok(json.gold);
    assert.ok(json.silver);
    assert.equal(typeof json.gold.price, "number");
    assert.equal(typeof json.silver.price, "number");
  }

  // Test 5: Fallback default CORS origin when CORS_ALLOW_ORIGIN is omitted
  {
    const req = new Request("http://localhost/", {
      method: "GET",
    });
    const res = await worker.fetch(req, {}, {});
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("access-control-allow-origin"), "*");
    assert.equal(res.headers.get("x-content-type-options"), "nosniff");
  }

  console.log("All price-worker security and method validation tests passed!");
}

runTests().catch((err) => {
  console.error(err);
  process.exit(1);
});
