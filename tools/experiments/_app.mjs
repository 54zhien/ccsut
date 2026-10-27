import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148";
const sleep=(ms)=>new Promise(r=>setTimeout(r,ms));
async function req(p, {method="GET", form=null}={}){
  const headers={cookie:ck,"user-agent":UA,accept:"application/json, */*"};
  let body;
  if(form!==null){ headers["content-type"]="application/x-www-form-urlencoded; charset=UTF-8"; body=form; }
  try{
    const r = await fetch("https://tls.ccsut.cn"+p,{method,headers,body,redirect:"manual"});
    const t = await r.text();
    return {s:r.status, loc:r.headers.get("location")||"", len:t.length, t};
  }catch(e){ return {s:"ERR", len:0, t:e.message}; }
}

console.log("=== /app/ 前缀是否是完整移动端 API ===");
const checks = [
  ["GET",  "/app/admin/xsd/xk/listV2"],
  ["POST", "/app/admin/xsd/xk/listV2"],
  ["POST", "/app/admin/xsd/pkgl/xskb/sdpkkbList"],
  ["GET",  "/app/admin/xsd/xsdzgcjcx/xscjcx"],
  ["POST", "/app/admin/xsd/xsdzgcjcx/xscjcx"],
  ["POST", "/app/admin/xsd/xsdzgcjcx/xscjdy"],
  ["POST", "/app/admin/xsd/xsdzgcjcx/list"],
];
for (const [m,p] of checks) {
  const r = await req(p, {method:m, form: m==="POST" ? "" : null});
  const head = r.t.slice(0,150).replace(/\s+/g," ");
  console.log(`\n${m.padEnd(4)} ${p}`);
  console.log(`  ${r.s} ${r.len}b  ${head}`);
  await sleep(600);
}
