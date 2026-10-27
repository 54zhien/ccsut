import fs from "node:fs/promises";
const html = await fs.readFile("./out/showScore.html","utf8");

// 所有提到 xnxq 的片段
const hits = [...html.matchAll(/xnxq[^;{}\n]{0,140}/g)].map(m=>m[0].replace(/\s+/g," "));
console.log("=== xnxq 相关片段 ===");
[...new Set(hits)].slice(0,20).forEach(h=>console.log("  " + h));

// 学期选项生成逻辑
for (const kw of ["xnxqList","xqList","semester","学期","termList"]) {
  const i = html.indexOf(kw);
  if (i > 0) {
    console.log(`\n=== 附近 ${kw} ===`);
    console.log(html.slice(Math.max(0,i-200), i+400).replace(/\s+/g," "));
  }
}

// 找形如 "2024-2025-2" 的字符串
const terms = [...new Set([...html.matchAll(/["'](20\d\d-20\d\d-[12])["']/g)].map(m=>m[1]))];
console.log("\n=== 页面里出现的学期字面量 ===");
console.log(terms.join(", ") || "无");
