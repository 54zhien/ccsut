import fs from "node:fs/promises";
const HAR = "C:/Users/Azusa/.dsh/attachments/v1/files/be/becc8710556623b358630437f91194d88f64e7bb95fe49a322267fb4263fec01/HTTPS_Capture_Session_1792665227_f1704a64.har";
const har = JSON.parse(await fs.readFile(HAR, "utf8"));
const entries = har.log.entries;

const jw = entries.filter(e => e.request.url.includes("tls.ccsut.cn") || e.request.url.includes("vkb.jw.chaoxing"));
console.log("=== tls.ccsut.cn + vkb.jw 共 " + jw.length + " 条 ===\n");
jw.forEach((e, i) => {
  const u = new URL(e.request.url);
  const st = e.response?.status ?? "—";
  const len = e.response?.content?.size ?? 0;
  const m = e.request.method;
  console.log(`${String(i).padStart(2)} ${String(st).padEnd(4)} ${m.padEnd(4)} ${String(len).padStart(7)}b  ${u.host}${u.pathname}${u.search.slice(0,90)}`);
});
