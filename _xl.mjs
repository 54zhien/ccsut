import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function get(p){
  const r = await fetch("https://tls.ccsut.cn"+p,{headers:{cookie:ck,"user-agent":UA}});
  return {s:r.status, text: await r.text()};
}
for (const p of ["/admin/api/getXlzc", "/admin/api/getZclistByXnxq?xnxq=2026-2027-1&role=&userId=&xqid=01"]) {
  const r = await get(p);
  console.log("\n=== " + p + " ===", r.s);
  console.log(r.text.slice(0, 700));
}
