import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
const get = async (p) => {
  const r = await fetch("https://tls.ccsut.cn"+p, { headers:{cookie:ck,"user-agent":UA,"x-requested-with":"XMLHttpRequest"}, redirect:"manual" });
  return { s: r.status, t: await r.text() };
};

const jxbid = "4d47120c4a2f4521bb134d42410411de";  // 合声实验室

for (const [name, path] of [
  ["课程简介 getKcjj", `/admin/xsd/xk/getKcjj?jxbid=${jxbid}`],
  ["教师信息 getJsxx", `/admin/xsd/xk/getJsxx?jxbid=${jxbid}`],
]) {
  const r = await get(path);
  console.log(`\n=== ${name}  ${r.s}  ${r.t.length}b ===`);
  console.log(r.t.slice(0, 900));
}

// 再拿一门网课对比
const init = JSON.parse((await get("/admin/xsd/xk/listV2")).t);
const [pcid, pcenc] = Object.entries(init.data.pcencs)[0];
const form = new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();
const lr = await fetch("https://tls.ccsut.cn/admin/xsd/xk/listjxbDataV2",{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form});
const j = JSON.parse(await lr.text());
const net = (j.data.initData||[]).find(c=>c.kcjj || c.jsjj);
if (net) {
  console.log(`\n=== 网课对比: ${net.kcmc} ===`);
  console.log("列表里的 kcjj 字段:", (net.kcjj||"").slice(0,120));
  console.log("列表里的 jsjj 字段:", (net.jsjj||"").slice(0,120));
  const r2 = await get(`/admin/xsd/xk/getKcjj?jxbid=${net.id}`);
  console.log("getKcjj:", r2.s, r2.t.slice(0,300));
}
