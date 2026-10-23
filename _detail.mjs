import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function post(p, form){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form});
  return await r.text();
}
const init = JSON.parse(await post("/admin/xsd/xk/listV2",""));
const [pcid, pcenc] = Object.entries(init.data.pcencs)[1];
const form = new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();
const j = JSON.parse(await post("/admin/xsd/xk/listjxbDataV2", form));
const c = j.data.initData[0];

console.log("=== 一门课的完整字段 ===\n");
const skip = new Set(["kcjj","jsjj"]);
for (const [k,v] of Object.entries(c)) {
  if (skip.has(k)) continue;
  const s = String(v ?? "");
  if (s === "" || s === "-") continue;
  console.log(`${k.padEnd(18)} ${s.length > 90 ? s.slice(0,90) + "…" : s}`);
}
