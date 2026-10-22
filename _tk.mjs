import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148";
const sleep=(ms)=>new Promise(r=>setTimeout(r,ms));

// 1) 拿登录后 URL 里的 enc
const r0 = await fetch("https://tls.ccsut.cn/admin/",{headers:{cookie:ck,"user-agent":UA},redirect:"manual"});
const loc = r0.headers.get("location")||"";
const u = new URL(loc);
const enc = u.searchParams.get("enc");
const username = u.searchParams.get("username");
const dbname = u.searchParams.get("dbname");
console.log("enc =", enc);
console.log("username =", username, " dbname =", dbname);

async function req(p, opts={}){
  const headers={cookie:ck,"user-agent":UA,accept:"application/json, */*",...(opts.headers||{})};
  let body=opts.body;
  try{
    const r = await fetch("https://tls.ccsut.cn"+p,{method:opts.method||"GET",headers,body,redirect:"manual"});
    const t=await r.text();
    return `${r.status} ${t.length}b  ${t.slice(0,180).replace(/\s+/g," ")}`;
  }catch(e){ return "ERR "+e.message; }
}

console.log("\n=== 带 enc 参数 ===");
const tries = [
  `/app/admin/xsd/xsdzgcjcx/xscjcx?enc=${enc}`,
  `/app/admin/xsd/xsdzgcjcx/xscjcx?enc=${enc}&username=${username}&dbname=${dbname}`,
  `/app/admin/xsd/xk/listV2?enc=${enc}`,
  `/app/admin/xsd/xk/listV2?enc=${enc}&username=${username}&dbname=${dbname}`,
];
for (const p of tries){ console.log((await req(p)).slice(0,200)); await sleep(600); }

console.log("\n=== 带 header token ===");
for (const h of [
  {enc: enc},
  {token: enc},
  {Authorization: "Bearer " + enc},
  {"X-Token": enc},
]) {
  const r = await req(`/app/admin/xsd/xk/listV2`, {headers:h});
  console.log(JSON.stringify(h).slice(0,40).padEnd(44), r.slice(0,140));
  await sleep(600);
}

console.log("\n=== POST JSON ===");
console.log((await req("/app/admin/xsd/xk/listV2", {method:"POST", headers:{"content-type":"application/json"}, body:JSON.stringify({enc, username, dbname})})).slice(0,200));

console.log("\n=== /app 根路径与文档 ===");
for (const p of ["/app/", "/app/index", "/app/api", "/app/admin/xsd"]) {
  console.log(p.padEnd(20), (await req(p)).slice(0,150));
  await sleep(500);
}
