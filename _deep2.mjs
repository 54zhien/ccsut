import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function post(p, form=""){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form,redirect:"manual"});
  return await r.text();
}
const init = JSON.parse(await post("/admin/xsd/xk/listV2",""));
const entries = Object.entries(init.data.pcencs);

for (let i = 0; i < entries.length; i++) {
  const [pcid, pcenc] = entries[i];
  const form = new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();
  const t = await post("/admin/xsd/xk/listjxbDataV2", form);
  let j = null; try { j = JSON.parse(t); } catch { console.log(`批次 ${i}: 非 JSON，${t.slice(0,80)}`); continue; }
  const d = j.data || {};
  console.log(`\n=== 批次 ${i}  ${pcid.slice(0,8)}…  ${t.length}b ===`);
  console.log("keys:", Object.keys(d).join(", ") || "(空)");
  console.log("initData:", Array.isArray(d.initData) ? `数组 ${d.initData.length} 条` : String(d.initData));
  console.log("condition:", JSON.stringify(d.condition)?.slice(0,150));
  console.log("kfrlbfb:", JSON.stringify(d.kfrlbfb)?.slice(0,80));
  if (Array.isArray(d.initData) && d.initData[0]) {
    const c = d.initData[0];
    console.log("首条:", c.kcmc, "| status:", c.status, "| id 类型:", typeof c.id);
    // 找出所有非基本类型的字段（可能是嵌套对象，Swift 端没定义就会解码失败）
    const complex = Object.entries(c).filter(([k,v]) => v !== null && typeof v === "object");
    if (complex.length) console.log("嵌套字段:", complex.map(([k,v])=>`${k}(${Array.isArray(v)?"arr":typeof v})`).join(", "));
  }
}
