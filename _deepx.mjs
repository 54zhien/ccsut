import fs from "node:fs/promises";
const t = await fs.readFile("./out/xk_ggxxk.js","utf8");

console.log("=== url 相关 ===");
const urls = [...t.matchAll(/url\s*[:=]\s*[`"']([^`"']{4,90})[`"']/g)].map(m=>m[1]);
[...new Set(urls)].forEach(u=>console.log("  " + u));

console.log("\n=== 含 xk/ 的字符串 ===");
const seg = [...new Set([...t.matchAll(/[`"']([^`"']*xk\/[^`"']*)[`"']/g)].map(m=>m[1]))];
seg.forEach(u=>console.log("  " + u));

console.log("\n=== 函数定义 ===");
const fns = [...t.matchAll(/function\s+(\w+)\s*\(/g)].map(m=>m[1]);
console.log("  " + [...new Set(fns)].join(", "));

console.log("\n=== 关键调用上下文 ===");
for (const kw of ["xkOperate","saveXk","addXk","delXk","cancelXk","submitXk","xkCourse","operate"]) {
  const i = t.indexOf(kw);
  if (i > 0) console.log(`\n[${kw}] …${t.slice(Math.max(0,i-160), i+220).replace(/\s+/g," ")}…`);
}
