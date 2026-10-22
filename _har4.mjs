import fs from "node:fs/promises";
const HAR = "C:/Users/Azusa/.dsh/attachments/v1/files/be/becc8710556623b358630437f91194d88f64e7bb95fe49a322267fb4263fec01/HTTPS_Capture_Session_1792665227_f1704a64.har";
const har = JSON.parse(await fs.readFile(HAR, "utf8"));
const entries = har.log.entries;

function find(pat) { return entries.find(e => e.request.url.includes(pat)); }

function dump(pat, label) {
  const e = find(pat);
  if (!e) { console.log(`\n[${label}] 未找到 ${pat}`); return; }
  console.log(`\n${"=".repeat(72)}\n[${label}]`);
  console.log(`${e.request.method} ${e.request.url}`);
  const ck = (e.request.headers||[]).find(h=>h.name.toLowerCase()==="cookie");
  const ref = (e.request.headers||[]).find(h=>h.name.toLowerCase()==="referer");
  if (ck) console.log(`  Cookie(${ck.value.length}字): ${ck.value.slice(0,150)}…`);
  if (ref) console.log(`  Referer: ${ref.value}`);
  const body = e.response?.content?.text || "";
  console.log(`  RESP ${e.response?.status} ${body.length}b`);
  console.log("  " + body.replace(/\s+/g," ").slice(0, 1400));
}

dump("getXscjJson", "成绩 JSON");
dump("getXszgcjJson", "综测成绩 JSON");
dump("ydd/inf/showScore", "成绩页 HTML");
