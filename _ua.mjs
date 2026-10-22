import fs from "node:fs/promises";
const state = JSON.parse(await fs.readFile("./out/state.json","utf8"));
const ck = state.cookies.filter(c=>c.domain.includes("ccsut.cn")).map(c=>`${c.name}=${c.value}`).join("; ");
const sleep=(ms)=>new Promise(r=>setTimeout(r,ms));

const UAS = {
  "iPhone Safari": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
  "桌面 Chrome": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36",
  "无 UA": "",
};

async function post(p, form, ua){
  const h = {cookie: ck, "content-type":"application/x-www-form-urlencoded; charset=UTF-8", "x-requested-with":"XMLHttpRequest"};
  if (ua) h["user-agent"] = ua;
  const r = await fetch("https://tls.ccsut.cn"+p,{method:"POST",headers:h,body:form});
  return await r.text();
}

const init = JSON.parse(await post("/admin/xsd/xk/listV2","",UAS["桌面 Chrome"]));
const [pcid, pcenc] = Object.entries(init.data.pcencs)[1];
const form = new URLSearchParams({from:"ggxxk",kcmc:"",kcxz:"",jxms:"",kcgs:"",teacher:"",pcid,kkxq:"",kclb:"",pcenc,kclx:""}).toString();

for (const [name, ua] of Object.entries(UAS)) {
  const t = await post("/admin/xsd/xk/listjxbDataV2", form, ua);
  let n = "解析失败";
  try { n = JSON.parse(t).data?.initData?.length ?? "字段缺失"; } catch {}
  console.log(`${name.padEnd(14)} → ${String(n).padStart(4)} 门   响应${String(t.length).padStart(6)}b`);
  await sleep(800);
}
