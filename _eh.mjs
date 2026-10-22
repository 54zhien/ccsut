import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function probe(url){
  try{
    const r = await fetch(url,{headers:{cookie:ck,"user-agent":UA},redirect:"manual"});
    const t = Buffer.from(await r.arrayBuffer());
    return `${r.status} ${t.length}b ${(r.headers.get("location")||"").slice(0,80)}`;
  }catch(e){ return "ERR " + e.message.slice(0,50); }
}
console.log("=== ehall 能否用同一套 Cookie ===");
for (const p of ["/backstage", "/backstage/auth/page/oafportal/", "/backstage/cjcx", "/"]) {
  console.log("ehall" + p.padEnd(32), await probe("https://ehall.ccsut.cn" + p));
}
