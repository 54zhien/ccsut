import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
const sleep=(ms)=>new Promise(r=>setTimeout(r,ms));
async function post(p, form=""){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form});
  return await r.text();
}

const init = JSON.parse(await post("/admin/xsd/xk/listV2",""));
console.log("listV2 ret:", init.ret, "msg:", init.msg);
const d = init.data || {};
console.log("xkxnxq:", d.xkxnxq);
console.log("cxxkwkcts:", d.cxxkwkcts);
console.log("pcencs keys:", Object.keys(d.pcencs || {}));
console.log("sfksxk:", d.sfksxk, " sfkxk:", d.sfkxk);
console.log("showGoHome:", d.showGoHome);

await sleep(700);
for (const [pcid, pcenc] of Object.entries(d.pcencs || {})) {
  const form = new URLSearchParams({
    from:"ggxxk", kcmc:"", kcxz:"", jxms:"", kcgs:"", teacher:"",
    pcid, kkxq:"", kclb:"", pcenc, kclx:""
  }).toString();
  const t = await post("/admin/xsd/xk/listjxbDataV2", form);
  let j=null; try{ j=JSON.parse(t); }catch{}
  const n = j?.data?.initData?.length;
  console.log(`\n批次 ${pcid.slice(0,8)}… → ret=${j?.ret} msg=${j?.msg} 课程数=${n ?? "字段缺失"}  响应${t.length}b`);
  if (n) {
    console.log("  样例:", j.data.initData[0].kcmc, "|", j.data.initData[0].teacher, "|", j.data.initData[0].yxrl);
    const picked = j.data.initData.filter(c=>c.status==="1");
    console.log("  已选:", picked.length, picked.map(c=>c.kcmc.slice(0,14)).join(", "));
  } else {
    console.log("  data keys:", Object.keys(j?.data||{}).join(","));
  }
  await sleep(700);
}
