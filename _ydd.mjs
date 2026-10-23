import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function probe(p, method="GET") {
  try {
    const r = await fetch("https://tls.ccsut.cn"+p, { method, headers:{cookie:ck,"user-agent":UA}, redirect:"manual" });
    const loc = r.headers.get("location")||"";
    const t = r.status === 200 ? await r.text() : "";
    const isJson = t.trim().startsWith("{");
    return { s: r.status, loc, isJson, len: t.length, head: t.slice(0,110).replace(/\s+/g," ") };
  } catch(e) { return { s:0, loc:"", isJson:false, len:0, head:"ERR" }; }
}

console.log("=== ydd/inf 系列（成绩/排名/绩点）===\n");
const ydd = [
  "getXscjJson?xnxq=111", "getXszgcjJson?xnxq=111", "getXspm?xnxq=111",
  "getXxzyXspm?xnxq=111", "getXsdpjf?xnxq=111", "getXsdjqpjf?xnxq=111",
  "getXsdjqxwpjf?xnxq=111", "getXspjxwjd?xnxq=111", "getXspjxfjd?xnxq=111",
  "getXscjTjfx?xnxq=111", "getXscjPm?xnxq=111",
];
for (const p of ydd) {
  const r = await probe("/admin/ydd/inf/" + p);
  const tag = r.s===200 ? (r.isJson ? "JSON" : "HTML") : String(r.s);
  console.log(`${p.padEnd(28)} ${tag.padStart(4)} ${String(r.len).padStart(6)}b  ${r.head.slice(0,60)}`);
}

console.log("\n=== 其他推测模块 ===\n");
const others = [
  "/admin/ydd/inf/showKb", "/admin/ydd/inf/showKc", "/admin/ydd/index",
  "/admin/xsd/xsjbxx/getXsxx", "/admin/xsd/ksxx/ksxx", "/admin/xsd/pyfa/getPyfa",
  "/admin/xsd/kbcx/kbcx", "/admin/xsd/pj/pjlb", "/admin/xsd/bysh/bysh",
  "/admin/api/getZclistByXnxq", "/admin/api/getXnList",
];
for (const p of others) {
  const r = await probe(p);
  const tag = r.s===200 ? (r.isJson ? "JSON" : "HTML") : String(r.s);
  console.log(`${p.padEnd(34)} ${tag.padStart(4)} ${String(r.len).padStart(6)}b`);
}
