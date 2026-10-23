import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function req(p, method="GET", form){
  const h = {cookie:ck,"user-agent":UA,"x-requested-with":"XMLHttpRequest"};
  if (form) h["content-type"] = "application/x-www-form-urlencoded; charset=UTF-8";
  const r = await fetch("https://tls.ccsut.cn"+p, { method, headers:h, body:form, redirect:"manual" });
  return { s:r.status, t: await r.text() };
}

console.log("=== getShowTab ===");
const tab = await req("/admin/xsd/xk/getShowTab");
console.log(tab.s, tab.t.slice(0, 600));

console.log("\n=== getDictByGroupCode ===");
for (const code of ["xkLx","kclx","kcxz","ksLx","ksxs"]) {
  const r = await req(`/admin/xsd/xkprocess/student/getDictByGroupCode?groupCode=${code}`);
  console.log(`${code.padEnd(8)} ${r.s} ${r.t.slice(0,150)}`);
}

console.log("\n=== getStartEndTime / getEndTime（选课时间，看是否含考试）===");
const init = JSON.parse((await req("/admin/xsd/xk/listV2","POST","")).t);
const pcid = Object.keys(init.data.pcencs)[0];
const r1 = await req(`/admin/xsd/xk/getStartEndTime?pcid=${pcid}`);
console.log("getStartEndTime:", r1.s, r1.t.slice(0,200));
