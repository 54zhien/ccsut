import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const all = state.cookies.filter(c=>c.domain.includes("ccsut.cn"));
console.log("state.json Cookie 数:", all.length);
console.log("名字:", all.map(c=>c.name).sort().join(","));

const ck = all.map(c=>`${c.name}=${c.value}`).join("; ");
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131.0.0.0 Safari/537.36";

async function post(p, form=""){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form,redirect:"manual"});
  return {s:r.status, loc:r.headers.get("location")||"", text: await r.text()};
}
async function get(p){
  const r = await fetch("https://tls.ccsut.cn"+p,{headers:{cookie:ck,"user-agent":UA},redirect:"manual"});
  return {s:r.status, loc:r.headers.get("location")||"", text: await r.text()};
}

const probe = await get("/admin/");
console.log("\n/admin/ =>", probe.s, probe.loc.slice(0,70));
const alive = probe.s === 302 && !/\/admin\/login|loginFailPage/.test(probe.loc);
console.log("会话是否有效:", alive);

if (alive) {
  const init = await post("/admin/xsd/xk/listV2","");
  let j=null; try{ j=JSON.parse(init.text); }catch{}
  console.log("listV2 ret:", j?.ret, " pcencs:", Object.keys(j?.data?.pcencs||{}).length);
  const [pcid, pcenc] = Object.entries(j?.data?.pcencs||{})[1] || [];
  if (pcid) {
    const form = new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();
    const r = await post("/admin/xsd/xk/listjxbDataV2", form);
    let rj=null; try{ rj=JSON.parse(r.text); }catch{}
    console.log("listjxbDataV2 →", rj?.data?.initData?.length ?? "字段缺失", "门");
    console.log("data keys:", Object.keys(rj?.data||{}).join(","));
  }
} else {
  console.log("\n会话已失效，无法对照");
}
