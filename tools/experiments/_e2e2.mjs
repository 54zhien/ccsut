import { requireSchoolWrite } from "../require-school-write.mjs";
requireSchoolWrite();
﻿import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function post(p, form){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form,redirect:"manual"});
  return await r.text();
}
const init = JSON.parse(await post("/admin/xsd/xk/listV2",""));
const [pcid, pcenc] = Object.entries(init.data.pcencs).find(([k])=>k.startsWith("139c"));
const listForm = () => new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();
const chk = () => post("/admin/xsd/xk/listjxbDataV2", listForm()).then(t=>JSON.parse(t));

let j = await chk();
const selected = (j.data.initData||[]).filter(c=>c.status==="1");
console.log("线下批次已选:", selected.map(c=>c.kcmc.slice(0,20)).join(", "));

// 拿一门已选的课，退掉再选回来 —— 这样不会新增课程，只是验证接口
const t = selected[0];
if (!t) { console.log("线下批次没有已选课程"); process.exit(0); }
console.log(`\n>>> 闭合测试目标: ${t.kcmc}  jxbid=${t.id.slice(0,10)}…`);

console.log("\n[1] 退课 →");
const r1 = await post("/admin/xsd/xk/xsdTkV2", new URLSearchParams({jxbid:t.id, pcid}).toString());
console.log("   " + r1.slice(0,200));

await new Promise(r=>setTimeout(r,1500));
let after = await chk();
let got = (after.data.initData||[]).find(c=>c.id===t.id);
console.log(`[2] status=${got?.status} yxrl=${got?.yxrl}`);

if (got?.status === "0") {
  console.log("\n[3] 重新选课 →");
  const r2 = await post("/admin/xsd/xk/xsdXkV2", new URLSearchParams({jxbid:t.id, pcid, sfqc:""}).toString());
  console.log("   " + r2.slice(0,200));
  await new Promise(r=>setTimeout(r,1500));
  after = await chk();
  got = (after.data.initData||[]).find(c=>c.id===t.id);
  console.log(`[4] 恢复确认: status=${got?.status} yxrl=${got?.yxrl}`);
  console.log(got?.status === "1" ? "\n✓ 退课+选课闭环成功，课程已恢复" : "\n⚠️ 未恢复，请立即用学习通手动选回！");
} else {
  console.log("\n退课未生效：" + r1.slice(0,120));
}
