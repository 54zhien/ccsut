import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const UA="Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";
async function post(p, form=""){
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8"},body:form});
  return {s:r.status, text: await r.text()};
}
const init = await post("/admin/xsd/xk/listV2");
const encs = JSON.parse(init.text).data.pcencs || {};

for (const [pcid, pcenc] of Object.entries(encs)) {
  const form = new URLSearchParams({
    from:"ggxxk", kcmc:"", kcxz:"", jxms:"", kcgs:"", teacher:"",
    pcid, kkxq:"", kclb:"", pcenc, kclx:""
  }).toString();
  const r = await post("/admin/xsd/xk/listjxbDataV2", form);
  let n = 0, sample = null;
  try {
    const j = JSON.parse(r.text);
    n = j.data?.initData?.length ?? 0;
    if (n) { const c = j.data.initData[0]; sample = `${c.kcmc} | ${c.teacher} | ${c.xf}学分 | ${c.yxrl}`; }
  } catch(e) { sample = "解析失败 " + r.text.slice(0,80); }
  console.log(`pcid=${pcid.slice(0,12)}…  →  ${n} 个教学班  ${sample ?? ""}`);
}
