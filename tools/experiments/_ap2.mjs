import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148";
const sleep=(ms)=>new Promise(r=>setTimeout(r,ms));
async function req(p, method="GET"){
  try{
    const r = await fetch("https://tls.ccsut.cn"+p,{method,headers:{cookie:ck,"user-agent":UA,"x-requested-with":"XMLHttpRequest",accept:"application/json"},redirect:"manual"});
    const t=await r.text();
    const ok = !t.includes("system_error");
    return {ok, s:r.status, t};
  }catch(e){ return {ok:false, s:"ERR", t:e.message}; }
}

const cands = [
  "/app/admin/xsd/xsdzgcjcx/xscjcx.do",
  "/app/admin/xsd/xsdzgcjcx/xscjcx.json",
  "/app/admin/xsd/xsdzgcjcx/xscjcx/list",
  "/app/admin/xsd/xsdzgcjcx/xscjcx/list.json",
  "/app/jw/xsd/xsdzgcjcx/xscjcx",
  "/app/jwadmin/xsd/xsdzgcjcx/xscjcx",
  "/app/admin/xsd/cjcx/list",
  "/app/admin/xsd/xk/listV2.do",
  "/app/entry",
  "/app/service",
  "/app/help",
  "/app/version",
  "/app/health",
];

console.log("=== 非 system_error 的响应才是有效路径 ===");
for (const p of cands) {
  const r = await req(p);
  const mark = r.ok ? "★" : " ";
  console.log(`${mark} ${String(r.s).padEnd(4)} ${p.padEnd(42)} ${r.t.slice(0,110).replace(/\s+/g," ")}`);
  await sleep(500);
}

// 已确认能用的接口，换 /app 前缀对照
console.log("\n=== 对照：同一接口 PC 版 vs /app 版 ===");
const pc = await req("/admin/xsd/xk/listV2", "POST");
const ap = await req("/app/admin/xsd/xk/listV2", "POST");
console.log("PC   /admin/xsd/xk/listV2 →", pc.t.slice(0,80));
console.log("APP  /app/admin/xsd/xk/listV2 →", ap.t.slice(0,80));
