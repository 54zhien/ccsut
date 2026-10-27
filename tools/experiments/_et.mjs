import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function get(p){
  const r = await fetch("https://tls.ccsut.cn"+p,{headers:{cookie:ck,"user-agent":UA}});
  return {s:r.status, text: await r.text()};
}
const init = JSON.parse((await get("/admin/api/getXlzc")).text);
console.log("当前周:", init.data?.xlzc);

for (const pcid of ["c550d45411024427bce4fa2c2e6ceca9","139c616117c84fa1b97364dfd3baaff8"]) {
  for (const t of ["1","2"]) {
    const r = await get(`/admin/xsd/xk/getEndTime/${t}?pcid=${pcid}`);
    console.log(`getEndTime/${t} ${pcid.slice(0,8)}… => ${r.s} ${r.text.slice(0,160)}`);
  }
}

// 再对比一次：现在这个会话还能不能拿到教学班
const encs = JSON.parse((await get("/admin/xsd/xk/listV2")).text || "{}");
const r2 = await fetch("https://tls.ccsut.cn/admin/xsd/xk/listV2",{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8"},body:""});
const j2 = JSON.parse(await r2.text());
const [pcid, pcenc] = Object.entries(j2.data.pcencs)[1];
const form = new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();
const r3 = await fetch("https://tls.ccsut.cn/admin/xsd/xk/listjxbDataV2",{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8"},body:form});
const j3 = JSON.parse(await r3.text());
console.log("\n现在 curl 拿到的 initData:", j3.data?.initData?.length ?? "字段不存在");
console.log("data 的 key:", Object.keys(j3.data || {}).join(", "));
