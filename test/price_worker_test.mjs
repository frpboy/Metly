import assert from "node:assert/strict";
import worker from "../backend/price-worker/worker.js";

async function runTests() {
  const env = {
    CORS_ALLOW_ORIGIN: "https://metly.app",
  };

  // Test 1: OPTIONS CORS preflight returns correct headers
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

  // Test 2: GET request returns prices and security headers
  {
    const req = new Request("http://localhost/", {
      method: "GET",
    });
    const res = await worker.fetch(req, env, {});
    assert.equal(res.status, 200);
    assert.equal(res.headers.get("x-content-type-options"), "nosniff");
    assert.equal(res.headers.get("content-type"), "application/json");
    const json = await res.json();
    assert.ok(json.gold);
    assert.ok(json.silver);
    assert.equal(json.gold.metal, "gold");
    assert.equal(json.silver.metal, "silver");
  }

  // Test 3: Unsupported methods return 405 Method Not Allowed
  for (const method of ["POST", "PUT", "DELETE", "PATCH"]) {
    const req = new Request("http://localhost/", {
      method,
    });
    const res = await worker.fetch(req, env, {});
    assert.equal(res.status, 405);
    assert.equal(res.headers.get("x-content-type-options"), "nosniff");
    assert.equal(res.headers.get("allow"), "GET, OPTIONS");
    const body = await res.json();
    assert.equal(body.error, "Method not allowed");
  }

  console.log("All price worker security and endpoint tests passed!");
}

runTests().catch((err) => {
  console.error(err);
  process.exit(1);
});
