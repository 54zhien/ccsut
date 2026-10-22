import fs from "node:fs/promises";
const HAR = "C:/Users/Azusa/.dsh/attachments/v1/files/be/becc8710556623b358630437f91194d88f64e7bb95fe49a322267fb4263fec01/HTTPS_Capture_Session_1792665227_f1704a64.har";
const har = JSON.parse(await fs.readFile(HAR, "utf8"));
const entries = har.log.entries;

function show(idx, label) {
  const e = entries[idx];
  if (!e) return;
  console.log(`\n${"=".repeat(70)}\n[${idx}] ${label}\n${e.request.method} ${e.request.url}`);
  const reqHdr = (e.request.headers||[]).filter(h=>/cookie|referer|content-type/i.test(h.name));
  reqHdr.forEach(h=>console.log(`  REQ ${h.name}: ${String(h.value).slice(0,120)}`));
  if (e.request.postData?.text) console.log("  BODY:", e.request.postData.text.slice(0,200));
  const body = e.response?.content?.text || "";
  console.log(`  RESP ${e.response?.status} ${body.length}b`);
  console.log("  " + body.replace(/\s+/g," ").slice(0, 1200));
}

show(30, "成绩 JSON");
show(66, "综测成绩 JSON (本学期)");
show(78, "综测成绩 JSON (历史学期)");
show(19, "成绩页面 HTML");
