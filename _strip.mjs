import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
const get = async (p) => {
  const r = await fetch("https://tls.ccsut.cn"+p, { headers:{cookie:ck,"user-agent":UA,"x-requested-with":"XMLHttpRequest"}, redirect:"manual" });
  return { s: r.status, t: await r.text() };
};
const strip = (h) => h.replace(/<script[\s\S]*?<\/script>/gi,"").replace(/<style[\s\S]*?<\/style>/gi,"")
  .replace(/<[^>]+>/g,"\n").replace(/&nbsp;/g," ").replace(/&lt;/g,"<").replace(/&gt;/g,">").replace(/&amp;/g,"&")
  .split("\n").map(s=>s.trim()).filter(Boolean).join("\n");

const jxbid = "4d47120c4a2f4521bb134d42410411de";
for (const [name, p] of [
  ["课程简介", `/admin/xsd/xk/getKcjj?jxbid=${jxbid}`],
  ["教师信息", `/admin/xsd/xk/getJsxx?jxbid=${jxbid}`],
]) {
  const r = await get(p);
  console.log(`\n${"=".repeat(60)}\n${name}  ${r.s}  ${r.t.length}b`);
  const text = strip(r.t);
  console.log(text.slice(0, 700) || "(无正文)");
}
