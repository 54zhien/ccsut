import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function probe(p, opts={}){
  try {
    const r = await fetch("https://tls.ccsut.cn"+p,{headers:{cookie:ck,"user-agent":UA,...(opts.headers||{})},redirect:"manual",method:opts.method||"GET",body:opts.body});
    const buf = Buffer.from(await r.arrayBuffer());
    return {s:r.status, loc:(r.headers.get("location")||"").slice(0,100), size:buf.length, text:buf.toString("utf8").slice(0,200)};
  } catch(e){ return {s:"ERR", err:e.cause?.code||e.message}; }
}
const r1 = await probe("/admin/");
console.log("会话检查 /admin/ =>", r1.s, r1.loc || "");
if (r1.s === 302 && r1.loc.includes("login")) {
  console.log("!! 本地会话已过期，需要重抓");
} else {
  console.log("本地会话仍有效");
}
