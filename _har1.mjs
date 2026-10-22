import fs from "node:fs/promises";
const HAR = "C:/Users/Azusa/.dsh/attachments/v1/files/be/becc8710556623b358630437f91194d88f64e7bb95fe49a322267fb4263fec01/HTTPS_Capture_Session_1792665227_f1704a64.har";
const har = JSON.parse(await fs.readFile(HAR, "utf8"));
const entries = har.log.entries;
console.log("总请求:", entries.length);
console.log("抓包工具:", har.log.creator?.name, har.log.creator?.version);

// 域名分布
const hosts = {};
entries.forEach(e => {
  try { const h = new URL(e.request.url).host; hosts[h] = (hosts[h]||0)+1; } catch {}
});
console.log("\n=== 域名分布 ===");
Object.entries(hosts).sort((a,b)=>b[1]-a[1]).slice(0,25).forEach(([h,n])=>console.log(`  ${String(n).padStart(4)}  ${h}`));
