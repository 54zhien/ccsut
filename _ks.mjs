import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function probe(p) {
  try {
    const r = await fetch("https://tls.ccsut.cn"+p, { headers:{cookie:ck,"user-agent":UA}, redirect:"manual" });
    const loc = r.headers.get("location")||"";
    const t = r.status === 200 ? await r.text() : "";
    const title = t.match(/<title>([^<]*)<\/title>/i)?.[1]?.trim() || "";
    const isJson = t.trim().startsWith("{");
    return { s:r.status, len:t.length, title, isJson, head:t.slice(0,90).replace(/\s+/g," ") };
  } catch(e) { return { s:0, len:0, title:"", isJson:false, head:"ERR" }; }
}

const cands = [];
// ydd/inf 模式
for (const n of ["showKs","showKsap","showExam","showKaoshi","showKsxx","showKsxxList","getKsxxJson","getKsapJson","getKsJson","getExamJson","showKcap","showKcKs"])
  cands.push("/admin/ydd/inf/" + n);
// xsd 下的考试模块
for (const m of ["ksgl/ksxx","ksgl/ksap","ksgl/index","ksxx/ksxx","ksxx/ksap","ksap/ksap","ksap/ksxx","ksap/index","kwgl/ksap","kwgl/ksxx"])
  cands.push("/admin/xsd/" + m);
// 顶层
for (const p of ["/admin/ksap","/admin/ksgl","/admin/ksxx","/admin/kwxx"])
  cands.push(p);

const hits = [];
for (const p of cands) {
  const r = await probe(p);
  if (r.s !== 404) {
    hits.push({ p, ...r });
    console.log(`${p.padEnd(38)} ${String(r.s).padStart(4)} ${String(r.len).padStart(6)}b  ${r.isJson ? "JSON " + r.head.slice(0,60) : r.title}`);
  }
}
if (!hits.length) console.log("全部 404 —— 教务系统里没有考试安排模块");
