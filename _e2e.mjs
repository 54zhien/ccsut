import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function post(p, form){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form,redirect:"manual"});
  return await r.text();
}
const init = JSON.parse(await post("/admin/xsd/xk/listV2",""));
const [pcid, pcenc] = Object.entries(init.data.pcencs).find(([k])=>k.startsWith("c550"));
const listForm = () => new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();

let j = JSON.parse(await post("/admin/xsd/xk/listjxbDataV2", listForm()));
const avail = (j.data.initData||[]).filter(c => {
  const [used, cap] = (c.yxrl||"0/0").split("/").map(Number);
  return c.status === "0" && cap > 0 && used < cap;
});
console.log(`未选且有余量: ${avail.length} 门，例如:`);
avail.slice(0,5).forEach(c=>console.log(`  ${c.kcmc.slice(0,28).padEnd(30)} ${c.yxrl}  jxbid=${c.id.slice(0,8)}…`));

const target = avail[0];
if (!target) { console.log("没有可测试的课程"); process.exit(0); }
console.log(`\n>>> 测试目标: ${target.kcmc} (${target.yxrl})`);

console.log("\n[1] 选课 →");
const r1 = await post("/admin/xsd/xk/xsdXkV2", new URLSearchParams({jxbid: target.id, pcid, sfqc:""}).toString());
console.log("   " + r1.slice(0,200));

await new Promise(r=>setTimeout(r, 1500));
const chk = () => post("/admin/xsd/xk/listjxbDataV2", listForm()).then(t=>JSON.parse(t));
let after = await chk();
let got = (after.data.initData||[]).find(c=>c.id===target.id);
console.log(`[2] 状态确认: status=${got?.status} yxrl=${got?.yxrl}`);

if (got?.status === "1") {
  console.log("\n[3] 退课 →");
  const r2 = await post("/admin/xsd/xk/xsdTkV2", new URLSearchParams({jxbid: target.id, pcid}).toString());
  console.log("   " + r2.slice(0,200));
  await new Promise(r=>setTimeout(r, 1500));
  after = await chk();
  got = (after.data.initData||[]).find(c=>c.id===target.id);
  console.log(`[4] 回滚确认: status=${got?.status} yxrl=${got?.yxrl}`);
  console.log(got?.status === "0" ? "\n✓ 选课+退课闭环验证成功" : "\n⚠️ 退课后状态未恢复，请手动检查");
} else {
  console.log("\n✗ 选课未生效，不要继续");
}
