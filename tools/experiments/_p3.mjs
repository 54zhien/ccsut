import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
const sleep=(ms)=>new Promise(r=>setTimeout(r,ms));
async function probe(p){
  try{
    const r = await fetch("https://tls.ccsut.cn"+p,{headers:{cookie:ck,"user-agent":UA},redirect:"manual"});
    const b=Buffer.from(await r.arrayBuffer());
    return `${r.status} ${b.length}b ${(r.headers.get("location")||"").slice(0,70)}`;
  }catch(e){ return "ERR "+e.message.slice(0,40); }
}
const list = [
  "/frontend/index.html",
  "/frontend/views/student/index.html",
  "/admin/xsd/xk/xkjg",
  "/admin/xsd/xk/listYxkc",
  "/admin/xsd/xk/getYxkc",
  "/admin/xsd/xk/xkjgList",
  "/admin/xsd/xsdzgcjcx/xscjcxb",
  "/admin/xsd/cjgl/xscjcx",
];
for(const p of list){
  console.log(p.padEnd(42), await probe(p));
  await sleep(700);
}
