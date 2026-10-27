import fs from "node:fs/promises";
const files = ["xk_ggxxk.js","xk_xsdxk.js","xk_cxxk.js","xk_index.js"];
const all = new Set();
for (const f of files) {
  const t = await fs.readFile("./out/" + f, "utf8");
  for (const m of t.matchAll(/[`"']((?:adminPath\s*\+\s*)?["'`]?)?\/(xsd|ydd|system|api)\/[A-Za-z0-9_\/]+/g)) {}
  for (const m of t.matchAll(/\/(?:admin\/)?(xsd|ydd|system|api)\/[A-Za-z0-9_\/]+/g)) all.add(m[0]);
}
const list = [...all].sort();
const groups = {};
for (const p of list) {
  const g = p.split("/")[1] || "other";
  (groups[g] ||= []).push(p);
}
for (const [g, arr] of Object.entries(groups)) {
  console.log(`\n=== ${g} (${arr.length}) ===`);
  arr.forEach(p => console.log("  " + p));
}
