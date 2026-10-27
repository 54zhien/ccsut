import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function post(p, form=""){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8"},body:form});
  return await r.text();
}
const init = JSON.parse(await post("/admin/xsd/xk/listV2",""));
const encs = init.data.pcencs;

for (const [pcid, pcenc] of Object.entries(encs)) {
  const form = new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();
  const j = JSON.parse(await post("/admin/xsd/xk/listjxbDataV2", form));
  const arr = j.data?.initData || [];
  console.log(`\n===== 批次 ${pcid.slice(0,8)}…  共 ${arr.length} 条 =====`);

  // 状态字段分布
  const statusDist = {};
  const bmztDist = {};
  arr.forEach(o => {
    statusDist[o.status] = (statusDist[o.status]||0)+1;
    bmztDist[o.bmzt] = (bmztDist[o.bmzt]||0)+1;
  });
  console.log("status 分布:", JSON.stringify(statusDist));
  console.log("bmzt   分布:", JSON.stringify(bmztDist));

  // 找出非 0 状态的
  const picked = arr.filter(o => (o.status && o.status !== "0") || (o.bmzt && o.bmzt !== "0"));
  console.log("状态非 0 的:", picked.length);
  picked.forEach(o => console.log(`   ${o.kcmc} | status=${o.status} bmzt=${o.bmzt} | ${o.teacher}`));

  // AI 相关
  const ai = arr.filter(o => /AI|人工智能|智能/i.test(o.kcmc || ""));
  console.log("AI 相关课程:", ai.length);
  ai.slice(0,10).forEach(o => console.log(`   ${o.kcmc} | status=${o.status} | ${o.teacher} | ${o.yxrl}`));
}
