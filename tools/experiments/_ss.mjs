import fs from "node:fs/promises";
const HAR = "C:/Users/Azusa/.dsh/attachments/v1/files/be/becc8710556623b358630437f91194d88f64e7bb95fe49a322267fb4263fec01/HTTPS_Capture_Session_1792665227_f1704a64.har";
const har = JSON.parse(await fs.readFile(HAR, "utf8"));
const e = har.log.entries.find(x => x.request.url.includes("ydd/inf/showScore"));
const html = e.response.content.text;
await fs.writeFile("./out/showScore.html", html, "utf8");
console.log("showScore.html 已存:", html.length, "bytes");

// 学期下拉
const opts = [...html.matchAll(/<option[^>]*value=["']([^"']*)["'][^>]*>([^<]*)</g)].map(m=>`${m[1]}=${m[2].trim()}`);
console.log("\n=== option 列表 ===");
console.log(opts.join("\n") || "无 option");

// select 标签
const sels = [...html.matchAll(/<select[^>]*>/g)].map(m=>m[0]);
console.log("\n=== select 标签 ===");
console.log(sels.join("\n") || "无");

// 内嵌 JS 里的学期数组
const jsVars = [...html.matchAll(/(?:var|let|const)\s+(\w+)\s*=\s*(\[[^\]]{0,300}\]|\{[^}]{0,300}\})/g)].map(m=>`${m[1]} = ${m[2].slice(0,200)}`);
console.log("\n=== JS 变量 ===");
console.log(jsVars.slice(0,10).join("\n") || "无");

// getXscjJson 附近的调用代码
const idx = html.indexOf("getXscjJson");
if (idx > 0) {
  console.log("\n=== getXscjJson 调用处 ===");
  console.log(html.slice(Math.max(0,idx-500), idx+300).replace(/\s+/g," "));
}
