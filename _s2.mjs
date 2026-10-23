import fs from "node:fs/promises";
for (const f of ["xsdxk.js","cxxk.js","index.js"]) {
  const t = await fs.readFile("./out/xk_" + f, "utf8");
  console.log(`\n${"=".repeat(60)}\n${f}  ${t.length}b`);

  const seg = [...new Set([...t.matchAll(/[`"']([^`"']*(?:xsd\/xk|xdxxk)[^`"']*)[`"']/g)].map(m=>m[1]))];
  console.log("xk 路径:", seg.length ? "" : "无");
  seg.forEach(u=>console.log("  " + u));

  // 中文操作词
  const zh = [...new Set([...t.matchAll(/[`"']([^`"']{0,12}(?:选课|退选|退课|已选|确定|提交)[^`"']{0,12})[`"']/g)].map(m=>m[1]))].slice(0,10);
  if (zh.length) console.log("中文:", zh.join(" | "));

  // xkDone 上下文
  const i = t.indexOf("xkDone");
  if (i > 0) console.log("\nxkDone 上下文:\n  " + t.slice(Math.max(0,i-300), i+400).replace(/\s+/g," "));
}
