import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function post(p, form){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form,redirect:"manual"});
  return { s: r.status, loc: r.headers.get("location")||"", t: await r.text() };
}

// 先拿批次
const init = JSON.parse((await post("/admin/xsd/xk/listV2","")).t);
const pcids = Object.keys(init.data.pcencs);
console.log("批次:", pcids.map(p=>p.slice(0,8)).join(", "));
console.log("选课学期:", init.data.xkxnxq);

console.log("\n=== 选课接口：无效 jxbid 探测 ===");
for (const pcid of pcids.slice(0,1)) {
  const r = await post("/admin/xsd/xk/xsdXkV2", new URLSearchParams({jxbid:"00000000000000000000000000000000", pcid, sfqc:""}).toString());
  console.log(`  ${r.s} ${r.t.slice(0,160)}`);
}

console.log("\n=== 退课接口：无效 jxbid 探测 ===");
for (const pcid of pcids.slice(0,1)) {
  const r = await post("/admin/xsd/xk/xsdTkV2", new URLSearchParams({jxbid:"00000000000000000000000000000000", pcid}).toString());
  console.log(`  ${r.s} ${r.t.slice(0,160)}`);
}

// 已选课程的真实 jxbid
console.log("\n=== 已选课程（可用来安全测试退课）===");
const entries = Object.entries(init.data.pcencs);
for (const [pcid, pcenc] of entries) {
  const form = new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();
  const j = JSON.parse((await post("/admin/xsd/xk/listjxbDataV2", form)).t);
  (j.data?.initData||[]).filter(c=>c.status==="1").forEach(c=>{
    console.log(`  ${c.kcmc}  jxbid=${c.id}  pcid=${pcid.slice(0,8)}…`);
  });
}
