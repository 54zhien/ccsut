import fs from "node:fs/promises";
const t = await fs.readFile("./out/xk_xsdxk.js","utf8");

for (const kw of ["xsdXkV2","xsdTkV2","qxhbxk","queryChildClassesV2"]) {
  const i = t.indexOf(kw);
  if (i < 0) { console.log(`\n[${kw}] 未找到`); continue; }
  console.log(`\n${"=".repeat(64)}\n[${kw}]`);
  console.log(t.slice(Math.max(0, i-700), i+500).replace(/[ \t]+/g," "));
}
