import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function post(p, form){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form});
  return await r.text();
}
// 从 HTML 里拿学期列表
const html = await (await fetch("https://tls.ccsut.cn/admin/xsd/kwglXsdKscx/kslist?&role=xs&cpdx=", { headers:{cookie:ck,"user-agent":UA} })).text();
const opts = [...new Set([...html.matchAll(/<option[^>]*value=["']([^"']*)["'][^>]*>([^<]*)</g)].map(m=>`${m[1]}|${m[2].trim()}`))];
console.log("学期下拉:", opts.length ? opts.join(", ") : "无 option");
const li = [...new Set([...html.matchAll(/changeXn\(['"]([^'"]+)['"]\)/g)].map(m=>m[1]))];
if (li.length) console.log("changeXn:", li.join(", "));

const terms = opts.length ? opts.map(o=>o.split("|")[0]) : ["2026-2027-1","2025-2026-2","2025-2026-1","2024-2025-2","2024-2025-1"];
console.log("\n=== 各学期考试 ===");
for (const t of terms) {
  const r = await post("/admin/xsd/kwglXsdKscx/getXsKsxx", new URLSearchParams({xnxq:t}).toString());
  let j=null; try{ j=JSON.parse(r); }catch{}
  const n = j?.data?.list?.length ?? "—";
  console.log(`${t.padEnd(22)} ret=${j?.ret} ${n} 场  ${j?.msg||""}`);
  if (n && typeof n === "number" && n > 0) {
    j.data.list.forEach(e => console.log(`    ${e.ksrq} ${e.qssj}  ${e.kcmc}  ${e.jxlmc}${e.jsmc}  座位${e.zwh}  ${e.kspcmc}`));
  }
}
