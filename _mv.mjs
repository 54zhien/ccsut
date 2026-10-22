import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148";
const sleep=(ms)=>new Promise(r=>setTimeout(r,ms));
async function probe(p){
  try{
    const r = await fetch("https://tls.ccsut.cn"+p,{headers:{cookie:ck,"user-agent":UA},redirect:"manual"});
    const buf = Buffer.from(await r.arrayBuffer());
    const t = buf.toString("utf8");
    const isLogin = r.status===302 && /\/admin\/login|loginFailPage/.test(r.headers.get("location")||"");
    return {s:r.status, len:buf.length, loc:r.headers.get("location")||"", isLogin, hasScore:/成绩/.test(t), t};
  }catch(e){ return {s:"ERR", len:0, loc:"", isLogin:false, hasScore:false, t:e.message}; }
}
const paths = [
  "/m/", "/mobile/", "/phone/", "/wx/", "/h5/", "/app/",
  "/m/index.html", "/mobile/index.html",
  "/m/admin/", "/mobile/admin/",
  "/frontend/m/", "/frontend/mobile/",
  "/frontend/views/student/", "/frontend/views/",
];
console.log("=== 移动版前端探测 ===");
for (const p of paths) {
  const r = await probe(p);
  const flags = [r.isLogin?"需登录":"", r.hasScore?"含成绩字样":""].filter(Boolean).join(" ");
  console.log(`${String(r.s).padEnd(4)} ${String(r.len).padStart(6)}b ${p.padEnd(26)} ${r.loc.slice(0,40)} ${flags}`);
  await sleep(450);
}
