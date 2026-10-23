import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function probe(p) {
  try {
    const r = await fetch("https://tls.ccsut.cn"+p, { headers:{cookie:ck,"user-agent":UA}, redirect:"manual" });
    const loc = r.headers.get("location")||"";
    const t = r.status===200 ? await r.text() : "";
    return { s:r.status, loc, len:t.length, title:(t.match(/<title>([^<]*)<\/title>/i)?.[1]||"").trim() };
  } catch { return { s:0, loc:"", len:0, title:"" }; }
}
console.log("=== PC 端入口 ===");
for (const p of ["/admin/index","/admin/main","/admin/home","/admin/desktop","/admin/framework","/admin/index.html","/admin/xsd/index","/admin/login2?role=xs"]) {
  const r = await probe(p);
  const note = r.loc ? "→ " + r.loc.replace("https://tls.ccsut.cn","").slice(0,50) : r.title;
  console.log(`${p.padEnd(26)} ${String(r.s).padStart(4)}  ${note}`);
}

console.log("\n=== HAR 里搜「考试/考场/ksap/kwxx」 ===");
const HAR = "C:/Users/Azusa/.dsh/attachments/v1/files/be/becc8710556623b358630437f91194d88f64e7bb95fe49a322267fb4263fec01/HTTPS_Capture_Session_1792665227_f1704a64.har";
const har = JSON.parse(await fs.readFile(HAR, "utf8"));
const kw = /ksap|kwxx|kaoshi|exam|考试|考场|座位/i;
const hits = har.log.entries.filter(e => kw.test(decodeURIComponent(e.request.url)) || kw.test(e.response?.content?.text?.slice(0,3000) || ""));
console.log(`匹配 ${hits.length} 条`);
hits.slice(0,8).forEach(e => console.log("  " + decodeURIComponent(e.request.url).slice(0,110)));
