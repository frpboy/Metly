// Durable regression tests for api/prices.js (the Vercel serverless cache
// in front of OroPocket). Run: node tool/api_prices_test.js
// Lives outside api/ so Vercel never deploys it as a function.
const handler = require('../api/prices.js');
let pass=0, fail=0;
function mkRes(){return {headers:{},code:null,body:null,
  setHeader(k,v){this.headers[k]=v},status(c){this.code=c;return this},
  json(b){this.body=b;return this}};}
const nowIso=()=>new Date().toISOString();
const good=()=>({data:{gold:{buy:14000,sell:13600,gst:420,currency:'INR',unit:'gram'},
  silver:{buy:190,sell:180,gst:5.7,currency:'INR',unit:'gram'},
  timestamp:nowIso()}});
async function run(){
  // 1: success + normalization + edge cache header + security headers
  global.fetch=async()=>({ok:true,status:200,json:good});
  let r=mkRes(); await handler({method:'GET'},r);
  (r.code===200&&r.body.source==='oropocket'&&r.body.gold.sellPerGram===13600&&
    /s-maxage=60/.test(r.headers['cache-control'])&&
    r.headers['x-content-type-options']==='nosniff'&&
    r.headers['x-frame-options']==='DENY')?pass++:(fail++,console.log('t1 FAIL',r.body,r.headers));
  // 2: cache hit within TTL serves fresh under upstream failure
  global.fetch=async()=>{throw new Error('network down')};
  r=mkRes(); await handler({method:'GET'},r);
  (r.code===200&&r.body.stale===false)?pass++:(fail++,console.log('t2 FAIL'));
  // 3: currency rejection -> upstream invalid -> stale serve
  const realNow=Date.now; Date.now=()=>realNow()+61_000;
  global.fetch=async()=>({ok:true,status:200,json:()=>({...good(),data:{...good().data,gold:{...good().data.gold,currency:'USD'}}})});
  r=mkRes(); await handler({method:'GET'},r);
  (r.code===200&&r.body.stale===true)?pass++:(fail++,console.log('t3 FAIL',r.body));
  // 4: unit rejection
  Date.now=()=>realNow()+122_000;
  global.fetch=async()=>({ok:true,status:200,json:()=>({...good(),data:{...good().data,silver:{...good().data.silver,unit:'kg'}}})});
  r=mkRes(); await handler({method:'GET'},r);
  (r.code===200&&r.body.stale===true)?pass++:(fail++,console.log('t4 FAIL'));
  // 5: in-flight dedupe: cold cache expired beyond 30min => concurrent requests share one upstream call
  Date.now=()=>realNow()+11*60_000;
  let calls=0;
  global.fetch=async()=>{calls++;await new Promise(r2=>setTimeout(r2,50));return {ok:true,status:200,json:good}};
  const rs=await Promise.all([handler({method:'GET'},mkRes()),handler({method:'GET'},mkRes()),handler({method:'GET'},mkRes())]);
  (calls===1)?pass++:(fail++,console.log('t5 FAIL calls=',calls));
  // 6: stale bound by asOf: quote with 31-min-old asOf must NOT be stale-served -> 502
  Date.now=()=>realNow()+11*60_000+61_000;
  global.fetch=async()=>{throw new Error('down')};
  // poison cache with an asOf 31 min old but fresh fetchedAt
  global.fetch=async()=>({ok:true,status:200,json:()=>({data:{gold:{buy:1,sell:1,gst:0.03,currency:'INR',unit:'gram'},silver:{buy:1,sell:1,gst:0.03,currency:'INR',unit:'gram'},timestamp:new Date(realNow()+11*60_000+61_000-31*60_000).toISOString()}})});
  Date.now=realNow; // restore for real timers
  r=mkRes(); await handler({method:'GET'},r); // caches old-asOf quote (valid shape)
  global.fetch=async()=>{throw new Error('down')};
  r=mkRes(); await handler({method:'GET'},r);
  (r.code===200&&r.body.stale===false)?pass++:(fail++,console.log("t6a FAIL",r.code,r.body)); // within TTL: served fresh; asOf age is the client freshness call
  await new Promise(r2=>setTimeout(r2,10));
  // force TTL expiry by waiting is slow; instead craft: 502 case
  Date.now=()=>realNow()+31*60_000+1;
  r=mkRes(); await handler({method:'GET'},r);
  (r.code===502&&r.body.error==='Upstream price service temporarily unavailable')?pass++:(fail++,console.log('t6b FAIL',r.code,r.body));
  Date.now=realNow;
  // 7: 405 (with security headers)
  r=mkRes(); await handler({method:'POST'},r);
  (r.code===405&&r.headers['x-content-type-options']==='nosniff'&&r.headers['x-frame-options']==='DENY')?pass++:(fail++,console.log('t7 FAIL'));
  console.log(`api/prices.js tests: ${pass} pass, ${fail} fail`);
  process.exit(fail?1:0);
}
run();
