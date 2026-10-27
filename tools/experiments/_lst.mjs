import fs from "node:fs/promises";
const raw = await fs.readFile("./out/api.json","utf8");
const arr = JSON.parse(raw);
console.log("=== 已抓到的所有 tls.ccsut.cn 请求 ===");
arr.filter(r=>r.url.includes("tls.ccsut.cn")).forEach(r=>{
  console.log(`${String(r.status).padEnd(4)} ${r.method.padEnd(5)} ${new URL(r.url).pathname}`);
});
