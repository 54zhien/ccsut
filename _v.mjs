import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148";

async function q(xnxq){
  const url = `https://tls.ccsut.cn/admin/ydd/inf/getXscjJson?xnxq=${encodeURIComponent(xnxq)}`;
  const r = await fetch(url, {headers:{cookie:ck,"user-agent":UA,referer:"https://tls.ccsut.cn/admin/ydd/inf/showScore?&role=xs&cpdx="}});
  const t = await r.text();
  let j = null;
  try { j = JSON.parse(t); } catch {}
  return {s:r.status, len:t.length, j, t};
}

for (const x of ["111", "2024-2025-2", "2026-2027-1"]) {
  const r = await q(x);
  const n = r.j?.data?.xscjList?.length;
  console.log(`xnxq=${x.padEnd(12)} → ${r.s} ${String(r.len).padStart(6)}b  ret=${r.j?.ret}  msg=${r.j?.msg}  课程数=${n ?? "—"}`);
}

console.log("\n=== xnxq=111 的内容（按学期分组）===");
const all = await q("111");
const list = all.j?.data?.xscjList || [];
const byTerm = {};
list.forEach(c => (byTerm[c.xnxq] ||= []).push(c));
Object.entries(byTerm).sort().forEach(([t, arr]) => {
  console.log(`\n【${t}】${arr.length} 门`);
  arr.forEach(c => console.log(`   ${c.zhcj.padStart(3)} 分  ${String(c.jd).padEnd(4)}绩点  ${c.xf}学分  ${c.kcmc}`));
});
