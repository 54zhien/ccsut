import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
const sleep=(ms)=>new Promise(r=>setTimeout(r,ms));
async function post(p, form=""){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8"},body:form});
  return {s:r.status, text: await r.text()};
}
async function get(p){
  const r = await fetch("https://tls.ccsut.cn"+p,{headers:{cookie:ck,"user-agent":UA}});
  return {s:r.status, text: await r.text()};
}

const tab = await get("/admin/xsd/xk/getShowTab");
console.log("=== getShowTab ===", tab.s);
console.log(tab.text.slice(0, 900));

await sleep(600);
const init = await post("/admin/xsd/xk/listV2");
const encs = JSON.parse(init.text).data.pcencs || {};
const [pcid, pcenc] = Object.entries(encs)[1] || Object.entries(encs)[0] || [];

for (const from of ["ggxxk","jhxk","fjxxxk","cxxk","xsdxk"]) {
  const form = new URLSearchParams({
    from, kcmc:"", kcxz:"", jxms:"", kcgs:"", teacher:"",
    pcid: pcid||"", kkxq:"", kclb:"", pcenc: pcenc||"", kclx:""
  }).toString();
  try {
    const r = await post("/admin/xsd/xk/listjxbDataV2", form);
    const j = JSON.parse(r.text);
    const n = j.data?.initData?.length ?? 0;
    const first = n ? j.data.initData[0].kcmc : "";
    console.log(`from=${from.padEnd(8)} → ${String(n).padStart(3)} 门  ${first}`);
  } catch(e) {
    console.log(`from=${from.padEnd(8)} → 失败 ${r.text?.slice(0,60)}`);
  }
  await sleep(700);
}
