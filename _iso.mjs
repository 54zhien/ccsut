import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const UA = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) Chrome/131.0.0.0 Safari/537.36";

function build(exclude=[]) {
  return state.cookies
    .filter(c => c.domain.includes("ccsut.cn"))
    .filter(c => !exclude.includes(c.name))
    .map(c => `${c.name}=${c.value}`).join("; ");
}

async function trial(label, exclude) {
  const ck = build(exclude);
  const post = async (p, form="") => {
    const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:{cookie:ck,"user-agent":UA,"content-type":"application/x-www-form-urlencoded; charset=UTF-8","x-requested-with":"XMLHttpRequest"},body:form,redirect:"manual"});
    return await r.text();
  };
  try {
    const init = JSON.parse(await post("/admin/xsd/xk/listV2",""));
    const [pcid, pcenc] = Object.entries(init.data?.pcencs||{})[1] || [];
    if (!pcid) { console.log(`${label.padEnd(24)} listV2 无批次`); return; }
    const form = new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();
    const r = await post("/admin/xsd/xk/listjxbDataV2", form);
    const j = JSON.parse(r);
    console.log(`${label.padEnd(24)} → ${j.data?.initData?.length ?? "字段缺失"} 门`);
  } catch(e) {
    console.log(`${label.padEnd(24)} → 出错 ${e.message.slice(0,40)}`);
  }
}

console.log("=== 逐个排除 Cookie，看谁才是关键 ===\n");
await trial("全量 14 条", []);
await trial("去掉 JSESSIONID", ["JSESSIONID"]);
await trial("去掉 JSESSIONID+uid", ["JSESSIONID","uid"]);
await trial("去掉 TGC", ["TGC"]);
await trial("去掉 jw_uf", ["jw_uf"]);
await trial("去掉 jw_uf_d_u", ["jw_uf_d","jw_uf_u"]);
await trial("去掉 twiceAuthSign", ["twiceAuthSign"]);
await trial("去掉 username/puid", ["username","puid"]);
