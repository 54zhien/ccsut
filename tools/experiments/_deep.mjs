import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function post(p, form=""){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form,redirect:"manual"});
  return await r.text();
}
const init = JSON.parse(await post("/admin/xsd/xk/listV2",""));

for (const [i,[pcid, pcenc]] of Object.entries(Object.entries(init.data.pcencs)).entries()) {
  const form = new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();
  const t = await post("/admin/xsd/xk/listjxbDataV2", form);
  const j = JSON.parse(t);
  const d = j.data || {};
  console.log(`\n=== 批次 ${pcid.slice(0,8)}… (${t.length}b) ===`);
  console.log("data 的 key:", Object.keys(d).join(", "));
  console.log("initData 类型:", Array.isArray(d.initData) ? `数组 ${d.initData.length} 条` : String(d.initData));
  console.log("mysksjd 类型:", Array.isArray(d.mysksjd) ? `数组 ${d.mysksjd.length} 项` : String(d.mysksjd));
  console.log("kfrlbfb:", typeof d.kfrlbfb, JSON.stringify(d.kfrlbfb)?.slice(0,80));
  console.log("condition:", typeof d.condition, JSON.stringify(d.condition)?.slice(0,120));
  if (Array.isArray(d.initData) && d.initData[0]) {
    const c = d.initData[0];
    console.log("首条字段类型检查:");
    for (const k of ["id","kcmc","teacher","xf","yxrl","status","kfrlbfb","sksjddstr","kcgsList"]) {
      if (k in c) console.log(`  ${k}: ${Array.isArray(c[k])?"数组":"typeof "+typeof c[k]} = ${JSON.stringify(c[k])?.slice(0,40)}`);
    }
  }
}
