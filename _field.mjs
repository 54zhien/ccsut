import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function post(p, form){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form});
  return await r.text();
}
const init = JSON.parse(await post("/admin/xsd/xk/listV2",""));
const entries = Object.entries(init.data.pcencs);

for (const [pcid, pcenc] of entries) {
  const form = new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();
  const j = JSON.parse(await post("/admin/xsd/xk/listjxbDataV2", form));
  const arr = j.data.initData || [];
  const withKcjj = arr.filter(c => (c.kcjj||"").length > 10);
  const withJsjj = arr.filter(c => (c.jsjj||"").length > 10);
  console.log(`批次 ${pcid.slice(0,8)}: ${arr.length} 门 | 有课程简介 ${withKcjj.length} | 有教师简介 ${withJsjj.length}`);

  const sample = withKcjj[0] || arr[0];
  if (sample && pcid.startsWith("139c")) {
    console.log(`\n样例: ${sample.kcmc}`);
    console.log("  teacher   :", sample.teacher);
    console.log("  jsbq      :", sample.jsbq);
    console.log("  sksjddstr :", (sample.sksjddstr||"").slice(0,90));
    console.log("  kcjj 长度 :", (sample.kcjj||"").length);
    console.log("  kcjj 前 200:", (sample.kcjj||"").replace(/<[^>]+>/g,"").slice(0,200));
    console.log("  jsjj 长度 :", (sample.jsjj||"").length);
    console.log("  jsjj 前 200:", (sample.jsjj||"").replace(/<[^>]+>/g,"").slice(0,200));
  }
  const netSample = arr.find(c => c.kcmc && c.kcmc.includes("网络课程"));
  if (netSample && pcid.startsWith("c550")) {
    console.log(`\n网课样例: ${netSample.kcmc}`);
    console.log("  kcjj 长度:", (netSample.kcjj||"").length);
    console.log("  kcjj 前 200:", (netSample.kcjj||"").replace(/<[^>]+>/g,"").slice(0,200));
  }
}
