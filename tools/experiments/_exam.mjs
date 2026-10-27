import fs from "node:fs/promises";
const HAR = "C:/Users/Azusa/.dsh/attachments/v1/files/be/becc8710556623b358630437f91194d88f64e7bb95fe49a322267fb4263fec01/HTTPS_Capture_Session_1792665227_f1704a64.har";
const har = JSON.parse(await fs.readFile(HAR, "utf8"));
const entries = har.log.entries.filter(e => /kwglXsdKscx/.test(e.request.url));

console.log("=== HAR 里的考试请求 ===");
for (const e of entries) {
  console.log(`\n${e.request.method} ${decodeURIComponent(e.request.url)}`);
  console.log(`  状态 ${e.response?.status}  ${(e.response?.content?.text||"").length}b`);
  const body = e.response?.content?.text || "";
  if (body.trim().startsWith("{")) {
    console.log("  JSON: " + body.slice(0, 800));
  } else {
    console.log("  HTML 正文: " + body.replace(/<script[\s\S]*?<\/script>/gi,"").replace(/<style[\s\S]*?<\/style>/gi,"").replace(/<[^>]+>/g,"\n").split("\n").map(s=>s.trim()).filter(Boolean).join(" | ").slice(0, 600));
  }
}

// 实际探测
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
for (const p of ["/admin/xsd/kwglXsdKscx/kslist?&role=xs&cpdx=", "/admin/xsd/kwglXsdKscx/getXsKsxx"]) {
  const r = await fetch("https://tls.ccsut.cn"+p, { headers:{cookie:ck,"user-agent":UA,"x-requested-with":"XMLHttpRequest"}, redirect:"manual" });
  const t = await r.text();
  console.log(`\n>>> 实时 ${p}`);
  console.log(`    ${r.status} ${t.length}b  ${t.slice(0,300).replace(/\s+/g," ")}`);
}
