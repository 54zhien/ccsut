import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function post(p, form=""){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form,redirect:"manual"});
  return await r.text();
}
const init = JSON.parse(await post("/admin/xsd/xk/listV2",""));
const [pcid, pcenc] = Object.entries(init.data.pcencs)[1];
const form = new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();
const j = JSON.parse(await post("/admin/xsd/xk/listjxbDataV2", form));

console.log("=== TeachingClass 每个字段的实际类型（扫描全部 75 条）===");
const types = {};
for (const c of j.data.initData) {
  for (const [k, v] of Object.entries(c)) {
    const t = v === null ? "null" : Array.isArray(v) ? "array" : typeof v;
    (types[k] ||= new Set()).add(t);
  }
}
Object.entries(types).sort().forEach(([k, s]) => {
  const badge = s.size > 1 ? "⚠️" : (/array|object/.test([...s][0]) ? "🔶" : "  ");
  console.log(`${badge} ${k.padEnd(18)} ${[...s].join(" | ")}`);
});
